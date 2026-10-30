`timescale 1ns/1ps
module tb_contest_scaler_bridge;
    reg video_clk=0,sd_clk=0,rst=1;
    always #20 video_clk=~video_clk;
    initial begin #3; forever #5 sd_clk=~sd_clk; end // 相位错开，100 MHz
    reg load_start=0,abort=0,write_req_ack=0,write_finish=0;
    reg [31:0] bmp_start_sector=20;
    wire ready,busy,done,img_loaded,format_error,write_abort_req;
    wire [7:0] error_code;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    reg [7:0] sd_sec_read_data=0;
    reg sd_sec_read_data_valid=0,sd_sec_read_end=0;
    wire write_req,write_en,o_border_flag,o_last;
    wire [31:0] write_data;
    wire [9:0] o_x;
    wire [8:0] o_y;
    wire [4:0] debug_state;
    contest_scaler_bridge #(.SD_TIMEOUT_CYCLES(2000),.VIDEO_TIMEOUT_CYCLES(4000)) dut (
        .video_clk(video_clk),.sd_clk(sd_clk),.rst(rst),.load_start(load_start),
        .bmp_start_sector(bmp_start_sector),.abort(abort),.ready(ready),.busy(busy),
        .done(done),.img_loaded(img_loaded),.format_error(format_error),.error_code(error_code),
        .write_abort_req(write_abort_req),.sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),.write_req(write_req),.write_req_ack(write_req_ack),
        .write_en(write_en),.write_data(write_data),.write_finish(write_finish),
        .o_x(o_x),.o_y(o_y),.o_border_flag(o_border_flag),.o_last(o_last),.debug_state(debug_state)
    );
    reg [7:0] header[0:511];
    integer w=3,h=2,td=0,stride=12,offset=510,file_size=534,frame=0;
    integer sw,sh,left,top;
    integer output_count=0,sector_count=0,tests=0,frames=0,checked_pixels=0;
    integer sd_state=0,sd_index=0,sd_gap=0,sd_wait=0,sd_limit=512;
    integer fault_mode=0,stall_finish=0,ack_phase=0,ack_wait=0,finish_wait=-1,finish_coincident=0;
    integer cyc=0,ex,ey,sx,sy,rx_count=0;
    reg [31:0] model_lba=0;
    reg checking=0,previous_en=0,early_finish_sent=0;
    reg [9:0] previous_x=0;
    reg [23:0] expect_rgb;
    reg expect_border;
    integer row_pixels=0,source_rows=0,source_pixels=0,next_dst_row=0,expected_src_y=0;
    reg source_row_active=0;
    task fail;
        input [8*160-1:0] msg;
        begin $display("FAIL bridge test=%0d state=%0d count=%0d cycle=%0d: %0s",tests,debug_state,output_count,cyc,msg);$finish;end
    endtask
    function [23:0] pixel;
        input integer x,y;
        begin pixel=((frame&7)<<21)|((y&1023)<<11)|(x&2047);end
    endfunction
    function [7:0] byte_at;
        input [31:0] sector;
        input integer i;
        reg [63:0] p;
        integer rel,fy,x,component,vy;
        reg [23:0] rgb;
        begin
            p=({32'd0,sector}-{32'd0,bmp_start_sector})*64'd512+i;
            if(p<54) byte_at=header[p];
            else if(p>=offset && p<file_size) begin
                rel=p-offset;fy=rel/stride;x=(rel%stride)/3;component=(rel%stride)%3;
                if((rel%stride)>=w*3) byte_at=8'he7;
                else begin
                    vy=td ? fy : h-1-fy;rgb=pixel(x,vy);
                    case(component) 0:byte_at=rgb[7:0];1:byte_at=rgb[15:8];default:byte_at=rgb[23:16];endcase
                end
            end else byte_at=8'hd5;
        end
    endfunction
    task put32;
        input integer a;
        input [31:0] v;
        begin header[a]=v[7:0];header[a+1]=v[15:8];header[a+2]=v[23:16];header[a+3]=v[31:24];end
    endtask
    task make_header;
        input integer iw,ih,itop,ioffset;
        integer i;
        begin
            w=iw;h=ih;td=itop;offset=ioffset;stride=((w*3+3)/4)*4;file_size=offset+stride*h;
            for(i=0;i<512;i=i+1) header[i]=0;
            header[0]=8'h42;header[1]=8'h4d;put32(2,file_size);put32(10,offset);put32(14,40);
            put32(18,w);put32(22,td ? -h : h);header[26]=1;header[28]=24;put32(34,stride*h);
            if(w*480>=h*640) begin sw=640;sh=h*640/w;end
            else begin sh=480;sw=w*480/h;end
            if(sw<1)sw=1;if(sh<1)sh=1;left=(640-sw)/2;top=(480-sh)/2;
        end
    endtask

    // SD 模型：最快连续一个字节/100 MHz 拍，另有空拍、末字节同拍 end/延后 end。
    // mode1短扇区，2超长扇区，3不应答超时，4扇区开始后暂停以测试取消。
    always @(negedge sd_clk) begin
        sd_sec_read_data_valid=0;sd_sec_read_end=0;
        if(rst) begin sd_state=0;sd_index=0;sd_gap=0;sd_wait=0;end
        else case(sd_state)
            0:if(sd_sec_read) begin
                model_lba=sd_sec_read_addr;sector_count=sector_count+1;sd_index=0;sd_gap=0;sd_wait=0;
                sd_limit=(fault_mode==1)?511:((fault_mode==2)?513:512);sd_state=1;
            end
            1:begin
                if(sd_sec_read_addr!==model_lba) fail("SD LBA changed mid sector");
                if(fault_mode!=3 && fault_mode!=4) begin
                    sd_gap=sd_gap+1;
                    if((sector_count%3==0) && (sd_gap%7==0)) begin end
                    else begin
                        sd_sec_read_data=byte_at(model_lba,sd_index);sd_sec_read_data_valid=1;
                        if(sd_index==sd_limit-1) begin
                            if(sector_count%2==0) begin sd_sec_read_end=1;sd_state=3;end
                            else sd_state=2;
                        end
                        sd_index=sd_index+1;
                    end
                end else if(!sd_sec_read) sd_state=3;
            end
            2:begin sd_sec_read_end=1;sd_state=3;end
            3:if(!sd_sec_read) sd_state=0;
        endcase
    end

    always @(negedge video_clk) begin
        write_finish=0;
        if(rst) begin write_req_ack=0;ack_phase=0;ack_wait=0;finish_wait=-1;end
        else if(checking) begin
            if(ack_phase==0 && write_req) begin
                ack_wait=ack_wait+1;if(ack_wait==5)begin write_req_ack=1;ack_phase=1;ack_wait=0;end
            end else if(ack_phase==1 && !write_req) begin
                ack_wait=ack_wait+1;if(ack_wait==6)begin write_req_ack=0;ack_phase=2;end
            end
            if(!early_finish_sent && output_count==640) begin write_finish=1;early_finish_sent=1;end
            if(output_count==307200 && finish_wait==-1) finish_wait=17;
            if(finish_wait>0) finish_wait=finish_wait-1;
            else if(finish_wait==0 && !stall_finish) begin write_finish=1;finish_wait=-2;end
            if(finish_coincident && write_en && o_last) begin write_finish=1;finish_wait=-2;end
        end
    end
    always @(posedge video_clk) begin
        cyc=cyc+1;
        if(!rst && checking) begin
            if(img_loaded && output_count!=307200) fail("loaded before all pixels");
            if(previous_en && previous_x!=639 && !write_en && !abort) fail("gap inside output row");
            previous_en=write_en;previous_x=o_x;
            if(write_en) begin
                if(ack_phase!=2 || output_count>=307200) fail("output outside granted frame");
                ex=output_count%640;ey=output_count/640;
                expect_border=(ex<left || ex>=left+sw || ey<top || ey>=top+sh);
                if(expect_border)expect_rgb=24'h001030;
                else begin sx=(ex-left)*w/sw;sy=(ey-top)*h/sh;expect_rgb=pixel(sx,sy);end
                if(write_data!=={expect_rgb,8'h00}) begin
                    $display("pixel=(%0d,%0d) actual=%08x expect=%06x00",ex,ey,write_data,expect_rgb);
                    fail("golden pixel mismatch");
                end
                if(o_x!==ex || o_y!==ey || o_border_flag!==expect_border || o_last!==(output_count==307199))
                    fail("coordinate/border/last mismatch");
                output_count=output_count+1;checked_pixels=checked_pixels+1;
            end
        end
    end

    // 独立检查 scaler 的逐行源输入，不能仅凭最终画面掩盖重复/漏掉的源像素。
    // 每个新请求对应第一个尚未覆盖的目标图像行，放大时重复源行由 scaler 复用。
    always @(posedge video_clk) begin
        if(rst || (load_start && ready)) begin
            row_pixels=0;source_rows=0;source_pixels=0;next_dst_row=0;
            expected_src_y=0;source_row_active=0;
        end else if(checking && !abort && debug_state!=12) begin
            if(dut.line_ready && !source_row_active) begin
                if(next_dst_row>=sh)fail("unexpected extra source row request");
                expected_src_y=next_dst_row*h/sh;
                if(dut.source_y!==expected_src_y)fail("requested source_y differs from nearest-neighbor schedule");
                source_row_active=1;row_pixels=0;source_rows=source_rows+1;
            end
            if(dut.pixel_valid) begin
                if(!dut.line_ready || !source_row_active || row_pixels>=w)
                    fail("source RGB pulse outside requested row");
                if(dut.source_y!==expected_src_y || dut.pixel_rgb!==pixel(row_pixels,expected_src_y))
                    fail("source RGB/row order mismatch before scaler");
                row_pixels=row_pixels+1;source_pixels=source_pixels+1;
            end
            if(source_row_active && !dut.line_ready) begin
                if(row_pixels!=w)fail("source row does not contain exactly width RGB pulses");
                while(next_dst_row<sh && next_dst_row*h/sh==expected_src_y)
                    next_dst_row=next_dst_row+1;
                source_row_active=0;
            end
        end
        // 两个时钟的边沿刻意不重合：邮箱不能在 video 消费期间被 SD 改写。
        if(!rst && !dut.vr && (debug_state==5 || debug_state==6) && dut.sd_active)
            fail("video sector RAM read overlaps an active SD fill");
    end
    always @(posedge sd_clk) begin
        if(!rst && !dut.sr && dut.sd_active && sd_sec_read_data_valid && dut.sd_count<512 &&
           (debug_state==5 || debug_state==6))
            fail("SD sector RAM write overlaps video byte consumption");
    end

    task reset_all;
        begin
            @(negedge video_clk);rst=1;load_start=0;abort=0;checking=0;
            repeat(4)@(negedge video_clk);rst=0;
            repeat(5)@(negedge video_clk);
            output_count=0;previous_en=0;sector_count=0;early_finish_sent=0;stall_finish=0;finish_coincident=0;
            if(!ready || busy || img_loaded || error_code || done) fail("reset recovery");
        end
    endtask
    task launch;
        begin
            @(negedge video_clk);if(!ready)fail("not ready");load_start=1;
            @(negedge video_clk);load_start=0;
        end
    endtask
    task complete_good_frame;
        integer timeout;
        begin
            checking=0;launch;checking=1;timeout=0;
            while(!done && timeout<9000000)begin @(negedge video_clk);timeout=timeout+1;end
            if(!done || !img_loaded || format_error || error_code || output_count!=307200 || write_abort_req)
                fail("successful completion status");
            if(finish_wait!=-2)fail("loaded without commit");
            if(source_row_active || next_dst_row!=sh || source_pixels!=source_rows*w)
                fail("source row schedule incomplete at frame completion");
            checking=0;frames=frames+1;
            repeat(3)@(negedge video_clk);
            if(done || !img_loaded || write_en || write_req || !ready)fail("success sticky/pulse semantics");
            $display("PASS bridge frame=%0d src=%0dx%0d top_down=%0d offset=%0d stride=%0d sectors=%0d pixels=%0d cycles=%0d",frames,w,h,td,offset,stride,sector_count,output_count,timeout);
            $display("PASS bridge source_schedule rows=%0d rgb_pulses=%0d final_dst_row=%0d",source_rows,source_pixels,next_dst_row);
        end
    endtask
    task good_frame;
        input integer iw,ih,itop,ioffset;
        begin
            tests=tests+1;reset_all;fault_mode=0;frame=frame+1;make_header(iw,ih,itop,ioffset);
            complete_good_frame;
        end
    endtask
    // 不复位 DUT，重置的仅是测试平台的下一帧接收器与计数器。
    task rearm_model;
        begin
            checking=0;
            @(negedge video_clk);
            if(!ready || write_req || write_en)fail("not idle before restart without reset");
            output_count=0;previous_en=0;sector_count=0;early_finish_sent=0;stall_finish=0;finish_coincident=0;
            ack_phase=0;ack_wait=0;finish_wait=-1;
        end
    endtask
    task restart_without_reset_test;
        integer timeout;
        begin
            tests=tests+1;reset_all;fault_mode=0;make_header(1,1,1,54);header[28]=32;
            launch;timeout=0;
            while(!done && timeout<6000)begin @(negedge video_clk);timeout=timeout+1;end
            if(!done || !ready || !format_error || error_code!=8'h15 || img_loaded)
                fail("bad format did not leave a reusable transaction");
            $display("PASS bridge restart format_error_without_reset");
            rearm_model;tests=tests+1;bmp_start_sector=79;frame=frame+1;make_header(1,1,1,509);
            complete_good_frame;
            rearm_model;tests=tests+1;bmp_start_sector=123;frame=frame+1;make_header(2,2,0,507);
            finish_coincident=1;
            complete_good_frame;
            if(bmp_start_sector!=123 || !img_loaded)fail("second LBA restart did not complete");
            $display("PASS bridge restart format_error_to_success_then_success different_lba no_reset");
            $display("PASS bridge commit write_finish_coincident_with_last_pixel");
            bmp_start_sector=20;
        end
    endtask
    task bad_test;
        input integer mode,expected;
        integer timeout;
        begin
            tests=tests+1;reset_all;frame=1;make_header(7,5,1,54);fault_mode=0;
            case(mode)
                0:header[28]=32;
                1:put32(30,1);
                2:fault_mode=1;
                3:fault_mode=2;
                4:fault_mode=3;
                5:begin bmp_start_sector=32'hffffffff;make_header(640,480,1,54);end
            endcase
            launch;timeout=0;
            while(!done && timeout<6000)begin @(negedge video_clk);timeout=timeout+1;end
            if(!done || img_loaded || error_code!=expected || write_en || write_req)fail("rejection code/status");
            if(mode<2 || mode==5)begin if(!format_error || !ready)fail("format rejection not reusable");end
            else begin if(ready || !busy || format_error)fail("I/O error did not lock");end
            $display("PASS bridge reject mode=%0d code=%02x format_error=%0d",mode,error_code,format_error);
            bmp_start_sector=20;
        end
    endtask
    task abort_test;
        input integer after_grant;
        integer timeout;
        begin
            tests=tests+1;reset_all;fault_mode=0;make_header(640,480,1,54);checking=after_grant;launch;
            timeout=0;
            if(after_grant) while(output_count<640 && timeout<100000)begin @(negedge video_clk);timeout=timeout+1;end
            else while(!sd_sec_read && timeout<100)begin @(negedge video_clk);timeout=timeout+1;end
            @(negedge video_clk);abort=1;@(negedge video_clk);
            if(!done || error_code!=8'h30 || img_loaded || ready || write_en || write_req || write_abort_req!=after_grant)
                fail("abort lock/discard status");
            checking=0;abort=0;
            // SD 旧请求继续结束；故障仍保持，不能自动启动下一张图。
            repeat(700)@(negedge video_clk);
            load_start=1;@(negedge video_clk);load_start=0;
            if(ready || !busy || done || img_loaded)fail("late SD response unlocked old transaction");
            $display("PASS bridge abort after_grant=%0d late_sector_isolated",after_grant);
        end
    endtask
    task video_timeout_test;
        input integer after_output;
        integer timeout;
        begin
            tests=tests+1;reset_all;fault_mode=0;make_header(3,2,1,54);
            checking=after_output;stall_finish=1;launch;timeout=0;
            while(!done && timeout<400000)begin @(negedge video_clk);timeout=timeout+1;end
            if(!done || error_code!=8'h24 || img_loaded || ready || !busy || format_error ||
               !write_abort_req || write_en || write_req)
                fail("video timeout/discard status");
            if(after_output && output_count!=307200)fail("commit timeout occurred before full output");
            if(!after_output && output_count!=0)fail("unacknowledged frame produced pixels");
            checking=0;
            $display("PASS bridge video timeout after_output=%0d pixels=%0d partial_frame_discard=%0d",after_output,output_count,write_abort_req);
        end
    endtask
    task abort_ack_collision_test;
        integer timeout;
        begin
            tests=tests+1;reset_all;fault_mode=0;make_header(1,1,1,54);launch;timeout=0;
            while(!write_req && timeout<10000)begin @(negedge video_clk);timeout=timeout+1;end
            if(!write_req || write_req_ack)fail("could not isolate frame request before ACK");
            // 同一上升沿，写端确认先前已看到的请求，而桥接收到取消。
            // abort 会组合屏蔽 write_req，不能用已屏蔽的输出推断写端未分配帧。
            write_req_ack=1;abort=1;
            @(negedge video_clk);
            if(!done || error_code!=8'h30 || !write_abort_req || ready || write_en || write_req || img_loaded)
                fail("same-edge ACK/abort lost the partial-frame discard request");
            abort=0;write_req_ack=0;
            repeat(100)@(negedge video_clk);
            if(ready || !busy || write_en || img_loaded || !write_abort_req)
                fail("same-edge ACK/abort did not remain locked");
            $display("PASS bridge abort_ack_collision discard_preserved");
        end
    endtask
    task abort_inflight_pixel_test;
        input integer after_red;
        integer timeout;
        begin
            tests=tests+1;reset_all;fault_mode=0;make_header(640,480,1,54);checking=1;launch;
            timeout=0;
            while(timeout<10000 && !((!dut.header_mode && debug_state==6 && dut.component==2 && !after_red) ||
                                     (dut.pixel_valid && after_red))) begin
                @(negedge video_clk);timeout=timeout+1;
            end
            if(timeout==10000 || output_count!=0)fail("did not reach first in-flight RGB cancellation point");
            abort=1;
            @(negedge video_clk);
            if(!done || error_code!=8'h30 || !write_abort_req || img_loaded || ready || write_en || write_req)
                fail("in-flight RGB abort status/discard request");
            checking=0;abort=0;
            repeat(160) begin
                @(negedge video_clk);
                if(write_en || write_req || img_loaded || dut.pixel_valid || ready)
                    fail("in-flight RGB escaped after cancellation");
            end
            load_start=1;@(negedge video_clk);load_start=0;
            if(ready || !busy || done || error_code!=8'h30)fail("cancelled pipeline accepted a new frame");
            $display("PASS bridge abort_inflight after_red=%0d pipeline_discarded",after_red);
        end
    endtask
    initial begin
        repeat(3)@(negedge video_clk);rst=0;
        bad_test(0,8'h15);bad_test(1,8'h16);bad_test(2,8'h20);bad_test(3,8'h20);bad_test(4,8'h21);bad_test(5,8'h22);
        abort_test(0);abort_test(1);
        video_timeout_test(0);video_timeout_test(1);
        good_frame(3,2,0,510); // BGR 像素跨扇区，底向上，含 padding
        good_frame(7,5,1,513); // 非54偏移、顶部向下、多个相邻行共享扇区
        good_frame(640,480,0,54); // 默认直通尺寸，真实 BGR/行方向仍需处理
        good_frame(1280,1024,1,511); // 缩小，每源行最多9扇区
        good_frame(170,2,1,512); // 每行510字节，扇区最后两字节为padding，下一行从0开始
        good_frame(171,2,1,511); // 第一行首像素跨扇区，有效行最后R字节恰在扇区511
        restart_without_reset_test; // 最小图像、不同LBA，拒绝后恢复及成功后复用
        abort_inflight_pixel_test(0); // 已收G，下一拍原计划收R
        abort_inflight_pixel_test(1); // 已拼RGB，尚未被scaler采样的寄存脉冲
        abort_ack_collision_test;
        $display("PASS tb_contest_scaler_bridge tests=%0d frames=%0d checked_pixels=%0d clock_video_ns=40 clock_sd_ns=10",tests,frames,checked_pixels);
        $finish;
    end
    initial begin #1000000000;$display("FAIL bridge watchdog");$finish;end
endmodule

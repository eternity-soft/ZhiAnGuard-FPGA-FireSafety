`timescale 1ns/1ps
// 真实 manager + bmp_read + CDC + bridge + parser + scaler。
// SD控制器/SRAM提交端为明确的行为模型，不用于SPI电气或SDRAM时序签核。
module tb_v08_chain;
    reg sd_clk=0,video_clk=0,rst=1,key_next=1;
    always #5 sd_clk=~sd_clk;
    initial begin #3;forever #20 video_clk=~video_clk;end
    wire [31:0] load_sector,load_sector_v,bridge_lba,sd_lba;
    wire load_start,load_start_v,load_busy,takeover,io_reset,sd_read,bridge_read;
    wire bridge_ready,bridge_done,bridge_loaded,bridge_error,bridge_abort;
    wire req,en,last,border,done_sd,error_sd,pixel_sd,start_ready,start_overrun,finish_v;
    wire [31:0] data;
    wire [9:0] x;
    wire [8:0] y;
    wire display_valid,catalog,init_done,abort_req;
    wire [1:0] disp_buf,write_buf,image_idx,load_idx;
    reg abort_ack=0,ack=0,finish_toggle=0;
    wire [7:0] sd_data;
    wire sd_valid,sd_end;
    assign takeover=load_busy;
    contest_sd_card_bmp #(.CLK_FREQ_HZ(1000000),.SCAN_START_SECTOR(0),.SCAN_MAX_SECTOR(2813),
        .SCAN_TARGET_COUNT(2),.LOAD_TIMEOUT_MS(500000),.INIT_TIMEOUT_MS(500000),
        .RECOVERY_PAUSE_MS(2),.PREFETCH_GUARD_MS(2),.EXTERNAL_SCALER(1)) manager (
        .clk(sd_clk),.rst(rst),.key_next(key_next),.key_auto(1'b1),.key_period(1'b1),
        .state_code(),.auto_period_sel(),.bmp_width(16'd640),.bmp_height(16'd480),
        .display_valid(display_valid),.auto_play_active(),.current_image_idx(image_idx),
        .manual_audio_toggle(),.manual_audio_image_idx(),.write_finish_toggle(finish_toggle),
        .write_abort_req(abort_req),.write_abort_ack(abort_ack),.write_buf_idx(write_buf),.disp_buf_idx(disp_buf),
        .write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
        .load_sector_out(load_sector),.load_start_pulse_out(load_start),.load_busy_out(load_busy),
        .load_idx_out(load_idx),.catalog_ready_out(catalog),.sd_init_done_out(init_done),
        .sd_sec_read_o(sd_read),.sd_sec_read_addr_o(sd_lba),.sd_sec_read_i(bridge_read),.sd_sec_read_addr_i(bridge_lba),
        .sd_bus_takeover(takeover),.ext_pixel_inc(pixel_sd),.ext_source_done(done_sd),
        .ext_source_error(error_sd || start_overrun),.bridge_reset_out(io_reset),
        .sd_sec_read_data_o(sd_data),.sd_sec_read_data_valid_o(sd_valid),.sd_sec_read_end_o(sd_end)
    );
    contest_scaler_cdc cdc (
        .sd_clk(sd_clk),.video_clk(video_clk),.rst(rst),.io_reset_sd(io_reset),
        .load_start_sd(load_start),.load_sector_sd(load_sector),.load_ready_sd(start_ready),.load_overrun_sd(start_overrun),
        .bridge_ready_v(bridge_ready),.load_start_v(load_start_v),.load_sector_v(load_sector_v),
        .pixel_en_v(en),.pixel_inc_sd(pixel_sd),.bridge_done_v(bridge_done),.bridge_loaded_v(bridge_loaded),
        .source_done_sd(done_sd),.source_error_sd(error_sd),.finish_toggle_mem(finish_toggle),.finish_pulse_v(finish_v)
    );
    contest_scaler_bridge #(.MIN_SRC_WIDTH(640),.MIN_SRC_HEIGHT(480)) bridge (
        .sd_clk(sd_clk),.video_clk(video_clk),.rst(io_reset),.load_start(load_start_v),.bmp_start_sector(load_sector_v),
        .abort(1'b0),.ready(bridge_ready),.busy(),.done(bridge_done),.img_loaded(bridge_loaded),
        .format_error(bridge_error),.error_code(),.write_abort_req(bridge_abort),
        .sd_sec_read(bridge_read),.sd_sec_read_addr(bridge_lba),.sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),.write_req(req),.write_req_ack(ack),
        .write_en(en),.write_data(data),.write_finish(finish_v),.o_x(x),.o_y(y),.o_border_flag(border),.o_last(last),.debug_state()
    );
    integer pixels=0,total_pixels=0,frames=0,successes=0,failures=0,ack_state=0,delay_count=0,finish_wait=-1;
    integer w,h,sh,off_y,sx,sy,ex,ey,timeout;
    reg [23:0] expected;
    reg [1:0] frame_idx=0;
    reg [9:0] previous_x=0;
    reg previous_en=0;
    integer inject_short=0;
    function [23:0] source_pixel;
        input integer img,px,py;
        begin source_pixel=((img+1)<<20)|(py<<10)|px;end
    endfunction
    function [23:0] quality_box_pixel;
        input integer img,ox,oy,iw,ih;
        integer xs,ys,xp,yp,x0,x1,y0,y1;
        integer rr,gg,bb;
        reg [23:0] a,b,c,d;
        begin
            xs=((iw-1)*65536)/639;ys=((ih-1)*65536)/479;
            xp=ox*xs;yp=oy*ys;x0=xp>>16;y0=yp>>16;
            if(ox==639)x0=iw-1;if(oy==479)y0=ih-1;
            x1=(x0+1>=iw)?x0:x0+1;y1=(y0+1>=ih)?y0:y0+1;
            a=source_pixel(img,x0,y0);b=source_pixel(img,x1,y0);
            c=source_pixel(img,x0,y1);d=source_pixel(img,x1,y1);
            rr=(a[23:16]+b[23:16]+c[23:16]+d[23:16]+2)>>2;
            gg=(a[15:8]+b[15:8]+c[15:8]+d[15:8]+2)>>2;
            bb=(a[7:0]+b[7:0]+c[7:0]+d[7:0]+2)>>2;
            quality_box_pixel={rr[7:0],gg[7:0],bb[7:0]};
        end
    endfunction
    task fail;input [8*140-1:0] msg;begin
        $display("FAIL chain frames=%0d pixels=%0d manager_state=%0d %0s",frames,pixels,manager.recovery_state,msg);$finish;
    end endtask
    // 写通道模型：四阶段帧ACK；最后像素之后才翻转真实提交toggle。
    always @(negedge video_clk)begin
        if(rst || io_reset)begin ack=0;ack_state=0;delay_count=0;finish_wait=-1;previous_en=0;end
        else begin
            case(ack_state)
                0:if(req)begin
                    frame_idx=load_idx;pixels=0;previous_en=0;finish_wait=-1;delay_count=4;ack_state=1;
                end
                1:if(delay_count==0)begin ack=1;ack_state=2;end else delay_count=delay_count-1;
                2:if(!req)begin ack=0;ack_state=3;end
                3:if(pixels==307200 && finish_wait==-1)finish_wait=8;
            endcase
            if(finish_wait>0)finish_wait=finish_wait-1;
            else if(finish_wait==0)begin finish_toggle=~finish_toggle;finish_wait=-2;ack_state=0;frames=frames+1;end
        end
    end
    // 模拟存储取消请求/确认，允许在尚未写入像素时取消。
    always @(posedge sd_clk)begin
        if(rst)abort_ack<=0;
        else abort_ack<=abort_req;
        if(!rst && takeover && !io_reset && manager.sd_card_top_m0.rst)fail("takeover reset the SD controller");
        if(!rst && takeover && !io_reset && !manager.sd_init_done)fail("SD initialization lost during takeover");
        if(!rst && takeover && (manager.bmp_write_req || manager.sd_sec_read))fail("legacy reader competed for bus");
        if(!rst && done_sd)begin
            if(manager.pixels_sent!=307200)fail("external pixel count differs from canvas size");
            successes=successes+1;
            $display("PASS chain source_commit idx=%0d counted_pixels=%0d",load_idx,manager.pixels_sent);
        end
        if(!rst && error_sd)failures=failures+1;
    end
    always @(posedge video_clk)if(!rst && !io_reset)begin
        if(previous_en && previous_x!=639 && !en)fail("gap inside destination row");
        previous_en=en;previous_x=x;
        if(en)begin
            if(ack_state!=3 || pixels>=307200)fail("write outside frame grant");
            w=(frame_idx==0)?800:1024;h=(frame_idx==0)?600:768;sh=h*640/w;off_y=(480-sh)/2;
            ex=pixels%640;ey=pixels/640;
            if(ey<off_y || ey>=off_y+sh)expected=24'h001030;
            else expected=quality_box_pixel(frame_idx,ex,ey-off_y,w,h);
            if(data!=={expected,8'd0} || x!==ex || y!==ey || last!==(pixels==307199))fail("golden canvas mismatch");
            pixels=pixels+1;total_pixels=total_pixels+1;
        end
    end
    initial begin
        #501;rst=0;timeout=0;
        while(!manager.prefetch_done && timeout<8000000)begin @(negedge video_clk);timeout=timeout+1;end
        if(!manager.prefetch_done || !display_valid || image_idx!=0 || disp_buf!=0 || successes!=2 || failures!=0)
            fail("first frame or next-image prefetch did not complete");
        $display("PASS chain initial_display_and_prefetch display_idx=%0d cached_idx=%0d",image_idx,manager.prefetched_img_idx);
        // 按键命中预取后切换；下次预取注入坏扇区，验证旧画面不受错误帧污染。
        inject_short=1;key_next=0;
        repeat(21000)@(negedge sd_clk);key_next=1;
        timeout=0;
        while(manager.recovery_count==0 && timeout<100000)begin @(negedge sd_clk);timeout=timeout+1;end
        if(manager.recovery_count!=1 || image_idx!=1 || disp_buf!=1 || !display_valid || failures!=1)
            fail("bad bridge transaction did not recover while preserving display");
        inject_short=0;timeout=0;
        while((!manager.prefetch_done || successes<3) && timeout<4000000)begin @(negedge video_clk);timeout=timeout+1;end
        if(!manager.prefetch_done || successes!=3 || frames!=3 || image_idx!=1 || disp_buf!=1 || manager.recovery_state!=0)
            fail("retry after coordinated SD/bridge/writer reset");
        if(total_pixels!=921600)fail("wrong total output pixel count");
        $display("PASS chain manual_prefetch_swap recovery_retry display_preserved successes=%0d errors=%0d",successes,failures);
        $display("PASS tb_v08_chain frames=%0d checked_pixels=%0d",frames,total_pixels);$finish;
    end
    initial begin #1000000000;fail("watchdog");end
endmodule

// 本测试专用SD扇区模型。综合工程仍使用原始SD/sd_card_top.v。
module sd_card_top (
    input wire clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
    input wire [31:0] sd_sec_read_addr,sd_sec_write_addr,
    input wire [7:0] sd_sec_write_data,
    output wire SD_nCS,SD_DCLK,SD_MOSI,
    output reg sd_init_done,
    output reg [7:0] sd_sec_read_data,
    output reg sd_sec_read_data_valid,sd_sec_read_end,
    output wire sd_sec_write_data_req,sd_sec_write_end
);
    initial begin sd_init_done=0;sd_sec_read_data=0;sd_sec_read_data_valid=0;sd_sec_read_end=0;end
    assign SD_nCS=1'b1;assign SD_DCLK=clk;assign SD_MOSI=1'b1;
    assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
    integer state=0,n=0,gap=0,limit=512,img,w,h,stride,len,p,fr,px,phase,file_pos,base_lba;
    reg [31:0] active_lba;
    reg [7:0] header[0:53];
    reg [23:0] rgb;
    task put32;input integer a;input [31:0] v;begin
        header[a]=v;header[a+1]=v>>8;header[a+2]=v>>16;header[a+3]=v>>24;
    end endtask
    always @(negedge clk)begin
        sd_sec_read_data_valid=0;sd_sec_read_end=0;
        if(rst)begin sd_init_done=0;state=0;n=0;end
        else begin
            sd_init_done=1;
            case(state)
                0:if(sd_sec_read)begin
                    active_lba=sd_sec_read_addr;
                    if(active_lba>7421)tb_v08_chain.fail("unexpected file sector");
                    img=(active_lba>=2813);base_lba=img==0?0:2813;
                    w=img==0?800:1024;h=img==0?600:768;stride=((w*3+3)/4)*4;len=54+stride*h;
                    for(n=0;n<54;n=n+1)header[n]=0;
                    header[0]=8'h42;header[1]=8'h4d;put32(2,len);put32(10,54);put32(14,40);
                    put32(18,w);put32(22,img==0?h:-h);header[26]=1;header[28]=24;put32(34,stride*h);
                    n=0;gap=0;state=1;limit=tb_v08_chain.inject_short?511:512;
                end
                1:begin
                    if(sd_sec_read_addr!==active_lba)tb_v08_chain.fail("LBA changed during SD transfer");
                    gap=gap+1;
                    if(gap%7!=0)begin
                        file_pos=(active_lba-base_lba)*512+n;
                        if(file_pos<54)sd_sec_read_data=header[file_pos];
                        else if(file_pos<len)begin
                            p=file_pos-54;fr=p/stride;px=(p%stride)/3;phase=(p%stride)%3;
                            rgb=tb_v08_chain.source_pixel(img,px,img==0?h-1-fr:fr);
                            if(p%stride>=w*3)sd_sec_read_data=8'hee;
                            else case(phase)0:sd_sec_read_data=rgb[7:0];1:sd_sec_read_data=rgb[15:8];default:sd_sec_read_data=rgb[23:16];endcase
                        end else sd_sec_read_data=8'hdd;
                        sd_sec_read_data_valid=1;
                        if(n==limit-1)begin sd_sec_read_end=1;state=2;end
                        n=n+1;
                    end
                end
                2:if(!sd_sec_read)state=0;
            endcase
        end
    end
endmodule

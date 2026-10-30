`timescale 1ns/1ps
module tb_contest_image_scaler;
    reg clk,rst,start,abort,cfg_format_valid,bmp_data_wr_en,write_req_ack;
    reg [15:0] cfg_src_width,cfg_src_height;
    reg [23:0] bmp_data;
    wire ready,busy,done,o_format_error,o_line_ready,write_req,write_en;
    wire [3:0] error;
    wire [15:0] o_src_y;
    wire [23:0] write_data;
    wire [9:0] o_x,scaled_width,offset_x;
    wire [8:0] o_y,scaled_height,offset_y;
    wire o_border_flag,o_sof,o_eol,o_last;
    integer test_count,frame_count,total_golden_pixels,total_input_pixels;
    integer expected_rows[0:479];
    reg [31:0] prng;
    contest_image_scaler dut(
        .clk(clk),.rst(rst),.start(start),.abort(abort),
        .cfg_src_width(cfg_src_width),.cfg_src_height(cfg_src_height),
        .cfg_format_valid(cfg_format_valid),.bmp_data_wr_en(bmp_data_wr_en),
        .bmp_data(bmp_data),.write_req_ack(write_req_ack),.ready(ready),
        .busy(busy),.done(done),.o_format_error(o_format_error),.error(error),
        .o_line_ready(o_line_ready),.o_src_y(o_src_y),.write_req(write_req),
        .write_en(write_en),.write_data(write_data),.o_x(o_x),.o_y(o_y),
        .o_border_flag(o_border_flag),.o_sof(o_sof),.o_eol(o_eol),.o_last(o_last),
        .scaled_width(scaled_width),.scaled_height(scaled_height),
        .offset_x(offset_x),.offset_y(offset_y)
    );
    initial begin clk=0; forever #20 clk=~clk; end // 25 MHz
    initial begin #1000000000; $display("FAIL scaler global timeout"); $finish; end

    task fail;
        input [511:0] msg;
        begin
            $display("FAIL scaler test=%0d t=%0t: %0s",test_count,$time,msg);
            $finish;
        end
    endtask
    task rand_next;
        begin
            prng=prng^(prng<<13); prng=prng^(prng>>17); prng=prng^(prng<<5);
        end
    endtask
    // Unique coordinate coding throughout the supported source image.
    function [23:0] pixel;
        input integer x,y,frame;
        begin pixel=((frame&7)<<21)|((y&1023)<<11)|(x&2047); end
    endfunction
    task begin_frame;
        input integer w,h,fmt;
        begin
            @(negedge clk);
            if (!ready) fail("not ready at frame start");
            cfg_src_width=w; cfg_src_height=h; cfg_format_valid=fmt;
            start=1; bmp_data_wr_en=1; bmp_data=24'hbada55; write_req_ack=0;
            @(posedge clk); #1;
            // Poison on accepted start must not become a source pixel.
            @(negedge clk); start=0; bmp_data_wr_en=0;
        end
    endtask
    task acknowledge_frame;
        integer timeout;
        begin
            timeout=0;
            while (!write_req && timeout<110) begin
                @(negedge clk); timeout=timeout+1;
            end
            if (!write_req) fail("frame request timeout");
            write_req_ack=1;
            repeat (3) begin
                @(posedge clk); #1;
                if (write_en || o_line_ready) fail("activity before ack goes low");
                @(negedge clk);
            end
            if (write_req) fail("request not dropped after ack");
            write_req_ack=0;
        end
    endtask

    // Every emitted pixel is compared with a direct integer golden formula.
    // Golden source-row requests are separately derived by removing repeated
    // floor(v*H/scaledH) values; neither checker copies the RTL DDA recurrence.
    task run_frame;
        input integer w,h,input_bubbles;
        integer sw,sh,left,top,v,sy,last_sy,expected_requests;
        integer received,sent,requests,ix,requested_y,cycle,ex,ey,sx;
        integer ack_phase,ack_delay,ack_high_delay,sof_count,eol_count,last_count;
        integer expected_border,border_count,saw_done,request_seen;
        reg previous_line_ready;
        reg [23:0] expected_rgb;
        begin
            test_count=test_count+1; frame_count=frame_count+1;
            if (w*480 >= h*640) begin sw=640; sh=h*640/w; end
            else begin sh=480; sw=w*480/h; end
            if (sw<1) sw=1; if (sh<1) sh=1;
            left=(640-sw)/2; top=(480-sh)/2;
            expected_requests=0; last_sy=-1;
            for (v=0;v<sh;v=v+1) begin
                sy=v*h/sh;
                if (sy!=last_sy) begin
                    expected_rows[expected_requests]=sy;
                    expected_requests=expected_requests+1; last_sy=sy;
                end
            end
            begin_frame(w,h,1);
            received=0;sent=0;requests=0;ix=0;requested_y=0;cycle=0;
            ack_phase=0;ack_delay=0;ack_high_delay=0;previous_line_ready=0;
            sof_count=0;eol_count=0;last_count=0;border_count=0;saw_done=0;
            request_seen=0;
            while (!saw_done && cycle<1600000) begin
                @(negedge clk);
                // Latched config and busy-start immunity are exercised throughout.
                cfg_src_width=0;cfg_src_height=65535;cfg_format_valid=0;
                start=(cycle==7)||(cycle==105)||(cycle==50000);
                if (ack_phase==0) begin
                    if (write_req) begin
                        request_seen=1;ack_delay=ack_delay+1;
                        if (ack_delay==5) begin write_req_ack=1;ack_phase=1;end
                    end else if (request_seen) fail("request dropped before ack");
                end else if (ack_phase==1) begin
                    if (!write_req) begin
                        ack_high_delay=ack_high_delay+1;
                        if (ack_high_delay==7) begin write_req_ack=0;ack_phase=2;end
                    end
                end
                if (o_line_ready && !previous_line_ready) begin
                    if (requests>=expected_requests) fail("extra source-row request");
                    if (o_src_y!==expected_rows[requests]) begin
                        $display("request=%0d got_y=%0d expected_y=%0d",requests,o_src_y,expected_rows[requests]);
                        fail("wrong/repeated/skipped source-row request");
                    end
                    requested_y=o_src_y;requests=requests+1;ix=0;
                end
                if (!o_line_ready && previous_line_ready && ix!=w)
                    fail("source row closed before exact source width");
                previous_line_ready=o_line_ready;
                rand_next;
                bmp_data_wr_en=o_line_ready && (!input_bubbles || (prng[2:0]!=0));
                bmp_data=pixel(ix,requested_y,frame_count);
                if (o_line_ready && (o_src_y!==requested_y)) fail("source row changed during capture");
                if ((ack_phase!=2) && (write_en || o_line_ready))
                    fail("pixels or row request before four-phase handshake completes");
                @(posedge clk);
                if (bmp_data_wr_en && o_line_ready) begin ix=ix+1;sent=sent+1;end
                if ((received%640)!=0 && !write_en) fail("gap inside output row");
                if (write_en) begin
                    if (received>=307200) fail("extra output pixel");
                    ex=received%640;ey=received/640;
                    expected_border=(ex<left)||(ex>=left+sw)||(ey<top)||(ey>=top+sh);
                    if (expected_border) begin
                        expected_rgb=24'h001030;border_count=border_count+1;
                    end else begin
                        sx=(ex-left)*w/sw;sy=(ey-top)*h/sh;
                        expected_rgb=pixel(sx,sy,frame_count);
                    end
                    if (write_data!==expected_rgb) begin
                        $display("out=(%0d,%0d) got=%h expected=%h",ex,ey,write_data,expected_rgb);
                        fail("golden RGB mismatch");
                    end
                    if ((o_x!==ex)||(o_y!==ey)) fail("output coordinate/order mismatch");
                    if (o_border_flag!==expected_border[0]) fail("border flag mismatch");
                    if (o_sof!==((ex==0)&&(ey==0))) fail("SOF mismatch");
                    if (o_eol!==(ex==639)) fail("EOL mismatch");
                    if (o_last!==(received==307199)) fail("LAST mismatch");
                    if (o_sof) sof_count=sof_count+1;
                    if (o_eol) eol_count=eol_count+1;
                    if (o_last) last_count=last_count+1;
                    received=received+1;
                end
                if (done) begin
                    saw_done=1;
                    if (received!=307200) fail("done before complete output frame");
                    if (requests!=expected_requests || sent!=w*expected_requests)
                        fail("source request/count mismatch at done");
                    if (error || o_format_error || busy || !ready) fail("completion status mismatch");
                    if ((scaled_width!==sw)||(scaled_height!==sh)||
                        (offset_x!==left)||(offset_y!==top)) fail("fit geometry mismatch");
                end
                cycle=cycle+1;
            end
            if (!saw_done) fail("frame timeout");
            if (sof_count!=1 || eol_count!=480 || last_count!=1) fail("sideband totals");
            if (border_count!=307200-sw*sh) fail("border count mismatch");
            @(negedge clk);start=0;bmp_data_wr_en=0;
            repeat (3) begin
                @(posedge clk);#1;
                if (write_en || done || write_req || o_line_ready || !ready) fail("post-frame not idle");
            end
            total_golden_pixels=total_golden_pixels+received;
            total_input_pixels=total_input_pixels+sent;
            $display("PASS scaler frame=%0d src=%0dx%0d fit=%0dx%0d offset=(%0d,%0d) rows=%0d input=%0d output=%0d border=%0d cycles=%0d bubbles=%0d",
                     frame_count,w,h,sw,sh,left,top,requests,sent,received,border_count,cycle,input_bubbles);
        end
    endtask

    task invalid_config;
        input integer w,h,fmt,expected_error;
        begin
            test_count=test_count+1;
            @(negedge clk);
            cfg_src_width=w;cfg_src_height=h;cfg_format_valid=fmt;start=1;
            bmp_data_wr_en=0;write_req_ack=0;
            @(posedge clk);#1;
            if (!done || error!==expected_error || !o_format_error || !ready || busy)
                fail("invalid-config status mismatch");
            if (write_req || write_en || o_line_ready || scaled_width || scaled_height)
                fail("invalid-config produced activity");
            @(negedge clk);start=0;
            repeat (3) begin
                @(posedge clk);#1;
                if (done || error!==expected_error || !o_format_error)
                    fail("error not sticky or done not one pulse");
            end
            $display("PASS scaler reject src=%0dx%0d format=%0d error=%0d",w,h,fmt,expected_error);
        end
    endtask

    task prepare_small_row;
        integer n,timeout;
        begin
            acknowledge_frame;
            timeout=0;
            while (!o_line_ready && timeout<10) begin
                @(negedge clk);timeout=timeout+1;
            end
            if (!o_line_ready) fail("small-row request timeout");
            for (n=0;n<2;n=n+1) begin
                bmp_data_wr_en=1;bmp_data=pixel(n,0,7);
                @(posedge clk);#1;
                @(negedge clk);
            end
            bmp_data_wr_en=0;
        end
    endtask
    task cancel_test;
        input integer mode; // setup, partial row, request wait, output abort, output reset
        integer timeout;
        begin
            test_count=test_count+1;
            begin_frame(2,2,1);
            if (mode==1) begin
                acknowledge_frame;
                timeout=0;
                while (!o_line_ready && timeout<10) begin @(negedge clk);timeout=timeout+1;end
                if (!o_line_ready) fail("cancel row timeout");
                bmp_data_wr_en=1;bmp_data=24'h010203;
                @(posedge clk);#1;@(negedge clk);bmp_data_wr_en=0;
            end else if (mode==2) begin
                timeout=0;
                while (!write_req && timeout<110) begin @(negedge clk);timeout=timeout+1;end
                if (!write_req) fail("cancel request timeout");
            end else if (mode>=3) begin
                prepare_small_row;
                timeout=0;
                while ((!write_en || o_x<3) && timeout<20) begin @(negedge clk);timeout=timeout+1;end
                if (!write_en) fail("cancel output timeout");
            end
            @(negedge clk);start=1;bmp_data_wr_en=1;
            if (mode==4) rst=1; else abort=1;
            #1;
            if (write_en || write_req || o_line_ready) fail("cancel did not suppress interface");
            @(posedge clk);#1;
            if (done || error || o_format_error || busy || scaled_width || scaled_height)
                fail("cancel/reset status mismatch");
            @(negedge clk);rst=0;abort=0;start=0;bmp_data_wr_en=0;write_req_ack=0;
            repeat (3) begin
                @(posedge clk);#1;
                if (!ready || done || write_en || write_req || o_line_ready)
                    fail("cancel/reset left residual work");
            end
            $display("PASS scaler cancel/reset mode=%0d",mode);
        end
    endtask
    task protocol_error_test;
        input integer during_output;
        integer timeout;
        begin
            test_count=test_count+1;
            begin_frame(2,2,1);
            if (during_output) begin
                prepare_small_row;
                timeout=0;
                while (!write_en && timeout<10) begin @(negedge clk);timeout=timeout+1;end
                if (!write_en) fail("protocol-error output timeout");
            end
            @(negedge clk);bmp_data_wr_en=1;bmp_data=24'hdeadde;
            #1;
            if (write_en || write_req) fail("unexpected source pulse not suppressed");
            @(posedge clk);#1;
            if (!done || error!==4'd3 || !o_format_error || !ready)
                fail("unexpected source pulse not reported");
            @(negedge clk);bmp_data_wr_en=0;write_req_ack=0;
            @(posedge clk);#1;
            if (done || write_en || write_req || o_line_ready || error!==4'd3)
                fail("unexpected source pulse left activity");
            $display("PASS scaler source protocol violation during_output=%0d",during_output);
        end
    endtask

    initial begin
        rst=1;start=0;abort=0;cfg_format_valid=0;bmp_data_wr_en=0;write_req_ack=0;
        cfg_src_width=0;cfg_src_height=0;bmp_data=0;
        test_count=0;frame_count=0;total_golden_pixels=0;total_input_pixels=0;
        prng=32'h4d595df4;
        repeat (3) @(negedge clk);rst=0;
        invalid_config(640,480,0,1);
        invalid_config(0,480,1,2);
        invalid_config(640,0,1,2);
        invalid_config(1281,1024,1,2);
        invalid_config(1280,1025,1,2);
        invalid_config(1281,1025,1,2);
        invalid_config(65535,65535,1,2);
        cancel_test(0);cancel_test(1);cancel_test(2);cancel_test(3);cancel_test(4);
        protocol_error_test(0);protocol_error_test(1);
        run_frame(640,480,0);
        run_frame(320,240,1);
        run_frame(800,600,1);
        run_frame(1024,768,1);
        run_frame(480,480,1);
        run_frame(1280,1024,1);
        run_frame(1024,576,1);
        run_frame(319,239,1);
        run_frame(1,1,1);
        run_frame(1280,1,1);
        run_frame(1,1024,1);
        $display("PASS tb_contest_image_scaler tests=%0d frames=%0d golden_pixels=%0d requested_source_pixels=%0d seed=4d595df4 clock_period_ns=40",
                 test_count,frame_count,total_golden_pixels,total_input_pixels);
        $finish;
    end
endmodule

`timescale 1ns/1ps
module tb_contest_image_scaler_quality;
    reg clk=0,rst=1,start=0,abort=0,cfg_format_valid=0;
    reg bmp_data_wr_en=0,write_req_ack=0;
    reg [15:0] cfg_src_width=0,cfg_src_height=0;
    reg [23:0] bmp_data=0;
    wire ready,busy,done,o_format_error,o_line_ready,write_req,write_en;
    wire [3:0] error;
    wire [15:0] o_src_y;
    wire [23:0] write_data;
    wire [9:0] o_x,scaled_width,offset_x;
    wire [8:0] o_y,scaled_height,offset_y;
    wire o_border_flag,o_sof,o_eol,o_last;
    integer errors=0;
    integer source_mode=0;
    always #20 clk=~clk;

    contest_image_scaler dut(
        .clk(clk),.rst(rst),.start(start),.abort(abort),
        .cfg_src_width(cfg_src_width),.cfg_src_height(cfg_src_height),
        .cfg_format_valid(cfg_format_valid),.bmp_data_wr_en(bmp_data_wr_en),
        .bmp_data(bmp_data),.write_req_ack(write_req_ack),.ready(ready),.busy(busy),
        .done(done),.o_format_error(o_format_error),.error(error),
        .o_line_ready(o_line_ready),.o_src_y(o_src_y),.write_req(write_req),
        .write_en(write_en),.write_data(write_data),.o_x(o_x),.o_y(o_y),
        .o_border_flag(o_border_flag),.o_sof(o_sof),.o_eol(o_eol),.o_last(o_last),
        .scaled_width(scaled_width),.scaled_height(scaled_height),
        .offset_x(offset_x),.offset_y(offset_y)
    );

    task fail; input [8*120-1:0] msg; begin
        $display("FAIL quality_scaler %0s t=%0t",msg,$time); errors=errors+1;
    end endtask

    function [23:0] src_pixel;
        input integer x,y,mode;
        begin
            if(mode==0) begin
                if(y==0 && x==0) src_pixel=24'h000000;
                else if(y==0) src_pixel=24'hFF0000;
                else if(x==0) src_pixel=24'h00FF00;
                else src_pixel=24'hFFFFFF;
            end else begin
                src_pixel=((x&255)<<16)|((y&255)<<8)|((x+y)&255);
            end
        end
    endfunction

    task run_case;
        input integer w,h,expected_mode,check_x,check_y;
        integer cycles,ix,requested_y,row_requests,received;
        integer xstep,ystep,xphase,yphase,x0,x1,y0,y1,wx,wy;
        integer p00r,p00g,p00b,p10r,p10g,p10b,p01r,p01g,p01b,p11r,p11g,p11b;
        integer h0r,h0g,h0b,h1r,h1g,h1b,er,eg,eb;
        reg previous_line_ready,previous_write,saw_check;
        reg [9:0] previous_x;
        reg [23:0] expected;
        begin
            @(negedge clk);cfg_src_width=w;cfg_src_height=h;cfg_format_valid=1;start=1;
            @(posedge clk);#1;@(negedge clk);start=0;
            cycles=0;
            while(!write_req && cycles<120) begin @(negedge clk);cycles=cycles+1;end
            if(!write_req) fail("write request timeout");
            write_req_ack=1;repeat(2) @(negedge clk);write_req_ack=0;

            cycles=0;ix=0;requested_y=0;row_requests=0;received=0;
            previous_line_ready=0;previous_write=0;previous_x=0;saw_check=0;
            while(!done && cycles<2500000) begin
                @(negedge clk);
                if(o_line_ready && !previous_line_ready) begin
                    ix=0;requested_y=o_src_y;row_requests=row_requests+1;
                    if(row_requests==1 && dut.quality_mode!==expected_mode[1:0])
                        fail("wrong selected quality mode");
                end
                if(o_line_ready && o_src_y!==requested_y) fail("source row changed while loading");
                bmp_data_wr_en=o_line_ready;
                bmp_data=src_pixel(ix,requested_y,source_mode);
                previous_line_ready=o_line_ready;
                @(posedge clk);#1;
                if(bmp_data_wr_en && o_line_ready) ix=ix+1;
                if(previous_write && previous_x!=10'd639 && !write_en)
                    fail("gap inside output row");
                if(write_en) begin
                    received=received+1;
                    previous_x=o_x;
                    if(o_x==check_x && o_y==check_y) begin
                        xstep=((w-1)*65536)/(scaled_width-1);
                        ystep=((h-1)*65536)/(scaled_height-1);
                        xphase=(check_x-offset_x)*xstep;
                        yphase=(check_y-offset_y)*ystep;
                        x0=xphase>>16;y0=yphase>>16;
                        if(check_x==offset_x+scaled_width-1) begin x0=w-1;wx=0;end
                        else wx=(xphase>>8)&255;
                        if(check_y==offset_y+scaled_height-1) begin y0=h-1;wy=0;end
                        else wy=(yphase>>8)&255;
                        x1=(x0+1>=w)?x0:x0+1;y1=(y0+1>=h)?y0:y0+1;
                        expected=src_pixel(x0,y0,source_mode);
                        if(expected_mode==1) begin
                            p00r=src_pixel(x0,y0,source_mode)>>16;p00g=(src_pixel(x0,y0,source_mode)>>8)&255;p00b=src_pixel(x0,y0,source_mode)&255;
                            p10r=src_pixel(x1,y0,source_mode)>>16;p10g=(src_pixel(x1,y0,source_mode)>>8)&255;p10b=src_pixel(x1,y0,source_mode)&255;
                            p01r=src_pixel(x0,y1,source_mode)>>16;p01g=(src_pixel(x0,y1,source_mode)>>8)&255;p01b=src_pixel(x0,y1,source_mode)&255;
                            p11r=src_pixel(x1,y1,source_mode)>>16;p11g=(src_pixel(x1,y1,source_mode)>>8)&255;p11b=src_pixel(x1,y1,source_mode)&255;
                            h0r=p00r*(256-wx)+p10r*wx;h0g=p00g*(256-wx)+p10g*wx;h0b=p00b*(256-wx)+p10b*wx;
                            h1r=p01r*(256-wx)+p11r*wx;h1g=p01g*(256-wx)+p11g*wx;h1b=p01b*(256-wx)+p11b*wx;
                            er=(h0r*(256-wy)+h1r*wy+32768)>>16;
                            eg=(h0g*(256-wy)+h1g*wy+32768)>>16;
                            eb=(h0b*(256-wy)+h1b*wy+32768)>>16;
                            expected={er[7:0],eg[7:0],eb[7:0]};
                        end else if(expected_mode==2) begin
                            er=((src_pixel(x0,y0,source_mode)>>16)+(src_pixel(x1,y0,source_mode)>>16)+
                                (src_pixel(x0,y1,source_mode)>>16)+(src_pixel(x1,y1,source_mode)>>16)+2)>>2;
                            eg=(((src_pixel(x0,y0,source_mode)>>8)&255)+((src_pixel(x1,y0,source_mode)>>8)&255)+
                                ((src_pixel(x0,y1,source_mode)>>8)&255)+((src_pixel(x1,y1,source_mode)>>8)&255)+2)>>2;
                            eb=((src_pixel(x0,y0,source_mode)&255)+(src_pixel(x1,y0,source_mode)&255)+
                                (src_pixel(x0,y1,source_mode)&255)+(src_pixel(x1,y1,source_mode)&255)+2)>>2;
                            expected={er[7:0],eg[7:0],eb[7:0]};
                        end
                        if(write_data!==expected) begin
                            $display("mode=%0d point=(%0d,%0d) got=%h expected=%h",expected_mode,o_x,o_y,write_data,expected);
                            fail("quality pixel mismatch");
                        end
                        saw_check=1;
                    end
                end
                previous_write=write_en;
                cycles=cycles+1;
            end
            @(negedge clk);bmp_data_wr_en=0;
            if(!done) fail("frame timeout");
            if(received!=307200) fail("output frame pixel count");
            if(!saw_check) fail("quality checkpoint not observed");
            if(error||o_format_error) fail("unexpected scaler error");
            $display("PASS quality case src=%0dx%0d mode=%0d rows=%0d output=%0d",w,h,expected_mode,row_requests,received);
            repeat(3) @(posedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst=0;
        source_mode=0;run_case(2,2,1,320,240);       // bilinear enlargement
        source_mode=1;run_case(800,600,2,100,100);   // 2x2 shrink filter
        source_mode=1;run_case(640,480,0,100,100);   // exact nearest fallback
        if(errors==0) $display("PASS tb_contest_image_scaler_quality bilinear box nearest_fallback");
        else $display("FAIL tb_contest_image_scaler_quality errors=%0d",errors);
        $finish;
    end
    initial begin #300000000;fail("global watchdog");$finish;end
endmodule

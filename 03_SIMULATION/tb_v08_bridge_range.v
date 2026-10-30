`timescale 1ns/1ps
// V08生产配置的尺寸门限：小图不能发出帧写请求，拒绝后无需复位即可重试。
module tb_v08_bridge_range;
    reg sd_clk=0,video_clk=0,rst=1,start=0;
    always #5 sd_clk=~sd_clk;
    initial begin #3;forever #20 video_clk=~video_clk;end
    wire ready,done,loaded,error,req,en,sd_read;
    wire [7:0] code;
    wire [31:0] lba;
    reg [7:0] data=0,hdr[0:511];
    reg valid=0,rd_end=0;
    integer st=0,idx=0,tests=0,i,stride,size,timeout;
    contest_scaler_bridge #(.MIN_SRC_WIDTH(640),.MIN_SRC_HEIGHT(480)) dut (
        .video_clk(video_clk),.sd_clk(sd_clk),.rst(rst),.load_start(start),.bmp_start_sector(32'd8),
        .abort(1'b0),.ready(ready),.busy(),.done(done),.img_loaded(loaded),.format_error(error),.error_code(code),
        .write_abort_req(),.sd_sec_read(sd_read),.sd_sec_read_addr(lba),.sd_sec_read_data(data),
        .sd_sec_read_data_valid(valid),.sd_sec_read_end(rd_end),.write_req(req),.write_req_ack(1'b0),
        .write_en(en),.write_data(),.write_finish(1'b0),.o_x(),.o_y(),.o_border_flag(),.o_last(),.debug_state()
    );
    task fail;input [8*90-1:0] msg;begin $display("FAIL bridge_range test=%0d %0s",tests,msg);$finish;end endtask
    task put32;input integer a;input [31:0] v;begin
        hdr[a]=v;hdr[a+1]=v>>8;hdr[a+2]=v>>16;hdr[a+3]=v>>24;
    end endtask
    always @(negedge sd_clk)begin
        valid=0;rd_end=0;
        if(rst)begin st=0;idx=0;end
        else case(st)
            0:if(sd_read)begin if(lba!=8)fail("only header sector expected");idx=0;st=1;end
            1:begin data=hdr[idx];valid=1;if(idx==511)begin rd_end=1;st=2;end idx=idx+1;end
            2:if(!sd_read)st=0;
        endcase
    end
    task check;input integer w,h,accepted;begin
        tests=tests+1;
        if(!ready)fail("not reusable");
        for(i=0;i<512;i=i+1)hdr[i]=0;
        stride=((w*3+3)/4)*4;size=54+stride*h;
        hdr[0]=8'h42;hdr[1]=8'h4d;put32(2,size);put32(10,54);put32(14,40);
        put32(18,w);put32(22,-h);hdr[26]=1;hdr[28]=24;put32(34,stride*h);
        @(negedge video_clk);start=1;@(negedge video_clk);start=0;timeout=0;
        while(!done && !req && timeout<2000)begin @(negedge video_clk);timeout=timeout+1;end
        if(accepted)begin
            if(!req || error || en || loaded || done)fail("legal 640x480 header rejected");
        end else begin
            if(!done || !ready || !error || code!=8'h17 || req || en || loaded)fail("small image reached writer");
            repeat(10)begin @(negedge video_clk);if(req || en || loaded)fail("output after format rejection");end
        end
        $display("PASS V08 bridge src=%0dx%0d accepted_header=%0d",w,h,accepted);
    end endtask
    initial begin
        #101;rst=0;repeat(10)@(negedge video_clk);
        check(320,240,0);check(480,480,0);check(639,480,0);check(640,479,0);check(640,480,1);
        $display("PASS tb_v08_bridge_range tests=%0d small_input_rejected_before_write_req",tests);$finish;
    end
    initial begin #1000000;fail("watchdog");end
endmodule

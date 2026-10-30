`timescale 1ns/1ps
// 分拍校验器与原功能参考逐字段比较；参考模块只用于逻辑仿真，不用于100MHz实现。
module tb_bmp_scan_header;
    reg clk=0,rst=1,start=0,abort=0,valid=0,last=0;
    reg [7:0] data=0,hdr[0:53];
    always #5 clk=~clk;
    wire r0,r1,s0,s1,d0,d1;
    wire [214:0] a,b;
    reg seen0=0,seen1=0;
    contest_bmp_meta_parser ref_parser (
        .clk(clk),.rst(rst),.start(start),.abort(abort),.s_valid(valid),.s_ready(s0),.s_data(data),.s_last(last),
        .ready(r0),.busy(),.done(d0),.o_format_valid(a[214]),.o_format_error(a[213]),.o_error_code(a[212:209]),
        .o_width(a[208:193]),.o_height(a[192:177]),.o_top_down(a[176]),.file_size(a[175:144]),
        .o_pixel_offset(a[143:112]),.dib_size(a[111:80]),.o_row_stride(a[79:64]),
        .row_padding(a[63:62]),.pixel_bytes(a[61:30]),.pixel_count()
    );
    contest_bmp_scan_header scan_parser (
        .clk(clk),.rst(rst),.start(start),.abort(abort),.s_valid(valid),.s_ready(s1),.s_data(data),.s_last(last),
        .ready(r1),.busy(),.done(d1),.o_format_valid(b[214]),.o_format_error(b[213]),.o_error_code(b[212:209]),
        .o_width(b[208:193]),.o_height(b[192:177]),.o_top_down(b[176]),.file_size(b[175:144]),
        .o_pixel_offset(b[143:112]),.dib_size(b[111:80]),.o_row_stride(b[79:64]),
        .row_padding(b[63:62]),.pixel_bytes(b[61:30]),.pixel_count()
    );
    assign a[29:0]=0;assign b[29:0]=0;
    wire [31:0] count0=ref_parser.pixel_count,count1=scan_parser.pixel_count;
    integer test_id,i,w,h,stride,off,size,limit;
    task fail;input [8*100-1:0] msg;begin $display("FAIL scan_header test=%0d %0s",test_id,msg);$finish;end endtask
    task put32;input integer idx;input [31:0] v;begin
        hdr[idx]=v;hdr[idx+1]=v>>8;hdr[idx+2]=v>>16;hdr[idx+3]=v>>24;
    end endtask
    always @(posedge clk)begin if(start || rst)begin seen0=0;seen1=0;end else begin if(d0)seen0=1;if(d1)seen1=1;end end
    initial begin
        #91;rst=0;
        for(test_id=0;test_id<512;test_id=test_id+1)begin
            @(negedge clk);if(!r0 || !r1)fail("not reusable");
            w=640+(test_id*31)%641;h=480+(test_id*17)%545;stride=((w*3+3)/4)*4;off=54+(test_id%7)*64;size=off+stride*h;
            for(i=0;i<54;i=i+1)hdr[i]=0;
            hdr[0]=8'h42;hdr[1]=8'h4d;put32(2,size);put32(10,off);put32(14,40);
            put32(18,w);put32(22,test_id%2 ? -h:h);hdr[26]=1;hdr[28]=24;put32(34,stride*h);
            limit=54;
            case(test_id%16)
                1:hdr[0]=0;
                2:hdr[6]=1;
                3:put32(14,12);
                4:hdr[26]=2;
                5:hdr[28]=32;
                6:put32(30,1);
                7:put32(18,32'h00010001);
                8:put32(22,32'h80000000);
                9:put32(10,40);
                10:put32(2,size-1);
                11:put32(34,stride*h+1);
                12:put32(46,32'hffffffff);
                13:limit=1+test_id%53;
                default:;
            endcase
            start=1;@(negedge clk);start=0;
            for(i=0;i<limit;i=i+1)begin
                if(!s0 || !s1)fail("header ready differs");
                valid=1;last=(i==limit-1);data=hdr[i];@(negedge clk);
                valid=0;last=0;if(i%7==0)@(negedge clk);
            end
            repeat(12)@(negedge clk);
            if(!seen0 || !seen1 || a!==b || count0!==count1 || !r0 || !r1)fail("pipelined validation differs from reference");
        end
        $display("PASS tb_bmp_scan_header cases=512 metadata_and_error_equivalence");$finish;
    end
    initial begin #2000000;fail("watchdog");end
endmodule

`timescale 1ns/1ps
module tb_bmp_read_dynamic;
    reg clk=0,rst=1,scan_start=0,load_start=0,ack=0;
    always #5 clk=~clk;
    reg [31:0] scan_max=0;
    reg [2:0] target=1;
    wire ready,scan_done,found,req,read_req,wr;
    wire [31:0] found_sector,lba;
    wire [2:0] total;
    wire [23:0] rgb;
    reg [7:0] data=0,header[0:511];
    reg valid=0,read_end=0;
    integer width=3,height=2,stride=12,offset=54,size=78,top_down=0;
    integer i,st=0,index=0,gap=0,requests=0,found_count=0,pixels=0,tests=0;
    reg [31:0] active_lba;
    reg loading=0;
    bmp_read dut (
        .clk(clk),.rst(rst),.ready(ready),.scan_start(scan_start),.scan_start_sector(32'd0),
        .scan_max_sector(scan_max),.scan_target_count(target),.scan_done(scan_done),
        .scan_found_valid(found),.scan_found_sector(found_sector),.scan_found_total(total),
        .load_start(load_start),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),
        .bmp_width(16'd640),.bmp_height(16'd480),.write_req(req),.write_req_ack(ack),
        .sd_sec_read(read_req),.sd_sec_read_addr(lba),.sd_sec_read_data(data),
        .sd_sec_read_data_valid(valid),.sd_sec_read_end(read_end),.bmp_data_wr_en(wr),.bmp_data(rgb)
    );
    task fail;input [8*120-1:0] msg;begin $display("FAIL bmp_read test=%0d %0s",tests,msg);$finish;end endtask
    task put32;input integer a;input [31:0] v;begin
        header[a]=v;header[a+1]=v>>8;header[a+2]=v>>16;header[a+3]=v>>24;
    end endtask
    task make_header;input integer w,h,td,off;begin
        width=w;height=h;top_down=td;offset=off;stride=((w*3+3)/4)*4;size=off+stride*h;
        for(i=0;i<512;i=i+1)header[i]=0;
        header[0]=8'h42;header[1]=8'h4d;put32(2,size);put32(10,off);put32(14,40);
        put32(18,w);put32(22,td ? -h:h);header[26]=1;header[28]=24;put32(34,stride*h);
    end endtask
    function [23:0] pixel;input integer n;begin pixel=24'h123400+n;end endfunction
    function [7:0] byte_at;input integer p;
        integer row,col,phase;reg [23:0] v;
        begin
            if(p<54)byte_at=header[p];
            else if(p>=offset && p<size)begin
                row=(p-offset)/stride;col=((p-offset)%stride)/3;phase=((p-offset)%stride)%3;
                v=pixel(row*width+col);
                if((p-offset)%stride>=width*3)byte_at=8'hee;
                else case(phase)0:byte_at=v[7:0];1:byte_at=v[15:8];default:byte_at=v[23:16];endcase
            end else byte_at=8'hdd;
        end
    endfunction
    always @(negedge clk) begin
        valid=0;read_end=0;
        if(rst)begin st=0;index=0;gap=0;ack=0;end
        else begin
            ack=req;
            case(st)
                0:if(read_req)begin active_lba=lba;index=0;requests=requests+1;st=1;end
                1:begin
                    gap=gap+1;
                    if(gap%7!=0)begin
                        // 扫描候选LBA放同一合法头；加载时使用真实字节偏移。
                        data=byte_at(loading ? active_lba*512+index : index);valid=1;
                        if(index==511)begin read_end=1;st=2;end
                        index=index+1;
                    end
                end
                2:if(!read_req)st=0;
            endcase
        end
    end
    always @(posedge clk)if(!rst)begin
        if(found)begin
            if(found_sector!=found_count*((size+511)/512) && target==4)fail("multi-file scan sector order");
            found_count=found_count+1;
        end
        if(wr)begin
            if(!loading || pixels>=width*height || rgb!==pixel(pixels))fail("padding/trailer emitted or BGR order wrong");
            pixels=pixels+1;
        end
    end
    task reset_all;begin
        @(negedge clk);rst=1;scan_start=0;load_start=0;loading=0;
        repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
        requests=0;found_count=0;pixels=0;target=1;scan_max=0;
    end endtask
    task scan_test;input integer w,h,td,mode,expected;
        integer timeout;
        begin
            tests=tests+1;reset_all;make_header(w,h,td,54);
            case(mode)1:header[28]=32;2:put32(30,1);3:put32(18,32'h00010280);endcase
            scan_start=1;@(negedge clk);scan_start=0;timeout=0;
            while(!scan_done && timeout<2000)begin @(negedge clk);timeout=timeout+1;end
            repeat(3)@(negedge clk);
            if(!scan_done || !ready || found_count!=expected || total!=expected || requests!=1)fail("dynamic header scan");
            if(expected && (dut.width!=w || dut.height!=h || dut.top_down!=td))fail("metadata was narrowed incorrectly");
            $display("PASS bmp_read src=%0dx%0d top_down=%0d mode=%0d accepted=%0d",w,h,td,mode,expected);
        end
    endtask
    integer timeout;
    initial begin
        scan_test(640,480,0,0,1);scan_test(320,240,0,0,1);scan_test(800,600,0,0,1);
        scan_test(1024,768,1,0,1);scan_test(480,480,0,0,1);scan_test(1280,1024,1,0,1);
        scan_test(639,480,0,0,1);scan_test(640,479,1,0,1);
        scan_test(1281,1024,0,0,0);scan_test(640,480,0,1,0);scan_test(640,480,0,2,0);
        scan_test(640,480,0,3,0);
        tests=tests+1;reset_all;make_header(640,480,0,54);target=4;scan_max=3*((size+511)/512);scan_start=1;
        @(negedge clk);scan_start=0;timeout=0;
        while(!scan_done && timeout<6000)begin @(negedge clk);timeout=timeout+1;end
        repeat(3)@(negedge clk);
        if(!scan_done || total!=4 || found_count!=4 || requests!=4)fail("continuous headers / coincident end");
        $display("PASS bmp_read consecutive_catalog headers=4 end_coincident_with_last_byte");
        tests=tests+1;reset_all;make_header(641,480,1,510);loading=1;load_start=1;
        @(negedge clk);load_start=0;timeout=0;
        while((!ready || pixels==0) && timeout<2000000)begin @(negedge clk);timeout=timeout+1;end
        repeat(4)@(negedge clk);
        // 旧读器先独立读一次头，再从文件首扇区读取完整像素载荷。
        if(!ready || pixels!=641*480 || requests!=1+(size+511)/512)fail("native load metadata/padding/sector boundary");
        $display("PASS bmp_read native_load src=641x480 offset=510 padding=1 pixels=%0d sectors=%0d",pixels,requests);
        $display("PASS tb_bmp_read_dynamic tests=%0d",tests);$finish;
    end
    initial begin #30000000;fail("watchdog");end
endmodule

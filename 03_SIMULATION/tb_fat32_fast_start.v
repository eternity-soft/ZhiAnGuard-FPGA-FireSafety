`timescale 1ns/1ps
module tb_fat32_fast_start;
reg clk=0,rst=1,scan_start=0,load_start=0,sd_init_done=1;
reg write_req_ack=0,sd_sec_read_data_valid=0,sd_sec_read_end=0;
reg [7:0] sd_sec_read_data=0;
wire ready,scan_done,scan_found_valid,write_req,sd_sec_read,bmp_data_wr_en;
wire [31:0] scan_found_sector,sd_sec_read_addr;
wire [2:0] scan_found_total;
wire [3:0] state_code;
wire [23:0] bmp_data;
integer errors=0;
integer mode=0;
always #5 clk=~clk;

bmp_read #(.FAST_FAT32_START(1)) dut(
    .clk(clk),.rst(rst),.ready(ready),
    .scan_start(scan_start),.scan_start_sector(32'd0),
    .scan_max_sector(32'd131071),.scan_target_count(3'd4),
    .scan_done(scan_done),.scan_found_valid(scan_found_valid),
    .scan_found_sector(scan_found_sector),.scan_found_total(scan_found_total),
    .load_start(load_start),.load_sector(32'd0),.sd_init_done(sd_init_done),
    .state_code(state_code),.bmp_width(16'd640),.bmp_height(16'd480),
    .write_req(write_req),.write_req_ack(write_req_ack),
    .sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid),
    .sd_sec_read_end(sd_sec_read_end),.bmp_data_wr_en(bmp_data_wr_en),.bmp_data(bmp_data)
);

function [7:0] sector_byte;
    input integer which;
    input [31:0] lba;
    input integer index;
    begin
        sector_byte=8'h00;
        if(which==1 && lba==0) begin // MBR: FAT32 LBA partition at 2048
            case(index)
                450:sector_byte=8'h0c;
                454:sector_byte=8'h00;455:sector_byte=8'h08;
                456:sector_byte=8'h00;457:sector_byte=8'h00;
                510:sector_byte=8'h55;511:sector_byte=8'haa;
                default:sector_byte=0;
            endcase
        end else if(which==1 && lba==2048) begin // FAT32 BPB
            case(index)
                11:sector_byte=8'h00;12:sector_byte=8'h02; // 512 bytes/sector
                13:sector_byte=8'h08;                      // 8 sectors/cluster
                14:sector_byte=8'h20;15:sector_byte=8'h00; // 32 reserved
                16:sector_byte=8'h02;                      // two FATs
                36:sector_byte=8'he8;37:sector_byte=8'h03; // FAT size 1000
                38:sector_byte=0;39:sector_byte=0;
                510:sector_byte=8'h55;511:sector_byte=8'haa;
                default:sector_byte=0;
            endcase
        end else if(which==2 && lba==0) begin // superfloppy FAT32 BPB
            case(index)
                11:sector_byte=8'h00;12:sector_byte=8'h02;
                13:sector_byte=8'h08;
                14:sector_byte=8'h20;15:sector_byte=8'h00;
                16:sector_byte=8'h02;
                36:sector_byte=8'hc8;37:sector_byte=8'h00; // FAT size 200
                38:sector_byte=0;39:sector_byte=0;
                510:sector_byte=8'h55;511:sector_byte=8'haa;
                default:sector_byte=0;
            endcase
        end
    end
endfunction

task reset_dut;
    begin
        rst=1;scan_start=0;sd_sec_read_data_valid=0;sd_sec_read_end=0;
        repeat(4) @(posedge clk);rst=0;repeat(3) @(posedge clk);
    end
endtask

task start_scan;
    begin
        @(negedge clk);scan_start=1;
        @(negedge clk);scan_start=0;
    end
endtask

task serve_sector;
    input [31:0] expected_lba;
    integer i,guard;
    begin
        guard=0;
        while(!(sd_sec_read && sd_sec_read_addr==expected_lba) && guard<2000) begin
            @(posedge clk);guard=guard+1;
        end
        if(guard>=2000) begin
            $display("FAIL no read request lba=%0d actual=%0d",expected_lba,sd_sec_read_addr);
            errors=errors+1;
        end
        for(i=0;i<512;i=i+1) begin
            @(negedge clk);sd_sec_read_data=sector_byte(mode,expected_lba,i);
            sd_sec_read_data_valid=1;
        end
        @(negedge clk);sd_sec_read_data_valid=0;sd_sec_read_end=1;
        @(negedge clk);sd_sec_read_end=0;
    end
endtask

task expect_next_read;
    input [31:0] expected_lba;
    integer guard;
    begin
        guard=0;
        while(!(sd_sec_read && sd_sec_read_addr==expected_lba) && guard<2000) begin
            @(posedge clk);guard=guard+1;
        end
        if(guard>=2000) begin
            $display("FAIL expected next lba=%0d actual=%0d read=%0b",expected_lba,sd_sec_read_addr,sd_sec_read);
            errors=errors+1;
        end else $display("PASS next scan lba=%0d",expected_lba);
    end
endtask

initial begin
    mode=1;reset_dut;start_scan;serve_sector(0);serve_sector(2048);
    expect_next_read(4080); // 2048 + 32 + 2*1000

    mode=2;reset_dut;start_scan;serve_sector(0);
    expect_next_read(432);  // 0 + 32 + 2*200

    mode=3;reset_dut;start_scan;serve_sector(0);
    expect_next_read(0);    // invalid media falls back to legacy sector 0 scan

    if(errors==0) $display("PASS tb_fat32_fast_start mbr superfloppy fallback");
    else $display("FAIL tb_fat32_fast_start errors=%0d",errors);
    $finish;
end
endmodule

`timescale 1ns/1ps
// 用真实写调度器逐字检查四个缓存地址，覆盖第4帧跨越地址bit20。
module tb_cache_addresses;
reg clk=0,rst=1,req=0;
reg [1:0] bank=0;
wire ack,done,en;
wire [20:0] addr;
always #4 clk=~clk;
my_frame_fifo_write #(.WRITE_V_FLIP(0)) dut(
 .rst(rst),.abort_pending(1'b0),.mem_clk(clk),.Sdr_init_done(1'b1),
 .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(1'b0),.O_wr_busy(),
 .App_wr_en(en),.App_wr_addr(addr),.write_req(req),.write_req_ack(ack),.write_finish(done),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),.write_addr_3(21'd921600),
 .write_addr_index(bank),.write_len(21'd307200),.fifo_aclr(),.rdusedw(10'd511));
integer count=0,total=0,b;
always @(posedge clk)if(!rst && en)begin
 if(addr!==bank*307200+count || count>=307200 || addr>=2097152)begin
  $display("FAIL tb_cache_addresses bank=%0d count=%0d addr=%0d",bank,count,addr);$finish;
 end
 count=count+1;total=total+1;
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(b=0;b<4;b=b+1)begin
  @(negedge clk);bank=b;count=0;repeat(4)@(negedge clk);req=1;
  wait(ack);@(negedge clk);req=0;wait(!ack);wait(done);@(negedge clk);
  if(count!=307200)begin $display("FAIL tb_cache_addresses early finish");$finish;end
  $display("PASS cache_address bank=%0d first=%0d last=%0d words=%0d",b,b*307200,(b+1)*307200-1,count);
  wait(!done);repeat(5)@(negedge clk);
 end
 $display("PASS tb_cache_addresses frames=4 checked_words=%0d",total);$finish;
end
initial begin #50000000;$display("FAIL tb_cache_addresses watchdog");$finish;end
endmodule

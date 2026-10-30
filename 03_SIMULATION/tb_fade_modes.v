`timescale 1ns/1ps
module fade_case #(parameter NORMAL_N=15)(output reg done);
reg clk=0,rst=1,vs=1,req=0,de=1;
wire ack;
reg [1:0] target=0;
reg read_valid=1;
reg [1:0] read_bank=0;
wire [1:0] shown;
wire [7:0] level;
wire [23:0] rgb;
wire active;
always #20 clk=~clk;
my_fade #(.FADE_FRAMES(NORMAL_N)) dut(
 .clk(clk),.rst(rst),.de_in(de),.vs_in(vs),.rgb_in(24'hffffff),
 .disp_idx_new(target),.display_req_toggle(req),.display_ack_toggle(ack),.disp_idx_disp(shown),
 .read_bank_valid(read_valid),.read_bank_active(read_bank),
 .rgb_out(rgb),.fade_level(level),.fade_active(active));
task fail;input [8*80-1:0] msg;begin $display("FAIL fade frames=%0d %0s",NORMAL_N,msg);$finish;end endtask
task frame;begin
 @(negedge clk);vs=0;repeat(4)@(negedge clk);
 vs=1;repeat(4)@(negedge clk);
end endtask
integer n,step,i,expected;
task transition;input mode;input [1:0] bank;begin
 target=bank;req=~req;repeat(8)@(negedge clk);
 n=NORMAL_N;if(n==0)n=1;step=(255+n-1)/n;
 if(!active || level!=255 || shown==bank || ack==req)fail("start state");
 expected=255;
 for(i=1;i<=n;i=i+1)begin
  frame;expected=(i==n || expected<step)?0:expected-step;
  if(level!==expected)fail("fade-out brightness mismatch/underflow");
  if((i<n && shown==bank) || (i==n && shown!=bank))fail("bank switch not at black frame");
 end
 // The display bank has changed at black, but fade-in must not begin until
 // the real SDRAM reader acknowledges the same bank.
 repeat(3)begin
  frame;
  if(level!==0 || !active || ack==req)fail("did not hold black while reader was stale");
 end
 read_bank=bank;
 frame;
 if(level!==0 || !active || ack==req)fail("reader ACK did not preserve black guard frame");
 expected=0;
 for(i=1;i<=n;i=i+1)begin
  frame;expected=(i==n || expected+step>255)?255:expected+step;
  if(level!==expected)fail("fade-in brightness mismatch/overflow");
  if(i<n && !active)fail("fade completed early");
 end
 if(active || level!=255 || shown!=bank || ack!=req)fail("completion state");
 $display("PASS fade per_stage=%0d frames=%0d bank=%0d read-bank interlock",NORMAL_N,2*n+4,bank);
end endtask
initial begin
 done=0;repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);
 transition(1,3);transition(0,0);de=0;#1;if(rgb!==24'd0)fail("blanking output");
 done=1;
end
endmodule
module tb_fade_modes;
wire a,b,c;
fade_case normal(a);
fade_case #(.NORMAL_N(16)) rounding(b);
fade_case #(.NORMAL_N(0)) clamp_zero(c);
initial begin wait(a&&b&&c);$display("PASS tb_fade_modes transitions=6");$finish;end
initial begin #1000000;$display("FAIL tb_fade_modes watchdog");$finish;end
endmodule

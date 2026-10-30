`timescale 1ns/1ps
// 新增监测支路必须逐拍保持V18左右音频输出；不以“听起来差不多”代替。
module tb_audio_meter_equivalence;
reg clk=0,rst=1,img=0,period=0,auto_on=0;reg [1:0] idx=0,sel=0,vol=3;
wire av,rv;wire signed [23:0] l,r,rl,rr,sfx,bgm;
integer checked=0,isolated=0,both=0,quiet=0,n;
always #5 clk=~clk;
contest_fire_audio_linkage_engine #(.CLK_HZ(1000000),.SAMPLE_RATE(10000)) dut(
 .I_clk(clk),.I_rst(rst),.I_image_event_toggle(img),.I_image_event_idx(idx),
 .I_period_event_toggle(period),.I_period_sel(sel),.I_auto_state(auto_on),.I_vol(vol),
 .O_audio_valid(av),.O_audio_left(l),.O_audio_right(r),.O_sfx_meter_sample(sfx),.O_bgm_meter_sample(bgm));
reference_fire_audio_engine #(.CLK_HZ(1000000),.SAMPLE_RATE(10000)) ref_dut(
 .I_clk(clk),.I_rst(rst),.I_image_event_toggle(img),.I_image_event_idx(idx),
 .I_period_event_toggle(period),.I_period_sel(sel),.I_auto_state(auto_on),.I_vol(vol),
 .O_audio_valid(rv),.O_audio_left(rl),.O_audio_right(rr));
task fail;input [511:0] msg;begin $display("FAIL tb_audio_meter_equivalence %0s",msg);$finish;end endtask
always @(posedge clk)begin
 #1;
 if(!rst)begin
  if(av!==rv || l!==rl || r!==rr)fail("audio differs from original V18");
  if(av)begin
   checked=checked+1;
   if((^sfx===1'bx)||(^bgm===1'bx))fail("meter tap unknown");
   if(sfx==0 && bgm!=0)isolated=isolated+1;
   if(sfx!=0 && bgm!=0)both=both+1;
   if(sfx==0 && bgm==0)quiet=quiet+1;
  end
 end
end
task samples;input integer count;integer target;begin target=checked+count;while(checked<target)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;samples(250);
 if(isolated<150)fail("BGM leaked into key meter");
 img=~img;idx=2;samples(200);if(both<50)fail("key/BGM simultaneous taps missing");
 sel=1;period=~period;samples(100);auto_on=1;samples(100);
 for(n=0;n<4;n=n+1)begin vol=n;samples(100);end
 vol=0;samples(30);if(sfx!=0 || bgm!=0)fail("taps do not follow mute");
 vol=3;auto_on=0;samples(6000);
 if(sfx!=0 || bgm==0)fail("key tap did not stop independently");
 $display("PASS tb_audio_meter_equivalence samples=%0d bgm_only=%0d both=%0d muted=%0d original_lr_bit_exact",checked,isolated,both,quiet);$finish;
end
initial begin #20000000;fail("timeout");end
endmodule


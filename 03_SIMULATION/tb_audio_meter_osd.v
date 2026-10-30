`timescale 1ns/1ps
module tb_audio_meter_osd;
reg clk=0,rst=1,vs=0,de=0,show=0;reg [7:0] sfx=96,bgm=32;
wire ovs,ode;wire [23:0] rgb;integer x,y,green=0,blue=0,white=0,file=0;
reg [2047:0] path;
always #5 clk=~clk;
contest_status_osd dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(24'h24445f),
 .I_auto_play(1'b0),.I_period_sel(2'd0),.I_image_idx(2'd0),.I_vol_sel(2'd3),.I_bri_sel(2'd3),
 .I_sfx_level(sfx),.I_bgm_level(bgm),.I_meter_visible(show),.O_vs(ovs),.O_de(ode),.O_rgb(rgb));
task fail;input [511:0] msg;begin $display("FAIL tb_audio_meter_osd %0s",msg);$finish;end endtask
task frame_edge;begin @(negedge clk);vs=1;repeat(2)@(negedge clk);vs=0;repeat(2)@(negedge clk);end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;show=1;frame_edge;
 if($value$plusargs("preview=%s",path))begin
  file=$fopen(path,"w");if(file==0)fail("preview file open");$fwrite(file,"P3\n640 480\n255\n");
 end
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)begin
   @(negedge clk);de=1;
   // 帧中修改输入，当前帧必须保持原柱长和可见状态。
   if(y==75 && x==0)begin sfx=0;bgm=0;show=0;end
   @(posedge clk);#1;
   if(!ode || ovs!==vs)fail("video control latency changed");
   if(x>=500 && x<628 && y>=62 && y<70)begin
    if(rgb!==(x<596?24'h45d78a:24'h26394d))fail("key meter fill length");
    if(rgb==24'h45d78a)green=green+1;
   end
   if(x>=500 && x<628 && y>=83 && y<91)begin
    if(rgb!==(x<532?24'h4ba6ff:24'h26394d))fail("BGM meter fill length/frame latch");
    if(rgb==24'h4ba6ff)blue=blue+1;
   end
   if(x>=444 && x<492 && ((y>=58 && y<74)||(y>=79 && y<95)) && rgb==24'hffffff)white=white+1;
   if(x==450 && y==56 && rgb!==24'h12222f)fail("panel transparency");
   if(x==430 && y==65 && rgb!==24'h24445f)fail("overlay escaped its panel");
   if(file!=0)$fwrite(file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
  end
  @(negedge clk);de=0;repeat(2)@(posedge clk);
 end
 if(file!=0)$fclose(file);
 if(green!=768 || blue!=256 || white<100)fail("bar or Chinese-label coverage");
 frame_edge;de=1;
 force dut.pixel_x=10'd520;force dut.pixel_y=9'd65;
 @(posedge clk);#1;if(rgb!==24'h24445f)fail("hidden overlay still modifies picture");
 release dut.pixel_x;release dut.pixel_y;
 $display("PASS tb_audio_meter_osd key_pixels=%0d bgm_pixels=%0d chinese_pixels=%0d hide frame_latch timing passthrough",green,blue,white);$finish;
end
initial begin #10000000;fail("timeout");end
endmodule


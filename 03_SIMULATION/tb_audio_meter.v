`timescale 1ns/1ps
module tb_audio_meter;
reg clk=0,rst=1,valid=1,image=0,period=0,auto_on=0;
reg [1:0] volume=3;
reg signed [23:0] sfx=0,bgm=24'h400000;
wire [7:0] a,b;wire visible;integer n,k;
always #5 clk=~clk;
contest_audio_meter #(.WINDOW_CYCLES(4),.SHOW_CYCLES(100)) dut(
 .clk(clk),.rst(rst),.sample_valid(valid),.sfx_sample(sfx),.bgm_sample(bgm),
 .image_toggle(image),.period_toggle(period),.auto_state(auto_on),.volume(volume),
 .sfx_level(a),.bgm_level(b),.visible(visible));
contest_audio_meter defaults(.clk(clk),.rst(rst),.sample_valid(valid),.sfx_sample(sfx),.bgm_sample(bgm),
 .image_toggle(image),.period_toggle(period),.auto_state(auto_on),.volume(volume),.sfx_level(),.bgm_level(),.visible());
task fail;input [511:0] msg;begin $display("FAIL tb_audio_meter %0s",msg);$finish;end endtask
task tick;input integer cycles;begin repeat(cycles)begin @(posedge clk);#1;end end endtask
task changed;begin
 tick(3);if(dut.show_count!=100 || !visible)fail("operation did not restart one-second counter");
end endtask
initial begin
 tick(4);@(negedge clk);rst=0;changed;
 if(defaults.show_count!=25000000)fail("25MHz default is not one second");
 tick(12);if(a!=0 || b!=64)fail("BGM-only indication or scale");
 tick(100);if(visible)fail("continuous BGM kept overlay visible");
 @(negedge clk);image=~image;changed;tick(70);
 @(negedge clk);period=~period;changed;tick(99);
 if(!visible || dut.show_count!=1)fail("hide too early");
 tick(1);if(visible)fail("hide too late");
 @(negedge clk);auto_on=1;changed;
 @(negedge clk);sfx=-24'sh200000;bgm=0;tick(80);
 if(a!=32 || b!=0)fail("negative PCM or independent envelopes");
 @(negedge clk);sfx=24'sh800000;tick(8);if(a!=128)fail("minimum signed sample absolute value");
 @(negedge clk);sfx=0;tick(140);if(a!=0)fail("release did not decay to zero");
 @(negedge clk);sfx=24'sh7fffff;bgm=24'sh7fffff;tick(8);
 @(negedge clk);volume=0;changed;tick(1);if(a!=0 || b!=0)fail("mute did not clear meters");
 @(negedge clk);volume=3;valid=0;changed;tick(12);if(a!=0 || b!=0)fail("invalid samples updated meters");
 $display("PASS tb_audio_meter independent_levels signed_min mute decay one_second_hide retrigger continuous_bgm_no_retrigger");$finish;
end
initial begin #100000;fail("timeout");end
endmodule


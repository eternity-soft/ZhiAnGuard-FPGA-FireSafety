`timescale 1ns/1ps
module tb_audio_drill_mode;
reg clk=0,rst=1;
reg [1:0] mode=0;
wire valid;
wire signed [23:0] left,right,sfx_meter,bgm_meter;
integer nonzero,muted,sfx_nonzero,i;
always #500 clk=~clk;

contest_fire_audio_linkage_engine #(
    .CLK_HZ(1000000),.SAMPLE_RATE(10000),.BGM_ENABLE(1),.DRILL_SUPPORT(1)
) dut(
    .I_clk(clk),.I_rst(rst),
    .I_image_event_toggle(1'b0),.I_image_event_idx(2'd0),
    .I_period_event_toggle(1'b0),.I_period_sel(2'd0),
    .I_auto_state(1'b0),.I_vol(2'd3),.I_bgm_mode(mode),
    .O_audio_valid(valid),.O_audio_left(left),.O_audio_right(right),
    .O_sfx_meter_sample(sfx_meter),.O_bgm_meter_sample(bgm_meter)
);

task count_samples;
    input integer n;
    begin
        nonzero=0;muted=0;sfx_nonzero=0;i=0;
        while(i<n) begin
            @(posedge clk);
            if(valid) begin
                if(left!==right) begin $display("FAIL stereo mismatch");$fatal;end
                if(left!=0) nonzero=nonzero+1; else muted=muted+1;
                if(sfx_meter!=0) sfx_nonzero=sfx_nonzero+1;
                i=i+1;
            end
        end
    end
endtask

initial begin
    repeat(8) @(posedge clk);rst=0;
    count_samples(300);
    if(nonzero<150) begin $display("FAIL normal BGM missing %0d",nonzero);$fatal;end
    mode=1;
    count_samples(400);
    if(nonzero<250 || sfx_nonzero!=0) begin
        $display("FAIL drill siren nonzero=%0d sfx=%0d",nonzero,sfx_nonzero);$fatal;
    end
    mode=2;
    count_samples(120);
    if(muted<100) begin $display("FAIL completion not silent muted=%0d",muted);$fatal;end
    mode=0;
    count_samples(300);
    if(nonzero<150) begin $display("FAIL BGM did not restore %0d",nonzero);$fatal;end
    $display("PASS tb_audio_drill_mode siren completion_mute bgm_restore continuous_stereo");
    $finish;
end
endmodule

`timescale 1ns/1ps
module tb_contest_status_osd_clock_scroll;
    reg clk=0,rst=1,vs=0,de=1;
    reg [23:0] rgb=24'h804020;
    wire ovs,ode;
    wire [23:0] orgb;
    integer errors=0;
    always #5 clk=~clk;

    contest_status_osd #(
        .H_ACTIVE(640),.V_ACTIVE(480),
        .PIXEL_CLK_HZ(10),.SCROLL_TICK_CYCLES(3)
    ) dut (
        .I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(rgb),
        .I_auto_play(1'b0),.I_period_sel(2'd0),.I_image_idx(2'd0),
        .I_vol_sel(2'd3),.I_bri_sel(2'd3),
        .O_vs(ovs),.O_de(ode),.O_rgb(orgb)
    );

    task fail; input [8*100-1:0] msg; begin
        $display("FAIL OSD %0s",msg); errors=errors+1;
    end endtask

    initial begin
        repeat(3) @(posedge clk);
        @(negedge clk); rst=0;
        repeat(10) @(posedge clk); #1;
        if(dut.sec_ones!==4'd1 || dut.sec_tens!==4'd0) fail("one-second BCD counter");
        if(dut.scroll_x!==12'sd637) fail("one-pixel smooth scroll cadence");

        // RUN 'R' is now drawn over the image, below the status bar.
        force dut.pixel_x=10'd510; force dut.pixel_y=9'd32;
        @(posedge clk); #1;
        if(orgb!==24'hFFFFFF) fail("runtime text overlay pixel");
        release dut.pixel_x; release dut.pixel_y;

        // The timer box darkens the live image by 50%, proving image-layer blend.
        force dut.pixel_x=10'd500; force dut.pixel_y=9'd28;
        @(posedge clk); #1;
        if(orgb!==24'h402010) fail("runtime image overlay blend");
        release dut.pixel_x; release dut.pixel_y;

        // Bottom bar blends the image to 50% where no glyph is present.
        force dut.pixel_x=10'd639; force dut.pixel_y=9'd456;
        @(posedge clk); #1;
        if(orgb!==24'h402010) fail("caption layer 50-percent blend");
        release dut.pixel_x; release dut.pixel_y;

        // First Chinese glyph, row 7 column 2, must render in caption yellow.
        force dut.scroll_x=12'sd0;
        force dut.pixel_x=10'd2; force dut.pixel_y=9'd467;
        @(posedge clk); #1;
        if(orgb!==24'hFFF27A) fail("Chinese 16x16 glyph overlay pixel");
        release dut.scroll_x; release dut.pixel_x; release dut.pixel_y;

        // Second slogan: the new '通' glyph must render.
        force dut.scroll_message_sel=2'd1; force dut.scroll_x=12'sd0;
        force dut.pixel_x=10'd37; force dut.pixel_y=9'd460;
        @(posedge clk); #1;
        if(orgb!==24'hFFF27A) fail("second slogan new glyph");
        release dut.scroll_message_sel; release dut.scroll_x;
        release dut.pixel_x; release dut.pixel_y;

        // Third slogan: the new '遇' glyph must render.
        force dut.scroll_message_sel=2'd2; force dut.scroll_x=12'sd0;
        force dut.pixel_x=10'd2; force dut.pixel_y=9'd460;
        @(posedge clk); #1;
        if(orgb!==24'hFFF27A) fail("third slogan new glyph");
        release dut.scroll_message_sel; release dut.scroll_x;
        release dut.pixel_x; release dut.pixel_y;

        // Fourth slogan: the new '出' glyph must render.
        force dut.scroll_message_sel=2'd3; force dut.scroll_x=12'sd0;
        force dut.pixel_x=10'd43; force dut.pixel_y=9'd460;
        @(posedge clk); #1;
        if(orgb!==24'hFFF27A) fail("fourth slogan new glyph");
        release dut.scroll_message_sel; release dut.scroll_x;
        release dut.pixel_x; release dut.pixel_y;

        if(errors==0)
            $display("PASS tb_contest_status_osd_clock_scroll runtime_bcd scroll_pixel blend four_slogans");
        else
            $display("FAIL tb_contest_status_osd_clock_scroll errors=%0d",errors);
        $finish;
    end
    initial begin #10000; fail("watchdog"); $finish; end
endmodule

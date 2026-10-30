// Lightweight status OSD for the HX4S20 contest project.
//
// Displays a 22-pixel-high status bar with:
//   AUTO ON/OFF | P1/P2/P4 | IMG 1..4 | VOL | BRI
// A separate translucent image overlay at the upper-right displays
// RUN HH:MM:SS, making the dynamic timer visibly independent of the status bar.
// and a 24-pixel-high, 50%-darkened caption layer at the bottom.  The caption
// is a 16x16 Chinese bitmap string that moves left one physical pixel per tick.
//
// The block is deliberately placed at the end of the RGB pipeline.  Video
// timing and RGB are delayed by exactly one pixel clock, so the downstream
// AXI-stream adapter always sees aligned control and pixel data.
module contest_status_osd #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer PIXEL_CLK_HZ = 25000000,
    parameter integer SCROLL_TICK_CYCLES = 1000000
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire        I_auto_play,
    input  wire [1:0]  I_period_sel,
    input  wire [1:0]  I_image_idx,
    input  wire [1:0]  I_vol_sel,
    input  wire [1:0]  I_bri_sel,
    input  wire [7:0]  I_sfx_level,
    input  wire [7:0]  I_bgm_level,
    input  wire [7:0]  I_sfx_peak,
    input  wire [7:0]  I_bgm_peak,
    input  wire        I_meter_visible,

    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_rgb
);

reg        de_d;
reg        vs_d;
reg [9:0]  pixel_x;
reg [8:0]  pixel_y;
reg [7:0]  meter_sfx_frame, meter_bgm_frame;
reg [7:0]  meter_sfx_peak_frame, meter_bgm_peak_frame;
reg        meter_visible_frame;

// Latch meter state only at a frame boundary so the bars never tear.
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        meter_sfx_frame      <= 8'd0;
        meter_bgm_frame      <= 8'd0;
        meter_sfx_peak_frame <= 8'd0;
        meter_bgm_peak_frame <= 8'd0;
        meter_visible_frame  <= 1'b0;
    end else if(I_vs && !vs_d) begin
        meter_sfx_frame      <= I_sfx_level;
        meter_bgm_frame      <= I_bgm_level;
        meter_sfx_peak_frame <= I_sfx_peak;
        meter_bgm_peak_frame <= I_bgm_peak;
        meter_visible_frame  <= I_meter_visible;
    end
end

wire in_meter_panel = I_de && meter_visible_frame &&
                      pixel_x >= 10'd438 && pixel_x < 10'd635 &&
                      pixel_y >= 9'd54 && pixel_y < 9'd98;

wire meter_panel_border = in_meter_panel &&
                         (pixel_x == 10'd438 || pixel_x == 10'd634 ||
                          pixel_y == 9'd54   || pixel_y == 9'd97);

wire meter_sfx_track = pixel_x >= 10'd500 && pixel_x < 10'd628 && pixel_y >= 9'd62 && pixel_y < 9'd70;
wire meter_bgm_track = pixel_x >= 10'd500 && pixel_x < 10'd628 && pixel_y >= 9'd83 && pixel_y < 9'd91;

wire meter_sfx_bezel = (pixel_x >= 10'd499 && pixel_x <= 10'd628 && (pixel_y == 9'd61 || pixel_y == 9'd70)) ||
                       ((pixel_y >= 9'd61 && pixel_y <= 9'd70) && (pixel_x == 10'd499 || pixel_x == 10'd628));
wire meter_bgm_bezel = (pixel_x >= 10'd499 && pixel_x <= 10'd628 && (pixel_y == 9'd82 || pixel_y == 9'd91)) ||
                       ((pixel_y >= 9'd82 && pixel_y <= 9'd91) && (pixel_x == 10'd499 || pixel_x == 10'd628));

wire [9:0] bar_offset = pixel_x - 10'd500;

wire meter_sfx_fill = meter_sfx_track && (bar_offset < meter_sfx_frame);
wire meter_bgm_fill = meter_bgm_track && (bar_offset < meter_bgm_frame);

// 16-segment LED bar separator gap (every 8th pixel: 7, 15, 23, 31, ...)
wire meter_led_gap = (bar_offset[2:0] == 3'b111);

// Peak-Hold Indicator: 2-pixel wide indicator at peak position
wire meter_sfx_is_peak = meter_sfx_track && (meter_sfx_peak_frame > 8'd0) &&
                         (bar_offset + 10'd2 >= meter_sfx_peak_frame) &&
                         (bar_offset < meter_sfx_peak_frame);
wire meter_bgm_is_peak = meter_bgm_track && (meter_bgm_peak_frame > 8'd0) &&
                         (bar_offset + 10'd2 >= meter_bgm_peak_frame) &&
                         (bar_offset < meter_bgm_peak_frame);

wire text_meter = draw_meter_label(pixel_x,pixel_y,9'd58,1'b0) |
                  draw_meter_label(pixel_x,pixel_y,9'd79,1'b1);

function [23:0] sfx_bar_color;
    input [9:0] pos;
    begin
        if (pos < 10'd80)
            sfx_bar_color = 24'h00E676; // Safe / Normal: Vibrant Jade Green
        else if (pos < 10'd108)
            sfx_bar_color = 24'hFFC400; // Headroom: Amber Yellow
        else
            sfx_bar_color = 24'hFF3D00; // Peak: Neon Coral Red
    end
endfunction

function [23:0] bgm_bar_color;
    input [9:0] pos;
    begin
        if (pos < 10'd80)
            bgm_bar_color = 24'h00E5FF; // Safe / Normal: Vivid Cyan
        else if (pos < 10'd108)
            bgm_bar_color = 24'h2979FF; // Headroom: Sky Blue
        else
            bgm_bar_color = 24'hD500F9; // Peak: Neon Magenta
    end
endfunction

// Elapsed time from reset/power-on.  BCD counters avoid hardware division.
reg [24:0] second_div;
reg [19:0] scroll_div;
reg [3:0]  sec_ones, sec_tens;
reg [3:0]  min_ones, min_tens;
reg [3:0]  hour_ones, hour_tens;
reg signed [11:0] scroll_x;
reg [1:0] scroll_message_sel;

wire [7:0] hour_tens_char = 8'h30 + {4'd0,hour_tens};
wire [7:0] hour_ones_char = 8'h30 + {4'd0,hour_ones};
wire [7:0] min_tens_char  = 8'h30 + {4'd0,min_tens};
wire [7:0] min_ones_char  = 8'h30 + {4'd0,min_ones};
wire [7:0] sec_tens_char  = 8'h30 + {4'd0,sec_tens};
wire [7:0] sec_ones_char  = 8'h30 + {4'd0,sec_ones};

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        second_div <= 25'd0;
        scroll_div <= 20'd0;
        sec_ones <= 4'd0; sec_tens <= 4'd0;
        min_ones <= 4'd0; min_tens <= 4'd0;
        hour_ones <= 4'd0; hour_tens <= 4'd0;
        scroll_x <= 12'sd640;
        scroll_message_sel <= 2'd0;
    end else begin
        if (second_div == PIXEL_CLK_HZ-1) begin
            second_div <= 25'd0;
            if (sec_ones == 4'd9) begin
                sec_ones <= 4'd0;
                if (sec_tens == 4'd5) begin
                    sec_tens <= 4'd0;
                    if (min_ones == 4'd9) begin
                        min_ones <= 4'd0;
                        if (min_tens == 4'd5) begin
                            min_tens <= 4'd0;
                            if (hour_ones == 4'd9) begin
                                hour_ones <= 4'd0;
                                if (hour_tens == 4'd9) hour_tens <= 4'd0;
                                else hour_tens <= hour_tens + 1'b1;
                            end else hour_ones <= hour_ones + 1'b1;
                        end else min_tens <= min_tens + 1'b1;
                    end else min_ones <= min_ones + 1'b1;
                end else sec_tens <= sec_tens + 1'b1;
            end else sec_ones <= sec_ones + 1'b1;
        end else second_div <= second_div + 1'b1;

        if (scroll_div == SCROLL_TICK_CYCLES-1) begin
            scroll_div <= 20'd0;
            // Keep a fixed 15-glyph exit distance so every slogan has a clear gap.
            // After one complete pass, advance to the next public-safety message.
            if (scroll_x <= -12'sd270) begin
                scroll_x <= 12'sd640;
                if (scroll_message_sel == 2'd3)
                    scroll_message_sel <= 2'd0;
                else
                    scroll_message_sel <= scroll_message_sel + 1'b1;
            end else scroll_x <= scroll_x - 1'b1;
        end else scroll_div <= scroll_div + 1'b1;
    end
end

wire [7:0] period_char = (I_period_sel == 2'd0) ? "1" :
                         (I_period_sel == 2'd1) ? "2" : "4";
wire [7:0] image_char  = (I_image_idx == 2'd0) ? "1" :
                         (I_image_idx == 2'd1) ? "2" :
                         (I_image_idx == 2'd2) ? "3" : "4";
wire [7:0] vol_char    = (I_vol_sel == 2'd0) ? "0" :
                         (I_vol_sel == 2'd1) ? "1" :
                         (I_vol_sel == 2'd2) ? "2" : "3";
wire [7:0] bri_char    = (I_bri_sel == 2'd0) ? "0" :
                         (I_bri_sel == 2'd1) ? "1" :
                         (I_bri_sel == 2'd2) ? "2" : "3";

wire text_auto;
wire text_state;
wire text_period;
wire text_image;
wire text_vol;
wire text_bri;
wire text_clock;
wire text_scroll;
wire text_any;
wire in_status_bar;
wire in_state_box;
wire in_caption_bar;
wire in_clock_box;

assign text_auto =
       draw_char(pixel_x, pixel_y, 10'd8,  9'd4, "A")
     | draw_char(pixel_x, pixel_y, 10'd20, 9'd4, "U")
     | draw_char(pixel_x, pixel_y, 10'd32, 9'd4, "T")
     | draw_char(pixel_x, pixel_y, 10'd44, 9'd4, "O");

assign text_state = I_auto_play ?
       (draw_char(pixel_x, pixel_y, 10'd68, 9'd4, "O")
      | draw_char(pixel_x, pixel_y, 10'd80, 9'd4, "N")) :
       (draw_char(pixel_x, pixel_y, 10'd62, 9'd4, "O")
      | draw_char(pixel_x, pixel_y, 10'd74, 9'd4, "F")
      | draw_char(pixel_x, pixel_y, 10'd86, 9'd4, "F"));

assign text_period =
       draw_char(pixel_x, pixel_y, 10'd128, 9'd4, "P")
     | draw_char(pixel_x, pixel_y, 10'd140, 9'd4, period_char);

assign text_image =
       draw_char(pixel_x, pixel_y, 10'd188, 9'd4, "I")
     | draw_char(pixel_x, pixel_y, 10'd200, 9'd4, "M")
     | draw_char(pixel_x, pixel_y, 10'd212, 9'd4, "G")
     | draw_char(pixel_x, pixel_y, 10'd230, 9'd4, image_char);

assign text_vol =
       draw_char(pixel_x, pixel_y, 10'd280, 9'd4, "V")
     | draw_char(pixel_x, pixel_y, 10'd292, 9'd4, "O")
     | draw_char(pixel_x, pixel_y, 10'd304, 9'd4, "L")
     | draw_char(pixel_x, pixel_y, 10'd322, 9'd4, vol_char);

assign text_bri =
       draw_char(pixel_x, pixel_y, 10'd380, 9'd4, "B")
     | draw_char(pixel_x, pixel_y, 10'd392, 9'd4, "R")
     | draw_char(pixel_x, pixel_y, 10'd404, 9'd4, "I")
     | draw_char(pixel_x, pixel_y, 10'd422, 9'd4, bri_char);

// Right-aligned elapsed time over the image.  This is runtime, not RTC time.
assign text_clock =
       draw_char(pixel_x, pixel_y, 10'd510, 9'd32, "R")
     | draw_char(pixel_x, pixel_y, 10'd520, 9'd32, "U")
     | draw_char(pixel_x, pixel_y, 10'd530, 9'd32, "N")
     | draw_char(pixel_x, pixel_y, 10'd550, 9'd32, hour_tens_char)
     | draw_char(pixel_x, pixel_y, 10'd560, 9'd32, hour_ones_char)
     | draw_char(pixel_x, pixel_y, 10'd570, 9'd32, ":")
     | draw_char(pixel_x, pixel_y, 10'd580, 9'd32, min_tens_char)
     | draw_char(pixel_x, pixel_y, 10'd590, 9'd32, min_ones_char)
     | draw_char(pixel_x, pixel_y, 10'd600, 9'd32, ":")
     | draw_char(pixel_x, pixel_y, 10'd610, 9'd32, sec_tens_char)
     | draw_char(pixel_x, pixel_y, 10'd620, 9'd32, sec_ones_char);

// Four slogans rotate after each full pass:
// 0: 关注消防安全，共建平安公共空间
// 1: 消防通道，严禁占用
// 2: 遇到火情，及时报警
// 3: 安全出口，保持畅通
assign text_scroll = (scroll_message_sel == 2'd0) ? (
       draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd0,  9'd460,4'd0)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd18, 9'd460,4'd1)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd36, 9'd460,4'd2)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd54, 9'd460,4'd3)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd72, 9'd460,4'd4)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd90, 9'd460,4'd5)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd108,9'd460,4'd6)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd126,9'd460,4'd7)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd144,9'd460,4'd8)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd162,9'd460,4'd9)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd180,9'd460,4'd4)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd198,9'd460,4'd10)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd216,9'd460,4'd7)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd234,9'd460,4'd11)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd252,9'd460,4'd12)) :
    (scroll_message_sel == 2'd1) ? (
       draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd0,  9'd460,5'd2)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd18, 9'd460,5'd3)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd36, 9'd460,5'd13)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd54, 9'd460,5'd14)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd72, 9'd460,5'd6)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd90, 9'd460,5'd15)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd108,9'd460,5'd16)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd126,9'd460,5'd17)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd144,9'd460,5'd18)) :
    (scroll_message_sel == 2'd2) ? (
       draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd0,  9'd460,5'd19)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd18, 9'd460,5'd20)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd36, 9'd460,5'd21)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd54, 9'd460,5'd22)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd72, 9'd460,5'd6)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd90, 9'd460,5'd23)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd108,9'd460,5'd24)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd126,9'd460,5'd25)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd144,9'd460,5'd26)) :
    (
       draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd0,  9'd460,5'd4)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd18, 9'd460,5'd5)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd36, 9'd460,5'd27)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd54, 9'd460,5'd28)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd72, 9'd460,5'd6)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd90, 9'd460,5'd29)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd108,9'd460,5'd30)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd126,9'd460,5'd31)
     | draw_hanzi(pixel_x,pixel_y,scroll_x+12'sd144,9'd460,5'd13));

assign text_any      = text_auto | text_state | text_period | text_image
                     | text_vol | text_bri | text_clock;
assign in_status_bar = I_de && (pixel_y < 9'd22);
assign in_state_box  = I_de && (pixel_y < 9'd22)
                    && (pixel_x >= 10'd58) && (pixel_x < 10'd100);
assign in_caption_bar = I_de && (pixel_y >= 9'd456);
assign in_clock_box = I_de
                    && (pixel_x >= 10'd500) && (pixel_x < 10'd635)
                    && (pixel_y >= 9'd28) && (pixel_y < 9'd50);

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        de_d    <= 1'b0;
        vs_d    <= 1'b0;
        pixel_x <= 10'd0;
        pixel_y <= 9'd0;
        O_vs    <= 1'b0;
        O_de    <= 1'b0;
        O_rgb   <= 24'd0;
    end else begin
        de_d <= I_de;
        vs_d <= I_vs;
        O_vs <= I_vs;
        O_de <= I_de;

        // A VS transition occurs before active video and starts a new frame.
        if (I_vs != vs_d)
            pixel_y <= 9'd0;
        else if (!I_de && de_d) begin
            if (pixel_y == V_ACTIVE - 1)
                pixel_y <= 9'd0;
            else
                pixel_y <= pixel_y + 9'd1;
        end

        if (!I_de)
            pixel_x <= 10'd0;
        else if (pixel_x == H_ACTIVE - 1)
            pixel_x <= 10'd0;
        else
            pixel_x <= pixel_x + 10'd1;

        if (!I_de)
            O_rgb <= I_rgb;
        else if (text_any)
            O_rgb <= 24'hFFFFFF;
        else if (text_scroll)
            O_rgb <= 24'hFFF27A;
        else if (in_meter_panel) begin
            if (text_meter)
                O_rgb <= 24'hFFFFFF; // Crisp white text
            else if (meter_sfx_is_peak)
                O_rgb <= 24'hFFFFFF; // SFX Peak-Hold: Brilliant White Dot
            else if (meter_bgm_is_peak)
                O_rgb <= 24'hFFFFFF; // BGM Peak-Hold: Brilliant White Dot
            else if (meter_sfx_fill) begin
                if (meter_led_gap)
                    O_rgb <= 24'h0F1B26; // LED Segment Gap
                else
                    O_rgb <= sfx_bar_color(bar_offset);
            end else if (meter_bgm_fill) begin
                if (meter_led_gap)
                    O_rgb <= 24'h0F1B26; // LED Segment Gap
                else
                    O_rgb <= bgm_bar_color(bar_offset);
            end else if (meter_sfx_bezel || meter_bgm_bezel)
                O_rgb <= 24'h3A5F80; // Metallic Bezel around tracks
            else if (meter_sfx_track || meter_bgm_track)
                O_rgb <= 24'h162230; // Dark recessed track groove
            else if (meter_panel_border)
                O_rgb <= 24'h2E4B6E; // Subtle panel HUD frame
            else
                O_rgb <= {1'b0, I_rgb[23:17], 1'b0, I_rgb[15:9], 1'b0, I_rgb[7:1]};
        end
        else if (in_state_box)
            O_rgb <= I_auto_play ? 24'h087F4B : 24'hA82828;
        else if (in_status_bar)
            O_rgb <= 24'h10243E;
        else if (in_clock_box)
            // Darken the live image instead of replacing it with a solid bar.
            O_rgb <= {1'b0,I_rgb[23:17],1'b0,I_rgb[15:9],1'b0,I_rgb[7:1]};
        else if (in_caption_bar)
            // 50% image brightness creates a translucent-looking overlay layer.
            O_rgb <= {1'b0,I_rgb[23:17],1'b0,I_rgb[15:9],1'b0,I_rgb[7:1]};
        else
            O_rgb <= I_rgb;
    end
end

// 5x7 glyph ROM.  bit[4] is the left-most pixel.
function [4:0] glyph_row;
    input [7:0] ch;
    input [2:0] row;
    begin
        glyph_row = 5'b00000;
        case (ch)
            "A": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b11111;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b10001; default: glyph_row=5'b00000;
            endcase
            "U": case (row)
                0: glyph_row=5'b10001; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b10001;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "T": case (row)
                0: glyph_row=5'b11111; 1: glyph_row=5'b00100;
                2: glyph_row=5'b00100; 3: glyph_row=5'b00100;
                4: glyph_row=5'b00100; 5: glyph_row=5'b00100;
                6: glyph_row=5'b00100; default: glyph_row=5'b00000;
            endcase
            "O": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b10001;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "N": case (row)
                0: glyph_row=5'b10001; 1: glyph_row=5'b11001;
                2: glyph_row=5'b11001; 3: glyph_row=5'b10101;
                4: glyph_row=5'b10011; 5: glyph_row=5'b10011;
                6: glyph_row=5'b10001; default: glyph_row=5'b00000;
            endcase
            "F": case (row)
                0: glyph_row=5'b11111; 1: glyph_row=5'b10000;
                2: glyph_row=5'b10000; 3: glyph_row=5'b11110;
                4: glyph_row=5'b10000; 5: glyph_row=5'b10000;
                6: glyph_row=5'b10000; default: glyph_row=5'b00000;
            endcase
            "P": case (row)
                0: glyph_row=5'b11110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b11110;
                4: glyph_row=5'b10000; 5: glyph_row=5'b10000;
                6: glyph_row=5'b10000; default: glyph_row=5'b00000;
            endcase
            "I": case (row)
                0: glyph_row=5'b11111; 1: glyph_row=5'b00100;
                2: glyph_row=5'b00100; 3: glyph_row=5'b00100;
                4: glyph_row=5'b00100; 5: glyph_row=5'b00100;
                6: glyph_row=5'b11111; default: glyph_row=5'b00000;
            endcase
            "M": case (row)
                0: glyph_row=5'b10001; 1: glyph_row=5'b11011;
                2: glyph_row=5'b10101; 3: glyph_row=5'b10101;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b10001; default: glyph_row=5'b00000;
            endcase
            "G": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10000; 3: glyph_row=5'b10111;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "V": case (row)
                0: glyph_row=5'b10001; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b10001;
                4: glyph_row=5'b10001; 5: glyph_row=5'b01010;
                6: glyph_row=5'b00100; default: glyph_row=5'b00000;
            endcase
            "L": case (row)
                0: glyph_row=5'b10000; 1: glyph_row=5'b10000;
                2: glyph_row=5'b10000; 3: glyph_row=5'b10000;
                4: glyph_row=5'b10000; 5: glyph_row=5'b10000;
                6: glyph_row=5'b11111; default: glyph_row=5'b00000;
            endcase
            "B": case (row)
                0: glyph_row=5'b11110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b11110;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b11110; default: glyph_row=5'b00000;
            endcase
            "R": case (row)
                0: glyph_row=5'b11110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b11110;
                4: glyph_row=5'b10100; 5: glyph_row=5'b10010;
                6: glyph_row=5'b10001; default: glyph_row=5'b00000;
            endcase
            "0": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10011; 3: glyph_row=5'b10101;
                4: glyph_row=5'b11001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "1": case (row)
                0: glyph_row=5'b00100; 1: glyph_row=5'b01100;
                2: glyph_row=5'b00100; 3: glyph_row=5'b00100;
                4: glyph_row=5'b00100; 5: glyph_row=5'b00100;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "2": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b00001; 3: glyph_row=5'b00010;
                4: glyph_row=5'b00100; 5: glyph_row=5'b01000;
                6: glyph_row=5'b11111; default: glyph_row=5'b00000;
            endcase
            "3": case (row)
                0: glyph_row=5'b11110; 1: glyph_row=5'b00001;
                2: glyph_row=5'b00001; 3: glyph_row=5'b01110;
                4: glyph_row=5'b00001; 5: glyph_row=5'b00001;
                6: glyph_row=5'b11110; default: glyph_row=5'b00000;
            endcase
            "4": case (row)
                0: glyph_row=5'b00010; 1: glyph_row=5'b00110;
                2: glyph_row=5'b01010; 3: glyph_row=5'b10010;
                4: glyph_row=5'b11111; 5: glyph_row=5'b00010;
                6: glyph_row=5'b00010; default: glyph_row=5'b00000;
            endcase
            "5": case (row)
                0: glyph_row=5'b11111; 1: glyph_row=5'b10000;
                2: glyph_row=5'b10000; 3: glyph_row=5'b11110;
                4: glyph_row=5'b00001; 5: glyph_row=5'b00001;
                6: glyph_row=5'b11110; default: glyph_row=5'b00000;
            endcase
            "6": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10000;
                2: glyph_row=5'b10000; 3: glyph_row=5'b11110;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "7": case (row)
                0: glyph_row=5'b11111; 1: glyph_row=5'b00001;
                2: glyph_row=5'b00010; 3: glyph_row=5'b00100;
                4: glyph_row=5'b01000; 5: glyph_row=5'b01000;
                6: glyph_row=5'b01000; default: glyph_row=5'b00000;
            endcase
            "8": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b01110;
                4: glyph_row=5'b10001; 5: glyph_row=5'b10001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            "9": case (row)
                0: glyph_row=5'b01110; 1: glyph_row=5'b10001;
                2: glyph_row=5'b10001; 3: glyph_row=5'b01111;
                4: glyph_row=5'b00001; 5: glyph_row=5'b00001;
                6: glyph_row=5'b01110; default: glyph_row=5'b00000;
            endcase
            ":": case (row)
                0: glyph_row=5'b00000; 1: glyph_row=5'b00100;
                2: glyph_row=5'b00100; 3: glyph_row=5'b00000;
                4: glyph_row=5'b00100; 5: glyph_row=5'b00100;
                6: glyph_row=5'b00000; default: glyph_row=5'b00000;
            endcase
            default: glyph_row=5'b00000;
        endcase
    end
endfunction

function glyph_pixel;
    input [7:0] ch;
    input [2:0] row;
    input [2:0] col;
    reg [4:0] bits;
    begin
        bits = glyph_row(ch, row);
        glyph_pixel = (col < 5) ? bits[4-col] : 1'b0;
    end
endfunction

// Glyphs are enlarged 2x to remain legible on a 640x480 display.
function draw_char;
    input [9:0] px;
    input [8:0] py;
    input [9:0] ox;
    input [8:0] oy;
    input [7:0] ch;
    reg [9:0] lx;
    reg [8:0] ly;
    begin
        draw_char = 1'b0;
        if ((px >= ox) && (px < ox + 10) &&
            (py >= oy) && (py < oy + 14)) begin
            lx = px - ox;
            ly = py - oy;
            draw_char = glyph_pixel(ch, ly[3:1], lx[3:1]);
        end
    end
endfunction

// 16x16 Song-style bitmap ROM for the four public-safety slogans.
// glyph IDs: 0关 1注 2消 3防 4安 5全 6， 7共 8建 9平 10公 11空 12间
//            13通 14道 15严 16禁 17占 18用 19遇 20到 21火 22情 23及 24时 25报 26警
//            27出 28口 29保 30持 31畅
function [15:0] hanzi_row;
    input [4:0] glyph;
    input [3:0] row;
    begin
        hanzi_row = 16'h0000;
        case (glyph)
            5'd0: case(row)
                0:hanzi_row=16'h0204; 1:hanzi_row=16'h0208; 2:hanzi_row=16'h0000; 3:hanzi_row=16'h0FFE;
                4:hanzi_row=16'h0040; 5:hanzi_row=16'h0040; 6:hanzi_row=16'h0040; 7:hanzi_row=16'h3FFF;
                8:hanzi_row=16'h0040; 9:hanzi_row=16'h00A0; 10:hanzi_row=16'h00A0; 11:hanzi_row=16'h0110;
                12:hanzi_row=16'h0208; 13:hanzi_row=16'h0C06; 14:hanzi_row=16'h3001; default:hanzi_row=0;
            endcase
            5'd1: case(row)
                0:hanzi_row=16'h0810; 1:hanzi_row=16'h0400; 2:hanzi_row=16'h05FF; 3:hanzi_row=16'h2010;
                4:hanzi_row=16'h1010; 5:hanzi_row=16'h1010; 6:hanzi_row=16'h0410; 7:hanzi_row=16'h04FF;
                8:hanzi_row=16'h0810; 9:hanzi_row=16'h3810; 10:hanzi_row=16'h0810; 11:hanzi_row=16'h0810;
                12:hanzi_row=16'h0810; 13:hanzi_row=16'h0BFF; default:hanzi_row=0;
            endcase
            5'd2: case(row)
                0:hanzi_row=16'h0892; 1:hanzi_row=16'h0452; 2:hanzi_row=16'h0454; 3:hanzi_row=16'h2010;
                4:hanzi_row=16'h10FE; 5:hanzi_row=16'h1282; 6:hanzi_row=16'h0282; 7:hanzi_row=16'h04FE;
                8:hanzi_row=16'h0482; 9:hanzi_row=16'h3882; 10:hanzi_row=16'h08FE; 11:hanzi_row=16'h0882;
                12:hanzi_row=16'h0882; 13:hanzi_row=16'h088A; 14:hanzi_row=16'h0084; default:hanzi_row=0;
            endcase
            5'd3: case(row)
                0:hanzi_row=16'h1F08; 1:hanzi_row=16'h1108; 2:hanzi_row=16'h12FF; 3:hanzi_row=16'h1220;
                4:hanzi_row=16'h1420; 5:hanzi_row=16'h1220; 6:hanzi_row=16'h123F; 7:hanzi_row=16'h1121;
                8:hanzi_row=16'h1121; 9:hanzi_row=16'h1121; 10:hanzi_row=16'h1A21; 11:hanzi_row=16'h1441;
                12:hanzi_row=16'h1041; 13:hanzi_row=16'h108A; 14:hanzi_row=16'h1104; default:hanzi_row=0;
            endcase
            5'd4: case(row)
                0:hanzi_row=16'h0040; 1:hanzi_row=16'h0FFF; 2:hanzi_row=16'h0801; 3:hanzi_row=16'h1082;
                4:hanzi_row=16'h0080; 5:hanzi_row=16'h0080; 6:hanzi_row=16'h3FFF; 7:hanzi_row=16'h0108;
                8:hanzi_row=16'h0208; 9:hanzi_row=16'h0610; 10:hanzi_row=16'h0190; 11:hanzi_row=16'h0060;
                12:hanzi_row=16'h0098; 13:hanzi_row=16'h0304; 14:hanzi_row=16'h1C02; default:hanzi_row=0;
            endcase
            5'd5: case(row)
                0:hanzi_row=16'h0040; 1:hanzi_row=16'h00A0; 2:hanzi_row=16'h0110; 3:hanzi_row=16'h0208;
                4:hanzi_row=16'h0404; 5:hanzi_row=16'h0BFA; 6:hanzi_row=16'h3041; 7:hanzi_row=16'h0040;
                8:hanzi_row=16'h0040; 9:hanzi_row=16'h07FC; 10:hanzi_row=16'h0040; 11:hanzi_row=16'h0040;
                12:hanzi_row=16'h0040; 13:hanzi_row=16'h1FFF; default:hanzi_row=0;
            endcase
            5'd6: case(row)
                10:hanzi_row=16'h0C00; 11:hanzi_row=16'h0C00; 12:hanzi_row=16'h0400;
                13:hanzi_row=16'h0800; default:hanzi_row=0;
            endcase
            5'd7: case(row)
                0:hanzi_row=16'h0108; 1:hanzi_row=16'h0108; 2:hanzi_row=16'h0108; 3:hanzi_row=16'h0FFF;
                4:hanzi_row=16'h0108; 5:hanzi_row=16'h0108; 6:hanzi_row=16'h0108; 7:hanzi_row=16'h0108;
                8:hanzi_row=16'h0108; 9:hanzi_row=16'h1FFF; 10:hanzi_row=16'h0000; 11:hanzi_row=16'h0108;
                12:hanzi_row=16'h0204; 13:hanzi_row=16'h0402; 14:hanzi_row=16'h0801; default:hanzi_row=0;
            endcase
            5'd8: case(row)
                0:hanzi_row=16'h0010; 1:hanzi_row=16'h3EFE; 2:hanzi_row=16'h0212; 3:hanzi_row=16'h05FF;
                4:hanzi_row=16'h0412; 5:hanzi_row=16'h08FE; 6:hanzi_row=16'h1E10; 7:hanzi_row=16'h02FE;
                8:hanzi_row=16'h0210; 9:hanzi_row=16'h1210; 10:hanzi_row=16'h0DFF; 11:hanzi_row=16'h0410;
                12:hanzi_row=16'h0B10; 13:hanzi_row=16'h10FF; 14:hanzi_row=16'h2000; default:hanzi_row=0;
            endcase
            5'd9: case(row)
                0:hanzi_row=16'h1FFF; 1:hanzi_row=16'h0040; 2:hanzi_row=16'h0040; 3:hanzi_row=16'h0444;
                4:hanzi_row=16'h0244; 5:hanzi_row=16'h0248; 6:hanzi_row=16'h0040; 7:hanzi_row=16'h3FFF;
                8:hanzi_row=16'h0040; 9:hanzi_row=16'h0040; 10:hanzi_row=16'h0040; 11:hanzi_row=16'h0040;
                12:hanzi_row=16'h0040; 13:hanzi_row=16'h0040; 14:hanzi_row=16'h0040; default:hanzi_row=0;
            endcase
            5'd10: case(row)
                0:hanzi_row=16'h0120; 1:hanzi_row=16'h0120; 2:hanzi_row=16'h0210; 3:hanzi_row=16'h0210;
                4:hanzi_row=16'h0408; 5:hanzi_row=16'h0804; 6:hanzi_row=16'h1082; 7:hanzi_row=16'h2081;
                8:hanzi_row=16'h0100; 9:hanzi_row=16'h0110; 10:hanzi_row=16'h0208; 11:hanzi_row=16'h0408;
                12:hanzi_row=16'h0FFC; 13:hanzi_row=16'h0404; default:hanzi_row=0;
            endcase
            5'd11: case(row)
                0:hanzi_row=16'h0040; 1:hanzi_row=16'h1FFF; 2:hanzi_row=16'h1000; 3:hanzi_row=16'h2209;
                4:hanzi_row=16'h0404; 5:hanzi_row=16'h0802; 6:hanzi_row=16'h0000; 7:hanzi_row=16'h07FC;
                8:hanzi_row=16'h0040; 9:hanzi_row=16'h0040; 10:hanzi_row=16'h0040; 11:hanzi_row=16'h0040;
                12:hanzi_row=16'h0040; 13:hanzi_row=16'h1FFF; default:hanzi_row=0;
            endcase
            5'd12: case(row)
                0:hanzi_row=16'h04FF; 1:hanzi_row=16'h0401; 2:hanzi_row=16'h1001; 3:hanzi_row=16'h11F1;
                4:hanzi_row=16'h1111; 5:hanzi_row=16'h1111; 6:hanzi_row=16'h1111; 7:hanzi_row=16'h11F1;
                8:hanzi_row=16'h1111; 9:hanzi_row=16'h1111; 10:hanzi_row=16'h1111; 11:hanzi_row=16'h11F1;
                12:hanzi_row=16'h1001; 13:hanzi_row=16'h1005; 14:hanzi_row=16'h1002; default:hanzi_row=0;
            endcase
            5'd13: case(row) // 通
                0:hanzi_row=16'h47F8; 1:hanzi_row=16'h2010; 2:hanzi_row=16'h21A0; 3:hanzi_row=16'h0040;
                4:hanzi_row=16'h07FC; 5:hanzi_row=16'hE444; 6:hanzi_row=16'h2444; 7:hanzi_row=16'h27FC;
                8:hanzi_row=16'h2444; 9:hanzi_row=16'h2444; 10:hanzi_row=16'h27FC; 11:hanzi_row=16'h2444;
                12:hanzi_row=16'h2454; 13:hanzi_row=16'h5408; 14:hanzi_row=16'h8FFE; default:hanzi_row=0;
            endcase
            5'd14: case(row) // 道
                0:hanzi_row=16'h2110; 1:hanzi_row=16'h1000; 2:hanzi_row=16'h17FC; 3:hanzi_row=16'h0080;
                4:hanzi_row=16'h03F8; 5:hanzi_row=16'hF208; 6:hanzi_row=16'h13F8; 7:hanzi_row=16'h1208;
                8:hanzi_row=16'h13F8; 9:hanzi_row=16'h1208; 10:hanzi_row=16'h13F8; 11:hanzi_row=16'h1208;
                12:hanzi_row=16'h2800; 13:hanzi_row=16'h47FE; default:hanzi_row=0;
            endcase
            5'd15: case(row) // 严
                0:hanzi_row=16'h7FFC; 1:hanzi_row=16'h0240; 2:hanzi_row=16'h1248; 3:hanzi_row=16'h0A50;
                4:hanzi_row=16'h0240; 5:hanzi_row=16'h3FFE; 6:hanzi_row=16'h2000; 7:hanzi_row=16'h2000;
                8:hanzi_row=16'h2000; 9:hanzi_row=16'h2000; 10:hanzi_row=16'h2000; 11:hanzi_row=16'h2000;
                12:hanzi_row=16'h4000; 13:hanzi_row=16'h4000; 14:hanzi_row=16'h8000; default:hanzi_row=0;
            endcase
            5'd16: case(row) // 禁
                0:hanzi_row=16'h0820; 1:hanzi_row=16'h7EFC; 2:hanzi_row=16'h0820; 3:hanzi_row=16'h1C70;
                4:hanzi_row=16'h2AA8; 5:hanzi_row=16'hC826; 6:hanzi_row=16'h0000; 7:hanzi_row=16'h3FF8;
                8:hanzi_row=16'h0000; 9:hanzi_row=16'h0000; 10:hanzi_row=16'hFFFE; 11:hanzi_row=16'h0100;
                12:hanzi_row=16'h1110; 13:hanzi_row=16'h2508; 14:hanzi_row=16'h4204; default:hanzi_row=0;
            endcase
            5'd17: case(row) // 占
                0:hanzi_row=16'h0100; 1:hanzi_row=16'h0100; 2:hanzi_row=16'h01FE; 3:hanzi_row=16'h0100;
                4:hanzi_row=16'h0100; 5:hanzi_row=16'h0100; 6:hanzi_row=16'h0100; 7:hanzi_row=16'h3FF8;
                8:hanzi_row=16'h2008; 9:hanzi_row=16'h2008; 10:hanzi_row=16'h2008; 11:hanzi_row=16'h2008;
                12:hanzi_row=16'h2008; 13:hanzi_row=16'h3FF8; 14:hanzi_row=16'h2008; default:hanzi_row=0;
            endcase
            5'd18: case(row) // 用
                0:hanzi_row=16'h3FF8; 1:hanzi_row=16'h2108; 2:hanzi_row=16'h2108; 3:hanzi_row=16'h2108;
                4:hanzi_row=16'h3FF8; 5:hanzi_row=16'h2108; 6:hanzi_row=16'h2108; 7:hanzi_row=16'h2108;
                8:hanzi_row=16'h3FF8; 9:hanzi_row=16'h2108; 10:hanzi_row=16'h2108; 11:hanzi_row=16'h2108;
                12:hanzi_row=16'h4108; 13:hanzi_row=16'h4128; 14:hanzi_row=16'h8010; default:hanzi_row=0;
            endcase
            5'd19: case(row) // 遇
                0:hanzi_row=16'h23F8; 1:hanzi_row=16'h1248; 2:hanzi_row=16'h13F8; 3:hanzi_row=16'h0248;
                4:hanzi_row=16'h03F8; 5:hanzi_row=16'hF040; 6:hanzi_row=16'h17FC; 7:hanzi_row=16'h1444;
                8:hanzi_row=16'h1454; 9:hanzi_row=16'h1474; 10:hanzi_row=16'h1594; 11:hanzi_row=16'h1404;
                12:hanzi_row=16'h140C; 13:hanzi_row=16'h2800; 14:hanzi_row=16'h47FE; default:hanzi_row=0;
            endcase
            5'd20: case(row) // 到
                0:hanzi_row=16'hFF84; 1:hanzi_row=16'h0804; 2:hanzi_row=16'h1024; 3:hanzi_row=16'h2224;
                4:hanzi_row=16'h4124; 5:hanzi_row=16'hFFA4; 6:hanzi_row=16'h08A4; 7:hanzi_row=16'h0824;
                8:hanzi_row=16'h0824; 9:hanzi_row=16'h7F24; 10:hanzi_row=16'h0824; 11:hanzi_row=16'h0804;
                12:hanzi_row=16'h0F84; 13:hanzi_row=16'hF814; 14:hanzi_row=16'h4008; default:hanzi_row=0;
            endcase
            5'd21: case(row) // 火
                0:hanzi_row=16'h0100; 1:hanzi_row=16'h0100; 2:hanzi_row=16'h1108; 3:hanzi_row=16'h1108;
                4:hanzi_row=16'h1110; 5:hanzi_row=16'h2120; 6:hanzi_row=16'h2100; 7:hanzi_row=16'h4280;
                8:hanzi_row=16'h0280; 9:hanzi_row=16'h0440; 10:hanzi_row=16'h0440; 11:hanzi_row=16'h0820;
                12:hanzi_row=16'h1010; 13:hanzi_row=16'h2008; 14:hanzi_row=16'hC006; default:hanzi_row=0;
            endcase
            5'd22: case(row) // 情
                0:hanzi_row=16'h1040; 1:hanzi_row=16'h17FC; 2:hanzi_row=16'h1040; 3:hanzi_row=16'h1BF8;
                4:hanzi_row=16'h5440; 5:hanzi_row=16'h57FE; 6:hanzi_row=16'h5000; 7:hanzi_row=16'h93F8;
                8:hanzi_row=16'h1208; 9:hanzi_row=16'h13F8; 10:hanzi_row=16'h1208; 11:hanzi_row=16'h13F8;
                12:hanzi_row=16'h1208; 13:hanzi_row=16'h1228; 14:hanzi_row=16'h1210; default:hanzi_row=0;
            endcase
            5'd23: case(row) // 及
                0:hanzi_row=16'h3FE0; 1:hanzi_row=16'h0820; 2:hanzi_row=16'h0820; 3:hanzi_row=16'h0840;
                4:hanzi_row=16'h0840; 5:hanzi_row=16'h0CF8; 6:hanzi_row=16'h0A08; 7:hanzi_row=16'h0A08;
                8:hanzi_row=16'h0910; 9:hanzi_row=16'h1110; 10:hanzi_row=16'h10A0; 11:hanzi_row=16'h2040;
                12:hanzi_row=16'h20A0; 13:hanzi_row=16'h4318; 14:hanzi_row=16'h8C06; default:hanzi_row=0;
            endcase
            5'd24: case(row) // 时
                0:hanzi_row=16'h0008; 1:hanzi_row=16'h7C08; 2:hanzi_row=16'h4408; 3:hanzi_row=16'h45FE;
                4:hanzi_row=16'h4408; 5:hanzi_row=16'h4408; 6:hanzi_row=16'h7C08; 7:hanzi_row=16'h4488;
                8:hanzi_row=16'h4448; 9:hanzi_row=16'h4448; 10:hanzi_row=16'h4408; 11:hanzi_row=16'h7C08;
                12:hanzi_row=16'h4408; 13:hanzi_row=16'h0028; 14:hanzi_row=16'h0010; default:hanzi_row=0;
            endcase
            5'd25: case(row) // 报
                0:hanzi_row=16'h11FC; 1:hanzi_row=16'h1104; 2:hanzi_row=16'h1104; 3:hanzi_row=16'hFD14;
                4:hanzi_row=16'h1108; 5:hanzi_row=16'h1100; 6:hanzi_row=16'h15FC; 7:hanzi_row=16'h1944;
                8:hanzi_row=16'h3144; 9:hanzi_row=16'hD128; 10:hanzi_row=16'h1128; 11:hanzi_row=16'h1110;
                12:hanzi_row=16'h1128; 13:hanzi_row=16'h5144; 14:hanzi_row=16'h2182; default:hanzi_row=0;
            endcase
            5'd26: case(row) // 警
                0:hanzi_row=16'hFF20; 1:hanzi_row=16'h247E; 2:hanzi_row=16'h7EC4; 3:hanzi_row=16'h8228;
                4:hanzi_row=16'h7A10; 5:hanzi_row=16'h4A28; 6:hanzi_row=16'h7AC6; 7:hanzi_row=16'h0500;
                8:hanzi_row=16'hFFFE; 9:hanzi_row=16'h0000; 10:hanzi_row=16'h3FF8; 11:hanzi_row=16'h0000;
                12:hanzi_row=16'h3FF8; 13:hanzi_row=16'h2008; 14:hanzi_row=16'h3FF8; default:hanzi_row=0;
            endcase
            5'd27: case(row) // 出
                0:hanzi_row=16'h0100; 1:hanzi_row=16'h2108; 2:hanzi_row=16'h2108; 3:hanzi_row=16'h2108;
                4:hanzi_row=16'h2108; 5:hanzi_row=16'h3FF8; 6:hanzi_row=16'h0108; 7:hanzi_row=16'h0100;
                8:hanzi_row=16'h0100; 9:hanzi_row=16'h4104; 10:hanzi_row=16'h4104; 11:hanzi_row=16'h4104;
                12:hanzi_row=16'h4104; 13:hanzi_row=16'h7FFC; 14:hanzi_row=16'h0004; default:hanzi_row=0;
            endcase
            5'd28: case(row) // 口
                0:hanzi_row=16'h0000; 1:hanzi_row=16'h3FF8; 2:hanzi_row=16'h2008; 3:hanzi_row=16'h2008;
                4:hanzi_row=16'h2008; 5:hanzi_row=16'h2008; 6:hanzi_row=16'h2008; 7:hanzi_row=16'h2008;
                8:hanzi_row=16'h2008; 9:hanzi_row=16'h2008; 10:hanzi_row=16'h2008; 11:hanzi_row=16'h2008;
                12:hanzi_row=16'h3FF8; 13:hanzi_row=16'h2008; default:hanzi_row=0;
            endcase
            5'd29: case(row) // 保
                0:hanzi_row=16'h0BF8; 1:hanzi_row=16'h0A08; 2:hanzi_row=16'h1208; 3:hanzi_row=16'h1208;
                4:hanzi_row=16'h33F8; 5:hanzi_row=16'h3040; 6:hanzi_row=16'h5040; 7:hanzi_row=16'h97FC;
                8:hanzi_row=16'h10E0; 9:hanzi_row=16'h1150; 10:hanzi_row=16'h1248; 11:hanzi_row=16'h1444;
                12:hanzi_row=16'h1842; 13:hanzi_row=16'h1040; 14:hanzi_row=16'h1040; default:hanzi_row=0;
            endcase
            5'd30: case(row) // 持
                0:hanzi_row=16'h1020; 1:hanzi_row=16'h1020; 2:hanzi_row=16'h11FC; 3:hanzi_row=16'hFC20;
                4:hanzi_row=16'h1020; 5:hanzi_row=16'h13FE; 6:hanzi_row=16'h1008; 7:hanzi_row=16'h1808;
                8:hanzi_row=16'h33FE; 9:hanzi_row=16'hD008; 10:hanzi_row=16'h1088; 11:hanzi_row=16'h1048;
                12:hanzi_row=16'h1008; 13:hanzi_row=16'h5028; 14:hanzi_row=16'h2010; default:hanzi_row=0;
            endcase
            5'd31: case(row) // 畅
                0:hanzi_row=16'h11F8; 1:hanzi_row=16'h1010; 2:hanzi_row=16'h7C20; 3:hanzi_row=16'h5440;
                4:hanzi_row=16'h5480; 5:hanzi_row=16'h7DFC; 6:hanzi_row=16'h5454; 7:hanzi_row=16'h5454;
                8:hanzi_row=16'h5494; 9:hanzi_row=16'h7D24; 10:hanzi_row=16'h5424; 11:hanzi_row=16'h1044;
                12:hanzi_row=16'h1084; 13:hanzi_row=16'h1128; 14:hanzi_row=16'h1010; default:hanzi_row=0;
            endcase
            default: hanzi_row=16'h0000;
        endcase
    end
endfunction

function draw_hanzi;
    input [9:0] px;
    input [8:0] py;
    input signed [11:0] ox;
    input [8:0] oy;
    input [4:0] glyph;
    reg signed [11:0] px_signed;
    reg signed [11:0] local_x;
    reg [8:0] local_y;
    reg [15:0] bits;
    begin
        draw_hanzi = 1'b0;
        px_signed = $signed({1'b0,px});
        local_x = px_signed - ox;
        local_y = py - oy;
        if ((local_x >= 0) && (local_x < 16) &&
            (py >= oy) && (py < oy + 16)) begin
            bits = hanzi_row(glyph,local_y[3:0]);
            draw_hanzi = bits[15-local_x[3:0]];
        end
    end
endfunction

// Six 16x16 glyphs for the labels: 按键音 / 背景乐.
function [15:0] meter_glyph_row;
 input [2:0] glyph; input [3:0] row;
 begin
  meter_glyph_row=0;
  case(glyph)
   3'd0:case(row)
    0:meter_glyph_row=16'h1040;1:meter_glyph_row=16'h1020;
    2:meter_glyph_row=16'h1020;3:meter_glyph_row=16'h13FE;
    4:meter_glyph_row=16'hFA02;5:meter_glyph_row=16'h1444;
    6:meter_glyph_row=16'h1040;7:meter_glyph_row=16'h1BFE;
    8:meter_glyph_row=16'h3088;9:meter_glyph_row=16'hD088;
    10:meter_glyph_row=16'h1108;11:meter_glyph_row=16'h10D0;
    12:meter_glyph_row=16'h1020;13:meter_glyph_row=16'h1050;
    14:meter_glyph_row=16'h5088;15:meter_glyph_row=16'h2304;
   endcase
   3'd1:case(row)
    0:meter_glyph_row=16'h2010;1:meter_glyph_row=16'h2010;
    2:meter_glyph_row=16'h3B7C;3:meter_glyph_row=16'h2114;
    4:meter_glyph_row=16'h41FE;5:meter_glyph_row=16'h7A14;
    6:meter_glyph_row=16'hA27C;7:meter_glyph_row=16'h2710;
    8:meter_glyph_row=16'hF97C;9:meter_glyph_row=16'h2510;
    10:meter_glyph_row=16'h25FE;11:meter_glyph_row=16'h2210;
    12:meter_glyph_row=16'h2A10;13:meter_glyph_row=16'h3500;
    14:meter_glyph_row=16'h28FE;15:meter_glyph_row=16'h0000;
   endcase
   3'd2:case(row)
    0:meter_glyph_row=16'h0200;1:meter_glyph_row=16'h0100;
    2:meter_glyph_row=16'h3FF8;3:meter_glyph_row=16'h0000;
    4:meter_glyph_row=16'h0820;5:meter_glyph_row=16'h0440;
    6:meter_glyph_row=16'hFFFE;7:meter_glyph_row=16'h0000;
    8:meter_glyph_row=16'h1FF0;9:meter_glyph_row=16'h1010;
    10:meter_glyph_row=16'h1010;11:meter_glyph_row=16'h1FF0;
    12:meter_glyph_row=16'h1010;13:meter_glyph_row=16'h1010;
    14:meter_glyph_row=16'h1FF0;15:meter_glyph_row=16'h1010;
   endcase
   3'd3:case(row)
    0:meter_glyph_row=16'h0480;1:meter_glyph_row=16'h0498;
    2:meter_glyph_row=16'h7CE0;3:meter_glyph_row=16'h0484;
    4:meter_glyph_row=16'h1C84;5:meter_glyph_row=16'hE47C;
    6:meter_glyph_row=16'h4000;7:meter_glyph_row=16'h1FF0;
    8:meter_glyph_row=16'h1010;9:meter_glyph_row=16'h1FF0;
    10:meter_glyph_row=16'h1010;11:meter_glyph_row=16'h1FF0;
    12:meter_glyph_row=16'h1010;13:meter_glyph_row=16'h1010;
    14:meter_glyph_row=16'h1050;15:meter_glyph_row=16'h1020;
   endcase
   3'd4:case(row)
    0:meter_glyph_row=16'h1FF0;1:meter_glyph_row=16'h1010;
    2:meter_glyph_row=16'h1FF0;3:meter_glyph_row=16'h1010;
    4:meter_glyph_row=16'h1FF0;5:meter_glyph_row=16'h0100;
    6:meter_glyph_row=16'hFFFE;7:meter_glyph_row=16'h0000;
    8:meter_glyph_row=16'h1FF0;9:meter_glyph_row=16'h1010;
    10:meter_glyph_row=16'h1010;11:meter_glyph_row=16'h1FF0;
    12:meter_glyph_row=16'h0100;13:meter_glyph_row=16'h2108;
    14:meter_glyph_row=16'h4504;15:meter_glyph_row=16'h0200;
   endcase
   3'd5:case(row)
    0:meter_glyph_row=16'h0020;1:meter_glyph_row=16'h00F0;
    2:meter_glyph_row=16'h1F00;3:meter_glyph_row=16'h1000;
    4:meter_glyph_row=16'h1100;5:meter_glyph_row=16'h2100;
    6:meter_glyph_row=16'h2100;7:meter_glyph_row=16'h3FFC;
    8:meter_glyph_row=16'h0100;9:meter_glyph_row=16'h0920;
    10:meter_glyph_row=16'h0910;11:meter_glyph_row=16'h1108;
    12:meter_glyph_row=16'h2104;13:meter_glyph_row=16'h4104;
    14:meter_glyph_row=16'h0500;15:meter_glyph_row=16'h0200;
   endcase
   default:meter_glyph_row=0;
  endcase
 end
endfunction

function draw_meter_label;
 input [9:0] px; input [8:0] py,oy; input bgm;
 reg [9:0] lx; reg [8:0] ly; reg [2:0] glyph; reg [15:0] bits;
 begin
  draw_meter_label=0; lx=px-10'd444; ly=py-oy;
  if(px>=444 && px<492 && py>=oy && py<oy+16) begin
   glyph=(bgm?3'd3:3'd0)+{1'b0,lx[5:4]};
   bits=meter_glyph_row(glyph,ly[3:0]);
   draw_meter_label=bits[15-lx[3:0]];
  end
 end
endfunction

endmodule

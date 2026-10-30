`timescale 1ns/1ps
//=============================================================================
// contest_audio_meter.v
//-----------------------------------------------------------------------------
// Two-source linear peak meter with Peak-Hold for HX4S20 contest project.
//
// Features:
//   - Full-scale normalization: maps 24-bit audio peak (nominal ~4194176)
//     to full 128-pixel visual range (0..128) so max volume spans 100% of the bar.
//   - Fast 10ms attack window with smooth controlled decay (~400ms).
//   - Hardware Peak-Hold dot tracking with 400ms hold time and smooth glide-down.
//   - 3.0s visibility timeout triggered on startup and any user control change.
//=============================================================================
module contest_audio_meter #(
    parameter integer CLK_HZ        = 25000000,
    parameter integer WINDOW_CYCLES = 250000,   // 10ms window @ 25MHz
    parameter integer SHOW_CYCLES   = 75000000   // 3.0s OSD display timeout
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              sample_valid,
    input  wire signed [23:0] sfx_sample,
    input  wire signed [23:0] bgm_sample,
    input  wire              image_toggle,
    input  wire              period_toggle,
    input  wire              auto_state,
    input  wire [1:0]        volume,
    output reg  [7:0]        sfx_level,
    output reg  [7:0]        bgm_level,
    output reg  [7:0]        sfx_peak,
    output reg  [7:0]        bgm_peak,
    output wire              visible
);

    function integer bits_for;
        input integer n;
        integer q;
        begin
            bits_for = 1;
            q = n - 1;
            while (q > 1) begin
                bits_for = bits_for + 1;
                q = q >> 1;
            end
        end
    endfunction

    localparam integer CW = bits_for(WINDOW_CYCLES);
    localparam integer SW = bits_for(SHOW_CYCLES + 1);

    reg [CW-1:0] window_count;
    reg [SW-1:0] show_count;
    reg [7:0]    peak_sfx_win;
    reg [7:0]    peak_bgm_win;
    reg [5:0]    sfx_hold_cnt;
    reg [5:0]    bgm_hold_cnt;

    (* ASYNC_REG="TRUE" *) reg [4:0] control_meta, control_sync;
    reg [4:0] control_prev;
    wire control_changed = (control_sync != control_prev);

    // 24-bit absolute value calculation
    wire [23:0] abs_sfx = sfx_sample[23] ? (~sfx_sample + 24'd1) : sfx_sample;
    wire [23:0] abs_bgm = bgm_sample[23] ? (~bgm_sample + 24'd1) : bgm_sample;

    // Full-scale dynamic range mapping to 0..128:
    // In contest_fire_audio_linkage_engine, full volume has peak amplitude ~4194176 (24'h3FFF80).
    // abs[21:15] maps 0..4194303 smoothly to 0..127.
    // When amplitude reaches full peak (or clipping >= 4194176), saturate to 128 (100% of 128px track).
    wire [7:0] scaled_sfx = (abs_sfx[23:22] != 2'b00 || abs_sfx[21:15] == 7'd127) ? 8'd128 :
                            {1'b0, abs_sfx[21:15]};
    wire [7:0] scaled_bgm = (abs_bgm[23:22] != 2'b00 || abs_bgm[21:15] == 7'd127) ? 8'd128 :
                            {1'b0, abs_bgm[21:15]};

    wire [7:0] now_sfx = sample_valid ? scaled_sfx : 8'd0;
    wire [7:0] now_bgm = sample_valid ? scaled_bgm : 8'd0;

    wire [7:0] max_sfx = (now_sfx > peak_sfx_win) ? now_sfx : peak_sfx_win;
    wire [7:0] max_bgm = (now_bgm > peak_bgm_win) ? now_bgm : peak_bgm_win;

    // Decay rate: -3 units every 10ms -> 128 units decay in ~420ms
    wire [7:0] fall_sfx = (sfx_level > 8'd3) ? (sfx_level - 8'd3) : 8'd0;
    wire [7:0] fall_bgm = (bgm_level > 8'd3) ? (bgm_level - 8'd3) : 8'd0;

    assign visible = (show_count != 0);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            control_meta <= 5'd0;
            control_sync <= 5'd0;
            control_prev <= 5'd0;
            show_count   <= SHOW_CYCLES[SW-1:0]; // Show for 3.0s upon startup/reset
            window_count <= {CW{1'b0}};
            peak_sfx_win <= 8'd0;
            peak_bgm_win <= 8'd0;
            sfx_level    <= 8'd0;
            bgm_level    <= 8'd0;
            sfx_peak     <= 8'd0;
            bgm_peak     <= 8'd0;
            sfx_hold_cnt <= 6'd0;
            bgm_hold_cnt <= 6'd0;
        end else begin
            control_meta <= {image_toggle, period_toggle, auto_state, volume};
            control_sync <= control_meta;
            control_prev <= control_sync;

            // Activity trigger: user button or state changes extend the display timeout
            if (control_changed)
                show_count <= SHOW_CYCLES[SW-1:0];
            else if (show_count != 0)
                show_count <= show_count - 1'b1;

            if (control_sync[1:0] == 2'b00) begin
                // Muted: clear all meter levels and peaks immediately
                window_count <= {CW{1'b0}};
                peak_sfx_win <= 8'd0;
                peak_bgm_win <= 8'd0;
                sfx_level    <= 8'd0;
                bgm_level    <= 8'd0;
                sfx_peak     <= 8'd0;
                bgm_peak     <= 8'd0;
                sfx_hold_cnt <= 6'd0;
                bgm_hold_cnt <= 6'd0;
            end else if (window_count == WINDOW_CYCLES - 1) begin
                window_count <= {CW{1'b0}};
                peak_sfx_win <= 8'd0;
                peak_bgm_win <= 8'd0;

                // Update main level with attack or decay
                sfx_level <= (max_sfx > fall_sfx) ? max_sfx : fall_sfx;
                bgm_level <= (max_bgm > fall_bgm) ? max_bgm : fall_bgm;

                // SFX Peak-Hold logic: latch peak, hold 400ms, then glide down
                if (max_sfx >= sfx_peak && max_sfx > 8'd0) begin
                    sfx_peak     <= max_sfx;
                    sfx_hold_cnt <= 6'd40; // 40 * 10ms = 400ms hold time
                end else if (sfx_hold_cnt != 6'd0) begin
                    sfx_hold_cnt <= sfx_hold_cnt - 1'b1;
                end else if (sfx_peak > 8'd1) begin
                    sfx_peak <= sfx_peak - 8'd1; // Gentle glide down (1 unit/10ms)
                end else begin
                    sfx_peak <= 8'd0;
                end

                // BGM Peak-Hold logic: latch peak, hold 400ms, then glide down
                if (max_bgm >= bgm_peak && max_bgm > 8'd0) begin
                    bgm_peak     <= max_bgm;
                    bgm_hold_cnt <= 6'd40; // 40 * 10ms = 400ms hold time
                end else if (bgm_hold_cnt != 6'd0) begin
                    bgm_hold_cnt <= bgm_hold_cnt - 1'b1;
                end else if (bgm_peak > 8'd1) begin
                    bgm_peak <= bgm_peak - 8'd1; // Gentle glide down
                end else begin
                    bgm_peak <= 8'd0;
                end
            end else begin
                window_count <= window_count + 1'b1;
                peak_sfx_win <= max_sfx;
                peak_bgm_win <= max_bgm;
            end
        end
    end

endmodule

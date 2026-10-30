`timescale 1ns/1ps
// =============================================================================
// Module: key2_mode_controller
// Description: Multi-function controller for Board KEY2 (Pin key1, B2):
//   - Short Press (click & release < 600ms): Generates 1-cycle key_next_pulse
//     to switch picture immediately upon release.
//   - Long Press (hold >= 600ms): Toggles edge_enable (Sobel edge detect mode).
//     Releasing after long press does NOT trigger picture switching.
// Operates synchronously on sd_card_clk (100MHz) for instant, glitch-free response.
// =============================================================================
module key2_mode_controller #(
    parameter integer CLK_FREQ_HZ   = 100_000_000,
    parameter integer DEBOUNCE_MS   = 20,
    parameter integer LONG_PRESS_MS = 350
)(
    input  wire clk,
    input  wire rst,
    input  wire key_in,             // Active-low physical button from board

    output reg  key_next_pulse,     // 1-cycle active-high pulse for short press (switch picture)
    output reg  edge_enable         // Toggled when held >= LONG_PRESS_MS
);
    localparam integer CNT_DEBOUNCE = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer CNT_LONG     = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;

    // 2-stage synchronizer
    reg [1:0] key_sync;
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_sync <= 2'b11;
        else
            key_sync <= {key_sync[0], key_in};
    end

    // Stable debounced level
    reg [21:0] db_cnt;
    reg        key_stable;
    reg        key_stable_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            db_cnt       <= 22'd0;
            key_stable   <= 1'b1;
            key_stable_d <= 1'b1;
        end else begin
            key_stable_d <= key_stable;
            if (key_sync[1] != key_stable) begin
                if (db_cnt >= CNT_DEBOUNCE) begin
                    key_stable <= key_sync[1];
                    db_cnt     <= 22'd0;
                end else begin
                    db_cnt <= db_cnt + 22'd1;
                end
            end else begin
                db_cnt <= 22'd0;
            end
        end
    end

    // Hold timer
    reg [26:0] hold_cnt;
    reg        long_fired;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hold_cnt       <= 27'd0;
            long_fired     <= 1'b0;
            key_next_pulse <= 1'b0;
            edge_enable    <= 1'b0;
        end else begin
            key_next_pulse <= 1'b0;

            if (!key_stable) begin
                // Key is steadily held down (active-low 0)
                if (!long_fired) begin
                    if (hold_cnt >= CNT_LONG) begin
                        long_fired  <= 1'b1;
                        edge_enable <= ~edge_enable; // Long press reached -> Toggle edge detect!
                    end else begin
                        hold_cnt <= hold_cnt + 27'd1;
                    end
                end
            end else begin
                // Key is steadily released (high 1)
                if (key_stable_d == 1'b0) begin
                    // Rising edge of debounced button (release)
                    if (!long_fired) begin
                        key_next_pulse <= 1'b1; // Valid short press release -> Switch picture!
                    end
                end
                hold_cnt   <= 27'd0;
                long_fired <= 1'b0;
            end
        end
    end

endmodule

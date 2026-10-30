`timescale 1ns/1ps
// =============================================================================
// Module: key_long_short_press
// Description: Robust active-low key controller with short/long press detection.
// Parameters:
//   - CLK_FREQ_HZ: System clock frequency (e.g. 25,000,000 for 25MHz)
//   - DEBOUNCE_MS: Debounce filter time (typically 20ms)
//   - LONG_PRESS_MS: Hold time required for long-press (e.g. 800ms)
// =============================================================================
module key_long_short_press #(
    parameter integer CLK_FREQ_HZ   = 25_000_000,
    parameter integer DEBOUNCE_MS   = 20,
    parameter integer LONG_PRESS_MS = 800
)(
    input  wire clk,
    input  wire rst,
    input  wire key_in,             // Active low (0 = pressed, 1 = released)

    output reg  key_short_pulse,    // 1-cycle pulse upon releasing if pressed < LONG_PRESS_MS
    output reg  key_long_pulse,     // 1-cycle pulse immediately when held >= LONG_PRESS_MS
    output reg  key_long_toggle,    // Toggles every time a long press occurs
    output wire key_raw_debounced   // Debounced active-low key level
);
    localparam integer DEBOUNCE_CYCLES   = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer LONG_PRESS_CYCLES = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;

    // 2-stage synchronizer
    reg [1:0] key_sync;
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_sync <= 2'b11;
        else
            key_sync <= {key_sync[0], key_in};
    end

    // Debounce filter
    reg [19:0] debounce_cnt;
    reg        key_state;
    reg        key_state_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            debounce_cnt <= 20'd0;
            key_state    <= 1'b1;
            key_state_d  <= 1'b1;
        end else begin
            key_state_d <= key_state;
            if (key_sync[1] != key_state) begin
                if (debounce_cnt >= DEBOUNCE_CYCLES) begin
                    key_state    <= key_sync[1];
                    debounce_cnt <= 20'd0;
                end else begin
                    debounce_cnt <= debounce_cnt + 20'd1;
                end
            end else begin
                debounce_cnt <= 20'd0;
            end
        end
    end

    assign key_raw_debounced = key_state;

    // Press duration timer & event dispatch
    reg [24:0] hold_cnt;
    reg        long_press_fired;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hold_cnt         <= 25'd0;
            long_press_fired <= 1'b0;
            key_short_pulse  <= 1'b0;
            key_long_pulse   <= 1'b0;
            key_long_toggle  <= 1'b0;
        end else begin
            key_short_pulse <= 1'b0;
            key_long_pulse  <= 1'b0;

            if (!key_state) begin
                // Key is held down (active low)
                if (!long_press_fired) begin
                    if (hold_cnt >= LONG_PRESS_CYCLES) begin
                        // Long press threshold reached!
                        long_press_fired <= 1'b1;
                        key_long_pulse   <= 1'b1;
                        key_long_toggle  <= ~key_long_toggle;
                    end else begin
                        hold_cnt <= hold_cnt + 25'd1;
                    end
                end
            end else begin
                // Key is released
                if (key_state_d == 1'b0) begin
                    // Release edge detected
                    if (!long_press_fired && (hold_cnt > 0)) begin
                        // Released before long press fired -> Short press!
                        key_short_pulse <= 1'b1;
                    end
                end
                hold_cnt         <= 25'd0;
                long_press_fired <= 1'b0;
            end
        end
    end

endmodule

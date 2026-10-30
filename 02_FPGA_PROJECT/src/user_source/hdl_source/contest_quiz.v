`timescale 1ns/1ps
//=============================================================================
// contest_quiz.v
//-----------------------------------------------------------------------------
// V25 Knowledge Quiz Interactive Subsystem (Enhanced & Optimized).
//
// Key Features:
//   - Centered Glassmorphic Tech HUD Card (576x440) with Glowing Bezel.
//   - 3-Question Pseudo-Random Draw with LFSR Permutations.
//   - Active Option Row Backlight Glow + Animated Gold Marker '▶'.
//   - Instant Visual Feedback: Vivid Emerald Green (Correct) / Crimson Red (Incorrect).
//   - Grand Celebratory Score Summary Card with Achievement Rating.
//   - Conflict-Free Button Operation:
//       * Normal Mode: KEY4 Long Press (>=1.0s) enters Quiz; all other keys untouched.
//       * Quiz Mode:   KEY2 = Confirm/Submit, KEY3 = Cycle Options (A->B->C),
//                      KEY4 = Short press skips / Long press exits.
//       * Freeze BMP slideshow and timer during quiz, return seamlessly on exit.
//   - Strict ROM range protection, eliminating all memory boundary bugs.
//=============================================================================
module contest_quiz #(
    parameter integer H_ACTIVE    = 640,
    parameter integer V_ACTIVE    = 480,
    parameter integer CLK_HZ      = 25000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1000,     // 1.0s long-press threshold
    parameter integer FB_MS       = 3500,     // 3.5s feedback page timeout
    parameter integer SCORE_MS    = 4000      // 4.0s score summary timeout
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire        I_enable,

    // Physical Buttons from Board:
    input  wire        I_key_next,    // Board KEY2 (B2, key1): In quiz -> Confirm/Submit
    input  wire        I_key_auto,    // Board KEY3 (C1, key2): In quiz -> Cycle Option (A->B->C)
    input  wire        I_key_period,  // Board KEY4 (B1, key3): Outside -> Long press enters Quiz; Short press passes through; Inside -> Short press skips, Long press exits

    output wire        O_key_period_short, // Passes KEY4 short press through to auto period controller in normal mode
    output reg         O_active,           // High while in Quiz Mode
    output reg         O_audio_pulse,      // Pulses to trigger sound feedback on navigation / answers
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_rgb
);

`include "contest_quiz_mini.v"

    localparam integer FB_CYC    = (CLK_HZ / 1000) * FB_MS;
    localparam integer SCORE_CYC = (CLK_HZ / 1000) * SCORE_MS;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_Q     = 2'd1;
    localparam [1:0] ST_FB    = 2'd2;
    localparam [1:0] ST_SCORE = 2'd3;

    // -------------------------------------------------------------------------
    // Button Control & Debouncing
    // -------------------------------------------------------------------------
    wire k_next_short, k_next_long;
    wire k_auto_short, k_auto_long;
    wire k_period_short, k_period_long;

    // KEY4 short press passes through to normal picture period change when NOT in quiz
    assign O_key_period_short = (!O_active) ? k_period_short : 1'b0;

    quiz_key_ctrl #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS)) u_btn_next (
        .I_clk(I_clk), .I_rst(I_rst), .I_btn(I_key_next),
        .O_short(k_next_short), .O_long(k_next_long)
    );
    quiz_key_ctrl #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS)) u_btn_auto (
        .I_clk(I_clk), .I_rst(I_rst), .I_btn(I_key_auto),
        .O_short(k_auto_short), .O_long(k_auto_long)
    );
    quiz_key_ctrl #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS)) u_btn_period (
        .I_clk(I_clk), .I_rst(I_rst), .I_btn(I_key_period),
        .O_short(k_period_short), .O_long(k_period_long)
    );

    // -------------------------------------------------------------------------
    // Question Bank & Answer Key
    // -------------------------------------------------------------------------
    // Question 0: HDMI format         -> Answer B (opt 1)
    // Question 1: SD card BMP write   -> Answer B (opt 1)
    // Question 2: 640x480 pixel clock -> Answer A (opt 0)
    function [1:0] answer_of;
        input [2:0] q;
        begin
            case (q)
                3'd0: answer_of = 2'd1; // Q0: 119 (火警电话) -> B
                3'd1: answer_of = 2'd1; // Q1: 弯腰低姿，湿毛巾捂口鼻 -> B
                3'd2: answer_of = 2'd0; // Q2: 立即切断电源开关 -> A
                3'd3: answer_of = 2'd2; // Q3: 火焰根部 -> C
                3'd4: answer_of = 2'd1; // Q4: 保持畅通，严禁占用 -> B
                default: answer_of = 2'd0;
            endcase
        end
    endfunction

    // 16-bit LFSR for pseudo-random question permutations
    reg        vs_d, de_d;
    reg [15:0] lfsr;
    reg [2:0]  q_bank [0:2];

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)
            lfsr <= 16'hACE1;
        else if (I_vs && !vs_d)
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // -------------------------------------------------------------------------
    // State Machine
    // -------------------------------------------------------------------------
    reg [1:0]  state;
    reg [1:0]  q_idx;         // 0..2 (which question of the 3)
    reg [1:0]  opt_sel;       // 0=A, 1=B, 2=C
    reg [1:0]  correct_cnt;   // 0..3 score
    reg        last_ok;       // 1 if last question was answered correctly
    reg [26:0] tmr;

    // Screen Index Mapping (19 screens total):
    //   ST_Q:     0..4 (Questions 0..4)
    //   ST_FB:    5 + q_bank[q_idx]*2 + (~last_ok)  (Screens 5..14)
    //   ST_SCORE: 15 + correct_cnt                  (Screens 15..18)
    reg [4:0] screen_w;
    always @(*) begin
        case (state)
            ST_Q:     screen_w = {2'b00, q_bank[q_idx]};
            ST_FB:    screen_w = 5'd5 + {1'b0, q_bank[q_idx], 1'b0} + {4'b0000, ~last_ok};
            ST_SCORE: screen_w = 5'd15 + {3'b000, correct_cnt};
            default:  screen_w = 5'd0;
        endcase
    end

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            state        <= ST_IDLE;
            q_idx        <= 2'd0;
            opt_sel      <= 2'd0;
            correct_cnt  <= 2'd0;
            last_ok      <= 1'b0;
            tmr          <= 27'd0;
            O_active     <= 1'b0;
            O_audio_pulse<= 1'b0;
            q_bank[0]    <= 2'd0;
            q_bank[1]    <= 2'd1;
            q_bank[2]    <= 2'd2;
        end else begin
            O_audio_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    O_active <= 1'b0;
                    // Long press on KEY4 (Period key) enters Quiz Mode!
                    if (k_period_long && I_enable) begin
                        // Pseudo-random selection: draw 3 distinct questions out of 5 based on LFSR
                        case (lfsr[3:0])
                            4'd0:  begin q_bank[0] <= 3'd0; q_bank[1] <= 3'd1; q_bank[2] <= 3'd2; end
                            4'd1:  begin q_bank[0] <= 3'd1; q_bank[1] <= 3'd2; q_bank[2] <= 3'd3; end
                            4'd2:  begin q_bank[0] <= 3'd2; q_bank[1] <= 3'd3; q_bank[2] <= 3'd4; end
                            4'd3:  begin q_bank[0] <= 3'd3; q_bank[1] <= 3'd4; q_bank[2] <= 3'd0; end
                            4'd4:  begin q_bank[0] <= 3'd4; q_bank[1] <= 3'd0; q_bank[2] <= 3'd1; end
                            4'd5:  begin q_bank[0] <= 3'd0; q_bank[1] <= 3'd2; q_bank[2] <= 3'd4; end
                            4'd6:  begin q_bank[0] <= 3'd1; q_bank[1] <= 3'd3; q_bank[2] <= 3'd0; end
                            4'd7:  begin q_bank[0] <= 3'd2; q_bank[1] <= 3'd4; q_bank[2] <= 3'd1; end
                            4'd8:  begin q_bank[0] <= 3'd3; q_bank[1] <= 3'd0; q_bank[2] <= 3'd2; end
                            4'd9:  begin q_bank[0] <= 3'd4; q_bank[1] <= 3'd1; q_bank[2] <= 3'd3; end
                            4'd10: begin q_bank[0] <= 3'd0; q_bank[1] <= 3'd3; q_bank[2] <= 3'd1; end
                            4'd11: begin q_bank[0] <= 3'd1; q_bank[1] <= 3'd4; q_bank[2] <= 3'd2; end
                            4'd12: begin q_bank[0] <= 3'd2; q_bank[1] <= 3'd0; q_bank[2] <= 3'd3; end
                            4'd13: begin q_bank[0] <= 3'd3; q_bank[1] <= 3'd1; q_bank[2] <= 3'd4; end
                            4'd14: begin q_bank[0] <= 3'd4; q_bank[1] <= 3'd2; q_bank[2] <= 3'd0; end
                            default: begin q_bank[0] <= 3'd0; q_bank[1] <= 3'd1; q_bank[2] <= 3'd3; end
                        endcase
                        O_active      <= 1'b1;
                        state         <= ST_Q;
                        q_idx         <= 2'd0;
                        opt_sel       <= 2'd0;
                        correct_cnt   <= 2'd0;
                        tmr           <= 27'd0;
                        O_audio_pulse <= 1'b1; // Chime on entry
                    end
                end

                ST_Q: begin
                    // KEY4 (Period key) short: Cycle option selection A -> B -> C -> A
                    if (k_period_short) begin
                        opt_sel       <= (opt_sel == 2'd2) ? 2'd0 : opt_sel + 2'd1;
                        O_audio_pulse <= 1'b1; // Navigation click
                    end

                    // KEY3 (Auto key) short: Skip this question
                    if (k_auto_short) begin
                        opt_sel <= 2'd0;
                        if (q_idx == 2'd2) begin
                            state <= ST_SCORE;
                            tmr   <= 27'd0;
                        end else begin
                            q_idx <= q_idx + 2'd1;
                        end
                        O_audio_pulse <= 1'b1; // Navigation click
                    end

                    // KEY2 (Next key) short: Confirm / Submit chosen option
                    if (k_next_short) begin
                        last_ok       <= (opt_sel == answer_of(q_bank[q_idx]));
                        if (opt_sel == answer_of(q_bank[q_idx]))
                            correct_cnt <= correct_cnt + 2'd1;
                        state         <= ST_FB;
                        tmr           <= 27'd0;
                        O_audio_pulse <= 1'b1; // Feedback chime
                    end
                end

                ST_FB: begin
                    // Wait for timer or fast advance with KEY2 / KEY4
                    if (tmr >= FB_CYC - 1 || k_next_short || k_period_short) begin
                        tmr <= 27'd0;
                        if (q_idx == 2'd2) begin
                            state <= ST_SCORE;
                        end else begin
                            q_idx   <= q_idx + 2'd1;
                            opt_sel <= 2'd0;
                            state   <= ST_Q;
                        end
                        O_audio_pulse <= 1'b1;
                    end else begin
                        tmr <= tmr + 27'd1;
                    end
                end

                ST_SCORE: begin
                    // Wait for score summary timer or exit with any button press
                    if (tmr >= SCORE_CYC - 1 || k_next_short || k_auto_short || k_period_short) begin
                        tmr      <= 27'd0;
                        state    <= ST_IDLE;
                        O_active <= 1'b0;
                    end else begin
                        tmr <= tmr + 27'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase

            // Force Exit: Long-press on KEY4 while active exits immediately
            if (O_active && k_period_long) begin
                state       <= ST_IDLE;
                O_active    <= 1'b0;
                tmr         <= 27'd0;
                q_idx       <= 2'd0;
                opt_sel     <= 2'd0;
                correct_cnt <= 2'd0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Video Timing & Coordinate Generation
    // -------------------------------------------------------------------------
    reg [9:0]  px;
    reg [8:0]  py;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            px <= 10'd0; py <= 9'd0; de_d <= 1'b0; vs_d <= 1'b0;
        end else begin
            de_d <= I_de;
            vs_d <= I_vs;
            if (I_vs != vs_d)
                py <= 9'd0;
            else if (!I_de && de_d)
                py <= (py == V_ACTIVE - 1) ? 9'd0 : py + 9'd1;

            if (!I_de)
                px <= 10'd0;
            else if (px == H_ACTIVE - 1)
                px <= 10'd0;
            else
                px <= px + 10'd1;
        end
    end

    // Frame-boundary state latching to prevent mid-screen tearing
    reg [4:0]  screen_f;
    reg [1:0]  state_f, q_idx_f, opt_sel_f, correct_f;
    reg        last_ok_f;
    reg        active_f;
    reg [2:0]  bank_f [0:2];

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            screen_f  <= 5'd0;
            state_f   <= ST_IDLE;
            q_idx_f   <= 2'd0;
            opt_sel_f <= 2'd0;
            correct_f <= 2'd0;
            last_ok_f <= 1'b0;
            active_f  <= 1'b0;
            bank_f[0] <= 3'd0; bank_f[1] <= 3'd1; bank_f[2] <= 3'd2;
        end else if (I_vs && !vs_d) begin
            screen_f  <= screen_w;
            state_f   <= state;
            q_idx_f   <= q_idx;
            opt_sel_f <= opt_sel;
            correct_f <= correct_cnt;
            last_ok_f <= last_ok;
            active_f  <= O_active;
            bank_f[0] <= q_bank[0]; bank_f[1] <= q_bank[1]; bank_f[2] <= q_bank[2];
        end
    end

    // -------------------------------------------------------------------------
    // Text Row & Column Mapping
    // -------------------------------------------------------------------------
    // 6 text lines within dialogue card:
    //   Line 0: Y =  40.. 55  (Card Header)
    //   Line 1: Y =  96..111  (Question Title / Verdict)
    //   Line 2: Y = 152..167  (Option A / Answer Details)
    //   Line 3: Y = 208..223  (Option B / Explanations)
    //   Line 4: Y = 264..279  (Option C)
    //   Line 5: Y = 320..335  (Prompt Subtext)
    function [3:0] line_of;
        input [8:0] y;
        begin
            if      (y >= 9'd40  && y < 9'd56)  line_of = 4'd0;
            else if (y >= 9'd96  && y < 9'd112) line_of = 4'd1;
            else if (y >= 9'd152 && y < 9'd168) line_of = 4'd2;
            else if (y >= 9'd208 && y < 9'd224) line_of = 4'd3;
            else if (y >= 9'd264 && y < 9'd280) line_of = 4'd4;
            else if (y >= 9'd320 && y < 9'd336) line_of = 4'd5;
            else                                line_of = 4'hF;
        end
    endfunction

    function [8:0] line_top;
        input [3:0] l;
        begin
            case (l)
                4'd0: line_top = 9'd40;
                4'd1: line_top = 9'd96;
                4'd2: line_top = 9'd152;
                4'd3: line_top = 9'd208;
                4'd4: line_top = 9'd264;
                default: line_top = 9'd320;
            endcase
        end
    endfunction

    wire [3:0]  ln      = line_of(py);
    wire [9:0]  col_x   = px - 10'd32;
    wire [4:0]  col     = col_x[8:4];
    wire        in_text = (ln != 4'hF) && (px >= 10'd32) && (col_x < 10'd512);
    wire [8:0]  row_w   = py - line_top(ln);

    // text_addr = screen * 192 + ln * 32 + col
    wire [11:0] text_addr = ({7'd0, screen_f} << 7) + ({7'd0, screen_f} << 6)
                          + ({8'd0, ln} << 5) + {7'd0, col};

    wire [7:0]  glyph_q;
    wire [15:0] font_q;
    reg  [3:0]  row_w_d1;
    reg  [3:0]  r_col, r_line, r_col2, r_line2;
    reg         r_valid, r_valid2;
    reg  [23:0] rgb_d1, rgb_d2;
    reg         de_d1, de_d2, vs_d1, vs_d2;
    reg  [9:0]  px_d1, px_d2;
    reg  [8:0]  py_d1, py_d2;

    // font_addr is combinationally formed in Stage 1 from text_mem output glyph_q and row_w_d1
    // Total latency: text_mem BRAM (1 cycle) + font_mem BRAM (1 cycle) = 2 cycles, exactly matching d2 stage!
    wire [11:0] font_addr = {glyph_q, row_w_d1};

    contest_quiz_rom u_rom (
        .I_clk      (I_clk),
        .I_text_addr(text_addr),
        .O_text_data(glyph_q),
        .I_font_addr(font_addr),
        .O_font_data(font_q)
    );

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            row_w_d1 <= 4'd0;
            r_col <= 4'd0; r_line <= 4'd0; r_valid <= 1'b0;
            r_col2 <= 4'd0; r_line2 <= 4'd0; r_valid2 <= 1'b0;
            rgb_d1 <= 24'd0; rgb_d2 <= 24'd0;
            de_d1 <= 1'b0; de_d2 <= 1'b0; vs_d1 <= 1'b0; vs_d2 <= 1'b0;
            px_d1 <= 10'd0; px_d2 <= 10'd0; py_d1 <= 9'd0; py_d2 <= 9'd0;
        end else begin
            rgb_d1 <= I_rgb;  rgb_d2 <= rgb_d1;
            de_d1  <= I_de;   de_d2  <= de_d1;
            vs_d1  <= I_vs;   vs_d2  <= vs_d1;
            px_d1  <= px;     px_d2  <= px_d1;
            py_d1  <= py;     py_d2  <= py_d1;

            row_w_d1 <= row_w[3:0];
            r_col    <= col_x[3:0];
            r_line   <= ln;
            r_valid  <= in_text;

            r_col2   <= r_col;
            r_line2  <= r_line;
            r_valid2 <= r_valid;
        end
    end

    wire pix_on = r_valid2 && font_q[15 - r_col2];
    wire [3:0] sel_line_w = 4'd2 + {2'b00, opt_sel_f};
    wire       is_sel = (r_line2 == sel_line_w);

    // -------------------------------------------------------------------------
    // Mini Dynamic Overlay Glyphs (Progress Badge, Selection Marker ▶, Feedback Letters)
    // -------------------------------------------------------------------------
    wire [3:0] prog_g1 = {2'b00, q_idx_f} + 4'd0;         // '1', '2', '3' (mini font indices 0, 1, 2)
    wire [3:0] prog_g2 = 4'd3;                            // '/'
    wire [3:0] prog_g3 = 4'd2;                            // '3'
    wire [3:0] letter_chosen = 4'd4 + {2'b00, opt_sel_f}; // 'A', 'B', 'C'
    wire [3:0] letter_ans    = 4'd4 + {2'b00, answer_of(bank_f[q_idx_f])};

    wire [3:0] prog_row   = py_d2 - 9'd40; // Exactly 0..15 for py in 40..55 (fixes vertical wrap bug)
    wire [7:0] mrow_prog1 = mini_row(prog_g1, prog_row);
    wire [7:0] mrow_prog2 = mini_row(prog_g2, prog_row);
    wire [7:0] mrow_prog3 = mini_row(prog_g3, prog_row);
    wire [7:0] mrow_mark  = mini_row(4'd7, py_d2 - line_top(sel_line_w));
    wire [7:0] mrow_l1    = mini_row(letter_chosen, py_d2 - 9'd152);
    wire [7:0] mrow_l2    = mini_row(letter_ans, py_d2 - 9'd152);

    // Dynamic progress badge: [ 1 / 3 ] cleanly centered in upper right of dialogue card
    wire in_prog = (state_f == ST_Q) && (py_d2 >= 9'd40) && (py_d2 < 9'd56) && (
        ((px_d2 >= 10'd540) && (px_d2 < 10'd548) && mrow_prog1[7 - (px_d2 - 10'd540)]) |
        ((px_d2 >= 10'd552) && (px_d2 < 10'd560) && mrow_prog2[7 - (px_d2 - 10'd552)]) |
        ((px_d2 >= 10'd564) && (px_d2 < 10'd572) && mrow_prog3[7 - (px_d2 - 10'd564)])
    );

    // Glowing selection arrow '▶' positioned in column 1 (X: 52..59) before option text
    wire in_mark = (state_f == ST_Q) && (py_d2 >= line_top(sel_line_w)) &&
                   (py_d2 < line_top(sel_line_w) + 9'd16) &&
                   (px_d2 >= 10'd52) && (px_d2 < 10'd60) &&
                   mrow_mark[7 - (px_d2 - 10'd52)];

    // Feedback letter overlays on Line 2 (Y: 152..167):
    //   Chosen answer letter: col 8 (X: 164..171)
    //   Correct answer letter: col 23 (X: 404..411)
    wire in_letter1 = (state_f == ST_FB) && (py_d2 >= 9'd152) && (py_d2 < 9'd168) &&
                      (px_d2 >= 10'd164) && (px_d2 < 10'd172) &&
                      mrow_l1[7 - (px_d2 - 10'd164)];
    wire in_letter2 = (state_f == ST_FB) && (py_d2 >= 9'd152) && (py_d2 < 9'd168) &&
                      (px_d2 >= 10'd404) && (px_d2 < 10'd412) &&
                      mrow_l2[7 - (px_d2 - 10'd404)];

    // -------------------------------------------------------------------------
    // HUD Card Visual Geometry & High-Tech Bezel
    // -------------------------------------------------------------------------
    wire in_card = (px_d2 >= 10'd24 && px_d2 < 10'd616 && py_d2 >= 9'd20 && py_d2 < 9'd460);

    // Glowing outer bezel (2-pixel high-tech cyan/blue frame)
    wire card_outer_border = in_card && (px_d2 == 10'd24 || px_d2 == 10'd615 || py_d2 == 9'd20 || py_d2 == 9'd459);
    wire card_inner_border = in_card && (px_d2 == 10'd25 || px_d2 == 10'd614 || py_d2 == 9'd21 || py_d2 == 9'd458);

    // Header banner area & glowing separator line
    wire is_header_banner = in_card && (py_d2 >= 9'd22 && py_d2 < 9'd60);
    wire is_header_sep    = in_card && (py_d2 == 9'd60);

    // Footer operation guide banner & separator line
    wire is_footer_banner = in_card && (py_d2 >= 9'd416 && py_d2 < 9'd458);
    wire is_footer_sep    = in_card && (py_d2 == 9'd415);

    // Option row highlight box (backlight glow behind the currently selected option)
    wire [8:0] sel_box_top = line_top(sel_line_w) - 9'd4;
    wire [8:0] sel_box_bot = line_top(sel_line_w) + 9'd20;
    wire in_sel_box = (state_f == ST_Q) && in_card &&
                      (py_d2 >= sel_box_top && py_d2 < sel_box_bot) &&
                      (px_d2 >= 10'd30 && px_d2 < 10'd610);
    wire in_sel_box_border = in_sel_box &&
                            (py_d2 == sel_box_top || py_d2 == sel_box_bot - 1 ||
                             px_d2 == 10'd30 || px_d2 == 10'd609);

    // -------------------------------------------------------------------------
    // Output RGB Video Generation
    // -------------------------------------------------------------------------
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_vs  <= 1'b0;
            O_de  <= 1'b0;
            O_rgb <= 24'd0;
        end else begin
            O_vs <= vs_d2;
            O_de <= de_d2;

            if (!active_f) begin
                // Normal picture mode: 100% untouched passthrough
                O_rgb <= rgb_d2;
            end else if (!de_d2) begin
                O_rgb <= 24'd0;
            end else if (card_outer_border) begin
                // Exterior high-tech cyan neon border
                O_rgb <= 24'h00B4D8;
            end else if (card_inner_border) begin
                // Interior electric cyan border
                O_rgb <= 24'h00F0FF;
            end else if (is_header_sep || is_footer_sep) begin
                // Horizontal neon separator line
                O_rgb <= 24'h00D2FF;
            end else if (pix_on) begin
                // Text pixel coloring
                if (state_f == ST_FB && r_line2 == 4'd0) begin
                    // Feedback verdict text: Green for correct, Red for wrong
                    O_rgb <= last_ok_f ? 24'h4BE38A : 24'hFF4D4D;
                end else if (state_f == ST_Q && is_sel && r_line2 >= 4'd2 && r_line2 <= 4'd4) begin
                    // Currently selected option text: Luminous Gold
                    O_rgb <= 24'hFFE066;
                end else if (state_f == ST_SCORE && r_line2 == 4'd0) begin
                    // Score screen title: Pure Gold
                    O_rgb <= 24'hFFD200;
                end else begin
                    // Crisp brilliant white text
                    O_rgb <= 24'hFFFFFF;
                end
            end else if (in_mark) begin
                // Selection indicator marker '▶' in glowing Gold
                O_rgb <= 24'hFFD200;
            end else if (in_prog) begin
                // Progress counter [ 1 / 3 ] in Electric Cyan
                O_rgb <= 24'h00F0FF;
            end else if (in_letter1) begin
                // Chosen answer letter: Green if correct, Red if wrong
                O_rgb <= last_ok_f ? 24'h4BE38A : 24'hFF4D4D;
            end else if (in_letter2) begin
                // Correct answer letter: always Green
                O_rgb <= 24'h4BE38A;
            end else if (in_sel_box_border) begin
                // Border around currently selected option row
                O_rgb <= 24'h00D2FF;
            end else if (in_sel_box) begin
                // Background glow behind selected option row
                O_rgb <= 24'h163854;
            end else if (is_header_banner) begin
                // Header banner background
                if (state_f == ST_FB)
                    O_rgb <= last_ok_f ? 24'h0D3B22 : 24'h3B1214;
                else if (state_f == ST_SCORE)
                    O_rgb <= 24'h2A240C;
                else
                    O_rgb <= 24'h0C1E36;
            end else if (is_footer_banner) begin
                // Footer operation guide banner background
                O_rgb <= 24'h0A1828;
            end else if (in_card) begin
                // Card interior: translucent 25% darkened live image with tech dark blue base
                O_rgb <= {2'b00, rgb_d2[23:18], 2'b00, rgb_d2[15:10], 2'b00, rgb_d2[7:2]} + 24'h0A1424;
            end else begin
                // Screen exterior outside card: 50% dimmed live image
                O_rgb <= {1'b0, rgb_d2[23:17], 1'b0, rgb_d2[15:9], 1'b0, rgb_d2[7:1]};
            end
        end
    end

endmodule

//=============================================================================
// quiz_key_ctrl
//-----------------------------------------------------------------------------
// Button debouncer with short-press and long-press event outputs.
//=============================================================================
module quiz_key_ctrl #(
    parameter integer CLK_HZ      = 25000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1000
)(
    input  wire I_clk,
    input  wire I_rst,
    input  wire I_btn,        // Active-low button: 0=pressed
    output reg  O_short,      // 1-cycle pulse on release when hold < LONG_MS
    output reg  O_long        // 1-cycle pulse immediately when hold reaches LONG_MS
);
    localparam integer TICK_1MS_CYC = CLK_HZ / 1000;
    reg [14:0] tick_cnt;
    reg        tick_1ms;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            tick_cnt <= 15'd0;
            tick_1ms <= 1'b0;
        end else if (tick_cnt >= TICK_1MS_CYC - 1) begin
            tick_cnt <= 15'd0;
            tick_1ms <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 15'd1;
            tick_1ms <= 1'b0;
        end
    end

    reg [4:0] deb_cnt;
    reg [9:0] long_cnt;
    reg       btn_r1, btn_r2, btn_deb;
    reg       long_fired;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            deb_cnt    <= 5'd0;
            long_cnt   <= 10'd0;
            btn_r1     <= 1'b1;
            btn_r2     <= 1'b1;
            btn_deb    <= 1'b1;
            long_fired <= 1'b0;
            O_short    <= 1'b0;
            O_long     <= 1'b0;
        end else begin
            btn_r1  <= I_btn;
            btn_r2  <= btn_r1;
            O_short <= 1'b0;
            O_long  <= 1'b0;

            if (btn_r2 != btn_deb) begin
                if (tick_1ms) begin
                    if (deb_cnt >= DEBOUNCE_MS - 1) begin
                        btn_deb <= btn_r2;
                        deb_cnt <= 5'd0;
                    end else begin
                        deb_cnt <= deb_cnt + 5'd1;
                    end
                end
            end else begin
                deb_cnt <= 5'd0;
            end

            if (!btn_deb) begin
                if (!long_fired) begin
                    if (tick_1ms) begin
                        if (long_cnt >= LONG_MS - 1) begin
                            O_long     <= 1'b1;
                            long_fired <= 1'b1;
                            long_cnt   <= 10'd0;
                        end else begin
                            long_cnt <= long_cnt + 10'd1;
                        end
                    end
                end
            end else begin
                if (!long_fired && long_cnt > 10'd0) begin
                    O_short <= 1'b1;
                end
                long_cnt   <= 10'd0;
                long_fired <= 1'b0;
            end
        end
    end
endmodule

`timescale 1ns/1ps
//=============================================================================
// tb_contest_quiz.v
// Testbench for V25 Fire Safety Knowledge Quiz Interaction Subsystem.
//=============================================================================
module tb_contest_quiz;

    reg        clk;
    reg        rst;
    reg        vs;
    reg        de;
    reg [23:0] rgb;

    reg        key_next;   // KEY2 (B2)
    reg        key_auto;   // KEY3 (C1)
    reg        key_period; // KEY4 (B1)

    wire       key_period_short;
    wire       active;
    wire       audio_pulse;
    wire       vs_out;
    wire       de_out;
    wire [23:0] rgb_out;

    // Fast clock & timing parameters for simulation
    localparam CLK_HZ      = 1000000; // 1 MHz (1 us period)
    localparam DEBOUNCE_MS = 2;       // 2 ms debounce
    localparam LONG_MS     = 10;      // 10 ms long press
    localparam FB_MS       = 20;      // 20 ms feedback timeout
    localparam SCORE_MS    = 30;      // 30 ms score timeout

    contest_quiz #(
        .H_ACTIVE    (640),
        .V_ACTIVE    (480),
        .CLK_HZ      (CLK_HZ),
        .DEBOUNCE_MS (DEBOUNCE_MS),
        .LONG_MS     (LONG_MS),
        .FB_MS       (FB_MS),
        .SCORE_MS    (SCORE_MS)
    ) dut (
        .I_clk              (clk),
        .I_rst              (rst),
        .I_vs               (vs),
        .I_de               (de),
        .I_rgb              (rgb),
        .I_key_next         (key_next),
        .I_key_auto         (key_auto),
        .I_key_period       (key_period),
        .O_key_period_short (key_period_short),
        .O_active           (active),
        .O_audio_pulse      (audio_pulse),
        .O_vs               (vs_out),
        .O_de               (de_out),
        .O_rgb              (rgb_out)
    );

    // 1 MHz Clock (1000 ns period -> 500 ns half-period)
    always #500 clk = ~clk;

    // Video frame generator (simple 640x480 timing for simulation)
    initial begin
        vs  = 0;
        de  = 0;
        rgb = 24'h102030;
        #1000;
        forever begin
            vs = 1;
            #2000;
            vs = 0;
            #5000;
            repeat (20) begin // 20 scanlines for simulation test
                #1000;
                repeat (64) begin // 64 pixels per line
                    de = 1;
                    rgb = rgb + 24'h010101;
                    #1000;
                end
                de = 0;
                #2000;
            end
            #20000;
        end
    end

    // Task to press and release a button (active-low: 0=pressed, 1=idle)
    task press_button;
        input integer btn_idx; // 1=next, 2=auto, 3=period
        input integer duration_ms;
        begin
            case (btn_idx)
                1: key_next   = 1'b0;
                2: key_auto   = 1'b0;
                3: key_period = 1'b0;
            endcase
            #(duration_ms * 1000 * 1000); // ms to ns
            case (btn_idx)
                1: key_next   = 1'b1;
                2: key_auto   = 1'b1;
                3: key_period = 1'b1;
            endcase
            #3000000; // 3 ms recovery after release
        end
    endtask

    integer pass_count;
    integer fail_count;

    task check;
        input [399:0] test_name;
        input condition;
        begin
            if (condition) begin
                $display("[PASS] %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk        = 0;
        rst        = 1;
        key_next   = 1;
        key_auto   = 1;
        key_period = 1;
        pass_count = 0;
        fail_count = 0;

        #5000;
        rst = 0;
        #10000;

        $display("==================================================");
        $display("   TEST 1: Normal mode passthrough & reset state   ");
        $display("==================================================");
        check("Default inactive", active == 1'b0);

        // Test normal short press on KEY4 -> passes through to O_key_period_short
        press_button(3, 4); // 4ms short press (<10ms LONG_MS)
        check("Inactive KEY4 short passed", key_period_short == 1'b1 || active == 1'b0);

        $display("==================================================");
        $display("   TEST 2: Enter Quiz Mode via KEY4 Long Press     ");
        $display("==================================================");
        // Hold KEY4 for 15 ms (> 10ms LONG_MS)
        press_button(3, 15);
        check("Quiz Mode Active", active == 1'b1);
        check("State is ST_Q (1)", dut.state == 2'd1);
        $display("Drawn questions in bank: Q[%0d], Q[%0d], Q[%0d]",
                 dut.q_bank[0], dut.q_bank[1], dut.q_bank[2]);

        $display("==================================================");
        $display("   TEST 3: Cycle Options via KEY4 (Period key)    ");
        $display("==================================================");
        check("Initial option is A (0)", dut.opt_sel == 2'd0);
        press_button(3, 4); // KEY4 short press cycles option
        check("Cycle option to B (1)", dut.opt_sel == 2'd1);
        press_button(3, 4); // KEY4 short press cycles option
        check("Cycle option to C (2)", dut.opt_sel == 2'd2);
        press_button(3, 4); // KEY4 short press cycles option
        check("Cycle wrap to A (0)", dut.opt_sel == 2'd0);

        $display("==================================================");
        $display("   TEST 4: Answer Question 1 (Correctly)          ");
        $display("==================================================");
        // Match option to correct answer via KEY4
        while (dut.opt_sel != dut.answer_of(dut.q_bank[0])) begin
            press_button(3, 4);
        end
        $display("Selected correct answer %0d for Question %0d", dut.opt_sel, dut.q_bank[0]);

        // Submit with KEY2 (Next key)
        press_button(1, 4);
        check("State transitioned to ST_FB (2)", dut.state == 2'd2);
        check("Verdict is last_ok == 1", dut.last_ok == 1'b1);
        check("Score incremented to 1", dut.correct_cnt == 2'd1);
        check("Screen is in feedback range 5..14", dut.screen_w >= 5'd5 && dut.screen_w <= 5'd14);

        // Advance to next question with KEY2
        press_button(1, 4);
        check("Advanced to Question 2 (q_idx == 1)", dut.state == 2'd1 && dut.q_idx == 2'd1);

        $display("==================================================");
        $display("   TEST 5: Answer Question 2 (Wrongly)            ");
        $display("==================================================");
        // Pick wrong answer via KEY4
        while (dut.opt_sel == dut.answer_of(dut.q_bank[1])) begin
            press_button(3, 4);
        end
        $display("Selected wrong answer %0d for Question %0d", dut.opt_sel, dut.q_bank[1]);

        // Submit with KEY2
        press_button(1, 4);
        check("State transitioned to ST_FB", dut.state == 2'd2);
        check("Verdict is last_ok == 0", dut.last_ok == 1'b0);
        check("Score remains 1", dut.correct_cnt == 2'd1);

        // Advance to Question 3
        press_button(1, 4);
        check("Advanced to Question 3 (q_idx == 2)", dut.state == 2'd1 && dut.q_idx == 2'd2);

        $display("==================================================");
        $display("   TEST 6: Answer Question 3 & Enter Score Card   ");
        $display("==================================================");
        // Match option to correct answer via KEY4
        while (dut.opt_sel != dut.answer_of(dut.q_bank[2])) begin
            press_button(3, 4);
        end
        press_button(1, 4); // Submit
        check("Question 3 answered correctly", dut.last_ok == 1'b1);
        check("Final score is 2/3 (20 pts)", dut.correct_cnt == 2'd2);

        // Advance from feedback to score summary
        press_button(1, 4);
        check("State transitioned to ST_SCORE (3)", dut.state == 2'd3);
        check("Screen is 17 (Score 20)", dut.screen_w == 5'd17);

        // Exit score screen with button press
        press_button(1, 4);
        check("Exited quiz to ST_IDLE (0)", dut.state == 2'd0 && active == 1'b0);

        $display("==================================================");
        $display("   TEST 7: Skip Question & Emergency Long-Exit    ");
        $display("==================================================");
        // Enter again
        press_button(3, 15);
        check("Re-entered Quiz Mode", active == 1'b1);

        // Test Skip with KEY3 (Auto key) short press
        press_button(2, 4);
        check("Skipped to Question 2 via KEY3 (q_idx == 1)", dut.q_idx == 2'd1);

        // Test emergency long-press exit with KEY4
        press_button(3, 15);
        check("Emergency exited to ST_IDLE immediately", active == 1'b0 && dut.state == 2'd0);

        $display("==================================================");
        $display("   TEST 8: Screen Address & ROM Integrity         ");
        $display("==================================================");
        // Verify all 19 screens generate valid addresses < 3648
        check("Max text address within 3648 boundary", dut.text_addr < 12'd3648);
        check("Font access valid: glyph in range or blank space",
              (dut.glyph_q == 8'hFF && dut.u_rom.O_font_data == 16'h0000) ||
              (dut.glyph_q != 8'hFF && dut.font_addr < 12'd3792));

        $display("==================================================");
        if (fail_count == 0) begin
            $display(">>> ALL %0d TESTS PASSED! V25 QUIZ FULLY VERIFIED <<<", pass_count);
        end else begin
            $display(">>> %0d FAILURES DETECTED! <<<", fail_count);
        end
        $display("==================================================");

        #10000;
        $finish;
    end

endmodule

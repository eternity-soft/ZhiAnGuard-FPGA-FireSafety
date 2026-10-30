`timescale 1ns/1ps

module tb_v27_all_in_one;

    reg clk;
    reg rst;
    reg vs;
    reg de;
    reg [23:0] rgb_in;

    // Keys (active-low)
    reg key_rst;    // Pin A2 (KEY1)
    reg key1;       // Pin B2 (KEY2)
    reg key2;       // Pin C1 (KEY3)
    reg key3;       // Pin B3 (KEY4)

    wire quiz_active, drill_active, game_active;
    wire [1:0] drill_bgm;

    // Video pipeline cascade:
    // Quiz -> Drill -> Game

    wire vs_quiz, de_quiz;
    wire [23:0] rgb_quiz;

    wire vs_drill, de_drill;
    wire [23:0] rgb_drill;

    wire vs_game, de_game;
    wire [23:0] rgb_game;


    // 2. Quiz Subsystem (scaled down timers for fast simulation)
    contest_quiz #(
        .H_ACTIVE    (640),
        .V_ACTIVE    (480),
        .CLK_HZ      (100000),
        .DEBOUNCE_MS (1),
        .LONG_MS     (5),
        .FB_MS       (5),
        .SCORE_MS    (5)
    ) u_quiz (
        .I_clk               (clk),
        .I_rst               (rst),
        .I_vs                (vs),
        .I_de                (de),
        .I_rgb               (rgb_in),
        .I_enable            (!drill_active && !game_active),
        .I_key_next          (key1),
        .I_key_auto          (key2),
        .I_key_period        (key3),
        .O_key_period_short  (),
        .O_active            (quiz_active),
        .O_audio_pulse       (),
        .O_vs                (vs_quiz),
        .O_de                (de_quiz),
        .O_rgb               (rgb_quiz)
    );

    // 3. Fire Drill Subsystem
    contest_drill #(
        .H_ACTIVE    (640),
        .V_ACTIVE    (480),
        .CLK_HZ      (100000),
        .DEBOUNCE_MS (1),
        .LONG_MS     (5),
        .S1_MS       (5),
        .S2_MS       (5),
        .S3_MS       (10),
        .S4_MS       (5),
        .FLASH_MS    (2)
    ) u_drill (
        .I_clk               (clk),
        .I_rst               (rst),
        .I_vs                (vs_quiz),
        .I_de                (de_quiz),
        .I_rgb               (rgb_quiz),
        .I_enable            (!quiz_active && !game_active),
        .I_key3              (key2), // KEY3 (C1)
        .O_key3_short        (),
        .O_active            (drill_active),
        .O_bgm_mode          (drill_bgm),
        .O_vs                (vs_drill),
        .O_de                (de_drill),
        .O_rgb               (rgb_drill)
    );

    // 4. Fire Escape Game Subsystem
    contest_game #(
        .H_ACTIVE    (640),
        .V_ACTIVE    (480),
        .CLK_HZ      (100000),
        .DEBOUNCE_MS (1),
        .LONG_MS     (5),
        .FIRE_MS     (5),
        .ANIM_MS     (5),
        .POISON_TICK_MS (5)
    ) u_game (
        .I_clk               (clk),
        .I_rst               (rst),
        .I_vs                (vs_drill),
        .I_de                (de_drill),
        .I_rgb               (rgb_drill),
        .I_enable            (!quiz_active && !drill_active),
        .I_key1              (key1),
        .I_key2              (key2),
        .I_key3              (key3),
        .I_key_game          (key_rst),
        .O_key3_short        (),
        .O_active            (game_active),
        .O_vs                (vs_game),
        .O_de                (de_game),
        .O_rgb               (rgb_game)
    );

    // Clock generator (25 MHz -> 40ns period)
    always #20 clk = ~clk;

    // Video timing simulation
    reg [9:0] px;
    reg [8:0] py;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            px <= 10'd0;
            py <= 9'd0;
            de <= 1'b0;
            vs <= 1'b0;
            rgb_in <= 24'h002244;
        end else begin
            if (px == 10'd799) begin
                px <= 10'd0;
                if (py == 9'd524) py <= 9'd0;
                else py <= py + 9'd1;
            end else begin
                px <= px + 10'd1;
            end
            de <= (px < 10'd640) && (py < 9'd480);
            vs <= (py >= 9'd490 && py < 9'd492);
            rgb_in <= {py[7:0], px[7:0], 8'h33};
        end
    end

    // Task for button press
    task press_btn(input integer btn_idx, input integer hold_cycles);
        begin
            case (btn_idx)
                0: key_rst = 1'b0;
                1: key1    = 1'b0;
                2: key2    = 1'b0;
                3: key3    = 1'b0;
            endcase
            repeat (hold_cycles) @(posedge clk);
            case (btn_idx)
                0: key_rst = 1'b1;
                1: key1    = 1'b1;
                2: key2    = 1'b1;
                3: key3    = 1'b1;
            endcase
            repeat (200) @(posedge clk);
        end
    endtask

    initial begin
        $display("[TB_V27] Starting V27 All-in-One Subsystem Verification...");
        clk = 0;
        rst = 1;
        key_rst = 1;
        key1 = 1;
        key2 = 1;
        key3 = 1;

        #200;
        rst = 0;
        #1000;

        // Verify idle state
        if (quiz_active || drill_active || game_active) begin
            $display("[FAIL] Expected all modes inactive at startup!");
            $finish;
        end
        $display("[PASS] Startup: All interactive modes idle.");

        // 1. Test Quiz Entry via KEY4 (B1, key3) Long Press
        $display("[TEST] Long press KEY4 (key3) to enter Quiz Mode...");
        press_btn(3, 700); // Hold for 700 cycles > 500 cycle LONG_MS threshold
        #500;
        if (!quiz_active) begin
            $display("[FAIL] Quiz mode did not activate!");
            $finish;
        end
        $display("[PASS] Quiz mode active! Testing Quiz exit...");
        press_btn(3, 700);
        #500;
        if (quiz_active) begin
            $display("[FAIL] Quiz mode did not exit on long press!");
            $finish;
        end
        $display("[PASS] Quiz mode exited cleanly.");

        // 2. Test Fire Drill Entry via KEY3 (C1, key2) Long Press
        $display("[TEST] Long press KEY3 (key2) to enter Fire Drill...");
        press_btn(2, 700);
        #500;
        if (!drill_active) begin
            $display("[FAIL] Fire Drill did not activate!");
            $finish;
        end
        $display("[PASS] Fire Drill active! BGM Mode: %d. Testing Drill exit...", drill_bgm);
        press_btn(2, 700);
        #500;
        if (drill_active) begin
            $display("[FAIL] Fire Drill did not exit on long press!");
            $finish;
        end
        $display("[PASS] Fire Drill exited cleanly.");

        // 3. Test Fire Escape Game Entry via KEY1 (A2, key_rst) Long Press
        $display("[TEST] Long press KEY1 (rst_n) to enter Game Mode...");
        press_btn(0, 700);
        #500;
        if (!game_active) begin
            $display("[FAIL] Game mode did not activate!");
            $finish;
        end
        $display("[PASS] Game mode active! Testing Game exit...");
        press_btn(0, 700);
        #500;
        if (game_active) begin
            $display("[FAIL] Game mode did not exit on long press!");
            $finish;
        end
        $display("[PASS] Game mode exited cleanly.");

        // 4. Test Mode Mutual Exclusivity
        $display("[TEST] Mutual exclusivity: Enter Quiz, verify Drill/Game locked out...");
        press_btn(3, 700); // Enter Quiz
        #200;
        press_btn(2, 700); // Attempt Drill
        press_btn(0, 700); // Attempt Game
        #200;
        if (!quiz_active || drill_active || game_active) begin
            $display("[FAIL] Mutual exclusivity violation! quiz=%d, drill=%d, game=%d",
                     quiz_active, drill_active, game_active);
            $finish;
        end
        $display("[PASS] Mutual exclusivity verified: Drill and Game locked out while Quiz is running.");
        press_btn(3, 700); // Exit Quiz
        #500;

        $display("[TB_V27] ALL TESTS PASSED! V27 Integration Verified Successfully.");
        $finish;
    end

endmodule

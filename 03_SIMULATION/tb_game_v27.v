`timescale 1ns/1ps

module tb_game_v27;
    reg clk = 0, rst = 1, enable = 1;
    reg vs = 0, de = 0;
    reg [23:0] rgb_in = 24'h202020;
    reg k1 = 1, k2 = 1, k3 = 1, k_game = 1;

    wire vs_o, de_o;
    wire [23:0] rgb_o;
    wire gactive, k3_short;

    contest_game #(
        .CLK_HZ      (100000),
        .DEBOUNCE_MS (1),
        .LONG_MS     (5),
        .FIRE_MS     (5),
        .ANIM_MS     (5),
        .POISON_TICK_MS (5),
        .INTRO_MS    (100),
        .ITEM_MS     (50)
    ) dut (
        .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_rgb(rgb_in),
        .I_enable(enable), .I_key1(k1), .I_key2(k2), .I_key3(k3),
        .I_key_game(k_game),
        .O_key3_short(k3_short), .O_active(gactive),
        .O_vs(vs_o), .O_de(de_o), .O_rgb(rgb_o)
    );

    always #20 clk = ~clk;

    task cyc(input integer n); begin #(40*n); end endtask

    task press_k1;
        begin k1 = 0; cyc(150); k1 = 1; cyc(150); end
    endtask

    task press_k2;
        begin k2 = 0; cyc(150); k2 = 1; cyc(150); end
    endtask

    task press_k3;
        begin k3 = 0; cyc(150); k3 = 1; cyc(150); end
    endtask

    task long_press_game;
        begin k_game = 0; cyc(600); k_game = 1; cyc(150); end
    endtask

    initial begin
        $display("[TB_GAME_V27] Starting Game Feature & Bugfix Simulation...");
        cyc(10);
        rst = 0;
        cyc(50);

        if (gactive != 0 || dut.state != 0) begin
            $display("[FAIL] Expected ST_IDLE on boot!"); $finish;
        end
        $display("[PASS] Boot: Game is IDLE.");

        // 1. Long press KEY1 to enter INTRO
        long_press_game();
        if (dut.state != 3'd1) begin
            $display("[FAIL] Expected ST_INTRO! Got: %d", dut.state); $finish;
        end
        $display("[PASS] Entered ST_INTRO successfully.");

        // 2. Short press KEY2 (k1) to skip to ITEM1
        press_k1();
        if (dut.state != 3'd2) begin
            $display("[FAIL] Expected ST_ITEM1 after skip! Got: %d", dut.state); $finish;
        end
        $display("[PASS] Skipped to ST_ITEM1 successfully.");

        // 3. Short press KEY2 to skip to ITEM2
        press_k1();
        if (dut.state != 3'd3) begin
            $display("[FAIL] Expected ST_ITEM2 after skip! Got: %d", dut.state); $finish;
        end
        $display("[PASS] Skipped to ST_ITEM2 successfully.");

        // 4. Short press KEY2 to enter PLAY
        press_k1();
        if (dut.state != 3'd4) begin
            $display("[FAIL] Expected ST_PLAY! Got: %d", dut.state); $finish;
        end
        $display("[PASS] Entered ST_PLAY (Interactive Game) successfully.");

        // 5. Test turning with KEY3 (k2)
        if (dut.dir != 2'd0) begin $display("[FAIL] Initial dir != 0"); $finish; end
        press_k2();
        if (dut.dir != 2'd1) begin $display("[FAIL] Expected dir 1 after turn"); $finish; end
        press_k2();
        if (dut.dir != 2'd2) begin $display("[FAIL] Expected dir 2 after turn"); $finish; end
        $display("[PASS] Turn direction operates correctly.");

        // 6. Test movement and towel item pickup
        // Force player next to towel at (10, 2)
        dut.pos_x = 5'd10; dut.pos_y = 4'd1; dut.dir = 2'd0; // Facing down towards (10, 2)
        cyc(20);
        press_k1(); // Move down to (10, 2)
        cyc(3500);   // Allow scan engine to process
        if (dut.has_towel != 1) begin
            $display("[FAIL] Towel pickup failed!"); $finish;
        end
        $display("[PASS] Wet Towel pickup successful! has_towel = 1.");

        // 7. Test extinguisher item pickup
        dut.pos_x = 5'd10; dut.pos_y = 4'd7; dut.dir = 2'd0; // Facing down towards (10, 8)
        cyc(20);
        press_k1(); // Move down to (10, 8)
        cyc(3500);
        if (dut.has_ext != 1) begin
            $display("[FAIL] Extinguisher pickup failed!"); $finish;
        end
        $display("[PASS] Extinguisher pickup successful! has_ext = 1.");

        // 8. Test using extinguisher with KEY4 (k3)
        dut.pos_x = 5'd10; dut.pos_y = 4'd9; dut.dir = 2'd0; // Facing fire at (10, 10)
        cyc(20);
        press_k3();
        cyc(3500);
        if (dut.ext_uses != 2'd2) begin
            $display("[FAIL] Extinguisher uses count not decremented! ext_uses = %d", dut.ext_uses); $finish;
        end
        $display("[PASS] Fire extinguisher sprayed! ext_uses decremented to 2.");

        // 9. Test death and restart
        dut.pos_x = 5'd5; dut.pos_y = 4'd2; // Walk into bedroom fire at (5, 2)
        cyc(3500);
        if (dut.state != 3'd5 || dut.lose_fire != 1) begin
            $display("[FAIL] Expected ST_DEAD with lose_fire! state = %d", dut.state); $finish;
        end
        $display("[PASS] Stepped into fire -> ST_DEAD triggered with lose_fire = 1.");

        // 10. Restart from dead curtain via KEY2 (k1)
        press_k1();
        cyc(3500);
        if (dut.state != 3'd4) begin
            $display("[FAIL] Expected restart to ST_PLAY! state = %d", dut.state); $finish;
        end
        if (dut.pos_x != 5'd2 || dut.pos_y != 4'd2) begin
            $display("[FAIL] Player spawn not reset after restart! pos=(%d,%d)", dut.pos_x, dut.pos_y); $finish;
        end
        if (dut.ext_uses != 2'd3) begin
            $display("[FAIL] Extinguisher uses not restored to 3! ext_uses = %d", dut.ext_uses); $finish;
        end
        $display("[PASS] Restart successful: Player reset to bedroom (2,2), ammo reset to 3.");

        // 11. Test Exit to Win
        dut.pos_x = 5'd18; dut.pos_y = 4'd12; // At EXIT door
        cyc(3500);
        if (dut.state != 3'd6) begin
            $display("[FAIL] Expected ST_WIN at exit door! state = %d", dut.state); $finish;
        end
        $display("[PASS] Reached exit door -> ST_WIN triggered successfully.");

        // 12. Exit game via KEY1 long press
        long_press_game();
        if (dut.state != 3'd0) begin
            $display("[FAIL] Expected exit to ST_IDLE! state = %d", dut.state); $finish;
        end
        $display("[PASS] Exited game back to ST_IDLE successfully.");

        $display("\n=======================================================");
        $display("  ALL 12 V27 GAME UPGRADE TESTS PASSED SUCCESSFULLY!  ");
        $display("=======================================================\n");
        $finish;
    end
endmodule



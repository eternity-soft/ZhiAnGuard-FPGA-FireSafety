`timescale 1ns/1ps

module tb_sd_key_debounce;
    reg clk;
    reg rst;
    reg key_auto;
    reg key_period;

    wire auto_play_active;
    wire [1:0] auto_period_sel;

    contest_sd_card_bmp #(
        .CLK_FREQ_HZ(10_000_000), // 10MHz for faster simulation
        .PREFETCH_ENABLE(0),
        .EXTERNAL_SCALER(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .key_next(1'b1),
        .key_next_pulse(1'b0),
        .key_auto(key_auto),
        .key_period(key_period),
        .quiz_hold(1'b0),
        .state_code(),
        .auto_period_sel(auto_period_sel),
        .bmp_width(16'd640),
        .bmp_height(16'd480),
        .display_valid(),
        .auto_play_active(auto_play_active),
        .current_image_idx(),
        .manual_audio_toggle(),
        .manual_audio_image_idx(),
        .write_finish_toggle(1'b0),
        .write_abort_req(),
        .write_abort_ack(1'b0),
        .write_buf_idx(),
        .disp_buf_idx(),
        .display_req_toggle(),
        .display_ack_toggle_video(1'b0),
        .cache_valid_mask(),
        .write_req(),
        .write_req_ack(1'b0),
        .write_en(),
        .write_data(),
        .SD_nCS(),
        .SD_DCLK(),
        .SD_MOSI(),
        .SD_MISO(1'b1),
        .load_sector_out(),
        .load_start_pulse_out(),
        .load_busy_out(),
        .load_idx_out(),
        .catalog_ready_out(),
        .sd_init_done_out(),
        .sd_sec_read_o(),
        .sd_sec_read_addr_o(),
        .sd_sec_read_i(1'b0),
        .sd_sec_read_addr_i(32'd0),
        .sd_bus_takeover(1'b0),
        .ext_pixel_inc(1'b0),
        .ext_source_done(1'b0),
        .ext_source_error(1'b0),
        .bridge_reset_out(),
        .sd_sec_read_data_o(),
        .sd_sec_read_data_valid_o(),
        .sd_sec_read_end_o()
    );

    always #50 clk = ~clk; // 10MHz

    task press_auto;
        begin
            $display("[ACTION] Pressing KEY4 (key_auto)...");
            key_auto = 1'b0; // Active low
            #25000000;      // 25ms (exceeds 20ms debounce)
            key_auto = 1'b1; // Release
            #25000000;      // 25ms
        end
    endtask

    task press_period;
        begin
            $display("[ACTION] Pressing KEY3 (key_period)...");
            key_period = 1'b0; // Active low
            #25000000;        // 25ms
            key_period = 1'b1; // Release
            #25000000;        // 25ms
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        key_auto = 1;
        key_period = 1;
        #1000;
        rst = 0;
        #1000;

        // Force catalog ready and images found for testing key handling while idle
        dut.catalog_ready = 1'b1;
        dut.img_found_count = 3'd4;
        dut.recovery_state = 0; // R_RUN
        dut.sd_init_done_out = 1'b1;

        $display("Initial: auto_play_active = %d, auto_period_sel = %d", auto_play_active, auto_period_sel);

        // 1. Press KEY4 to enable auto play
        press_auto();
        if (auto_play_active !== 1'b1) begin
            $display("[FAIL] Auto play did not turn ON! Got: %d", auto_play_active);
            $finish;
        end
        $display("[PASS] Auto play successfully turned ON: %d", auto_play_active);

        // 2. Press KEY4 again to DISABLE auto play (User reported: 'key4自动轮播打开之后怎么关不了')
        press_auto();
        if (auto_play_active !== 1'b0) begin
            $display("[FAIL] Auto play did not turn OFF! Got: %d", auto_play_active);
            $finish;
        end
        $display("[PASS] Auto play successfully turned OFF: %d (CLOSING VERIFIED!)", auto_play_active);

        // 3. Cycle period with KEY3
        press_period();
        if (auto_period_sel !== 2'd1) begin
            $display("[FAIL] Period did not switch to 1! Got: %d", auto_period_sel);
            $finish;
        end
        $display("[PASS] Period switched to 1 (2s)");

        press_period();
        if (auto_period_sel !== 2'd2) begin
            $display("[FAIL] Period did not switch to 2! Got: %d", auto_period_sel);
            $finish;
        end
        $display("[PASS] Period switched to 2 (4s)");

        press_period();
        if (auto_period_sel !== 2'd0) begin
            $display("[FAIL] Period did not wrap to 0! Got: %d", auto_period_sel);
            $finish;
        end
        $display("[PASS] Period wrapped to 0 (1s)");

        $display("=================================================");
        $display("  ALL AUTO-PLAY & PERIOD KEY DEBOUNCE TESTS PASS! ");
        $display("=================================================");
        $finish;
    end
endmodule

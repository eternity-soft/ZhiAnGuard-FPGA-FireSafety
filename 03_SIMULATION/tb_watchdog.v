`timescale 1ns/1ps

module tb_watchdog;
    reg clk;
    reg rst;
    reg vs;
    reg de;
    reg [23:0] rgb;
    reg display_ready;

    wire o_anomaly;
    wire o_reset_pulse;

    contest_pixel_anomaly_watchdog #(
        .H_ACTIVE       (640),
        .V_ACTIVE       (480),
        .X_MIN          (4),
        .X_MAX          (635),
        .Y_MIN          (4),
        .Y_MAX          (475),
        .DIFF_THRESHOLD (70),
        .BG_DIFF_MAX    (16),
        .ANOMALY_THRESH (8)
    ) dut (
        .I_clk              (clk),
        .I_rst              (rst),
        .I_vs               (vs),
        .I_de               (de),
        .I_rgb              (rgb),
        .I_display_ready    (display_ready),
        .O_anomaly_detected (o_anomaly),
        .O_auto_reset_pulse (o_reset_pulse)
    );

    initial begin
        clk = 0;
        forever #20 clk = ~clk; // 25MHz
    end

    integer x, y, f;
    reg inject_snow;
    integer reset_fired_count;

    task send_frame;
        input inject;
        integer ix, iy;
        begin
            // VSYNC low (pulse)
            vs = 0;
            #1000;
            vs = 1;
            #1000;
            
            // Send 480 lines
            for (iy = 0; iy < 480; iy = iy + 1) begin
                de = 0;
                #320;
                for (ix = 0; ix < 640; ix = ix + 1) begin
                    @(posedge clk);
                    de <= 1'b1;
                    // Normal background
                    rgb <= 24'h404040;
                    
                    // Inject isolated snow pixels if requested
                    if (inject && (iy % 5 == 0 && iy >= 50 && iy <= 100) && (ix == 100)) begin
                        // Center is 0xFF, neighbors are 0x40 -> jump of 191
                        rgb <= 24'hFFFFFF;
                    end
                end
                @(posedge clk);
                de <= 1'b0;
                #100;
            end
            
            // End of frame: VSYNC pulse goes low
            #500;
            @(posedge clk);
            vs <= 1'b0;
            #1000;
        end
    endtask

    initial begin
        rst = 1;
        vs = 1;
        de = 0;
        rgb = 0;
        display_ready = 1;
        reset_fired_count = 0;
        #100;
        rst = 0;
        #100;

        // Force settle_frames to armed directly or simulate 32 frames
        // In simulation, let's fast-forward settle
        dut.settle_frames = 7'd30;
        dut.ready_armed = 1'b1;

        $display("--- Test 1: Send clean frame (no noise) ---");
        send_frame(0);
        #500;
        if (o_reset_pulse == 0)
            $display("PASS: Clean frame did not fire reset!");
        else
            $display("FAIL: Clean frame fired false reset!");

        $display("--- Test 2: Send 2 noisy frames with snow glitches ---");
        send_frame(1); // Frame 1
        #500;
        send_frame(1); // Frame 2
        #500;

        if (reset_fired_count > 0)
            $display("PASS: Snow glitch successfully detected and auto-reset triggered!");
        else
            $display("FAIL: Watchdog failed to detect snow noise!");

        $finish;
    end

    always @(posedge clk) begin
        if (o_reset_pulse) begin
            reset_fired_count = reset_fired_count + 1;
            $display("WATCHDOG AUTO_RESET PULSE FIRED at time %t!", $time);
        end
    end

endmodule

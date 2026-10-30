`timescale 1ns/1ps

module tb_contest_fire_audio_linkage_engine;
    localparam integer CLK_HZ = 1000000;
    localparam integer FS     = 10000;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg image_toggle = 1'b0;
    reg [1:0] image_idx = 2'd0;
    reg period_toggle = 1'b0;
    reg [1:0] period_sel = 2'd0;
    reg auto_state = 1'b0;
    reg [1:0] vol = 2'd3;
    wire audio_valid;
    wire signed [23:0] audio_left;
    wire signed [23:0] audio_right;

    integer valid_count = 0;
    integer nonzero_count = 0;
    integer cycles_since_valid = 0;
    integer errors = 0;

    always #500 clk = ~clk;

    contest_fire_audio_linkage_engine #(
        .CLK_HZ(CLK_HZ),
        .SAMPLE_RATE(FS),
        .BGM_ENABLE(1)
    ) dut (
        .I_clk(clk),
        .I_rst(rst),
        .I_image_event_toggle(image_toggle),
        .I_image_event_idx(image_idx),
        .I_period_event_toggle(period_toggle),
        .I_period_sel(period_sel),
        .I_auto_state(auto_state),
        .I_vol(vol),
        .O_audio_valid(audio_valid),
        .O_audio_left(audio_left),
        .O_audio_right(audio_right)
    );

    always @(posedge clk) begin
        if (rst) begin
            cycles_since_valid <= 0;
        end else begin
            cycles_since_valid <= cycles_since_valid + 1;
            if (audio_valid) begin
                valid_count <= valid_count + 1;
                if ((^audio_left === 1'bx) || (^audio_right === 1'bx)) begin
                    $display("FAIL: X/Z on audio output at %0t", $time);
                    errors <= errors + 1;
                end
                if (audio_left !== audio_right) begin
                    $display("FAIL: left/right mismatch at %0t", $time);
                    errors <= errors + 1;
                end
                if ((audio_left != 0) || (audio_right != 0))
                    nonzero_count <= nonzero_count + 1;
                // The counter excludes the current valid edge, so 100 clock periods
                // appear as 99 intervening non-valid rising edges here.
                if ((valid_count > 2) && (cycles_since_valid != 99)) begin
                    $display("FAIL: sample cadence=%0d intervening clocks, expected 99", cycles_since_valid);
                    errors <= errors + 1;
                end
                cycles_since_valid <= 0;
            end
        end
    end

    task wait_valid_samples;
        input integer number;
        integer target;
        begin
            target = valid_count + number;
            while (valid_count < target) @(posedge clk);
        end
    endtask

    task wait_sfx_tag;
        input [3:0] expected;
        integer guard;
        begin
            guard = 0;
            while ((dut.sfx_tag !== expected || dut.sfx_state == 0) && guard < 30000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 30000) begin
                $display("FAIL: event tag %0d did not start", expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;
        repeat (16) @(posedge clk);

        wait_valid_samples(80);
        if (nonzero_count == 0) begin
            $display("FAIL: fire BGM remained silent");
            errors = errors + 1;
        end

        image_idx = 2'd2;
        image_toggle = ~image_toggle;
        wait_sfx_tag(4'd2);
        if (!(dut.sfx_inc_hi > dut.sfx_inc_lo) || dut.sfx_sweep_step == 0) begin
            $display("FAIL: image alarm is not configured as a sweep");
            errors = errors + 1;
        end

        period_sel = 2'd1;
        period_toggle = ~period_toggle;
        wait_sfx_tag(4'd5);

        auto_state = 1'b1;
        wait_sfx_tag(4'd7);

        vol = 2'd0;
        wait_valid_samples(16);
        if ((audio_left != 0) || (audio_right != 0)) begin
            $display("FAIL: volume zero is not silent");
            errors = errors + 1;
        end

        vol = 2'd3;
        wait_valid_samples(32);
        if (errors == 0)
            $display("V08_FIRE_AUDIO_INHERIT_PASS valid=%0d nonzero=%0d", valid_count, nonzero_count);
        else
            $display("V07_FIRE_AUDIO_SIM_FAIL errors=%0d", errors);
        $finish;
    end
endmodule

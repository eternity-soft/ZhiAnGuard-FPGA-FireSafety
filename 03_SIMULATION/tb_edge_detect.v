`timescale 1ns/1ps

module tb_edge_detect;
    reg clk;
    reg rst;
    reg enable;
    reg vs;
    reg de;
    reg [23:0] rgb;

    wire o_vs;
    wire o_de;
    wire [23:0] o_rgb;

    contest_edge_detect #(
        .H_ACTIVE  (640),
        .V_ACTIVE  (480),
        .THRESHOLD (11'd75)
    ) dut (
        .I_clk    (clk),
        .I_rst    (rst),
        .I_enable (enable),
        .I_vs     (vs),
        .I_de     (de),
        .I_rgb    (rgb),
        .O_vs     (o_vs),
        .O_de     (o_de),
        .O_rgb    (o_rgb)
    );

    initial begin
        clk = 0;
        forever #20 clk = ~clk; // 25MHz
    end

    integer x, y;
    integer white_pixel_count;

    initial begin
        rst = 1;
        enable = 1;
        vs = 0;
        de = 0;
        rgb = 0;
        white_pixel_count = 0;
        #100;
        rst = 0;
        #100;

        // VSYNC pulse (active low)
        vs = 0;
        #1000;
        vs = 1; // Active video region has vs = 1
        #1000;

        // Simulate 10 lines of 640 pixels
        for (y = 0; y < 10; y = y + 1) begin
            // Front porch
            de = 0;
            #320; // 16 pixels
            
            // Active line
            for (x = 0; x < 640; x = x + 1) begin
                @(posedge clk);
                de <= 1'b1;
                // Generate a vertical white stripe at x = 100 to 120
                if (x >= 100 && x <= 120 && y >= 3)
                    rgb <= 24'hFFFFFF;
                else
                    rgb <= 24'h000000;
                
                if (o_de && o_rgb > 24'h000000)
                    white_pixel_count = white_pixel_count + 1;
            end
            @(posedge clk);
            de <= 1'b0;
            #1000; // Blanking
        end

        #2000;
        $display("Simulation finished: white edge pixels = %d", white_pixel_count);
        if (white_pixel_count > 0)
            $display("TEST_PASS: Edge detection produces non-black pixels!");
        else
            $display("TEST_FAIL: Edge detection is BLACK SCREEN!");
        $finish;
    end

endmodule

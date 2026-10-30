`timescale 1ns/1ps
//=============================================================================
// contest_dynamic_flame.v
//-----------------------------------------------------------------------------
// V25 Organic Roaring Fire Plumes (Lower-Left and Lower-Right Corners)
//
// Key Features:
//   - Theme: 消防宣传 (Fire Safety Promotion) Realistic organic licking flames.
//   - Fluid / Organic Multi-Octave Harmonic Turbulence Engine:
//       * Real-time thermal heat convection model.
//       * 3 rising harmonic waves creating swirling, curling, licking flame tongues.
//       * Independent phase offsets for Left and Right torches (natural non-mirrored motion).
//       * 4 continuous thermal gradient zones: White-Hot Core -> Golden Yellow ->
//         Fiery Orange -> Crimson Wisps.
//   - Audio Volume Reactive:
//       * Quiet / Muted: Cozy, warm organic burning plume (Height ~34px).
//       * Loud audio / BGM / SFX: Roaring, vigorous licking flames leaping up to ~78px.
//   - Hardware Efficient:
//       * ZERO Block RAMs (0 BRAMs).
//       * ZERO DSP Multipliers (0 DSPs).
//       * 3-stage pipelined architecture ensuring 25 MHz HDMI timing closure.
//=============================================================================
module contest_dynamic_flame #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer BASE_Y   = 458,  // Anchored at Y=458 (above bottom scrolling slogan)
    parameter integer H_BASE   = 28
)(
    input  wire        I_clk,         // Video pixel clock (25 MHz)
    input  wire        I_rst,         // System reset
    input  wire        I_vs,          // Video VSYNC
    input  wire        I_de,          // Video Data Enable
    input  wire [23:0] I_rgb,         // Background pixel RGB
    input  wire [7:0]  I_audio_level, // Audio volume envelope level (0..128)
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_rgb
);

    // -------------------------------------------------------------------------
    // Horizontal Anchors (88 pixels wide per corner plume)
    // -------------------------------------------------------------------------
    localparam [9:0] XL_CENTER = 10'd56;   // Left plume center: X in [12, 100]
    localparam [9:0] XR_CENTER = 10'd584;  // Right plume center: X in [540, 628]
    localparam [9:0] HALF_SPAN = 10'd44;

    // -------------------------------------------------------------------------
    // Frame Timing & Flame Height / Convection Animation (at VSYNC boundary)
    // -------------------------------------------------------------------------
    reg        vs_d;
    reg [7:0]  t_frame;
    reg [6:0]  max_h;    // 50 (quiet) to 115 (loud)
    reg [5:0]  inv_h;    // 2048 / max_h
    reg [5:0]  p1, p2, p3;

    function [5:0] calc_inv_h;
        input [6:0] h;
        begin
            if (h <= 7'd52) calc_inv_h = 6'd40;
            else if (h <= 7'd60) calc_inv_h = 6'd35;
            else if (h <= 7'd68) calc_inv_h = 6'd30;
            else if (h <= 7'd76) calc_inv_h = 6'd27;
            else if (h <= 7'd85) calc_inv_h = 6'd24;
            else if (h <= 7'd95) calc_inv_h = 6'd21;
            else if (h <= 7'd105) calc_inv_h = 6'd19;
            else calc_inv_h = 6'd17;
        end
    endfunction

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            vs_d    <= 1'b0;
            t_frame <= 8'd0;
            max_h   <= 7'd50;
            inv_h   <= 6'd41;
            p1      <= 6'd0;
            p2      <= 6'd0;
            p3      <= 6'd0;
        end else begin
            vs_d <= I_vs;
            if (I_vs && !vs_d) begin
                t_frame <= t_frame + 8'd1;
                // Height scaling with audio: 50 (quiet) to 114 (loudest), zero DSP multipliers
                max_h <= 7'd50 + {1'b0, I_audio_level[7:1]};
                inv_h <= calc_inv_h(7'd50 + {1'b0, I_audio_level[7:1]});

                // 3 rising wave convection phases (pure shift-adds, 0 DSPs)
                p1 <= (((t_frame << 1) + t_frame)) & 6'd63;
                p2 <= (((t_frame << 2) + t_frame)) & 6'd63;
                p3 <= (t_frame << 3) & 6'd63;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Video Timing & Coordinates
    // -------------------------------------------------------------------------
    reg [9:0] px;
    reg [8:0] py;
    reg       de_d;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            px <= 10'd0; py <= 9'd0; de_d <= 1'b0;
        end else begin
            de_d <= I_de;
            if (I_vs && !vs_d)
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

    // -------------------------------------------------------------------------
    // Sine Lookup Function (64 entries: -63 to +63, ~15 LUTs, 0 BRAMs)
    // -------------------------------------------------------------------------
    function signed [6:0] sin64;
        input [5:0] a;
        begin
            case (a)
                6'd0:  sin64 =  7'sd0;  6'd1:  sin64 =  7'sd6;  6'd2:  sin64 =  7'sd12; 6'd3:  sin64 =  7'sd18;
                6'd4:  sin64 =  7'sd24; 6'd5:  sin64 =  7'sd30; 6'd6:  sin64 =  7'sd36; 6'd7:  sin64 =  7'sd41;
                6'd8:  sin64 =  7'sd45; 6'd9:  sin64 =  7'sd49; 6'd10: sin64 =  7'sd53; 6'd11: sin64 =  7'sd56;
                6'd12: sin64 =  7'sd58; 6'd13: sin64 =  7'sd60; 6'd14: sin64 =  7'sd62; 6'd15: sin64 =  7'sd63;
                6'd16: sin64 =  7'sd63; 6'd17: sin64 =  7'sd62; 6'd18: sin64 =  7'sd60; 6'd19: sin64 =  7'sd58;
                6'd20: sin64 =  7'sd56; 6'd21: sin64 =  7'sd53; 6'd22: sin64 =  7'sd49; 6'd23: sin64 =  7'sd45;
                6'd24: sin64 =  7'sd41; 6'd25: sin64 =  7'sd36; 6'd26: sin64 =  7'sd30; 6'd27: sin64 =  7'sd24;
                6'd28: sin64 =  7'sd18; 6'd29: sin64 =  7'sd12; 6'd30: sin64 =  7'sd6;  6'd31: sin64 =  7'sd0;
                6'd32: sin64 = -7'sd0;  6'd33: sin64 = -7'sd6;  6'd34: sin64 = -7'sd12; 6'd35: sin64 = -7'sd18;
                6'd36: sin64 = -7'sd24; 6'd37: sin64 = -7'sd30; 6'd38: sin64 = -7'sd36; 6'd39: sin64 = -7'sd41;
                6'd40: sin64 = -7'sd45; 6'd41: sin64 = -7'sd49; 6'd42: sin64 = -7'sd53; 6'd43: sin64 = -7'sd56;
                6'd44: sin64 = -7'sd58; 6'd45: sin64 = -7'sd60; 6'd46: sin64 = -7'sd62; 6'd47: sin64 = -7'sd63;
                6'd48: sin64 = -7'sd63; 6'd49: sin64 = -7'sd62; 6'd50: sin64 = -7'sd60; 6'd51: sin64 = -7'sd58;
                6'd52: sin64 = -7'sd56; 6'd53: sin64 = -7'sd53; 6'd54: sin64 = -7'sd49; 6'd55: sin64 = -7'sd45;
                6'd56: sin64 = -7'sd41; 6'd57: sin64 = -7'sd36; 6'd58: sin64 = -7'sd30; 6'd59: sin64 = -7'sd24;
                6'd60: sin64 = -7'sd18; 6'd61: sin64 = -7'sd12; 6'd62: sin64 = -7'sd6;  default: sin64 = 7'sd0;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Inverse Half-Width Table for Parabolic Envelope (w in [12..40])
    // -------------------------------------------------------------------------
    function [8:0] get_inv_w;
        input [5:0] w;
        begin
            if (w <= 6'd14)      get_inv_w = 9'd146;
            else if (w <= 6'd18) get_inv_w = 9'd113;
            else if (w <= 6'd22) get_inv_w = 9'd93;
            else if (w <= 6'd26) get_inv_w = 9'd78;
            else if (w <= 6'd30) get_inv_w = 9'd68;
            else if (w <= 6'd35) get_inv_w = 9'd58;
            else                 get_inv_w = 9'd51; // 40
        end
    endfunction

    // -------------------------------------------------------------------------
    // Stage 1: Spatial Bounds & Convection Wave Argument Generation
    // -------------------------------------------------------------------------
    wire in_box_L = (px >= (XL_CENTER - HALF_SPAN)) && (px <= (XL_CENTER + HALF_SPAN));
    wire in_box_R = (px >= (XR_CENTER - HALF_SPAN)) && (px <= (XR_CENTER + HALF_SPAN));
    wire in_box_y = (py <= BASE_Y) && (py >= (BASE_Y - {2'b00, max_h}));
    wire in_flame = I_de && in_box_y && (in_box_L | in_box_R);

    // Delta X relative to center (-44 to +44)
    wire signed [6:0] dx_w = in_box_R ? ($signed({1'b0, px}) - $signed({1'b0, XR_CENTER}))
                                      : ($signed({1'b0, px}) - $signed({1'b0, XL_CENTER}));
    // Delta Y from base (0 at base, max_h at top)
    wire [6:0] dy_w = BASE_Y[8:0] - py;

    // Normalized dy across max_h: dy_norm in [0, 255]
    (* syn_multstyle = "logic", use_dsp = "no" *) wire [11:0] prod_dy_norm = dy_w * inv_h;
    wire [7:0]  dy_norm_w    = (prod_dy_norm > 12'd2047) ? 8'd255 : prod_dy_norm[10:3];
    wire [7:0]  base_heat_w  = 8'd255 - dy_norm_w;

    // Flame half-width at height dy: 40 at base, 12 at top (wide, bold fire plume)
    (* syn_multstyle = "logic", use_dsp = "no" *) wire [13:0] prod_hw = dy_norm_w * 6'd28;
    wire [5:0]  hw_calc      = 6'd40 - prod_hw[13:8];
    wire [5:0]  half_w_w     = (hw_calc < 6'd12) ? 6'd12 : hw_calc;

    // Turbulence scale (higher at tips): 32 at base, 128 at top
    (* syn_multstyle = "logic", use_dsp = "no" *) wire [14:0] prod_turb_scale = dy_norm_w * 7'd96;
    wire [7:0]  turb_scale_w = 8'd32 + prod_turb_scale[14:8];

    // Phase offset for Right torch (+27 to avoid robotic mirroring)
    wire [5:0]  phase_off    = in_box_R ? 6'd27 : 6'd0;

    // 3 Wave Arguments (modulo 64 via 6-bit masking)
    wire [5:0]  arg1_w = ((dx_w << 1) + dx_w + (dy_w << 1) - p1 + phase_off) & 6'd63;
    wire [5:0]  arg2_w = (-(dx_w << 2) + (dy_w << 1) + dy_w - p2 + phase_off + 6'd20) & 6'd63;
    wire [5:0]  arg3_w = ((dx_w << 2) + dx_w - (dy_w << 2) - p3 + phase_off + 6'd40) & 6'd63;

    // Pipeline Registers (Stage 1)
    reg        in_flame_d1;
    reg signed [6:0] dx_d1;
    reg [6:0]  dy_d1;
    reg [7:0]  base_heat_d1;
    reg [5:0]  half_w_d1;
    reg [7:0]  turb_scale_d1;
    reg [5:0]  arg1_d1, arg2_d1, arg3_d1;
    reg [23:0] rgb_d1;
    reg        de_d1, vs_d1;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            in_flame_d1   <= 1'b0;
            dx_d1         <= 7'sd0;
            dy_d1         <= 7'd0;
            base_heat_d1  <= 8'd0;
            half_w_d1     <= 6'd0;
            turb_scale_d1 <= 8'd0;
            arg1_d1       <= 6'd0;
            arg2_d1       <= 6'd0;
            arg3_d1       <= 6'd0;
            rgb_d1        <= 24'd0;
            de_d1         <= 1'b0;
            vs_d1         <= 1'b0;
        end else begin
            in_flame_d1   <= in_flame;
            dx_d1         <= dx_w;
            dy_d1         <= dy_w;
            base_heat_d1  <= base_heat_w;
            half_w_d1     <= half_w_w;
            turb_scale_d1 <= turb_scale_w;
            arg1_d1       <= arg1_w;
            arg2_d1       <= arg2_w;
            arg3_d1       <= arg3_w;
            rgb_d1        <= I_rgb;
            de_d1         <= I_de;
            vs_d1         <= I_vs;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: Wave Harmonics, Horizontal Envelope & Net Heat Synthesis
    // -------------------------------------------------------------------------
    wire signed [6:0] s1 = sin64(arg1_d1);
    wire signed [6:0] s2 = sin64(arg2_d1);
    wire signed [6:0] s3 = sin64(arg3_d1);

    // Sum of 3 waves: range -160 to +160
    wire signed [8:0] turb_sum = $signed({{2{s1[6]}}, s1}) +
                                 $signed({{2{s2[6]}}, s2}) +
                                 $signed({{3{s3[6]}}, s3[6:1]});

    // Scaled turbulence modulated by flame envelope density
    (* syn_multstyle = "logic", use_dsp = "no" *) wire signed [16:0] prod_turb   = turb_sum * $signed({1'b0, env_heat_w});
    wire signed [8:0]  turb_heat_w = prod_turb[15:7];

    // Horizontal Envelope Modulation
    wire [5:0] abs_dx_w = (dx_d1 < 7'sd0) ? (-dx_d1) : dx_d1;
    wire [8:0] inv_w_val = get_inv_w(half_w_d1);

    reg [7:0]  h_env_r;
    reg [5:0]  diff_env;
    (* syn_multstyle = "logic", use_dsp = "no" *) reg [14:0] prod_env;

    always @(*) begin
        if (abs_dx_w >= {1'b0, half_w_d1}) begin
            h_env_r = 8'd0;
        end else begin
            diff_env = {1'b0, half_w_d1} - abs_dx_w;
            prod_env = diff_env * inv_w_val;
            h_env_r  = (prod_env > 15'd2047) ? 8'd255 : prod_env[10:3];
        end
    end

    (* syn_multstyle = "logic", use_dsp = "no" *) wire [15:0] prod_env_heat = base_heat_d1 * h_env_r;
    wire [7:0]  env_heat_w    = prod_env_heat[15:8];

    // Bed of glowing embers at the base (dy < 6)
    wire [6:0] ember_boost_w = (dy_d1 < 7'd6) ? ((7'd6 - dy_d1) * 4'd14) : 7'd0;

    // Combined net heat: range 0 to 255
    wire signed [10:0] net_heat_w = $signed({3'b000, env_heat_w}) +
                                    $signed({{2{turb_heat_w[8]}}, turb_heat_w}) +
                                    $signed({4'b0000, ember_boost_w});

    wire [7:0] heat_clamped = (net_heat_w < 11'sd0) ? 8'd0 :
                              (net_heat_w > 11'sd255) ? 8'd255 : net_heat_w[7:0];

    // Pipeline Registers (Stage 2)
    reg        in_flame_d2;
    reg [7:0]  heat_d2;
    reg [23:0] rgb_d2;
    reg        de_d2, vs_d2;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            in_flame_d2 <= 1'b0;
            heat_d2     <= 8'd0;
            rgb_d2      <= 24'd0;
            de_d2       <= 1'b0;
            vs_d2       <= 1'b0;
        end else begin
            in_flame_d2 <= in_flame_d1;
            heat_d2     <= heat_clamped;
            rgb_d2      <= rgb_d1;
            de_d2       <= de_d1;
            vs_d2       <= vs_d1;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: Smooth Continuous Thermal Color Gradient & Video Synthesis
    // -------------------------------------------------------------------------
    reg [23:0] flame_rgb_r;
    reg [5:0]  u_heat;

    always @(*) begin
        if (!in_flame_d2 || heat_d2 < 8'd24) begin
            // 100% passthrough original background pixel
            flame_rgb_r = rgb_d2;
            u_heat      = 6'd0;
        end else if (heat_d2 < 8'd72) begin
            // Zone 1: Crimson Wisps & Smoke-Red Outer Edge (heat: 24..71)
            u_heat      = heat_d2 - 8'd24; // 0..47
            flame_rgb_r = {
                8'd40 + (u_heat << 1) + (u_heat >> 2), // Red: 40 -> 148
                (u_heat * 5'd20) >> 6,                 // Green: 0 -> 15
                8'd0                                   // Blue: 0
            };
        end else if (heat_d2 < 8'd136) begin
            // Zone 2: Rich Flame Orange & Licking Tendrils (heat: 72..135)
            u_heat      = heat_d2 - 8'd72; // 0..63
            flame_rgb_r = {
                8'd150 + u_heat + (u_heat >> 1),       // Red: 150 -> 245
                8'd20 + u_heat + (u_heat >> 1),        // Green: 20 -> 115
                8'd0                                   // Blue: 0
            };
        end else if (heat_d2 < 8'd200) begin
            // Zone 3: Radiant Golden-Yellow Body (heat: 136..199)
            u_heat      = heat_d2 - 8'd136; // 0..63
            flame_rgb_r = {
                8'd255,                                // Red: 255
                8'd120 + u_heat + (u_heat >> 1),       // Green: 120 -> 215
                (u_heat * 6'd40) >> 6                  // Blue: 0 -> 40
            };
        end else begin
            // Zone 4: Blazing Incandescent White-Hot Core (heat: 200..255)
            u_heat      = (heat_d2 > 8'd254) ? 6'd54 : (heat_d2 - 8'd200); // 0..54
            flame_rgb_r = {
                8'd255,                                // Red: 255
                8'd225 + (u_heat >> 1),                // Green: 225 -> 252
                8'd40 + (u_heat << 2)                  // Blue: 40 -> 255
            };
        end
    end

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_vs  <= 1'b0;
            O_de  <= 1'b0;
            O_rgb <= 24'd0;
        end else begin
            O_vs  <= vs_d2;
            O_de  <= de_d2;
            O_rgb <= (!de_d2) ? 24'd0 : flame_rgb_r;
        end
    end

endmodule

`timescale 1ns/1ps
//=============================================================================
// contest_drill.v
//-----------------------------------------------------------------------------
// V27 消防应急演练互动子系统 (Pro Ultra-HD Red Glassmorphic HUD & 32x32 Bold Font).
//
// 核心升级与优化:
//   1. 32x32 宏大汉字点阵渲染 (2x2 无损硬件放大，彻底消除空旷感):
//      - 16 列 x 6 行大画幅布局，文字宽大饱满，清晰易读，充满科技质感。
//      - 严格 2 拍流水线锁步（Stage 1 组合字模地址 + Stage 2 点阵输出），零毛刺与零错位。
//      - 严密字符越界保护（col < line_num_chars 且 glyph < 38），杜绝任何越界溢出。
//      - 每行独立居中与左对齐（line_left 精确数学定位），第四条“沿安全出口”完全在框内。
//   2. 巨幕倒计时 (32x64 纯正大字 + 300px 动态疏散进度条，无冒号):
//      - S3 疏散倒计时采用 4x4 放大（32x64 纯正大字），居中无冒号震撼呈现。
//      - 300 像素动态疏散进度条，根据剩余时间平滑缩短，红/黄/绿动态警示色彩切换。
//   3. 高级科技感红色 HUD 弹窗 (Red Translucent Glassmorphic HUD Box):
//      - 4 角高亮科技感直角护角（HUD Corner Brackets ┌ ┐ └ ┘）。
//      - 双层高亮发光红框 + 顶部警示横幅 + 底部状态栏。
//      - 框内半透明红色光效叠加（底图保留 25% 细节 + 细腻深红滤镜），框外适度压暗 50%。
//      - S2 疏散指引 4 个关键步骤配备半透明悬浮高亮行底条（Backlight Step Strips）。
//   4. 真实消防警笛声联动：
//      - S1~S3 演练实操阶段输出 O_bgm_mode=1 驱动 500~900Hz 急促扫频警笛。
//      - S4 演练完成输出 O_bgm_mode=2 自动平稳静音。
//=============================================================================
module contest_drill #(
    parameter integer H_ACTIVE    = 640,
    parameter integer V_ACTIVE    = 480,
    parameter integer CLK_HZ      = 25000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1000,
    parameter integer S1_MS       = 3000,
    parameter integer S2_MS       = 3000,
    parameter integer S3_MS       = 30000,
    parameter integer S4_MS       = 3000,
    parameter integer FLASH_MS    = 250
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire        I_enable,
    input  wire        I_key3,       // 长按进出；短按脉冲供顶层
    output wire        O_key3_short,
    output wire        O_active,
    output wire [1:0]  O_bgm_mode,   // 0=正常BGM 1=急促警笛 2=静音
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_rgb
);

`include "contest_drill_mini.v"

    localparam integer S1_CYC    = (CLK_HZ / 1000) * S1_MS;
    localparam integer S2_CYC    = (CLK_HZ / 1000) * S2_MS;
    localparam integer S3_CYC    = (CLK_HZ / 1000) * S3_MS;
    localparam integer S4_CYC    = (CLK_HZ / 1000) * S4_MS;
    localparam integer FLASH_CYC = (CLK_HZ / 1000) * FLASH_MS;

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_S1   = 3'd1;
    localparam [2:0] ST_S2   = 3'd2;
    localparam [2:0] ST_S3   = 3'd3;
    localparam [2:0] ST_S4   = 3'd4;

    // -------------------------------------------------------------------------
    // 按键控制与长短按消抖
    // -------------------------------------------------------------------------
    wire k3_short, k3_long;
    drill_key_ctrl #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS)) u_k3 (
        .I_clk(I_clk), .I_rst(I_rst), .I_btn(I_key3),
        .O_short(k3_short), .O_long(k3_long)
    );
    assign O_key3_short = (!O_active) ? k3_short : 1'b0;

    // -------------------------------------------------------------------------
    // 演练主状态机与阶段倒计时
    // -------------------------------------------------------------------------
    reg [2:0]  state;
    reg [26:0] tmr;
    reg [5:0]  sec_left;      // 倒计时 29..0
    reg [24:0] sec_tmr;
    reg [22:0] flash_tmr;
    reg        flash_on;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            state     <= ST_IDLE;
            tmr       <= 27'd0;
            sec_left  <= 6'd29;
            sec_tmr   <= 27'd0;
            flash_tmr <= 23'd0;
            flash_on  <= 1'b0;
        end else if (I_enable) begin
            // 2Hz 警报/倒计时警示闪烁时钟
            if (flash_tmr >= FLASH_CYC - 1) begin
                flash_tmr <= 23'd0;
                flash_on  <= ~flash_on;
            end else begin
                flash_tmr <= flash_tmr + 23'd1;
            end

            case (state)
                ST_IDLE: begin
                    tmr       <= 27'd0;
                    sec_left  <= 6'd29;
                    sec_tmr   <= 27'd0;
                    flash_tmr <= 23'd0;
                    flash_on  <= 1'b0;
                    if (k3_long)
                        state <= ST_S1;
                end
                ST_S1: begin
                    // 阶段 1: 火情警报 (3s)
                    if (tmr >= S1_CYC - 1) begin
                        tmr   <= 27'd0;
                        state <= ST_S2;
                    end else begin
                        tmr   <= tmr + 27'd1;
                    end
                end
                ST_S2: begin
                    // 阶段 2: 疏散指南 (3s)
                    if (tmr >= S2_CYC - 1) begin
                        tmr   <= 27'd0;
                        state <= ST_S3;
                    end else begin
                        tmr   <= tmr + 27'd1;
                    end
                end
                ST_S3: begin
                    // 阶段 3: 疏散倒计时 (30s)
                    if (sec_tmr >= CLK_HZ - 1) begin
                        sec_tmr <= 25'd0;
                        if (sec_left == 6'd0) begin
                            state <= ST_S4;
                            tmr   <= 27'd0;
                        end else begin
                            sec_left <= sec_left - 6'd1;
                        end
                    end else begin
                        sec_tmr <= sec_tmr + 25'd1;
                    end
                end
                ST_S4: begin
                    // 阶段 4: 演练完成 (3s)
                    if (tmr >= S4_CYC - 1) begin
                        tmr   <= 27'd0;
                        state <= ST_IDLE;
                    end else begin
                        tmr   <= tmr + 27'd1;
                    end
                end
                default: state <= ST_IDLE;
            endcase

            // 任意演练阶段长按均可立即退出
            if (k3_long && state != ST_IDLE) begin
                state    <= ST_IDLE;
                tmr      <= 30'd0;
                sec_left <= 6'd29;
                sec_tmr  <= 30'd0;
            end
        end
    end

    assign O_active   = (state != ST_IDLE);
    // S1~S3 阶段急促消防警笛(1)，S4 阶段静音(2)，其余正常(0)
    assign O_bgm_mode = (state == ST_S1 || state == ST_S2 || state == ST_S3) ? 2'd1 :
                        (state == ST_S4) ? 2'd2 : 2'd0;

    // -------------------------------------------------------------------------
    // 视频时序与帧边界锁存 (消除跨帧画面撕裂)
    // -------------------------------------------------------------------------
    reg        de_d, vs_d;
    reg [9:0]  px;
    reg [8:0]  py;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            px   <= 10'd0;
            py   <= 9'd0;
            de_d <= 1'b0;
            vs_d <= 1'b0;
        end else begin
            de_d <= I_de;
            vs_d <= I_vs;
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

    reg [1:0] screen_f;
    reg [2:0] state_f;
    reg       active_f;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            screen_f <= 2'd0;
            state_f  <= ST_IDLE;
            active_f <= 1'b0;
        end else if (I_vs && !vs_d) begin
            screen_f <= (state == ST_S1) ? 2'd0 :
                        (state == ST_S2) ? 2'd1 :
                        (state == ST_S3) ? 2'd2 :
                        (state == ST_S4) ? 2'd3 : 2'd0;
            state_f  <= state;
            active_f <= (state != ST_IDLE);
        end
    end

    // -------------------------------------------------------------------------
    // 32x32 大画幅字符行映射 (6 行 x 16 列, 每行独立精确居中与边界锁定)
    // -------------------------------------------------------------------------
    function [3:0] line_of;
        input [8:0] y;
        begin
            if      (y >= 9'd76  && y < 9'd108) line_of = 4'd0;
            else if (y >= 9'd132 && y < 9'd164) line_of = 4'd1;
            else if (y >= 9'd188 && y < 9'd220) line_of = 4'd2;
            else if (y >= 9'd244 && y < 9'd276) line_of = 4'd3;
            else if (y >= 9'd300 && y < 9'd332) line_of = 4'd4;
            else if (y >= 9'd356 && y < 9'd388) line_of = 4'd5;
            else                                line_of = 4'hF;
        end
    endfunction

    function [8:0] line_top;
        input [3:0] l;
        begin
            case (l)
                4'd0: line_top = 9'd76;
                4'd1: line_top = 9'd132;
                4'd2: line_top = 9'd188;
                4'd3: line_top = 9'd244;
                4'd4: line_top = 9'd300;
                default: line_top = 9'd356;
            endcase
        end
    endfunction

    function [9:0] line_left;
        input [1:0] scr;
        input [3:0] l;
        begin
            case (scr)
                2'd0: begin
                    case (l)
                        4'd1: line_left = 10'd192; // 8 字居中 (192..447, 中心 320)
                        4'd3: line_left = 10'd240; // 5 字居中 (240..399, 中心 320)
                        default: line_left = 10'd64;
                    endcase
                end
                2'd1: begin
                    case (l)
                        4'd0: line_left = 10'd176; // 标题 9 字 (176..463, 中心 320)
                        4'd1: line_left = 10'd208; // 步骤1: 6 字 (208..399)
                        4'd2: line_left = 10'd208; // 步骤2: 6 字 (208..399)
                        4'd3: line_left = 10'd208; // 步骤3: 6 字 (208..399)
                        4'd4: line_left = 10'd208; // 步骤4: 7 字 (208..431, 框内安全)
                        default: line_left = 10'd64;
                    endcase
                end
                2'd2: begin
                    case (l)
                        4'd0: line_left = 10'd240; // 5 字居中 (240..399, 中心 320)
                        4'd4: line_left = 10'd240; // 5 字居中 (240..399, 中心 320)
                        default: line_left = 10'd64;
                    endcase
                end
                default: begin
                    case (l)
                        4'd1: line_left = 10'd192; // 8 字居中 (192..447, 中心 320)
                        4'd3: line_left = 10'd240; // 5 字居中 (240..399, 中心 320)
                        default: line_left = 10'd64;
                    endcase
                end
            endcase
        end
    endfunction

    function [3:0] line_num_chars;
        input [1:0] scr;
        input [3:0] l;
        begin
            case (scr)
                2'd0: begin
                    case (l)
                        4'd1: line_num_chars = 4'd8;
                        4'd3: line_num_chars = 4'd5;
                        default: line_num_chars = 4'd0;
                    endcase
                end
                2'd1: begin
                    case (l)
                        4'd0: line_num_chars = 4'd9;
                        4'd1: line_num_chars = 4'd6;
                        4'd2: line_num_chars = 4'd6;
                        4'd3: line_num_chars = 4'd6;
                        4'd4: line_num_chars = 4'd7;
                        default: line_num_chars = 4'd0;
                    endcase
                end
                2'd2: begin
                    case (l)
                        4'd0: line_num_chars = 4'd5;
                        4'd4: line_num_chars = 4'd5;
                        default: line_num_chars = 4'd0;
                    endcase
                end
                default: begin
                    case (l)
                        4'd1: line_num_chars = 4'd8;
                        4'd3: line_num_chars = 4'd5;
                        default: line_num_chars = 4'd0;
                    endcase
                end
            endcase
        end
    endfunction

    wire [3:0]  ln         = line_of(py);
    wire [9:0]  l_left     = line_left(screen_f, ln);
    wire [3:0]  l_count    = line_num_chars(screen_f, ln);
    wire [9:0]  col_x      = px - l_left;
    wire [3:0]  col        = col_x[8:5];        // col_x >> 5 (每字符 32 像素宽)
    wire        in_text    = (ln != 4'hF) && (px >= l_left) && (col < l_count);
    wire [8:0]  row_offset = py - line_top(ln); // 0..31
    wire [3:0]  row_w      = row_offset[4:1];   // row_offset >> 1 (0..15 行点阵)

    // text_addr = screen * 96 + ln * 16 + col (4 屏 x 6 行 x 16 列 = 384)
    wire [9:0] text_addr = ({8'd0, screen_f} << 6) + ({8'd0, screen_f} << 5)
                         + ({8'd0, ln} << 4) + {6'd0, col};

    wire [7:0]  glyph_q;
    wire [15:0] font_q;

    reg  [3:0]  row_w_d1;
    reg  [3:0]  r_col, r_line;
    reg         r_valid;
    reg  [23:0] rgb_d1;
    reg         de_d1, vs_d1;
    reg  [9:0]  px_d1;
    reg  [8:0]  py_d1;

    // Stage 1 组合字模寻址 (严格越界保护)
    wire        glyph_valid_w = (glyph_q < 8'd38);
    wire [9:0]  font_addr     = glyph_valid_w ? {glyph_q[5:0], row_w_d1[3:0]} : 10'd0;

    contest_drill_rom u_rom (
        .I_clk      (I_clk),
        .I_text_addr(text_addr),
        .O_text_data(glyph_q),
        .I_font_addr(font_addr),
        .O_font_data(font_q)
    );

    // -------------------------------------------------------------------------
    // 视频流水线同步打拍 (严格 2 拍对齐)
    // -------------------------------------------------------------------------
    reg  [3:0]  r_col2, r_line2;
    reg         r_valid2;
    reg         glyph_valid_d2;
    reg  [23:0] rgb_d2;
    reg         de_d2, vs_d2;
    reg  [9:0]  px_d2;
    reg  [8:0]  py_d2;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            row_w_d1       <= 4'd0;
            r_col          <= 4'd0;
            r_line         <= 4'd0;
            r_valid        <= 1'b0;
            rgb_d1         <= 24'd0;
            de_d1          <= 1'b0;
            vs_d1          <= 1'b0;
            px_d1          <= 10'd0;
            py_d1          <= 9'd0;

            r_col2         <= 4'd0;
            r_line2        <= 4'd0;
            r_valid2       <= 1'b0;
            glyph_valid_d2 <= 1'b0;
            rgb_d2         <= 24'd0;
            de_d2          <= 1'b0;
            vs_d2          <= 1'b0;
            px_d2          <= 10'd0;
            py_d2          <= 9'd0;
        end else begin
            // Stage 1 (Cycle 1)
            row_w_d1 <= row_w;
            r_col    <= col_x[4:1];             // col_x >> 1 (0..15 列点阵)
            r_line   <= ln;
            r_valid  <= in_text;
            rgb_d1   <= I_rgb;
            de_d1    <= I_de;
            vs_d1    <= I_vs;
            px_d1    <= px;
            py_d1    <= py;

            // Stage 2 (Cycle 2)
            r_col2         <= r_col;
            r_line2        <= r_line;
            r_valid2       <= r_valid;
            glyph_valid_d2 <= glyph_valid_w;
            rgb_d2         <= rgb_d1;
            de_d2          <= de_d1;
            vs_d2          <= vs_d1;
            px_d2          <= px_d1;
            py_d2          <= py_d1;
        end
    end

    // Stage 2 字符点阵采样（2x2 无损放大，完全消除断笔）
    wire pix_on = r_valid2 && glyph_valid_d2 && font_q[15 - r_col2];

    // -------------------------------------------------------------------------
    // S3 巨幕倒计时 (32x64 纯正大字，无冒号，居中震撼 + 动态应急疏散进度条)
    // -------------------------------------------------------------------------
    reg [3:0] dig_tens_r, dig_ones_r;
    always @(*) begin
        if (sec_left >= 6'd20) begin
            dig_tens_r = 4'd2;
            dig_ones_r = sec_left - 6'd20;
        end else if (sec_left >= 6'd10) begin
            dig_tens_r = 4'd1;
            dig_ones_r = sec_left - 6'd10;
        end else begin
            dig_tens_r = 4'd0;
            dig_ones_r = sec_left[3:0];
        end
    end
    wire [3:0] dig_tens = dig_tens_r;
    wire [3:0] dig_ones = dig_ones_r;

    // 4x4 放大：8x16 点阵 -> 32x64 巨幅大字 (高度 64 像素，Y: 136..199)
    wire [7:0] drow_tens = drill_digit_row(dig_tens, (py_d2 - 9'd136) >> 2);
    wire [7:0] drow_ones = drill_digit_row(dig_ones, (py_d2 - 9'd136) >> 2);

    // 十位在 X: 272..303，个位在 X: 336..367，中间 32 像素自然留白（严格按用户要求不加冒号，中心 320）
    wire in_dig_tens = (state_f == ST_S3) && (py_d2 >= 9'd136) && (py_d2 < 9'd200) &&
                       (px_d2 >= 10'd272) && (px_d2 < 10'd304) &&
                       drow_tens[7 - ((px_d2 - 10'd272) >> 2)];

    wire in_dig_ones = (state_f == ST_S3) && (py_d2 >= 9'd136) && (py_d2 < 9'd200) &&
                       (px_d2 >= 10'd336) && (px_d2 < 10'd368) &&
                       drow_ones[7 - ((px_d2 - 10'd336) >> 2)];

    // 300 像素动态疏散进度条 (X: 170..470, Y: 216..234)
    wire in_pbar_border = (state_f == ST_S3) && (py_d2 >= 9'd216 && py_d2 < 9'd234) &&
                          (px_d2 >= 10'd170 && px_d2 < 10'd470) &&
                          (px_d2 == 10'd170 || px_d2 == 10'd469 || py_d2 == 9'd216 || py_d2 == 9'd233);

    wire [9:0] bar_fill_w = ({4'd0, sec_left} * 10'd10); // 0..290 像素平滑填充
    wire in_pbar_fill   = (state_f == ST_S3) && (py_d2 >= 9'd218 && py_d2 < 9'd232) &&
                          (px_d2 >= 10'd172 && px_d2 < 10'd172 + bar_fill_w);

    // -------------------------------------------------------------------------
    // 红色半透明科技感 HUD 卡片几何定义 (Red Glassmorphic Box & HUD Accents)
    // -------------------------------------------------------------------------
    wire in_card = (px_d2 >= 10'd24 && px_d2 < 10'd616 && py_d2 >= 9'd20 && py_d2 < 9'd460);

    // 双层高亮发光红框
    wire card_outer_border = in_card && (px_d2 == 10'd24 || px_d2 == 10'd615 || py_d2 == 9'd20 || py_d2 == 9'd459);
    wire card_inner_border = in_card && (px_d2 == 10'd25 || px_d2 == 10'd614 || py_d2 == 9'd21 || py_d2 == 9'd458);

    // 四角科技感直角护角 (HUD Corner Brackets ┌ ┐ └ ┘)
    wire in_c_tl = in_card && ((px_d2 >= 10'd24  && px_d2 < 10'd46  && py_d2 >= 9'd20  && py_d2 < 9'd23) ||
                               (px_d2 >= 10'd24  && px_d2 < 10'd27  && py_d2 >= 9'd20  && py_d2 < 9'd42));
    wire in_c_tr = in_card && ((px_d2 >= 10'd594 && px_d2 < 10'd616 && py_d2 >= 9'd20  && py_d2 < 9'd23) ||
                               (px_d2 >= 10'd613 && px_d2 < 10'd616 && py_d2 >= 9'd20  && py_d2 < 9'd42));
    wire in_c_bl = in_card && ((px_d2 >= 10'd24  && px_d2 < 10'd46  && py_d2 >= 9'd457 && py_d2 < 9'd460) ||
                               (px_d2 >= 10'd24  && px_d2 < 10'd27  && py_d2 >= 9'd438 && py_d2 < 9'd460));
    wire in_c_br = in_card && ((px_d2 >= 10'd594 && px_d2 < 10'd616 && py_d2 >= 9'd457 && py_d2 < 9'd460) ||
                               (px_d2 >= 10'd613 && px_d2 < 10'd616 && py_d2 >= 9'd438 && py_d2 < 9'd460));
    wire in_corner_bracket = in_c_tl || in_c_tr || in_c_bl || in_c_br;

    // 顶部警示条与分隔线
    wire is_header_banner = in_card && (py_d2 >= 9'd22 && py_d2 < 9'd60);
    wire is_header_sep    = in_card && (py_d2 == 9'd60);

    // 底部状态条与分隔线
    wire is_footer_banner = in_card && (py_d2 >= 9'd416 && py_d2 < 9'd458);
    wire is_footer_sep    = in_card && (py_d2 == 9'd415);

    // S2 疏散指引行高亮条 (Backlight Step Rows, X: 170..470, 完美包裹文字 X: 208..431，宽阔对称绝不溢出)
    wire in_step_box = (state_f == ST_S2) && (px_d2 >= 10'd170 && px_d2 < 10'd470) && (
        (py_d2 >= 9'd126 && py_d2 < 9'd170) ||
        (py_d2 >= 9'd182 && py_d2 < 9'd226) ||
        (py_d2 >= 9'd238 && py_d2 < 9'd282) ||
        (py_d2 >= 9'd294 && py_d2 < 9'd338)
    );
    wire in_step_box_border = in_step_box && (
        px_d2 == 10'd170 || px_d2 == 10'd469 ||
        py_d2 == 9'd126  || py_d2 == 9'd169 ||
        py_d2 == 9'd182  || py_d2 == 9'd225 ||
        py_d2 == 9'd238  || py_d2 == 9'd281 ||
        py_d2 == 9'd294  || py_d2 == 9'd337
    );

    // 底部科技感状态指示光条 (X: 200..440, Y: 434..440)
    wire in_footer_glow_bar = is_footer_banner && (px_d2 >= 10'd200 && px_d2 < 10'd440) && (py_d2 >= 9'd434 && py_d2 < 9'd440);

    // -------------------------------------------------------------------------
    // 输出视频生成与 Alpha 混合 (Stage 3 输出寄存器)
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
                // 普通切图模式: 100% 原始直通
                O_rgb <= rgb_d2;
            end else if (!de_d2) begin
                O_rgb <= 24'd0;
            end else if (in_corner_bracket) begin
                // HUD 四角发光直角护角：纯正高亮金/电光红
                O_rgb <= 24'hFFD700;
            end else if (card_outer_border) begin
                // 外层发光边框 (S1警报金红交替闪烁)
                if (state_f == ST_S1 && flash_on)
                    O_rgb <= 24'hFFAE00;
                else
                    O_rgb <= 24'hFF3B3B;
            end else if (card_inner_border) begin
                // 内层亮红边框
                if (state_f == ST_S1 && flash_on)
                    O_rgb <= 24'hFF3333;
                else
                    O_rgb <= 24'hFF6B6B;
            end else if (is_header_sep || is_footer_sep) begin
                // 横向科技感分隔线
                O_rgb <= 24'hFF5555;
            end else if (pix_on) begin
                // 32x32 宏大汉字色彩分级渲染
                if (state_f == ST_S1) begin
                    // 警报阶段：第一行醒目亮黄，第二行纯白加亮
                    if (r_line2 == 4'd1)
                        O_rgb <= 24'hFFE600;
                    else
                        O_rgb <= 24'hFFFFFF;
                end else if (state_f == ST_S2) begin
                    // 疏散阶段：标题亮黄，步骤条目序号(col 0)亮青，正文纯白高对比度
                    if (r_line2 == 4'd0)
                        O_rgb <= 24'hFFE600;
                    else if (px_d2 < 10'd240)
                        O_rgb <= 24'h00F0FF; // 步骤序号 1/2/3/4 电光青
                    else
                        O_rgb <= 24'hFFFFFF; // 步骤正文纯白
                end else if (state_f == ST_S3) begin
                    // 倒计时阶段标题：辉光金色，底部撤离提示纯白
                    if (r_line2 == 4'd0)
                        O_rgb <= 24'hFFD200;
                    else
                        O_rgb <= 24'hFFFFFF;
                end else if (state_f == ST_S4) begin
                    // 完成阶段：对号与演练完成赋翡翠绿，安全提示纯白
                    if (r_line2 == 4'd1)
                        O_rgb <= 24'h4BE38A;
                    else
                        O_rgb <= 24'hFFFFFF;
                end else begin
                    O_rgb <= 24'hFFFFFF;
                end
            end else if (in_dig_tens || in_dig_ones) begin
                // S3 巨幕倒计时 (32x64 纯正大字，无冒号)：<=5秒紧急黄红交替闪烁
                if (sec_left <= 6'd5 && flash_on)
                    O_rgb <= 24'hFFE600;
                else
                    O_rgb <= 24'hFF3B3B;
            end else if (in_pbar_border) begin
                // 进度条边框
                O_rgb <= 24'h00D2FF;
            end else if (in_pbar_fill) begin
                // 动态应急疏散进度条填充色
                if (sec_left <= 6'd5)
                    O_rgb <= flash_on ? 24'hFF2222 : 24'hFFAE00;
                else if (sec_left <= 6'd10)
                    O_rgb <= 24'hFFC107;
                else
                    O_rgb <= 24'h00E676;
            end else if (in_step_box_border) begin
                // S2 步骤条高亮边框
                O_rgb <= 24'hFF4444;
            end else if (in_step_box) begin
                // S2 步骤条通透发光背景
                O_rgb <= {2'b00, rgb_d2[23:18], 2'b00, rgb_d2[15:10], 2'b00, rgb_d2[7:2]} + 24'h380A0A;
            end else if (is_header_banner) begin
                // 顶部警示条底色
                if (state_f == ST_S1)
                    O_rgb <= flash_on ? 24'h550A0A : 24'h330606;
                else if (state_f == ST_S4)
                    O_rgb <= 24'h0E381E; // 演练顺利完成翡翠底
                else
                    O_rgb <= 24'h360808;
            end else if (in_footer_glow_bar) begin
                // 底部科技感状态发光条
                O_rgb <= 24'h00F0FF;
            end else if (is_footer_banner) begin
                // 底部状态栏底色
                O_rgb <= 24'h260606;
            end else if (in_card) begin
                // 框内半透明红色混合底 (保留底图 25% 纹理 + 叠加通透暗红滤镜)
                if (state_f == ST_S1 && flash_on)
                    O_rgb <= {1'b0, rgb_d2[23:17] + 7'd80, 2'b00, rgb_d2[15:10], 2'b00, rgb_d2[7:2]};
                else
                    O_rgb <= {2'b00, rgb_d2[23:18], 2'b00, rgb_d2[15:10], 2'b00, rgb_d2[7:2]} + 24'h2E0808;
            end else begin
                // 框外底图适度压暗 50%
                O_rgb <= {1'b0, rgb_d2[23:17], 1'b0, rgb_d2[15:9], 1'b0, rgb_d2[7:1]};
            end
        end
    end

endmodule

//=============================================================================
// drill_key_ctrl
//-----------------------------------------------------------------------------
// 按键两级同步、硬件消抖与长短按分离控制器。
//=============================================================================
module drill_key_ctrl #(
    parameter integer CLK_HZ      = 25000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1000
)(
    input  wire I_clk,
    input  wire I_rst,
    input  wire I_btn,        // 低有效：按下=0
    output reg  O_short,      // 短按松开脉冲
    output reg  O_long        // 长按达标单周期脉冲
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

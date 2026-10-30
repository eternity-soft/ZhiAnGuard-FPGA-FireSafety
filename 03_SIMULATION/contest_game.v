// V27 火场逃生全功能集成与画质优化版 (Slim & Optimized for EG4S20 Placement)
module contest_game #(
    parameter integer H_ACTIVE    = 640,
    parameter integer V_ACTIVE    = 480,
    parameter integer CLK_HZ      = 25000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1000,
    parameter integer FIRE_MS     = 300,
    parameter integer ANIM_MS     = 250,
    parameter integer POISON_TICK_MS = 250,
    parameter integer INTRO_MS    = 5000,
    parameter integer ITEM_MS     = 3000
)(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire        I_enable,
    input  wire        I_key1,      // KEY2: 前进 / 跳过 / 重开
    input  wire        I_key2,      // KEY3: 转向
    input  wire        I_key3,      // KEY4: 灭火
    input  wire        I_key_game,  // KEY1: 长按进出游戏
    output wire        O_key3_short,
    output wire        O_active,
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_rgb
);

`include "contest_game_mini.v"

localparam integer TICK_1MS_CYC = CLK_HZ / 1000;
localparam integer POISON_MAX   = 13'd4800;
localparam integer EXT_USES_MAX = 3;

localparam [2:0] ST_IDLE  = 3'd0;
localparam [2:0] ST_INTRO = 3'd1;
localparam [2:0] ST_ITEM1 = 3'd2;
localparam [2:0] ST_ITEM2 = 3'd3;
localparam [2:0] ST_PLAY  = 3'd4;
localparam [2:0] ST_DEAD  = 3'd5;
localparam [2:0] ST_WIN   = 3'd6;

localparam T_FLOOR=8'd0; localparam T_FLOOR2=8'd1;
localparam T_WALL=8'd2;  localparam T_WALL2=8'd3;
localparam T_EXIT=8'd4;  localparam T_FIRE=8'd5;  localparam T_FIRE2=8'd6;
localparam T_BIGFIRE=8'd7; localparam T_EXT=8'd8; localparam T_RUG=8'd9;
localparam T_TABLE=8'd10; localparam T_CHAR=8'd11; localparam T_BED=8'd12;
localparam T_SOFA=8'd13; localparam T_TOILET=8'd14; localparam T_TUB=8'd15;
localparam T_COUNTER=8'd16; localparam T_STOVE=8'd17; localparam T_FRIDGE=8'd18;
localparam T_WARD=8'd19; localparam T_TV=8'd20; localparam T_TOWEL=8'd21;
localparam T_PLANT=8'd22; localparam T_WINDOW=8'd23; localparam T_WASHER=8'd24;

localparam [8:0] FIRE_SRC0 = 9'd45;    // Bedroom fire (5,2)
localparam [8:0] FIRE_SRC1 = 9'd88;    // Doorway fire (8,4)
localparam [8:0] FIRE_SRC2 = 9'd210;   // Corridor fire (10,10)
localparam [8:0] FIRE_SRC3 = 9'd211;   // Corridor fire (11,10)
localparam [8:0] ITEM_EXT_POS   = 9'd170; // Extinguisher (10,8)
localparam [8:0] ITEM_TOWEL_POS = 9'd50;  // Wet Towel (10,2)

function is_fire;
    input [7:0] t;
    begin is_fire = (t==T_FIRE)||(t==T_FIRE2)||(t==T_BIGFIRE); end
endfunction
function is_floorish;
    input [7:0] t;
    begin is_floorish = (t==T_FLOOR)||(t==T_FLOOR2); end
endfunction
function is_furniture;
    input [7:0] t;
    begin
        is_furniture = (t==T_RUG)||(t==T_TABLE)||(t==T_BED)||(t==T_SOFA)||
                       (t==T_TOILET)||(t==T_TUB)||(t==T_COUNTER)||(t==T_WARD);
    end
endfunction
function is_appliance;
    input [7:0] t;
    begin is_appliance = (t==T_FRIDGE)||(t==T_TV)||(t==T_WASHER); end
endfunction
function is_walkable;
    input [7:0] t;
    begin
        is_walkable = (t==T_FLOOR)||(t==T_FLOOR2)||(t==T_EXIT)||(t==T_EXT)||
                       (t==T_RUG)||(t==T_CHAR)||(t==T_TOWEL);
    end
endfunction

// ---------------------------------------------------------------- 全局 1ms 脉冲发生器
reg [14:0] tick_1ms_cnt;
reg        tick_1ms;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        tick_1ms_cnt <= 15'd0;
        tick_1ms     <= 1'b0;
    end else begin
        if (tick_1ms_cnt >= TICK_1MS_CYC - 1) begin
            tick_1ms_cnt <= 15'd0;
            tick_1ms     <= 1'b1;
        end else begin
            tick_1ms_cnt <= tick_1ms_cnt + 15'd1;
            tick_1ms     <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------- 按键控制器
wire k1_press, k2_press, k3_press;
wire k_game_short, k_game_long;

game_key_ctrl #(.DEBOUNCE_MS(DEBOUNCE_MS)) u_k1 (
    .I_clk(I_clk), .I_rst(I_rst), .I_tick(tick_1ms), .I_btn(I_key1), .O_press(k1_press));

game_key_ctrl #(.DEBOUNCE_MS(DEBOUNCE_MS)) u_k2 (
    .I_clk(I_clk), .I_rst(I_rst), .I_tick(tick_1ms), .I_btn(I_key2), .O_press(k2_press));

game_key_ctrl #(.DEBOUNCE_MS(DEBOUNCE_MS)) u_k3 (
    .I_clk(I_clk), .I_rst(I_rst), .I_tick(tick_1ms), .I_btn(I_key3), .O_press(k3_press));

game_long_ctrl #(.DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS)) u_key_game (
    .I_clk(I_clk), .I_rst(I_rst), .I_tick(tick_1ms), .I_btn(I_key_game), .O_short(k_game_short), .O_long(k_game_long));

assign O_key3_short = k3_press;

// ---------------------------------------------------------------- 主状态机
reg [2:0]  state;
reg [12:0] tmr;
reg        restart_req;
reg        entry_rst;
reg        win_flag, lose_fire, lose_poison;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        state <= ST_IDLE; tmr <= 13'd0; restart_req <= 1'b0; entry_rst <= 1'b0;
    end else if (I_enable) begin
        restart_req <= 1'b0;
        entry_rst   <= 1'b0;
        case (state)
        ST_IDLE: begin
            if (k_game_long) begin
                state     <= ST_INTRO;
                tmr       <= 13'd0;
                entry_rst <= 1'b1;
            end
        end
        ST_INTRO: begin
            if (k1_press || tmr >= INTRO_MS-1) begin tmr <= 13'd0; state <= ST_ITEM1; end
            else if (tick_1ms) tmr <= tmr + 13'd1;
        end
        ST_ITEM1: begin
            if (k1_press || tmr >= ITEM_MS-1) begin tmr <= 13'd0; state <= ST_ITEM2; end
            else if (tick_1ms) tmr <= tmr + 13'd1;
        end
        ST_ITEM2: begin
            if (k1_press || tmr >= ITEM_MS-1) begin tmr <= 13'd0; state <= ST_PLAY; end
            else if (tick_1ms) tmr <= tmr + 13'd1;
        end
        ST_PLAY: begin
            if (win_flag && !restart_req)           state <= ST_WIN;
            else if ((lose_fire || lose_poison) && !restart_req) state <= ST_DEAD;
        end
        ST_DEAD: begin
            if (k1_press) begin
                state       <= ST_PLAY;
                restart_req <= 1'b1;
            end
        end
        ST_WIN: begin
            if (k1_press) begin
                state       <= ST_PLAY;
                restart_req <= 1'b1;
            end
        end
        default: state <= ST_IDLE;
        endcase

        // 任何阶段长按 KEY1 均可退出游戏
        if (k_game_long && state != ST_IDLE) begin
            state <= ST_IDLE;
            tmr   <= 13'd0;
        end
    end
end

assign O_active = (state != ST_IDLE);
wire in_play  = (state == ST_PLAY);

// ---------------------------------------------------------------- 伪随机与动画
reg [15:0] lfsr;
always @(posedge I_clk or posedge I_rst)
    if (I_rst) lfsr <= 16'hBEEF;
    else       lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

reg        fire_anim;
reg [7:0]  anim_cnt;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin fire_anim <= 1'b0; anim_cnt <= 8'd0; end
    else if (tick_1ms) begin
        if (anim_cnt >= ANIM_MS-1) begin anim_cnt <= 8'd0; fire_anim <= ~fire_anim; end
        else anim_cnt <= anim_cnt + 8'd1;
    end
end

// ---------------------------------------------------------------- 角色控制
reg [1:0] dir;
reg [4:0] pos_x;
reg [3:0] pos_y;
reg [4:0] prev_x;
reg [3:0] prev_y;
reg       walk_toggle;
reg       has_towel, has_ext;
reg [1:0] ext_uses;
reg [4:0] ext_min_x, ext_max_x;
reg [3:0] ext_min_y, ext_max_y;
reg       ext_req;


reg       revert_flag;
reg       under_fire, under_exit;
reg       towel_pickup, ext_pickup;
reg       ext_ack;

// dir_next replaced with dir + 2'd1

wire dx_neg = (dir == 2'd1);
wire dx_pos = (dir == 2'd2);
wire dy_neg = (dir == 2'd3);
wire dy_pos = (dir == 2'd0);

wire move_ok =
    (dx_neg ? (pos_x != 5'd0)  : 1'b1) &
    (dx_pos ? (pos_x != 5'd19) : 1'b1) &
    (dy_neg ? (pos_y != 4'd0)  : 1'b1) &
    (dy_pos ? (pos_y != 4'd14) : 1'b1);

wire [4:0] fx_w = dx_neg ? (pos_x - 5'd1) : (dx_pos ? (pos_x + 5'd1) : pos_x);
wire [3:0] fy_w = dy_neg ? (pos_y - 4'd1) : (dy_pos ? (pos_y + 4'd1) : pos_y);
wire [8:0] player_cell_w = {1'b0, pos_y, 4'b0} + {3'b0, pos_y, 2'b0} + {4'b0, pos_x};


always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        dir <= 2'd0; pos_x <= 5'd2; pos_y <= 4'd2;
        prev_x <= 5'd2; prev_y <= 4'd2;
        walk_toggle <= 1'b0; has_towel <= 1'b0; has_ext <= 1'b0;
        ext_uses <= EXT_USES_MAX;
        ext_min_x <= 5'd0; ext_max_x <= 5'd0; ext_min_y <= 4'd0; ext_max_y <= 4'd0;
        win_flag <= 1'b0; lose_fire <= 1'b0;
        ext_req <= 1'b0; 
    end else if (entry_rst || restart_req) begin
        dir <= 2'd0; pos_x <= 5'd2; pos_y <= 4'd2;
        prev_x <= 5'd2; prev_y <= 4'd2;
        walk_toggle <= 1'b0; has_towel <= 1'b0; has_ext <= 1'b0;
        ext_uses <= EXT_USES_MAX;
        ext_min_x <= 5'd0; ext_max_x <= 5'd0; ext_min_y <= 4'd0; ext_max_y <= 4'd0;
        win_flag <= 1'b0; lose_fire <= 1'b0;
        ext_req <= 1'b0; 
    end else if (I_enable && in_play) begin
        if (towel_pickup) has_towel <= 1'b1;
        if (ext_pickup)   has_ext   <= 1'b1;
        if (ext_ack)      ext_req   <= 1'b0;
        if (k2_press) dir <= dir + 2'd1;
        if (k1_press && move_ok) begin
            prev_x <= pos_x; prev_y <= pos_y;
            pos_x <= fx_w;   pos_y <= fy_w;
            walk_toggle <= ~walk_toggle;
        end
        if (k3_press && has_ext && ext_uses > 2'd0) begin
            ext_req    <= 1'b1;
            ext_uses   <= ext_uses - 2'd1;
            ext_min_x  <= (pos_x == 5'd0)  ? 5'd0  : (pos_x - 5'd1);
            ext_max_x  <= (pos_x == 5'd19) ? 5'd19 : (pos_x + 5'd1);
            ext_min_y  <= (pos_y == 4'd0)  ? 4'd0  : (pos_y - 4'd1);
            ext_max_y  <= (pos_y == 4'd14) ? 4'd14 : (pos_y + 4'd1);
        end
        if (revert_flag) begin pos_x <= prev_x; pos_y <= prev_y; end
        if (under_fire) lose_fire <= 1'b1;
        if (under_exit || (pos_x == 5'd18 && pos_y == 4'd12)) win_flag <= 1'b1;
    end
end

// ---------------------------------------------------------------- 毒气积累
reg [12:0] poison_acc;
reg [7:0]  poison_tmr;
reg [9:0]  poison_fill_end;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        poison_acc <= 13'd0; poison_tmr <= 8'd0; lose_poison <= 1'b0; poison_fill_end <= 10'd60;
    end else if (entry_rst || restart_req) begin
        poison_acc <= 13'd0; poison_tmr <= 8'd0; lose_poison <= 1'b0; poison_fill_end <= 10'd60;
    end else if (I_enable && in_play) begin
        if (tick_1ms) begin
            poison_fill_end <= 10'd60 + {1'b0, poison_acc[12:4]};
            if (poison_tmr >= POISON_TICK_MS - 1) begin
                poison_tmr <= 8'd0;
                if (has_towel) begin
                    if (poison_acc >= POISON_MAX - 13'd12) begin
                        poison_acc <= POISON_MAX; lose_poison <= 1'b1;
                    end else poison_acc <= poison_acc + 13'd12;
                end else begin
                    if (poison_acc >= POISON_MAX - 13'd60) begin
                        poison_acc <= POISON_MAX; lose_poison <= 1'b1;
                    end else poison_acc <= poison_acc + 13'd60;
                end
            end else poison_tmr <= poison_tmr + 8'd1;
        end
    end
end

// ---------------------------------------------------------------- 地图扫描与物理引擎 (Port B)
reg        scan_en;
reg [2:0]  sph;

reg [8:0]  cell_idx;
reg [4:0]  scan_tx;
reg [3:0]  scan_ty;
reg [8:0]  nbr_cell;

reg [8:0]  fire_tmr;
reg [8:0]  b_addr_r;
reg [8:0]  b_waddr_r;
reg [7:0]  b_wdata_r;
reg        b_wen_r;
reg [7:0]  cur_byte, nbr_byte;
reg [7:0]  under_val;
reg        rst_mode;

wire        nbr_left_ok  = (scan_tx != 5'd0);
wire        nbr_right_ok = (scan_tx != 5'd19);
wire        nbr_ok       = lfsr[0] ? nbr_right_ok : nbr_left_ok;
wire [8:0]  nbr_offset   = lfsr[0] ? 9'd1 : -9'd1;
wire [8:0]  nbr_w        = cell_idx + nbr_offset;

// 灭火器周围 9 格判断 (pos_x-1..pos_x+1, pos_y-1..pos_y+1)
wire ext_x_match = (scan_tx >= ext_min_x && scan_tx <= ext_max_x);
wire ext_y_match = (scan_ty >= ext_min_y && scan_ty <= ext_max_y);
wire in_ext_9grid = ext_x_match && ext_y_match;

wire [7:0] cur     = cur_byte;
wire [7:0] nbr_val = nbr_byte;

// blast_mask[3:0] replaced app_tx/app_ty

wire [7:0] b_data_r;
reg        next_spread;





wire       is_last_cell   = (cell_idx == 9'd299);
wire       is_eol_cell    = (scan_tx == 5'd19);
wire [8:0] next_cell_idx  = cell_idx + 9'd1;
wire [4:0] next_scan_tx   = is_eol_cell ? 5'd0 : (scan_tx + 5'd1);
wire [3:0] next_scan_ty   = is_eol_cell ? (scan_ty + 4'd1) : scan_ty;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        scan_en <= 1'b0; sph <= 3'd0; 
        cell_idx <= 9'd0; scan_tx <= 5'd0; scan_ty <= 4'd0;
        nbr_cell <= 9'd0; 
        fire_tmr <= 9'd0; b_wen_r <= 1'b0;
        b_addr_r <= 11'd0; b_waddr_r <= 11'd0; b_wdata_r <= 8'd0;
        cur_byte <= 8'd0; nbr_byte <= 8'd0; under_val <= 8'd0;
        revert_flag <= 1'b0; under_fire <= 1'b0; under_exit <= 1'b0; 
        towel_pickup <= 1'b0; ext_pickup <= 1'b0; ext_ack <= 1'b0;
        rst_mode <= 1'b0;
    end else if (I_enable && (in_play || rst_mode)) begin
        b_wen_r <= 1'b0;
        revert_flag <= 1'b0;
        under_fire <= 1'b0; under_exit <= 1'b0; 
        towel_pickup <= 1'b0; ext_pickup <= 1'b0; ext_ack <= 1'b0;

        if (restart_req) begin
            scan_en  <= 1'b1; rst_mode <= 1'b1;
            sph      <= 3'd0; cell_idx <= 9'd0; scan_tx <= 5'd0; scan_ty <= 4'd0;
        end else if (!scan_en && fire_tmr >= FIRE_MS - 1) begin
            fire_tmr <= 9'd0;
            scan_en  <= 1'b1; rst_mode <= 1'b0;
            sph      <= 3'd0; cell_idx <= 9'd0; scan_tx <= 5'd0; scan_ty <= 4'd0;
        end else if (scan_en) begin
            case (sph)
            3'd0: begin
                b_addr_r <= cell_idx;
                sph <= 3'd1;
            end
            3'd1: sph <= 3'd2;
            3'd2: begin
                cur_byte <= b_data_r;
                sph <= 3'd3;
            end
            3'd3: begin
                next_spread = 1'b0;
                if (rst_mode) begin
                    if (cell_idx == FIRE_SRC0 || cell_idx == FIRE_SRC1 || cell_idx == FIRE_SRC2) begin
                        b_wen_r<=1'b1; b_waddr_r<=cell_idx; b_wdata_r<=T_FIRE;
                    end else if (cell_idx == ITEM_EXT_POS) begin
                        b_wen_r<=1'b1; b_waddr_r<=cell_idx; b_wdata_r<=T_EXT;
                    end else if (cell_idx == ITEM_TOWEL_POS) begin
                        b_wen_r<=1'b1; b_waddr_r<=cell_idx; b_wdata_r<=T_TOWEL;
                    end else if (is_fire(cur) || cur == T_CHAR) begin
                        b_wen_r<=1'b1; b_waddr_r<=cell_idx; b_wdata_r<=T_FLOOR;
                    end
                end
                else if (ext_req && in_ext_9grid) begin
                    if (is_fire(cur)) begin
                        b_wen_r<=1'b1; b_waddr_r<=cell_idx; b_wdata_r<=T_FLOOR;
                    end
                end
                else if (cell_idx == player_cell_w) begin
                    under_val <= cur;
                    if (cur == T_TOWEL) begin
                        towel_pickup <= 1'b1;
                        b_wen_r <= 1'b1; b_waddr_r <= cell_idx; b_wdata_r <= T_FLOOR;
                    end
                    if (cur == T_EXT) begin
                        ext_pickup   <= 1'b1;
                        b_wen_r <= 1'b1; b_waddr_r <= cell_idx; b_wdata_r <= T_FLOOR;
                    end
                    if (cur == T_EXIT)  under_exit   <= 1'b1;
                    if (is_fire(cur))   under_fire   <= 1'b1;
                    if (!is_walkable(cur)) revert_flag <= 1'b1;
                end
                else if (is_fire(cur)) begin
                    // 火焰持续燃烧绝不自行熄灭，仅横向蔓延
                    if (nbr_ok) begin
                        nbr_cell <= nbr_w;
                        b_addr_r <= nbr_w;
                        next_spread = 1'b1;
                    end
                end
                if (next_spread) sph <= 3'd4;
                else if (is_last_cell) begin
                    if (ext_req) ext_ack <= 1'b1;
                    scan_en <= 1'b0; rst_mode <= 1'b0; sph <= 3'd0;
                end
                else begin
                    cell_idx <= next_cell_idx;
                    b_addr_r <= next_cell_idx;
                    scan_tx  <= next_scan_tx;
                    scan_ty  <= next_scan_ty;
                    sph      <= 3'd1;
                end
            end
            3'd4: sph <= 3'd5;
            3'd5: begin
                nbr_byte <= b_data_r;
                sph <= 3'd6;
            end
            3'd6: begin
                if (is_floorish(nbr_val)) begin
                    if (lfsr[4]) begin
                        b_wen_r<=1'b1; b_waddr_r<=nbr_cell; b_wdata_r<=T_FIRE;
                    end
                end else if (is_furniture(nbr_val)) begin
                    b_wen_r<=1'b1; b_waddr_r<=nbr_cell; b_wdata_r<=T_BIGFIRE;
                end else if (is_appliance(nbr_val)) begin
                    b_wen_r<=1'b1; b_waddr_r<=nbr_cell; b_wdata_r<=T_BIGFIRE;
                    if (player_cell_w == nbr_cell) under_fire <= 1'b1;
                end

                if (is_last_cell) begin scan_en <= 1'b0; rst_mode <= 1'b0; sph <= 3'd0; end
                else begin
                    cell_idx <= next_cell_idx;
                    b_addr_r <= next_cell_idx;
                    scan_tx  <= next_scan_tx;
                    scan_ty  <= next_scan_ty;
                    sph      <= 3'd1;
                end
            end
            endcase
        end else begin
            if (tick_1ms) fire_tmr <= fire_tmr + 9'd1;
            sph <= 3'd0;
        end
    end
end
// ---------------------------------------------------------------- 调色板
function [23:0] pal;
    input [3:0] i;
    begin
        case (i)
        4'd0:  pal = 24'h000000;
        4'd1:  pal = 24'h141624;
        4'd2:  pal = 24'h3A271E;
        4'd3:  pal = 24'h5A3D2B;
        4'd4:  pal = 24'hC8A878;
        4'd5:  pal = 24'hA88858;
        4'd6:  pal = 24'hE43B44;
        4'd7:  pal = 24'hF77622;
        4'd8:  pal = 24'hFFC94A;
        4'd9:  pal = 24'h3B5DC9;
        4'd10: pal = 24'h9FC5E8;
        4'd11: pal = 24'h30A46C;
        4'd12: pal = 24'hFFFFFF;
        4'd13: pal = 24'h181425;
        4'd14: pal = 24'h566C86;
        default: pal = 24'hEF7D57;
        endcase
    end
endfunction

// ---------------------------------------------------------------- 文本查找逻辑 (全局单减法器槽位索引)
function [8:0] get_slot_glyph;
    input [2:0] screen;
    input [2:0] line_id;
    input [4:0] slot;
    input       lose_fire;
    begin
        get_slot_glyph = 9'h000;
        
        // 公共按键提示分支合并 (大幅消除冗余 LUT 与比较器树)
        // 底部按键引导行统一复用 (ST_INTRO Line 6, ST_ITEM1/2 Line 6, ST_DEAD/WIN Line 5)
        if ((screen == 3'd1 && line_id == 3'd6) ||
            ((screen == 3'd2 || screen == 3'd3) && line_id == 3'd6) ||
            ((screen == 3'd5 || screen == 3'd6) && line_id == 3'd5)) begin
            begin : footer_blk
                reg [4:0] base_slot;
                reg [4:0] rel_slot;
                reg       glyph_half;
                base_slot = (screen == 3'd1) ? 5'd7 : (((screen == 3'd5) || (screen == 3'd6)) ? 5'd8 : 5'd2);
                rel_slot  = slot - base_slot;
                glyph_half = (screen == 3'd1) ? slot[0] : ~slot[0];
                if (slot >= base_slot && rel_slot <= 5'd16) begin
                    case (rel_slot)
                    5'd0:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd37}; // [
                    5'd1:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd42}; // 空格
                    5'd2:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd20}; // K
                    5'd3:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd14}; // E
                    5'd4:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd34}; // Y
                    5'd5:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd2};  // 2
                    5'd6:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd36}; // :
                    5'd7,  5'd8:  get_slot_glyph = {1'b1, 1'b0, glyph_half, 6'd25};
                    5'd9,  5'd10: get_slot_glyph = {1'b1, 1'b0, glyph_half, 6'd26};
                    5'd11, 5'd12: get_slot_glyph = {1'b1, 1'b0, glyph_half, 6'd10};
                    5'd13, 5'd14: get_slot_glyph = {1'b1, 1'b0, glyph_half, 6'd11};
                    5'd15: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd42}; // 空格
                    5'd16: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd38}; // ]
                    default: get_slot_glyph = 9'h000;
                    endcase
                end else begin
                    get_slot_glyph = 9'h000;
                end
            end
        end else begin
            case (screen)
            3'd1: begin // ST_INTRO
                case (line_id)
                3'd0: begin
                    case (slot)
                    5'd10, 5'd11: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd0};
                    5'd12, 5'd13: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd1};
                    5'd14, 5'd15: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd2};
                    5'd16, 5'd17: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd3};
                    5'd18, 5'd19: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd4};
                    5'd20, 5'd21: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd5};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd1, 3'd2, 3'd3, 3'd4: begin
                    // KEY1长按:开始 | KEY2短按:前进 | KEY4短按:灭火 | KEY3短按:转向 (公共模板抽取)
                    case (slot)
                    5'd9:  get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd20};
                    5'd10: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd14};
                    5'd11: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd34};
                    5'd12: get_slot_glyph = {1'b1, 1'b1, 1'b0, (line_id==3'd1)?6'd1:((line_id==3'd2)?6'd2:((line_id==3'd3)?6'd3:6'd4))};
                    5'd13, 5'd14: get_slot_glyph = {1'b1, 1'b0, ~slot[0], (line_id==3'd1)?6'd6:6'd12};
                    5'd15, 5'd16: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd7};
                    5'd17: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd36};
                    5'd18, 5'd19: get_slot_glyph = {1'b1, 1'b0, slot[0], (line_id==3'd1)?6'd8:((line_id==3'd2)?6'd13:((line_id==3'd3)?6'd17:6'd15))};
                    5'd20, 5'd21: get_slot_glyph = {1'b1, 1'b0, slot[0], (line_id==3'd1)?6'd9:((line_id==3'd2)?6'd14:((line_id==3'd3)?6'd0:6'd16))};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd5: begin
                    case (slot)
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd18};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd19};
                    5'd10, 5'd11: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd20};
                    5'd12, 5'd13: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd21};
                    5'd14, 5'd15: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd22};
                    5'd16: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd42};
                    5'd17, 5'd18: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd2};
                    5'd19, 5'd20: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd9};
                    5'd21, 5'd22: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd23};
                    5'd23, 5'd24: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd24};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd6: get_slot_glyph = 9'h000;
                default: get_slot_glyph = 9'h000;
                endcase
            end
            3'd2: begin // ST_ITEM1
                case (line_id)
                3'd0: begin
                    case (slot)
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd17};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd0};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd29};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd2: begin
                    case (slot)
                    5'd2, 5'd3: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd27};
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd28};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd36};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd37};
                    5'd10, 5'd11: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd17};
                    5'd12, 5'd13: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd0};
                    5'd14, 5'd15: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd29};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd3: begin
                    case (slot)
                    5'd2, 5'd3: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd30};
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd17};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd0};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd31};
                    5'd10: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd42};
                    5'd11, 5'd12: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd58};
                    5'd13, 5'd14: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd59};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd4: begin
                    case (slot)
                    5'd2, 5'd3: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd32};
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd33};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd34};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd35};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                default: get_slot_glyph = 9'h000;
                endcase
            end
            3'd3: begin // ST_ITEM2
                case (line_id)
                3'd0: begin
                    case (slot)
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd18};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd19};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd20};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd2: begin
                    case (slot)
                    5'd2, 5'd3: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd38};
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd3};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd39};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd36};
                    5'd10, 5'd11: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd37};
                    5'd12, 5'd13: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd18};
                    5'd14, 5'd15: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd19};
                    5'd16, 5'd17: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd20};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd3: begin
                    case (slot)
                    5'd2, 5'd3: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd40};
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd41};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd42};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd43};
                    5'd10, 5'd11: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd44};
                    5'd12, 5'd13: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd45};
                    5'd14, 5'd15: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd46};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                3'd4: begin
                    case (slot)
                    5'd2, 5'd3: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd47};
                    5'd4, 5'd5: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd18};
                    5'd6, 5'd7: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd19};
                    5'd8, 5'd9: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd20};
                    5'd10, 5'd11: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd48};
                    5'd12, 5'd13: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd4};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                default: get_slot_glyph = 9'h000;
                endcase
            end
            3'd5: begin // ST_DEAD (仅保留 GAME OVER 与底部重新开始引导，去除火势过大文字)
                get_slot_glyph = 9'h000;
            end
            3'd6: begin // ST_WIN
                case (line_id)
                3'd3: begin
                    case (slot)
                    5'd7, 5'd8: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd56};
                    5'd9, 5'd10: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd57};
                    5'd11, 5'd12: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd58};
                    5'd13, 5'd14: get_slot_glyph = {1'b1, 1'b0, ~slot[0], 6'd59};
                    5'd15: get_slot_glyph = {1'b1, 1'b1, 1'b0, 6'd42};
                    5'd16, 5'd17: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd60};
                    5'd18, 5'd19: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd61};
                    5'd20, 5'd21: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd2};
                    5'd22, 5'd23: get_slot_glyph = {1'b1, 1'b0, slot[0], 6'd3};
                    default: get_slot_glyph = 9'h000;
                    endcase
                end
                default: get_slot_glyph = 9'h000;
                endcase
            end
            default: get_slot_glyph = 9'h000;
            endcase
        end
    end
endfunction


// ---------------------------------------------------------------- 视频与字模流水线
reg        de_d, vs_d;
reg [9:0]  px;
reg [8:0]  py;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin px <= 10'd0; py <= 9'd0; de_d <= 1'b0; vs_d <= 1'b0; end
    else begin
        de_d <= I_de; vs_d <= I_vs;
        if (I_vs != vs_d) py <= 9'd0;
        else if (!I_de && de_d) py <= (py == V_ACTIVE-1) ? 9'd0 : py + 9'd1;
        if (!I_de) px <= 10'd0;
        else if (px == H_ACTIVE-1) px <= 10'd0;
        else px <= px + 10'd1;
    end
end

reg [2:0] screen_f;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) screen_f <= 3'd0;
    else if (I_vs && !vs_d) screen_f <= state;
end

// --- Stage 0: 扫描行前级预译码寄存器与像素寻址 ---
reg [2:0] cur_line_id;
reg [3:0] cur_line_row;
reg       cur_in_text_y;
reg       cur_in_big_y;
reg [3:0] cur_big_row;
reg       cur_in_box_y;
reg       cur_in_border_y_outer;
reg       cur_in_border_y_inner;
reg       cur_in_inner_box_y;
reg       cur_in_pedestal_y;
reg       cur_pedestal_edge_y;
reg       cur_in_showcase_y;
reg [3:0] cur_showcase_ty;
reg [8:0]  cur_map_y_base;
reg        cur_in_hud_bar_y;
reg        cur_in_hud_fill_y;
reg        cur_in_hud_border_y;
reg        cur_in_hud_edge_y;
reg        cur_in_hud_dot_y;
reg        cur_in_dpad_plate_y;
reg        cur_in_dpad_edge_y;
reg        cur_in_dpad_up_y;
reg  [3:0] cur_dpad_up_ry;
reg        cur_in_dpad_mid_y;
reg  [3:0] cur_dpad_mid_ry;
reg        cur_in_dpad_down_y;
reg  [3:0] cur_dpad_down_ry;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        cur_line_id           <= 3'd7;
        cur_line_row          <= 4'd0;
        cur_in_text_y         <= 1'b0;
        cur_in_big_y          <= 1'b0;
        cur_big_row           <= 4'd0;
        cur_in_box_y          <= 1'b0;
        cur_in_border_y_outer <= 1'b0;
        cur_in_border_y_inner <= 1'b0;
        cur_in_inner_box_y    <= 1'b0;
        cur_in_pedestal_y     <= 1'b0;
        cur_pedestal_edge_y   <= 1'b0;
        cur_in_showcase_y     <= 1'b0;
        cur_showcase_ty       <= 4'd0;
        cur_map_y_base        <= 9'd0;
        cur_in_hud_bar_y      <= 1'b0;
        cur_in_hud_fill_y     <= 1'b0;
        cur_in_hud_border_y   <= 1'b0;
        cur_in_hud_edge_y     <= 1'b0;
        cur_in_hud_dot_y      <= 1'b0;
        cur_in_dpad_plate_y   <= 1'b0;
        cur_in_dpad_edge_y    <= 1'b0;
        cur_in_dpad_up_y      <= 1'b0;
        cur_dpad_up_ry        <= 4'd0;
        cur_in_dpad_mid_y     <= 1'b0;
        cur_dpad_mid_ry       <= 4'd0;
        cur_in_dpad_down_y    <= 1'b0;
        cur_dpad_down_ry      <= 4'd0;
    end else begin
        // UI 视窗 Y 轴范围预判定 (消除所有 25MHz 垂直比较器)
        cur_in_box_y          <= (py >= 9'd40 && py <= 9'd440);
        cur_in_border_y_outer <= (py == 9'd40 || py == 9'd41 || py == 9'd439 || py == 9'd440);
        cur_in_border_y_inner <= (py == 9'd44 || py == 9'd436);
        cur_in_inner_box_y    <= (py >= 9'd44 && py <= 9'd436);
        cur_in_pedestal_y     <= (py >= 9'd120 && py <= 9'd320);
        cur_pedestal_edge_y   <= (py == 9'd120 || py == 9'd320);
        cur_in_showcase_y     <= (py >= 9'd188 && py < 9'd252);
        cur_showcase_ty       <= (py - 9'd188) >> 2;
        cur_map_y_base        <= {1'b0, py[8:5], 4'b0} + {3'b0, py[8:5], 2'b0};
        cur_in_hud_bar_y      <= (py >= 9'd4 && py <= 9'd22);
        cur_in_hud_fill_y     <= (py >= 9'd8 && py <= 9'd18);
        cur_in_hud_border_y   <= (py >= 9'd7 && py <= 9'd19);
        cur_in_hud_edge_y     <= (py == 9'd7 || py == 9'd19);
        cur_in_hud_dot_y      <= (py >= 9'd9 && py <= 9'd17);

        // D-pad 方向控制器 Y 轴预译码 (消除高频比较器)
        cur_in_dpad_plate_y   <= (py >= 9'd402 && py <= 9'd470);
        cur_in_dpad_edge_y    <= (py == 9'd402 || py == 9'd470);
        cur_in_dpad_up_y      <= (py >= 9'd406 && py <= 9'd422);
        cur_dpad_up_ry        <= py[3:0] - 4'd6;
        cur_in_dpad_mid_y     <= (py >= 9'd428 && py <= 9'd444);
        cur_dpad_mid_ry       <= py[3:0] - 4'd12;
        cur_in_dpad_down_y    <= (py >= 9'd450 && py <= 9'd466);
        cur_dpad_down_ry      <= 5'd16 - (py[3:0] - 4'd2);

        // 大字 GAME OVER / VICTORY (y: 110..173，避开其他文本行)
        cur_in_big_y          <= (screen_f == ST_DEAD || screen_f == ST_WIN) && (py >= 9'd110 && py < 9'd174);
        cur_big_row           <= (py - 9'd110) >> 2;

        // 7 行文本行 Y 轴预译码 (DEAD/WIN 屏幕使用第 3 行与第 5 行，与大字完全不重叠)
        if      (py >= 9'd60  && py < 9'd92)  begin cur_line_id <= 3'd0; cur_line_row <= (py - 9'd60)  >> 1; cur_in_text_y <= 1'b1; end
        else if (py >= 9'd116 && py < 9'd148) begin cur_line_id <= 3'd1; cur_line_row <= (py - 9'd116) >> 1; cur_in_text_y <= 1'b1; end
        else if (py >= 9'd168 && py < 9'd200) begin cur_line_id <= 3'd2; cur_line_row <= (py - 9'd168) >> 1; cur_in_text_y <= 1'b1; end
        else if (py >= 9'd220 && py < 9'd252) begin cur_line_id <= 3'd3; cur_line_row <= (py - 9'd220) >> 1; cur_in_text_y <= 1'b1; end
        else if (py >= 9'd272 && py < 9'd304) begin cur_line_id <= 3'd4; cur_line_row <= (py - 9'd272) >> 1; cur_in_text_y <= 1'b1; end
        else if (py >= 9'd324 && py < 9'd356) begin cur_line_id <= 3'd5; cur_line_row <= (py - 9'd324) >> 1; cur_in_text_y <= 1'b1; end
        else if (py >= 9'd376 && py < 9'd408) begin cur_line_id <= 3'd6; cur_line_row <= (py - 9'd376) >> 1; cur_in_text_y <= 1'b1; end
        else                                  begin cur_line_id <= 3'd7; cur_line_row <= 4'd0;                cur_in_text_y <= 1'b0; end
    end
end

wire in_sprite_s0 = (px[9:5] == pos_x) && (py[8:5] == pos_y);
reg [3:0] sprite_id_w;
always @(*) begin
    case (dir)
    2'd0: sprite_id_w = walk_toggle ? 4'd1 : 4'd0;
    2'd1: sprite_id_w = walk_toggle ? 4'd4 : 4'd3;
    2'd2: sprite_id_w = walk_toggle ? 4'd7 : 4'd6;
    default: sprite_id_w = walk_toggle ? 4'd10 : 4'd9;
    endcase
end
wire [8:0] map_a_addr_w = cur_map_y_base + {4'b0, px[9:5]};

// 展台物品
wire in_showcase_tile = (screen_f == ST_ITEM1 || screen_f == ST_ITEM2) &&
                        cur_in_showcase_y && (px >= 10'd408 && px < 10'd472);
wire [7:0] showcase_tile_id = (screen_f == ST_ITEM1) ? T_EXT : T_TOWEL;
wire [3:0] showcase_tx_s0 = (px[6:0] - 7'd24) >> 2;
wire [3:0] showcase_ty_s0 = cur_showcase_ty;

// 文本行判定 (直接使用预译码寄存器，零减法器与函数开销)
wire [2:0] text_line_id_s0 = cur_line_id;
wire       in_text_line_s0  = cur_in_text_y && (px >= 10'd64 && px < 10'd576) && (screen_f != ST_IDLE && screen_f != ST_PLAY);
wire [3:0] text_row_s0      = cur_line_row;

wire [4:0] slot_s0          = px[8:4] - 5'd4; // 32 slots (0..31)
wire [8:0] slot_info_s0     = in_text_line_s0 ? get_slot_glyph(screen_f, text_line_id_s0, slot_s0, lose_fire) : 9'h000;
wire       glyph_valid_s0   = slot_info_s0[8];
wire       glyph_is_mini_s0 = slot_info_s0[7];
wire       glyph_is_right_s0= slot_info_s0[6];
wire [5:0] glyph_id_s0      = slot_info_s0[5:0];
// 精准字符点阵水平切片: mini 字符取 [0..7]，汉字左半取 [0..7]，汉字右半取 [8..15]，彻底消除奇数槽位颠倒模糊
wire [3:0] glyph_bit_x_s0   = glyph_is_mini_s0 ? {1'b0, px[3:1]} : {glyph_is_right_s0, px[3:1]};

// 文本颜色查找 (纯常量)
function [23:0] get_line_color;
    input [2:0] screen;
    input [2:0] lid;
    input       lf;
    begin
        case (screen)
        ST_INTRO: begin
            if (lid == 3'd0) get_line_color = 24'hFFD700;
            else if (lid == 3'd5) get_line_color = 24'hFFC94A;
            else if (lid == 3'd6) get_line_color = 24'h3CD070;
            else get_line_color = 24'hFFFFFF;
        end
        ST_ITEM1, ST_ITEM2: begin
            if (lid == 3'd0) get_line_color = 24'hFFD700;
            else if (lid == 3'd2) get_line_color = 24'hFFC94A;
            else if (lid == 3'd3) get_line_color = 24'h3CD070;
            else if (lid == 3'd4) get_line_color = 24'h4BA6FF;
            else get_line_color = 24'hFFFFFF;
        end
        ST_DEAD: begin
            if (lid == 3'd3) get_line_color = lf ? 24'hFF4B4B : 24'hE066FF;
            else if (lid == 3'd5) get_line_color = 24'hFFC94A;
            else get_line_color = 24'hFFFFFF;
        end
        ST_WIN: begin
            if (lid == 3'd3) get_line_color = 24'h2AE86B;
            else if (lid == 3'd5) get_line_color = 24'hFFD700;
            else get_line_color = 24'hFFFFFF;
        end
        default: get_line_color = 24'hFFFFFF;
        endcase
    end
endfunction

wire [23:0] cur_text_color     = get_line_color(screen_f, cur_line_id, lose_fire);
wire [23:0] border_outer_color = (screen_f == ST_WIN) ? 24'h2AE86B : ((screen_f == ST_ITEM2) ? 24'h3B82F6 : 24'hFF3B3B);
wire [23:0] border_inner_color = (screen_f == ST_WIN) ? 24'h4AF48C : ((screen_f == ST_ITEM2) ? 24'h60A5FA : 24'hFF6B6B);
wire [23:0] card_box_color     = (screen_f == ST_WIN) ? 24'h0A2614 : 24'h280606;
wire [23:0] cur_big_color      = (screen_f == ST_WIN) ? 24'hFFD700 : 24'hFFA500;

// 大字 GAME OVER (Screen 3) / VICTORY (Screen 4)
function [5:0] get_big_glyph;
    input is_win;
    input [4:0] slot;
    begin
        if (is_win) begin
            case (slot)
            5'd1: get_big_glyph = 6'd31; // V
            5'd2: get_big_glyph = 6'd18; // I
            5'd3: get_big_glyph = 6'd12; // C
            5'd4: get_big_glyph = 6'd29; // T
            5'd5: get_big_glyph = 6'd24; // O
            5'd6: get_big_glyph = 6'd27; // R
            5'd7: get_big_glyph = 6'd34; // Y
            default: get_big_glyph = 6'd42; // space
            endcase
        end else begin
            case (slot)
            5'd0: get_big_glyph = 6'd16; // G
            5'd1: get_big_glyph = 6'd10; // A
            5'd2: get_big_glyph = 6'd22; // M
            5'd3: get_big_glyph = 6'd14; // E
            5'd4: get_big_glyph = 6'd42; // space
            5'd5: get_big_glyph = 6'd24; // O
            5'd6: get_big_glyph = 6'd31; // V
            5'd7: get_big_glyph = 6'd14; // E
            5'd8: get_big_glyph = 6'd27; // R
            default: get_big_glyph = 6'd42; // space
            endcase
        end
    end
endfunction

wire in_big_title_s0 = cur_in_big_y && (px >= 10'd176 && px < 10'd464);
wire [9:0] big_px_rel  = px - 10'd176;
wire [4:0] big_slot_s0 = big_px_rel >> 5;
wire [3:0] big_row_s0  = cur_big_row;
wire [2:0] big_bit_s0  = (big_px_rel >> 2) & 3'd7;

wire [5:0] big_gid_s0 = get_big_glyph(screen_f == ST_WIN, big_slot_s0);
wire [5:0] sel_mini_gid_s0 = in_big_title_s0 ? big_gid_s0 : glyph_id_s0;
wire [3:0] sel_mini_row_s0 = in_big_title_s0 ? big_row_s0 : text_row_s0;
wire [7:0] shared_mini_row_s0 = (in_big_title_s0 || glyph_is_mini_s0) ? game_mini_row(sel_mini_gid_s0, sel_mini_row_s0) : 8'd0;
wire [7:0] mini_row_comb_s0 = shared_mini_row_s0;
wire [7:0] big_row_comb_s0  = shared_mini_row_s0;

// ROM 接口信号
reg  [11:0] a_tile_r;
reg  [10:0] a_spr_r;
reg  [8:0]  a_map_r;
reg  [9:0]  a_font_r;

wire [7:0]  tile_data_q;
wire [7:0]  spr_data_q;
wire [7:0]  map_data_q;
wire [15:0] font_data_q;

contest_game_rom u_rom (
    .I_clk          (I_clk),
    .I_tile_addr    (a_tile_r),
    .O_tile_data    (tile_data_q),
    .I_sprite_addr  (a_spr_r),
    .O_sprite_data  (spr_data_q),
    .I_map_a_addr   (a_map_r),
    .O_map_a_data   (map_data_q),
    .I_map_b_addr   (b_addr_r),
    .O_map_b_data   (b_data_r),
    .I_map_b_wen    (b_wen_r),
    .I_map_b_waddr  (b_waddr_r),
    .I_map_b_wdata  (b_wdata_r),
    .I_font_addr    (a_font_r),
    .O_font_data    (font_data_q)
);

// --- 流水线寄存器 ---
// Stage 1
reg [9:0]  x_s1, x_s2, x_s3;
reg [23:0] rgb_s1, rgb_s2, rgb_s3;
reg        de_s1, de_s2, de_s3;
reg        vs_s1, vs_s2, vs_s3;

reg        in_spr_s1, in_spr_s2, in_spr_s3;

reg        in_showcase_tile_s1, in_showcase_tile_s2, in_showcase_tile_s3;
reg [3:0]  sc_tx_s1;
reg        sc_tx0_s2, sc_tx0_s3;

reg        text_valid_s1, text_valid_s2;
reg        text_is_mini_s1, text_is_mini_s2;
reg [3:0]  text_bit_x_s1, text_bit_x_s2;
reg [7:0]  text_mini_row_s1, text_mini_row_s2;

reg        big_valid_s1, big_valid_s2;
reg [2:0]  big_bit_s1, big_bit_s2;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        a_map_r <= 9'd0; a_spr_r <= 11'd0; a_font_r <= 10'd0;
        x_s1 <= 10'd0; rgb_s1 <= 24'd0; de_s1 <= 1'b0; vs_s1 <= 1'b0;
        in_spr_s1 <= 1'b0;
        in_showcase_tile_s1 <= 1'b0; sc_tx_s1 <= 4'd0;
        text_valid_s1 <= 1'b0; text_is_mini_s1 <= 1'b0; text_bit_x_s1 <= 4'd0;
        text_mini_row_s1 <= 8'd0;
        big_valid_s1 <= 1'b0; big_bit_s1 <= 3'd0;
    end else begin
        a_map_r  <= map_a_addr_w;
        a_spr_r  <= {sprite_id_w, py[4:1], px[4:2]};
        a_font_r <= {glyph_id_s0, text_row_s0};

        x_s1 <= px; rgb_s1 <= I_rgb; de_s1 <= I_de; vs_s1 <= I_vs;
        in_spr_s1 <= in_sprite_s0;
        in_showcase_tile_s1 <= in_showcase_tile;
        sc_tx_s1 <= showcase_tx_s0;

        text_valid_s1 <= glyph_valid_s0; text_is_mini_s1 <= glyph_is_mini_s0;
        text_bit_x_s1 <= glyph_bit_x_s0; text_mini_row_s1 <= mini_row_comb_s0;
        
        big_valid_s1 <= in_big_title_s0; big_bit_s1 <= big_bit_s0;
    end
end

// --- Stage 1 -> Stage 2 ---
wire [7:0] eff_tile_s1 = (map_data_q == T_FIRE) ? (8'd5 + {7'b0, fire_anim}) : map_data_q;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        a_tile_r <= 12'd0;
        x_s2 <= 10'd0; rgb_s2 <= 24'd0; de_s2 <= 1'b0; vs_s2 <= 1'b0;
        in_spr_s2 <= 1'b0;
        in_showcase_tile_s2 <= 1'b0; sc_tx0_s2 <= 1'b0;
        text_valid_s2 <= 1'b0; text_is_mini_s2 <= 1'b0; text_bit_x_s2 <= 4'd0;
        text_mini_row_s2 <= 8'd0;
        big_valid_s2 <= 1'b0; big_bit_s2 <= 3'd0;
    end else begin
        a_tile_r <= in_showcase_tile_s1
                    ? {showcase_tile_id[4:0], cur_showcase_ty, sc_tx_s1[3:1]}
                    : {eff_tile_s1[4:0], py[4:1], x_s1[4:2]};

        x_s2 <= x_s1; rgb_s2 <= rgb_s1; de_s2 <= de_s1; vs_s2 <= vs_s1;
        in_spr_s2 <= in_spr_s1;
        in_showcase_tile_s2 <= in_showcase_tile_s1; sc_tx0_s2 <= sc_tx_s1[0];
        text_valid_s2 <= text_valid_s1; text_is_mini_s2 <= text_is_mini_s1;
        text_bit_x_s2 <= text_bit_x_s1; text_mini_row_s2 <= text_mini_row_s1;
        
        big_valid_s2 <= big_valid_s1; big_bit_s2 <= big_bit_s1;
    end
end

// --- Stage 2 -> Stage 3 (合成) ---
wire text_pixel_on_s2 = text_valid_s2 &&
                        (text_is_mini_s2 ? text_mini_row_s2[7 - text_bit_x_s2[2:0]] : font_data_q[15 - text_bit_x_s2]);
wire big_pixel_on_s2  = big_valid_s2 && text_mini_row_s2[7 - big_bit_s2];

reg text_pixel_on_s3, big_pixel_on_s3;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        x_s3 <= 10'd0; rgb_s3 <= 24'd0; de_s3 <= 1'b0; vs_s3 <= 1'b0;
        in_spr_s3 <= 1'b0;
        in_showcase_tile_s3 <= 1'b0; sc_tx0_s3 <= 1'b0;
        text_pixel_on_s3 <= 1'b0; big_pixel_on_s3 <= 1'b0;
    end else begin
        x_s3 <= x_s2; rgb_s3 <= rgb_s2; de_s3 <= de_s2; vs_s3 <= vs_s2;
        in_spr_s3 <= in_spr_s2;
        in_showcase_tile_s3 <= in_showcase_tile_s2; sc_tx0_s3 <= sc_tx0_s2;
        text_pixel_on_s3 <= text_pixel_on_s2; big_pixel_on_s3 <= big_pixel_on_s2;
    end
end

// Stage 3 像素提取
wire [3:0] tile_nib_s3 = in_showcase_tile_s3 ? (sc_tx0_s3 ? tile_data_q[7:4] : tile_data_q[3:0])
                                             : (x_s3[1] ? tile_data_q[7:4] : tile_data_q[3:0]);
wire [3:0] spr_nib_s3  = x_s3[1] ? spr_data_q[7:4] : spr_data_q[3:0];
wire       spr_on_s3   = in_spr_s3 && (spr_nib_s3 != 4'd0);

function arrow_pointing_min;
    input [3:0] a;
    input [3:0] b;
    begin
        case (a)
        4'd2: arrow_pointing_min = (b == 4'd8);
        4'd3: arrow_pointing_min = (b >= 4'd7 && b <= 4'd9);
        4'd4: arrow_pointing_min = (b >= 4'd6 && b <= 4'd10);
        4'd5: arrow_pointing_min = (b >= 4'd5 && b <= 4'd11);
        4'd6: arrow_pointing_min = (b >= 4'd4 && b <= 4'd12);
        4'd7, 4'd8, 4'd9, 4'd10, 4'd11, 4'd12, 4'd13:
              arrow_pointing_min = (b >= 4'd6 && b <= 4'd10);
        default: arrow_pointing_min = 1'b0;
        endcase
    end
endfunction

// (arrow_pointing_max merged into arrow_pointing_min mirror)

// --- HUD 左下角上下左右方向键 (带方向红色高亮, 纯4位LUT优化) ---
wire in_dpad_x_region  = (x_s3[9:7] == 3'b000);
wire in_dpad_col_mid   = in_dpad_x_region && (x_s3[6:0] >= 7'd34 && x_s3[6:0] <= 7'd50);
wire in_dpad_col_left  = in_dpad_x_region && (x_s3[6:0] >= 7'd14 && x_s3[6:0] <= 7'd30);
wire in_dpad_col_right = in_dpad_x_region && (x_s3[6:0] >= 7'd54 && x_s3[6:0] <= 7'd70);

wire [3:0] dpad_rx_mid   = x_s3[3:0] - 4'd2;
wire [3:0] dpad_rx_left  = x_s3[3:0] - 4'd14;
wire [3:0] dpad_rx_right = x_s3[3:0] - 4'd6;

wire in_up_box    = (screen_f == ST_PLAY) && cur_in_dpad_up_y   && in_dpad_col_mid;
wire in_down_box  = (screen_f == ST_PLAY) && cur_in_dpad_down_y && in_dpad_col_mid;
wire in_left_box  = (screen_f == ST_PLAY) && cur_in_dpad_mid_y  && in_dpad_col_left;
wire in_right_box = (screen_f == ST_PLAY) && cur_in_dpad_mid_y  && in_dpad_col_right;

wire is_up_arrow    = arrow_pointing_min(cur_dpad_up_ry,        dpad_rx_mid);
wire is_down_arrow  = arrow_pointing_min(cur_dpad_down_ry,      dpad_rx_mid);
wire is_left_arrow  = arrow_pointing_min(dpad_rx_left,          cur_dpad_mid_ry);
wire is_right_arrow = arrow_pointing_min(5'd16 - dpad_rx_right, cur_dpad_mid_ry);

wire in_dpad_plate  = (screen_f == ST_PLAY) && cur_in_dpad_plate_y && in_dpad_x_region && (x_s3[6:0] >= 7'd10 && x_s3[6:0] <= 7'd74);
wire in_dpad_border = in_dpad_plate && (x_s3[6:0] == 7'd10 || x_s3[6:0] == 7'd74 || cur_in_dpad_edge_y);

wire dir_up_active    = (dir == 2'd3);
wire dir_down_active  = (dir == 2'd0);
wire dir_left_active  = (dir == 2'd1);
wire dir_right_active = (dir == 2'd2);

wire in_dpad_arrow = (in_up_box    && is_up_arrow)   ||
                     (in_down_box  && is_down_arrow) ||
                     (in_left_box  && is_left_arrow) ||
                     (in_right_box && is_right_arrow);

wire in_dpad_active_arrow = (in_up_box    && is_up_arrow    && dir_up_active)   ||
                            (in_down_box  && is_down_arrow  && dir_down_active) ||
                            (in_left_box  && is_left_arrow  && dir_left_active) ||
                            (in_right_box && is_right_arrow && dir_right_active);

wire [23:0] dpad_arrow_col = in_dpad_active_arrow ? 24'hFF1E1E : 24'h8E96A8;

wire in_dpad_box_bg = (in_up_box || in_down_box || in_left_box || in_right_box);
wire in_dpad_active_box = (in_up_box && dir_up_active) || (in_down_box && dir_down_active) ||
                          (in_left_box && dir_left_active) || (in_right_box && dir_right_active);

wire [23:0] dpad_box_col = in_dpad_active_box ? 24'h4A0E0E : 24'h222636;

// --- HUD 几何边框与装饰组件判定 (极简无算术链) ---
wire is_ui_screen = (screen_f != ST_IDLE && screen_f != ST_PLAY);

wire in_box_outer_x = (x_s3 >= 10'd80 && x_s3 <= 10'd560);
wire in_box_inner_x = (x_s3 >= 10'd84 && x_s3 <= 10'd556);

wire in_card_box = is_ui_screen && cur_in_box_y && in_box_outer_x;

wire in_box_border_outer = is_ui_screen && (
    ((x_s3 == 10'd80 || x_s3 == 10'd81 || x_s3 == 10'd559 || x_s3 == 10'd560) && cur_in_box_y) ||
    (cur_in_border_y_outer && in_box_outer_x)
);

wire in_box_border_inner = is_ui_screen && (
    ((x_s3 == 10'd84 || x_s3 == 10'd556) && cur_in_inner_box_y) ||
    (cur_in_border_y_inner && in_box_inner_x)
);

wire in_pedestal_border = (screen_f == ST_ITEM1 || screen_f == ST_ITEM2) && cur_in_pedestal_y &&
    ((x_s3 == 10'd360 || x_s3 == 10'd520) || ((x_s3 >= 10'd360 && x_s3 <= 10'd520) && cur_pedestal_edge_y));

// 顶部 HUD (纯组合判断，省打拍寄存器)
wire in_play_hud_bar = (screen_f == ST_PLAY) && cur_in_hud_bar_y && (x_s3 >= 10'd8 && x_s3 <= 10'd632);
wire in_poison_fill  = (screen_f == ST_PLAY) && cur_in_hud_fill_y && (x_s3 >= 10'd60 && x_s3 < poison_fill_end);
wire in_poison_border = (screen_f == ST_PLAY) && cur_in_hud_border_y &&
                        ((x_s3 == 10'd59 || x_s3 == 10'd360) || ((x_s3 >= 10'd59 && x_s3 <= 10'd360) && cur_in_hud_edge_y));

wire [23:0] poison_color = (poison_acc < 13'd1600) ? 24'h3CD070 :
                           (poison_acc < 13'd3200) ? 24'hFFC94A :
                           (fire_anim ? 24'hFF3B3B : 24'h991111);

wire [9:0] ext_rel_x = x_s3 - 10'd390;
wire ext_dot1 = (ext_rel_x <= 10'd12);
wire ext_dot2 = (ext_rel_x >= 10'd20 && ext_rel_x <= 10'd32);
wire ext_dot3 = (ext_rel_x >= 10'd40 && ext_rel_x <= 10'd52);
wire in_ext_dot = (screen_f == ST_PLAY) && cur_in_hud_dot_y && (ext_dot1 || ext_dot2 || ext_dot3);
wire ext_dot_lit = ext_dot1 ? (ext_uses >= 2'd1) : (ext_dot2 ? (ext_uses >= 2'd2) : (ext_uses >= 2'd3));
wire [23:0] ext_dot_col = ext_dot_lit ? 24'hFF3B3B : 24'h3A3E4E;

wire in_towel_hud = (screen_f == ST_PLAY) && cur_in_hud_fill_y && (x_s3 >= 10'd470 && x_s3 <= 10'd530);
wire [23:0] towel_hud_col = has_towel ? 24'h4BA6FF : 24'h3A3E4E;

wire [3:0]  chosen_nib_s3 = (screen_f == ST_PLAY) ? (spr_on_s3 ? spr_nib_s3 : tile_nib_s3) : tile_nib_s3;
wire [23:0] chosen_pal_s3 = pal(chosen_nib_s3);

// --- 最终画面合成输出 ---
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        O_vs <= 1'b0; O_de <= 1'b0; O_rgb <= 24'd0;
    end else begin
        O_vs <= vs_s3;
        O_de <= de_s3;

        if (state == ST_IDLE) begin
            O_rgb <= rgb_s3;
        end else if (screen_f == ST_PLAY) begin
            if (in_poison_fill)
                O_rgb <= poison_color;
            else if (in_poison_border)
                O_rgb <= 24'hFFFFFF;
            else if (in_ext_dot)
                O_rgb <= ext_dot_col;
            else if (in_towel_hud)
                O_rgb <= towel_hud_col;
            else if (in_play_hud_bar)
                O_rgb <= 24'h141624;
            else if (in_dpad_arrow)
                O_rgb <= dpad_arrow_col;
            else if (in_dpad_box_bg)
                O_rgb <= dpad_box_col;
            else if (in_dpad_border)
                O_rgb <= 24'h4A5468;
            else if (in_dpad_plate)
                O_rgb <= 24'h121420;
            else
                O_rgb <= chosen_pal_s3;
        end else begin
            if (in_box_border_outer)
                O_rgb <= border_outer_color;
            else if (in_box_border_inner)
                O_rgb <= border_inner_color;
            else if (big_pixel_on_s3)
                O_rgb <= cur_big_color;
            else if (text_pixel_on_s3)
                O_rgb <= cur_text_color;
            else if (in_showcase_tile_s3 && tile_nib_s3 != 4'd0)
                O_rgb <= chosen_pal_s3;
            else if (in_pedestal_border)
                O_rgb <= 24'hFFD700;
            else if (in_card_box)
                O_rgb <= card_box_color;
            else
                O_rgb <= {1'b0, rgb_s3[23:17], 1'b0, rgb_s3[15:9], 1'b0, rgb_s3[7:1]};
        end
    end
end

endmodule

// ---------------------------------------------------------------- 精简按键长按与短按控制器 (带 1ms Tick)
module game_long_ctrl #(
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1000
)(
    input  wire I_clk,
    input  wire I_rst,
    input  wire I_tick,
    input  wire I_btn,
    output reg  O_short,
    output reg  O_long
);
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
                if (I_tick) begin
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
                    if (I_tick) begin
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

// ---------------------------------------------------------------- 精简按键短按控制器 (带 1ms Tick)
module game_key_ctrl #(
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire I_clk,
    input  wire I_rst,
    input  wire I_tick,
    input  wire I_btn,
    output reg  O_press
);
    reg [4:0] cnt;
    reg       btn_r1, btn_r2, btn_deb;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            cnt     <= 5'd0;
            btn_r1  <= 1'b1;
            btn_r2  <= 1'b1;
            btn_deb <= 1'b1;
            O_press <= 1'b0;
        end else begin
            btn_r1  <= I_btn;
            btn_r2  <= btn_r1;
            O_press <= 1'b0;

            if (btn_r2 != btn_deb) begin
                if (I_tick) begin
                    if (cnt >= DEBOUNCE_MS - 1) begin
                        btn_deb <= btn_r2;
                        cnt     <= 5'd0;
                        if (!btn_r2) O_press <= 1'b1;
                    end else begin
                        cnt <= cnt + 5'd1;
                    end
                end
            end else begin
                cnt <= 5'd0;
            end
        end
    end
endmodule

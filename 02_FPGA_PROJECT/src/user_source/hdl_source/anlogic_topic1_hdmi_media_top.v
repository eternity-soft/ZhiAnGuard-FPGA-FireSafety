// V08: V07 fire audio plus BMP24 aspect-fit image scaling into 640x480 HDMI.
`include "my_brightness.v"
module anlogic_topic1_hdmi_media_top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // KEY2 (B2): 手动下一张 / 长按边缘检测
    input                       key2,           // KEY3 (C1): 轮播周期配置（1s/2s/4s 循环）
    input                       key3,           // KEY4 (B1): 自动播放 开/关
    input [3:0]                 sw,             // 拨码：SW1=C8 SW2=C7 SW3=C6 SW4=C5（拨上=1）

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [15:0] FRAME_WIDTH   = 16'd640;
parameter [15:0] FRAME_HEIGHT  = 16'd480;
// Keep frame lengths and buffer addresses at the SDRAM controller address width.
// A 16-bit multiplication truncated 640*480 to 45056 and made write_finish
// arrive before the scaler had produced the complete 307200-pixel frame.
parameter [ADDR_BITS-1:0] FRAME_PIXELS = 21'd307200;
parameter [ADDR_BITS-1:0] BUF0_ADDR    = {ADDR_BITS{1'b0}};
parameter [ADDR_BITS-1:0] BUF1_ADDR    = 21'd307200;
parameter [ADDR_BITS-1:0] BUF2_ADDR    = 21'd614400;
parameter [ADDR_BITS-1:0] BUF3_ADDR    = 21'd921600;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data_pre_osd;
wire        vs_osd;
wire        de_osd;
wire [23:0] vout_data_status_osd;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire [6:0]  seg_data_period;         // 新增：轮播周期档位 7段码
wire [1:0]  auto_period_sel_w;       // 新增：轮播周期档位
wire        auto_play_active_w;
wire [1:0]  current_image_idx_w;
wire        manual_audio_toggle_w;
wire [1:0]  manual_audio_image_idx_w;
wire        key2_next_pulse_sd;
reg  [4:0]  osd_status_sync1;
reg  [4:0]  osd_status_sync2;
reg  [4:0]  osd_status_frame;
reg         osd_vs_d;
reg         display_valid_sync1;
reg         display_valid_sync2;

wire        video_read_req;
reg         video_read_req_mem;
reg  [1:0]  video_read_bank;
wire        video_read_req_ack;
wire        video_read_req_ack_mem;
wire        video_read_transaction_active;
wire        sd_card_write_req_ack_mem;
wire        manager_write_abort_req_w,write_abort_req_w;
wire        write_abort_ack_mem,write_abort_ack_w;
reg [1:0] video_ack_sync,sd_write_ack_sync,abort_ack_sync;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire        frame_load_read_pause_sd;
wire [2:0]  frame_load_guard_state;
reg  [1:0]  frame_load_pause_video_sync;

// ---- my_fade 淡入淡出集成 ----
wire [1:0]  disp_idx_disp_fade;
wire [23:0] vout_data_fade;
wire [7:0]  fade_level;
wire        fade_active;
wire        display_req_toggle;
wire        display_ack_toggle;
wire        active_read_valid;
wire [1:0]  active_read_buf;
reg         active_read_valid_sync1;
reg         active_read_valid_sync2;
reg  [1:0]  active_read_buf_sync1;
reg  [1:0]  active_read_buf_sync2;

// ---- 拨码音量/亮度（SW1/C8 SW2/C7 = 音量档，SW3/C6 SW4/C5 = 亮度档）----
wire [1:0]  vol_sel;
wire [1:0]  br_sel;
wire [23:0] vout_data_bright;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire signed [23:0] sfx_meter_sample,bgm_meter_sample;
wire [7:0] sfx_meter_level,bgm_meter_level;
wire [7:0] sfx_meter_peak,bgm_meter_peak;
wire audio_meter_visible;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
// -------------------------------------------------------------------------
// V27 上电复位脉冲（50MHz clk 下 20ms）
// -------------------------------------------------------------------------
reg [23:0] por_cnt = 24'd0;
reg        por_rst = 1'b1;
always @(posedge clk) begin
    if (por_cnt < 24'd1_000_000) begin
        por_cnt <= por_cnt + 24'd1;
        por_rst <= 1'b1;
    end else begin
        por_rst <= 1'b0;
    end
end

// -------------------------------------------------------------------------
// 板子 KEY1 (引脚 A2 / 外部标号 rst_n):
//   - 短按（< 1.0s，松手触发）：触发 10ms 软复位脉冲，使系统重新从第 1 张图开始加载
//   - 长按（>= 1.0s）：供 contest_game 模块识别并进出火场逃生小游戏
// -------------------------------------------------------------------------
reg        key1_s0, key1_s1, key1_stable;
reg [19:0] key1_db_cnt;
reg [27:0] key1_hold_cnt;
reg        key1_long_fired;
reg        soft_rst_pulse_v;
reg [18:0] soft_rst_timer;

always @(posedge video_clk or posedge por_rst) begin
    if (por_rst) begin
        key1_s0          <= 1'b1;
        key1_s1          <= 1'b1;
        key1_stable      <= 1'b1;
        key1_db_cnt      <= 20'd0;
        key1_hold_cnt    <= 28'd0;
        key1_long_fired  <= 1'b0;
        soft_rst_pulse_v <= 1'b0;
        soft_rst_timer   <= 19'd0;
    end else begin
        key1_s0 <= rst_n;
        key1_s1 <= key1_s0;

        // 20ms 消抖 (25MHz 下 500,000 拍)
        if (key1_s1 == key1_stable)
            key1_db_cnt <= 20'd0;
        else if (key1_db_cnt >= 20'd500_000) begin
            key1_stable <= key1_s1;
            key1_db_cnt <= 20'd0;
        end else
            key1_db_cnt <= key1_db_cnt + 20'd1;

        // 低电平有效（按下=0）
        if (!key1_stable) begin
            if (!key1_long_fired) begin
                if (key1_hold_cnt >= 28'd25_000_000) begin // 1.0s 长按
                    key1_long_fired <= 1'b1;
                end else begin
                    key1_hold_cnt <= key1_hold_cnt + 28'd1;
                end
            end
        end else begin
            // 松手时如果持续时间 < 1.0s 且非零，判定为短按回到第一张图
            if ((key1_hold_cnt >= 28'd1_250_000) && !key1_long_fired) begin
                soft_rst_timer <= 19'd250_000; // 10ms 快速复位脉冲
            end
            key1_hold_cnt   <= 28'd0;
            key1_long_fired <= 1'b0;
        end

        if (soft_rst_timer > 19'd0) begin
            soft_rst_timer   <= soft_rst_timer - 19'd1;
            soft_rst_pulse_v <= 1'b1;
        end else begin
            soft_rst_pulse_v <= 1'b0;
        end
    end
end

// 异常看门狗复位展宽（10ms硬件复位脉冲）与低资源帧节拍熔断自锁架构
reg [17:0] wd_rst_cnt;        // 10ms @ 25MHz = 250,000 (仅需18位)
reg [5:0]  wd_cooldown_f;     // 60帧 = 1.0秒冷却 (仅需6位)
reg [7:0]  wd_clear_f;        // 240帧 = 4.0秒观察窗 (仅需8位)
reg [1:0]  wd_retry_cnt;      // 连续自愈尝试次数 (2位)
reg [1:0]  prev_img_idx_wd;
reg        vs_wd_d;
wire       vs_frame_tick = (!vs && vs_wd_d);

wire       quiz_active;
wire       drill_active;
wire       game_active;
wire       watchdog_auto_reset_pulse; // 来自像素异常看门狗

// 熔断保护：若当前图片连续自愈重置 3 次依然无法消除，判定为图片自身高频特征，自动熔断挂起，避免死循环重启！
wire       watchdog_breaker_tripped = (wd_retry_cnt >= 2'd3);
wire       watchdog_trigger_safe = watchdog_auto_reset_pulse && !quiz_active && !drill_active && !game_active && !watchdog_breaker_tripped;

// 切换到新图片时，立即清零重试计数，恢复满血守护
wire       img_changed_wd = (osd_status_frame[1:0] != prev_img_idx_wd);

always @(posedge video_clk or posedge por_rst) begin
    if (por_rst) begin
        wd_rst_cnt      <= 18'd0;
        wd_cooldown_f   <= 6'd0;
        wd_clear_f      <= 8'd0;
        wd_retry_cnt    <= 2'd0;
        prev_img_idx_wd <= 2'd0;
        vs_wd_d         <= 1'b0;
    end else begin
        vs_wd_d         <= vs;
        prev_img_idx_wd <= osd_status_frame[1:0];

        // 帧节拍处理 (60Hz)
        if (vs_frame_tick) begin
            if (wd_cooldown_f > 6'd0)
                wd_cooldown_f <= wd_cooldown_f - 6'd1;

            if (wd_clear_f > 8'd0)
                wd_clear_f <= wd_clear_f - 8'd1;
            else
                wd_retry_cnt <= 2'd0;
        end

        // 切换到新图片时，立即清零重试计数，恢复满血守护
        if (img_changed_wd) begin
            wd_retry_cnt <= 2'd0;
            wd_clear_f   <= 8'd0;
        end

        if (watchdog_trigger_safe && (wd_cooldown_f == 6'd0)) begin
            wd_rst_cnt    <= 18'd250_000; // 10ms 硬件复位脉冲
            wd_cooldown_f <= 6'd60;       // 60帧 = 1.0秒冷却
            wd_retry_cnt  <= wd_retry_cnt + 2'd1;
            wd_clear_f    <= 8'd240;      // 240帧 = 4.0秒观察窗
        end else if (wd_rst_cnt > 18'd0) begin
            wd_rst_cnt <= wd_rst_cnt - 18'd1;
        end
    end
end
wire watchdog_rst = (wd_rst_cnt > 18'd0);

wire rst_all_raw = por_rst | ~audio_pll_lock | watchdog_rst | soft_rst_pulse_v;
wire rst_all;
EG_LOGIC_BUFG u_bufg_rst_all (
    .i (rst_all_raw),
    .o (rst_all)
);

// 同步至 video_clk 域的独立全局低偏斜复位树（通过 EG_LOGIC_BUFG 消除局部布线冲突）
reg rst_video_sync1, rst_video_sync2;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        rst_video_sync1 <= 1'b1;
        rst_video_sync2 <= 1'b1;
    end else begin
        rst_video_sync1 <= 1'b0;
        rst_video_sync2 <= rst_video_sync1;
    end
end

wire rst_video;
EG_LOGIC_BUFG u_bufg_rst_video (
    .i (rst_video_sync2),
    .o (rst_video)
);

// Lock the selected SDRAM cache bank at the beginning of each video read.
// The request is delayed one video clock so its synchronized bank index is
// stable before the memory-domain acknowledgement captures the address.
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        video_read_req_mem <= 1'b0;
        video_read_bank    <= 2'd0;
    end else begin
        // V17: keep the current cached picture alive while another independent
        // cache bank is loaded.  The SDRAM controller arbitrates read/write
        // bursts, so loading a new bank must not drain the HDMI read FIFO and
        // expose the blue fallback screen.
        video_read_req_mem <= video_read_req;
        if(video_read_req && !video_read_req_mem)
            video_read_bank <= disp_idx_disp_fade;
    end
end

// The memory reader publishes its accepted cache bank in ext_mem_clk.
// It remains stable for the complete read transaction, so a two-stage video
// clock synchronizer safely supplies the fade handoff interlock.
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        active_read_valid_sync1 <= 1'b0;
        active_read_valid_sync2 <= 1'b0;
        active_read_buf_sync1   <= 2'd0;
        active_read_buf_sync2   <= 2'd0;
    end else begin
        active_read_valid_sync1 <= active_read_valid;
        active_read_valid_sync2 <= active_read_valid_sync1;
        active_read_buf_sync1   <= active_read_buf;
        active_read_buf_sync2   <= active_read_buf_sync1;
    end
end

// 拨码：2级同步 + 20ms稳定消抖（video_clk=25MHz，20ms=500000拍）
// sw_sync 每变一次清零重计；连续稳定 20ms 才采纳为 sw_stable，毛刺进不了 vol/br
reg [3:0] sw_meta, sw_sync, sw_stable, sw_prev;
reg [19:0] sw_cnt;
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        sw_meta   <= 4'd0;
        sw_sync   <= 4'd0;
        sw_stable <= 4'd0;
        sw_prev   <= 4'd0;
        sw_cnt    <= 20'd0;
    end else begin
        sw_meta <= sw;
        sw_sync <= sw_meta;
        if(sw_sync != sw_prev) begin
            sw_prev <= sw_sync;
            sw_cnt  <= 20'd0;
        end else if(sw_cnt != 20'd500000) begin
            sw_cnt <= sw_cnt + 1'b1;
        end else begin
            sw_stable <= sw_sync;
        end
    end
end
assign vol_sel = sw_stable[1:0];   // SW1/SW2 音量档
assign br_sel  = sw_stable[3:2];   // SW3/SW4 亮度档

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// Level ACKs stay asserted until the source withdraws its request.
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) video_ack_sync<=0;
    else video_ack_sync<={video_ack_sync[0],video_read_req_ack_mem};
end
always @(posedge sd_card_clk or posedge rst_all) begin
    if(rst_all) begin sd_write_ack_sync<=0;abort_ack_sync<=0;end
    else begin
        sd_write_ack_sync<={sd_write_ack_sync[0],sd_card_write_req_ack_mem};
        abort_ack_sync<={abort_ack_sync[0],write_abort_ack_mem};
    end
end
assign video_read_req_ack=video_ack_sync[1];
assign sd_card_write_req_ack=sd_write_ack_sync[1];
assign write_abort_ack_w=abort_ack_sync[1];

// The scaler writes in video_clk. Synchronize the memory-side level ACK
// directly into that domain instead of routing it through sd_card_clk.
reg [1:0] scaler_write_ack_sync;
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) scaler_write_ack_sync<=2'b00;
    else scaler_write_ack_sync<={scaler_write_ack_sync[0],sd_card_write_req_ack_mem};
end
wire scaler_write_ack_v=scaler_write_ack_sync[1];

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描、缩放与双缓冲 =====================
wire [31:0] scaler_load_sector_sd;
wire scaler_load_start_sd,scaler_load_busy_sd;
wire [1:0] scaler_load_idx_sd;
wire scaler_catalog_ready_sd,scaler_sd_init_done_sd;
wire scaler_sd_read,scaler_bridge_sd_read;
wire [31:0] scaler_sd_read_addr,scaler_bridge_sd_read_addr;
wire [7:0] scaler_sd_data;
wire scaler_sd_data_valid,scaler_sd_end;
wire scaler_bridge_ready,scaler_bridge_busy,scaler_bridge_done,scaler_bridge_loaded;
wire scaler_bridge_format_error,scaler_bridge_abort_req;
wire [7:0] scaler_bridge_error;
wire [4:0] scaler_bridge_debug_state;
wire scaler_bridge_write_req,scaler_bridge_write_en;
wire [31:0] scaler_bridge_write_data;
wire scaler_io_reset,scaler_load_start_v,scaler_pixel_inc_sd;
wire scaler_done_sd,scaler_error_sd,scaler_start_ready_sd,scaler_start_overrun_sd;
wire scaler_finish_v;
wire [31:0] scaler_load_sector_v;

// Pause the HDMI SDRAM reader before arming a later scaled-frame write.  This
// removes the read/write overlap that can overflow the small asynchronous
// write FIFO and leave isolated stale pixels in buffers 1..3.
wire frame_prep_write_req;
wire scaler_prepared_start_sd;
wire [31:0] frame_prep_sector;
contest_frame_load_guard #(
    .PAUSE_GUARD_CYCLES(128),
    .QUIET_CYCLES(8)
) u_contest_frame_load_guard(
    .clk(sd_card_clk),
    .rst(scaler_io_reset),
    .load_start(scaler_load_start_sd),
    .load_sector(scaler_load_sector_sd),
    .load_busy(scaler_load_busy_sd),
    .read_active_async(video_read_transaction_active),
    .write_req_ack(sd_card_write_req_ack),
    .scaler_start_ready(scaler_start_ready_sd),
    .read_pause(frame_load_read_pause_sd),
    .write_req(frame_prep_write_req),
    .scaler_start(scaler_prepared_start_sd),
    .sector_latched(frame_prep_sector),
    .state_debug(frame_load_guard_state)
);

always @(posedge video_clk or posedge scaler_io_reset) begin
    if(scaler_io_reset)
        frame_load_pause_video_sync <= 2'b00;
    else
        frame_load_pause_video_sync <= {frame_load_pause_video_sync[0],
                                        frame_load_read_pause_sd};
end

// The external writer is already armed before the scaler starts.  Complete
// the scaler's local req/ack phase in video_clk without crossing that control
// level through the memory domain a second time.
reg scaler_virtual_write_ack;
always @(posedge video_clk or posedge scaler_io_reset) begin
    if(scaler_io_reset)
        scaler_virtual_write_ack<=1'b0;
    else
        scaler_virtual_write_ack<=scaler_bridge_write_req;
end

assign write_abort_req_w=manager_write_abort_req_w|scaler_bridge_abort_req;

// ===================== V27 三大消防互动模式跨时钟同步 =====================
wire [1:0] drill_bgm_mode;
wire interactive_active = quiz_active | drill_active | game_active;

(* ASYNC_REG = "TRUE" *) reg [1:0] interactive_sync_sd;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) interactive_sync_sd <= 2'b00;
    else interactive_sync_sd <= {interactive_sync_sd[0], interactive_active};
end
wire interactive_active_sd = interactive_sync_sd[1];

contest_scaler_cdc u_contest_scaler_cdc(
    .sd_clk(sd_card_clk),.video_clk(video_clk),.rst(rst_all),
    .io_reset_sd(scaler_io_reset),
    .load_start_sd(scaler_prepared_start_sd),.load_sector_sd(frame_prep_sector),
    .load_ready_sd(scaler_start_ready_sd),.load_overrun_sd(scaler_start_overrun_sd),
    .bridge_ready_v(scaler_bridge_ready),.load_start_v(scaler_load_start_v),
    .load_sector_v(scaler_load_sector_v),
    .pixel_en_v(scaler_bridge_write_en),.pixel_inc_sd(scaler_pixel_inc_sd),
    .bridge_done_v(scaler_bridge_done),.bridge_loaded_v(scaler_bridge_loaded),
    .source_done_sd(scaler_done_sd),.source_error_sd(scaler_error_sd),
    .finish_toggle_mem(frame_write_toggle_mem),.finish_pulse_v(scaler_finish_v)
);

contest_sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4),
    // V17: after the first image is committed, fill the remaining independent
    // cache banks in the background.  A later key press can then switch to an
    // already committed frame instead of waiting on SD/BMP/scaler work.
    .PREFETCH_ENABLE   (1),
    .EXTERNAL_SCALER   (1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (1'b1),
    .key_next_pulse    (interactive_active_sd ? 1'b0 : key2_next_pulse_sd),
    .key_auto          (interactive_active_sd ? 1'b1 : key2), // KEY3按键(引脚C1): 短按自动轮播 开/关
    .key_period        (interactive_active_sd ? 1'b1 : key3), // KEY4按键(引脚B1): 短按改周期 (1s/2s/4s)
    .quiz_hold         (interactive_active_sd),
    .auto_period_sel   (auto_period_sel_w),  // 新增：周期档位输出
    .state_code        (state_code),
    .bmp_width         (FRAME_WIDTH),
    .bmp_height        (FRAME_HEIGHT),
    .display_valid     (display_valid),
    .auto_play_active  (auto_play_active_w),
    .current_image_idx (current_image_idx_w),
    .manual_audio_toggle(manual_audio_toggle_w),
    .manual_audio_image_idx(manual_audio_image_idx_w),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_abort_req    (manager_write_abort_req_w),
    .write_abort_ack    (write_abort_ack_w),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .display_req_toggle(display_req_toggle),
    .display_ack_toggle_video(display_ack_toggle),
    .cache_valid_mask  (),

    .write_req         (),
    .write_req_ack     (1'b0),
    .write_en          (),
    .write_data        (),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso),
    .load_sector_out   (scaler_load_sector_sd),
    .load_start_pulse_out(scaler_load_start_sd),
    .load_busy_out     (scaler_load_busy_sd),
    .load_idx_out      (scaler_load_idx_sd),
    .catalog_ready_out (scaler_catalog_ready_sd),
    .sd_init_done_out  (scaler_sd_init_done_sd),
    .sd_sec_read_o     (scaler_sd_read),
    .sd_sec_read_addr_o(scaler_sd_read_addr),
    .sd_sec_read_i     (scaler_bridge_sd_read),
    .sd_sec_read_addr_i(scaler_bridge_sd_read_addr),
    .sd_bus_takeover   (scaler_load_busy_sd),
    .ext_pixel_inc     (scaler_pixel_inc_sd),
    .ext_source_done   (scaler_done_sd),
    .ext_source_error  (scaler_error_sd|scaler_start_overrun_sd),
    .bridge_reset_out  (scaler_io_reset),
    .sd_sec_read_data_o(scaler_sd_data),
    .sd_sec_read_data_valid_o(scaler_sd_data_valid),
    .sd_sec_read_end_o (scaler_sd_end)
);

contest_scaler_bridge #(
    // Accept both smaller and larger BMP files.  The scaler maps every legal
    // source to the 640x480 HDMI canvas while preserving aspect ratio.
    .MIN_SRC_WIDTH(1),
    .MIN_SRC_HEIGHT(1)
) u_contest_scaler_bridge(
    .video_clk(video_clk),.sd_clk(sd_card_clk),.rst(scaler_io_reset),
    .load_start(scaler_load_start_v),.bmp_start_sector(scaler_load_sector_v),
    .abort(1'b0),.ready(scaler_bridge_ready),.busy(scaler_bridge_busy),
    .done(scaler_bridge_done),.img_loaded(scaler_bridge_loaded),
    .format_error(scaler_bridge_format_error),.error_code(scaler_bridge_error),
    .write_abort_req(scaler_bridge_abort_req),
    .sd_sec_read(scaler_bridge_sd_read),.sd_sec_read_addr(scaler_bridge_sd_read_addr),
    .sd_sec_read_data(scaler_sd_data),.sd_sec_read_data_valid(scaler_sd_data_valid),
    .sd_sec_read_end(scaler_sd_end),
    .write_req(scaler_bridge_write_req),.write_req_ack(scaler_virtual_write_ack),
    .write_en(scaler_bridge_write_en),.write_data(scaler_bridge_write_data),
    .write_finish(scaler_finish_v),.o_x(),.o_y(),.o_border_flag(),.o_last(),
    .debug_state(scaler_bridge_debug_state)
);

assign sd_card_write_req=frame_prep_write_req;
assign sd_card_write_en=scaler_bridge_write_en;
assign sd_card_write_data=scaler_bridge_write_data;

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

// 新增：轮播周期档位译码（0=1秒 1=2秒 2=4秒）
seg_decoder seg_decoder_period_m0(
    .bin_data          ({2'b00, auto_period_sel_w}),
    .seg_data          (seg_data_period)
);

// V08 diagnostic display.  Preserve the normal rightmost manager/period
// digits, and use the four otherwise blank digits for the scaler bridge:
//   D0=latched error low nibble, D1=latched error high nibble,
//   D2=bridge state captured when error becomes visible, D3=live bridge state.
// Capture the state together with the non-zero error, before the manager's
// local recovery reset can clear the bridge.  The latches clear only on the
// board-wide reset/reprogramming.
reg [7:0] scaler_error_latched;
reg [4:0] scaler_failed_state_latched;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        scaler_error_latched       <= 8'h00;
        scaler_failed_state_latched<= 5'h00;
    end else if (scaler_bridge_error != 8'h00) begin
        scaler_error_latched <= scaler_bridge_error;
        // 0x24 且 SDRAM 尚未初始化时优先显示 5；否则显示桥接器
        // 细分状态 D/E/F。这样一次实板烧录即可区分存储就绪与握手问题。
        if ((scaler_bridge_error == 8'h24) && !Sdr_init_done)
            scaler_failed_state_latched <= 5'h05;
        else
            scaler_failed_state_latched <= scaler_bridge_debug_state;
    end
end

wire [6:0] seg_scaler_error_lo;
wire [6:0] seg_scaler_error_hi;
wire [6:0] seg_scaler_failed_state;
wire [6:0] seg_scaler_live_state;
seg_decoder seg_decoder_scaler_error_lo(
    .bin_data(scaler_error_latched[3:0]), .seg_data(seg_scaler_error_lo)
);
seg_decoder seg_decoder_scaler_error_hi(
    .bin_data(scaler_error_latched[7:4]), .seg_data(seg_scaler_error_hi)
);
seg_decoder seg_decoder_scaler_failed_state(
    .bin_data(scaler_failed_state_latched[3:0]), .seg_data(seg_scaler_failed_state)
);
seg_decoder seg_decoder_scaler_live_state(
    .bin_data(scaler_bridge_debug_state[3:0]), .seg_data(seg_scaler_live_state)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,seg_scaler_error_lo}),
    .seg_data_1        ({1'b1,seg_scaler_error_hi}),
    .seg_data_2        ({1'b1,seg_scaler_failed_state}),
    .seg_data_3        ({1'b1,seg_scaler_live_state}),
    .seg_data_4        ({1'b1,seg_data_0}),        // 倒数第2位：SD卡状态码
    .seg_data_5        ({1'b1,seg_data_period})    // 最右位：轮播周期档位
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// SD 控制状态跨到 video_clk 域：两级同步降低亚稳态风险，并在帧起始
// 一次性锁存整组状态，避免同一帧内文字/颜色发生撕裂。
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        osd_status_sync1  <= 5'b0;
        osd_status_sync2  <= 5'b0;
        osd_status_frame  <= 5'b0;
        osd_vs_d          <= 1'b0;
        display_valid_sync1 <= 1'b0;
        display_valid_sync2 <= 1'b0;
    end else begin
        osd_status_sync1  <= {auto_play_active_w, auto_period_sel_w,
                              current_image_idx_w};
        osd_status_sync2  <= osd_status_sync1;
        osd_vs_d          <= vs;
        display_valid_sync1 <= display_valid;
        display_valid_sync2 <= display_valid_sync1;

        if (vs && !osd_vs_d)
            osd_status_frame <= osd_status_sync2;
    end
end

// 首图提交前显示深蓝启动底色；第一张有效后始终保留当前图像。加载第2～4张
// 时不再主动切到蓝屏，目标缓存真正提交后才由淡入淡出模块切换。
assign vout_data_pre_osd = display_valid_sync2 ? vout_data_raw : 24'h003366;

// ===================== 按键2模式控制（短按切图 / 长按边缘检测） =====================
// 按键2（板子KEY2，引脚B2，对应key1）：
//   - 短按（松手时）：切到下一张图（无缝触发 sd_card_bmp 切图）
//   - 长按（按住>=0.6秒）：翻转 edge_enable（进入/退出边缘检测），松手时不误触切图
wire edge_enable_sd;

key2_mode_controller #(
    .CLK_FREQ_HZ   (100_000_000),
    .DEBOUNCE_MS   (20),
    .LONG_PRESS_MS (350)
) u_key2_ctrl (
    .clk            (sd_card_clk),
    .rst            (rst_all),
    .key_in         (key1),
    .key_next_pulse (key2_next_pulse_sd),
    .edge_enable    (edge_enable_sd)
);

// 将边缘检测使能信号跨时钟域安全同步至 video_clk (25MHz)
reg [1:0] edge_en_sync_v;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        edge_en_sync_v <= 2'b00;
    else
        edge_en_sync_v <= {edge_en_sync_v[0], edge_enable_sd};
end
wire edge_enable_video = edge_en_sync_v[1];

// ===================== 实时 Sobel 边缘检测模块 =====================
wire [23:0] vout_data_edge;
wire        vs_edge;
wire        de_edge;

contest_edge_detect #(
    .H_ACTIVE  (640),
    .V_ACTIVE  (480),
    .THRESHOLD (11'd75)
) u_edge_detect (
    .I_clk     (video_clk),
    .I_rst     (rst_video),
    .I_enable  (edge_enable_video),
    .I_vs      (vs),
    .I_de      (de),
    .I_rgb     (vout_data_pre_osd),
    .O_vs      (vs_edge),
    .O_de      (de_edge),
    .O_rgb     (vout_data_edge)
);

// ===================== 实时像素坏点异常看门狗监控 =====================
// 随时监测画面是否出现异常像素噪点/坏点；若出现立即输出 watchdog_auto_reset_pulse，
// 在顶层触发 20ms 系统级复位回到最初位置（第一张图），完美筈效于按下板子 KEY1 复位按键。
wire watchdog_anomaly_detected;

contest_pixel_anomaly_watchdog #(
    .H_ACTIVE        (640),
    .V_ACTIVE        (480),
    .X_MIN           (4),         // 全图监视（有效像素区 4 ~ 635）
    .X_MAX           (635),
    .Y_MIN           (4),         // 全图监视（有效行 4 ~ 475）
    .Y_MAX           (475),
    .DIFF_THRESHOLD  (60),        // 2D 十字空间冲激对比门限
    .BG_DIFF_MAX     (16),        // 背景平坦度门限
    .ANOMALY_THRESH  (500)         // 全图高灵敏门限（洁净图全图仅0~4点；出现雪花点>=10点立即自愈）
) u_pixel_watchdog (
    .I_clk              (video_clk),
    .I_rst              (rst_video),
    .I_vs               (vs),
    .I_de               (de),
    .I_rgb              (vout_data_pre_osd),
    .I_display_ready    (display_valid_sync2 && !fade_active),
    .O_anomaly_detected (watchdog_anomaly_detected),
    .O_auto_reset_pulse (watchdog_auto_reset_pulse)
);

contest_status_osd #(
    .H_ACTIVE (640),
    .V_ACTIVE (480)
) u_my_status_osd (
    .I_clk        (video_clk),
    .I_rst        (rst_video),
    .I_vs         (vs_edge),
    .I_de         (de_edge),
    .I_rgb        (vout_data_edge),
    .I_auto_play  (osd_status_frame[4]),
    .I_period_sel (osd_status_frame[3:2]),
    .I_image_idx  (osd_status_frame[1:0]),
    .I_vol_sel    (vol_sel),
    .I_bri_sel    (br_sel),
    .I_sfx_level  (sfx_meter_level),
    .I_bgm_level  (bgm_meter_level),
    .I_sfx_peak   (sfx_meter_peak),
    .I_bgm_peak   (bgm_meter_peak),
    .I_meter_visible(audio_meter_visible),
    .O_vs         (vs_osd),
    .O_de         (de_osd),
    .O_rgb        (vout_data_status_osd)
);

my_frame_read_write #(
    .WRITE_V_FLIP     (0),
    .FRAME_WIDTH      (FRAME_WIDTH),
    .FRAME_HEIGHT     (FRAME_HEIGHT)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .write_abort_req   (write_abort_req_w),
    .write_abort_ack   (write_abort_ack_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req_mem),
    .read_req_ack      (video_read_req_ack_mem),
    .read_finish       (),
    .active_read_buf   (active_read_buf),
    .active_read_valid (active_read_valid),
    .read_transaction_active(video_read_transaction_active),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (video_read_bank),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (video_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack_mem),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== V07 消防主题音频联动引擎 =====================
// 保持 V06 的事件接口、48kHz PCM 与 HDMI 音频链路不变；仅将音色替换为：
// 图片/周期/自动状态扫频警报 + 180~220Hz 低音持续警笛背景。
// 轮播周期档事件：auto_period_sel_w 变化时翻转 toggle（2 级同步跨时钟域防抖动）
reg [1:0] period_sel_sync1_w, period_sel_sync2_w, period_sel_prev_w;
reg       period_toggle_w;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        period_sel_sync1_w <= 2'd0;
        period_sel_sync2_w <= 2'd0;
        period_sel_prev_w  <= 2'd0;
        period_toggle_w    <= 1'b0;
    end else begin
        period_sel_sync1_w <= auto_period_sel_w;
        period_sel_sync2_w <= period_sel_sync1_w;
        if (period_sel_sync2_w != period_sel_prev_w) begin
            period_toggle_w  <= ~period_toggle_w;
            period_sel_prev_w <= period_sel_sync2_w;
        end
    end
end

wire quiz_audio_pulse;
reg  quiz_audio_toggle;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) quiz_audio_toggle <= 1'b0;
    else if (quiz_audio_pulse) quiz_audio_toggle <= ~quiz_audio_toggle;
end

contest_fire_audio_linkage_engine #(
    .CLK_HZ      (25000000),
    .SAMPLE_RATE (48000),
    .BGM_ENABLE  (1),
    .DRILL_SUPPORT(1)
) u_audio_linkage (
    .I_clk                 (video_clk),
    .I_rst                 (rst_video),
    .I_image_event_toggle  (manual_audio_toggle_w ^ quiz_audio_toggle),
    .I_image_event_idx     (manual_audio_image_idx_w),
    .I_period_event_toggle (period_toggle_w),
    .I_period_sel          (auto_period_sel_w),
    .I_auto_state          (auto_play_active_w),
    .I_vol                 (vol_sel),
    .I_bgm_mode            (drill_bgm_mode),
    .O_audio_valid         (audio_valid),
    .O_audio_left          (audio_left_data),
    .O_audio_right         (audio_right_data),
    .O_sfx_meter_sample    (sfx_meter_sample),
    .O_bgm_meter_sample    (bgm_meter_sample)
);

// Visualize the two source levels without changing the HDMI stereo mix.
contest_audio_meter u_audio_meter(
    .clk(video_clk),.rst(rst_video),.sample_valid(audio_valid),
    .sfx_sample(sfx_meter_sample),.bgm_sample(bgm_meter_sample),
    .image_toggle(manual_audio_toggle_w ^ quiz_audio_toggle),.period_toggle(period_toggle_w),
    .auto_state(auto_play_active_w),.volume(vol_sel),
    .sfx_level(sfx_meter_level),.bgm_level(bgm_meter_level),
    .sfx_peak(sfx_meter_peak),.bgm_peak(bgm_meter_peak),
    .visible(audio_meter_visible)
);

// ===================== 旧音频模块归档（不参与 V07 编译） =====================
// 归档目录：03_旧模块归档_my_audio；如需回退必须同时修改顶层例化和 .al 文件清单。
/*
my_audio #(
    .DEBOUNCE_MS    (20),
    .AUTO_INITIAL_ON(0),
    .USE_AUTO_STATE (1),
    .USE_SD_EVENT   (1),
    .BGM_ENABLE     (1),
    .BGM_IDLE_ONLY  (0),
    .BGM_NOTE_MS    (300),
    .BGM_GAIN_SHIFT (2)
) u_my_audio (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_key_next    (key1),
    .I_key_auto    (key2),
    .I_image_idx   (osd_status_sync2[1:0]),
    .I_auto_state  (auto_play_active_w),
    .I_next_event_toggle(manual_audio_toggle_w),
    .I_next_event_idx(manual_audio_image_idx_w),
    .I_vol           (vol_sel),
    .O_audio_valid (audio_valid),
    .O_audio_left  (audio_left_data),
    .O_audio_right (audio_right_data)
);
*/

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
// 切图淡入淡出：contest_status_osd 输出 -> [my_fade] -> vout_data_fade
my_fade #(
    .FADE_FRAMES(8'd11)
) u_my_fade(
    .clk          (video_clk),
    .rst          (rst_video),
    .de_in        (de_osd),
    .vs_in        (vs_osd),
    .rgb_in       (vout_data_status_osd),
    .disp_idx_new (disp_buf_idx),
    .display_req_toggle(display_req_toggle),
    .read_bank_valid(active_read_valid_sync2),
    .read_bank_active(active_read_buf_sync2),
    .display_ack_toggle(display_ack_toggle),
    .disp_idx_disp(disp_idx_disp_fade),
    .rgb_out      (vout_data_fade),
    .fade_level   (fade_level),
    .fade_active  (fade_active)
);

// ===================== 亮度调节（拨码 SW3/SW4 4 档） =====================
my_brightness u_my_brightness(
    .rgb_in  (vout_data_fade),
    .br_sel  (br_sel),
    .rgb_out (vout_data_bright)
);

// ===================== V27 知识问答互动子系统 (KEY4 长按进出) =====================
wire        vs_quiz;
wire        de_quiz;
wire [23:0] vout_data_quiz;

contest_quiz #(
    .H_ACTIVE    (640),
    .V_ACTIVE    (480),
    .CLK_HZ      (25000000),
    .DEBOUNCE_MS (20),
    .LONG_MS     (1000),
    .FB_MS       (3500),
    .SCORE_MS    (4000)
) u_contest_quiz (
    .I_clk               (video_clk),
    .I_rst               (rst_video),
    .I_vs                (vs_osd),
    .I_de                (de_osd),
    .I_rgb               (vout_data_bright),
    .I_enable            (!drill_active && !game_active),
    .I_key_next          (key1), // Board KEY2 (B2)
    .I_key_auto          (key2), // Board KEY3 (C1)
    .I_key_period        (key3), // Board KEY4 (B1)
    .O_key_period_short  (),
    .O_active            (quiz_active),
    .O_audio_pulse       (quiz_audio_pulse),
    .O_vs                (vs_quiz),
    .O_de                (de_quiz),
    .O_rgb               (vout_data_quiz)
);

// ===================== V27 消防演练展示子系统 (原短按自动轮播KEY3 长按进出) =====================
wire        vs_drill;
wire        de_drill;
wire [23:0] vout_data_drill;

contest_drill #(
    .H_ACTIVE    (640),
    .V_ACTIVE    (480),
    .CLK_HZ      (25000000),
    .DEBOUNCE_MS (20),
    .LONG_MS     (1000)
) u_contest_drill (
    .I_clk               (video_clk),
    .I_rst               (rst_video),
    .I_vs                (vs_quiz),
    .I_de                (de_quiz),
    .I_rgb               (vout_data_quiz),
    .I_enable            (!quiz_active && !game_active),
    .I_key3              (key2), // Board KEY3 (C1, 原短按自动轮播按键)
    .O_key3_short        (),
    .O_active            (drill_active),
    .O_bgm_mode          (drill_bgm_mode),
    .O_vs                (vs_drill),
    .O_de                (de_drill),
    .O_rgb               (vout_data_drill)
);

// ===================== V27 火场逃生游戏子系统 (KEY1 短按回到第一张长按进出) =====================
wire        vs_game;
wire        de_game;
wire [23:0] vout_data_game;

contest_game #(
    .H_ACTIVE    (640),
    .V_ACTIVE    (480),
    .CLK_HZ      (25000000),
    .DEBOUNCE_MS (20)
) u_contest_game (
    .I_clk               (video_clk),
    .I_rst               (rst_video),
    .I_vs                (vs_drill),
    .I_de                (de_drill),
    .I_rgb               (vout_data_drill),
    .I_enable            (!quiz_active && !drill_active),
    .I_key1              (key1),  // Board KEY2 (B2) - 前进
    .I_key2              (key2),  // Board KEY3 (C1) - 转向
    .I_key3              (key3),  // Board KEY4 (B1) - 使用灭火器
    .I_key_game          (rst_n), // Board KEY1 (A2) - 长按进出游戏
    .O_key3_short        (),
    .O_active            (game_active),
    .O_vs                (vs_game),
    .O_de                (de_game),
    .O_rgb               (vout_data_game)
);

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs_game),
    .I_de          (de_game),
    .I_rgb         (vout_data_game),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule

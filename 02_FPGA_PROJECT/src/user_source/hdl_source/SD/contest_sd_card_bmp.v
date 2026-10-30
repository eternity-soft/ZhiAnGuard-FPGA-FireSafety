`timescale 1ns/1ps
module contest_sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer LOAD_TIMEOUT_MS = 5000,
    parameter integer INIT_TIMEOUT_MS = 5000,
    parameter integer SCAN_TIMEOUT_MS = 60000,
    parameter integer LOAD_RETRY_LIMIT = 1,
    parameter integer RECOVERY_PAUSE_MS = 100,
    parameter integer PREFETCH_ENABLE = 1,
    parameter integer PREFETCH_GUARD_MS = 0, // 兼容旧参数；独立缓存不再复用显示缓冲
    parameter integer EXTERNAL_SCALER = 0
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_next_pulse,
    input                       key_auto,
    input                       key_period,          // 新增：轮播周期配置按键
    input                       quiz_hold,           // V25：问答模式占屏冻结图片轮播
    output [3:0]                state_code,
    output reg [1:0]            auto_period_sel,    // 新增：轮播周期档位 0=1s 1=2s 2=4s
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output wire                 auto_play_active,
    output wire [1:0]           current_image_idx,
    output reg                  manual_audio_toggle,
    output reg [1:0]            manual_audio_image_idx,

    input                       write_finish_toggle,
    // Internal recovery handshake only; no board pin changes.
    output reg                  write_abort_req,
    input                       write_abort_ack,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,
    // 发布的缓冲编号保持不变，直到 video 域完成整个转场并回传同一 toggle。
    output reg                  display_req_toggle,
    input                       display_ack_toggle_video,
    output [3:0]                cache_valid_mask,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO,

    output reg [31:0]           load_sector_out,
    output reg                  load_start_pulse_out,
    output reg                  load_busy_out,
    output reg [1:0]            load_idx_out,
    output reg                  catalog_ready_out,
    output reg                  sd_init_done_out,
    output                      sd_sec_read_o,
    output [31:0]               sd_sec_read_addr_o,
    input                       sd_sec_read_i,
    input [31:0]                sd_sec_read_addr_i,
    input                       sd_bus_takeover,
    input                       ext_pixel_inc,
    input                       ext_source_done,
    input                       ext_source_error,
    output                      bridge_reset_out,
    output [7:0]                sd_sec_read_data_o,
    output                      sd_sec_read_data_valid_o,
    output                      sd_sec_read_end_o
);

wire key_next_press;
wire key_auto_press;
wire key_period_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire             bmp_write_req;
wire [3:0]       bmp_state_code;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              next_req_pending; // 有尚未兑现的手动目标，不是单次排队位
reg [1:0]        requested_img_idx;
reg [1:0]        display_ack_sync;
reg [3:0]        cache_valid,cache_blocked;
reg              load_busy,load_is_prefetch,prefetch_busy;
reg load_plan_valid,load_plan_prefetch;
reg [1:0] load_plan_idx;
wire display_idle=(display_ack_sync[1]==display_req_toggle);
assign cache_valid_mask=cache_valid;
// 每张已扫描的图片固定对应同编号 SDRAM 缓冲，成功缓存后直到整机复位均不重写。
// 不再把淡入时间与下一张读图串行化，读卡可在任何转场阶段填充其他空缓冲。
always @(posedge clk or posedge rst) begin
    if(rst) display_ack_sync<=0;
    else display_ack_sync<={display_ack_sync[0],display_ack_toggle_video};
end
reg background_valid;
reg [1:0] background_idx;
integer cache_i;
always @* begin
    background_valid=0;background_idx=0;
    for(cache_i=3;cache_i>=0;cache_i=cache_i-1)
        if(cache_i<img_found_count && !cache_valid[cache_i] && !cache_blocked[cache_i]) begin
            background_valid=1;background_idx=cache_i;
        end
end

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
reg              source_started_seen;
reg              write_done_seen;
reg              catalog_ready;
reg              retry_pending;
reg [7:0]        retry_count;
reg [31:0]       pixels_sent;
// Millisecond counters avoid a continuously toggling 29-bit cycle counter.
// CLK_FREQ_HZ=100MHz -> 100000 clocks/ms -> 5000ms = 5 seconds.
localparam integer MS_DIV=(CLK_FREQ_HZ/1000<1)?1:CLK_FREQ_HZ/1000;
function integer timer_bits;
    input integer n;
    integer v;
    begin timer_bits=1;v=n-1;while(v>1)begin timer_bits=timer_bits+1;v=v>>1;end end
endfunction
reg [timer_bits(MS_DIV)-1:0] ms_div_count;
wire             ms_tick=(ms_div_count==MS_DIV-1);
reg [31:0]       load_timeout_cnt,init_timeout_cnt,scan_timeout_cnt;
reg [31:0]       recovery_ms;
reg [5:0]        reset_hold_count;
localparam R_RUN=0,R_RESET=1,R_MEM_ACK=2,R_MEM_RELEASE=3,R_INIT=4,R_PAUSE=5;
reg [2:0]        recovery_state;
wire             io_local_reset=rst || recovery_state==R_RESET || recovery_state==R_MEM_ACK;
wire             bmp_local_reset=io_local_reset || sd_bus_takeover ||
                                 (EXTERNAL_SCALER && load_busy);
assign bridge_reset_out=io_local_reset;
wire             timer_enable=load_busy || recovery_state!=R_RUN || !sd_init_done ||
                              (scan_kicked && !catalog_ready);
wire [31:0]      expected_pixels=bmp_width*bmp_height;
wire             source_complete=source_done_seen ||
                                 (!EXTERNAL_SCALER && source_started_seen && bmp_ready);
wire             pixel_increment=EXTERNAL_SCALER ? ext_pixel_inc : write_en;
wire [31:0]      pixels_after_inc=pixels_sent+(pixel_increment ? 32'd1 : 32'd0);
wire [31:0]      pixels_to_check=EXTERNAL_SCALER ? pixels_sent : pixels_after_inc;
wire             write_finish_pulse;
wire             memory_complete=write_done_seen || write_finish_pulse;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;

wire auto_tick;
wire [1:0] next_from_current;
wire key_next_valid=(key_next_press || key_next_pulse) && catalog_ready && img_found_count!=0 && !quiz_hold;
wire manual_request=next_req_pending || key_next_valid;
// 从上次手动目标继续计数；没有待处理手动目标时，从已发布图片继续计数。
wire [1:0] request_base=next_req_pending ? requested_img_idx : img_idx;
wire [1:0] manual_target=key_next_valid ? next_index_limited(request_base,img_found_count) : requested_img_idx;
wire prefetch_done=cache_valid[next_from_current];
wire [1:0] prefetched_img_idx=next_from_current;
wire [1:0] prefetched_buf_idx=next_from_current;


assign write_en = !EXTERNAL_SCALER && bmp_data_wr_en && load_busy && recovery_state==R_RUN;
assign write_req = !EXTERNAL_SCALER && bmp_write_req && load_busy && recovery_state==R_RUN;
assign state_code = (recovery_state!=R_RUN) ? 4'he :
                    ((EXTERNAL_SCALER && load_busy) ? 4'd4 : bmp_state_code);
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick  = (auto_cnt == auto_period_max(auto_period_sel));   // 周期按档位可配置
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign auto_play_active   = auto_play_en;
assign current_image_idx  = img_idx;

always @(posedge clk or posedge rst) begin
    if(rst) begin
        load_sector_out<=0;load_start_pulse_out<=0;load_busy_out<=0;load_idx_out<=0;
        catalog_ready_out<=0;sd_init_done_out<=0;
    end else begin
        load_sector_out<=load_sector;
        load_start_pulse_out<=load_start_pulse;
        load_busy_out<=load_busy;
        load_idx_out<=load_idx;
        catalog_ready_out<=catalog_ready;
        sd_init_done_out<=sd_init_done;
    end
end

wire sd_sec_read_mux=sd_bus_takeover ? sd_sec_read_i : sd_sec_read;
wire [31:0] sd_sec_read_addr_mux=sd_bus_takeover ? sd_sec_read_addr_i : sd_sec_read_addr;
assign sd_sec_read_o=sd_sec_read_mux;
assign sd_sec_read_addr_o=sd_sec_read_addr_mux;
assign sd_sec_read_data_o=sd_sec_read_data;
assign sd_sec_read_data_valid_o=sd_sec_read_data_valid;
assign sd_sec_read_end_o=sd_sec_read_end;

assign key_next_press = 1'b0; // key_next tied to 1'b1; manual pulses come via key_next_pulse

my_key_press_debounce #(
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .tick_ms    (ms_tick),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

my_key_press_debounce #(
    .DEBOUNCE_MS (20)
) u_key_period (
    .clk        (clk),
    .rst        (rst),
    .tick_ms    (ms_tick),
    .button_in  (key_period),
    .press_pulse(key_period_press)
);

function [31:0] auto_period_max;
    input [1:0] sel;
    begin
        // 档位0=1秒  档位1=2秒  档位2/3=4秒
        case (sel)
            2'd0:   auto_period_max = (CLK_FREQ_HZ << 0) - 32'd1;
            2'd1:   auto_period_max = (CLK_FREQ_HZ << 1) - 32'd1;
            default:auto_period_max = (CLK_FREQ_HZ << 2) - 32'd1;
        endcase
    end
endfunction

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

// Local I/O reset leaves cached file sectors, committed buffer and audio intact.
// This task is called only by this clocked controller.
task begin_recovery;
    begin
        recovery_state<=R_RESET;write_abort_req<=1'b1;
        reset_hold_count<=0;recovery_ms<=0;
        load_busy<=0;source_done_seen<=0;source_started_seen<=0;write_done_seen<=0;
        prefetch_busy<=0;load_plan_valid<=0;
        load_timeout_cnt<=0;init_timeout_cnt<=0;scan_timeout_cnt<=0;
        scan_start_pulse<=0;load_start_pulse<=0;pixels_sent<=0;auto_cnt<=0;
        if(!catalog_ready) begin
            scan_kicked<=0;img_found_count<=0;
            img_sector0<=0;img_sector1<=0;img_sector2<=0;img_sector3<=0;
        end
    end
endtask
// 先寄存选择结果，下一拍再驱动扇区号、缓冲和源启动，缩短100MHz控制路径。
task start_load;
    input [1:0] target;
    input [1:0] buffer_idx; // 固定图片编号=缓冲编号；保留调用形状便于审阅
    input is_prefetch;
    begin
        load_plan_valid<=1;load_plan_idx<=target;load_plan_prefetch<=is_prefetch;
    end
endtask
task launch_planned_load;
    begin
        load_plan_valid<=0;
        load_idx<=load_plan_idx;load_sector<=sector_lut(load_plan_idx);
        pending_buf_idx<=load_plan_idx;write_buf_idx<=load_plan_idx;
        load_start_pulse<=1;load_busy<=1;
        load_is_prefetch<=load_plan_prefetch;prefetch_busy<=load_plan_prefetch;
        source_done_seen<=0;source_started_seen<=0;write_done_seen<=0;
        pixels_sent<=0;load_timeout_cnt<=0;
        if(!load_plan_prefetch) auto_cnt<=0;
    end
endtask

// 数据已完整提交且当前转场确认完成，才发布下一个显示请求。
task commit_image;
    input [1:0] target;
    begin
        disp_buf_idx<=target;img_idx<=target;
        display_req_toggle<=~display_req_toggle;
        display_valid<=1;first_image_committed<=1;auto_cnt<=0;
    end
endtask
task emit_manual_event;
    input [1:0] target;
    begin
        manual_audio_image_idx<=target;
        manual_audio_toggle<=~manual_audio_toggle;
        // manual_target 已包含本周期新按键，兑现的是最新目标。
        next_req_pending<=0;
    end
endtask
task fail_load;
    begin
        if(retry_count<LOAD_RETRY_LIMIT) begin
            retry_pending<=1;retry_count<=retry_count+1'b1;
        end else begin
            retry_pending<=0;retry_count<=0;
            // Don't endlessly reload a failed speculative image while idle.
            // A fresh manual/auto transaction is still allowed to try it.
            cache_blocked[load_idx]<=1;auto_cnt<=0;
            // 有限重试耗尽后等待下一次操作，不能由未清目标触发无限重试。
            if(manual_request && manual_target==load_idx) next_req_pending<=0;
        end
        begin_recovery;
    end
endtask

always @(posedge clk or posedge rst) begin
    if(rst) ms_div_count<=0;
    else if(ms_tick) ms_div_count<=0;
    else ms_div_count<=ms_div_count+1'b1;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        manual_audio_toggle<=0;manual_audio_image_idx<=0;
        wrfin_tgl_sync<=0;scan_start_pulse<=0;load_start_pulse<=0;load_sector<=0;
        scan_kicked<=0;catalog_ready<=0;first_image_committed<=0;
        auto_play_en<=0;auto_cnt<=0;auto_period_sel<=0;img_found_count<=0;
        img_idx<=0;load_idx<=0;pending_buf_idx<=0;write_buf_idx<=0;disp_buf_idx<=0;
        img_sector0<=0;img_sector1<=0;img_sector2<=0;img_sector3<=0;
        next_req_pending<=0;requested_img_idx<=0;display_req_toggle<=0;load_busy<=0;source_done_seen<=0;
        load_is_prefetch<=0;prefetch_busy<=0;
        cache_valid<=0;cache_blocked<=0;load_plan_valid<=0;load_plan_idx<=0;load_plan_prefetch<=0;
        source_started_seen<=0;write_done_seen<=0;display_valid<=0;
        write_abort_req<=0;recovery_state<=R_RUN;reset_hold_count<=0;
        load_timeout_cnt<=0;init_timeout_cnt<=0;scan_timeout_cnt<=0;
        recovery_ms<=0;retry_pending<=0;retry_count<=0;pixels_sent<=0;
    end else begin
        wrfin_tgl_sync<={wrfin_tgl_sync[1:0],write_finish_toggle};
        scan_start_pulse<=0;load_start_pulse<=0;

        // Keys remain usable while loading/recovering. Only loading is deferred.
        if(key_next_valid) begin
            next_req_pending<=1;requested_img_idx<=manual_target;
            cache_blocked[manual_target]<=0;auto_cnt<=0;
        end
        if(key_auto_press && catalog_ready && img_found_count>1) begin
            auto_play_en<=~auto_play_en;auto_cnt<=0;
        end
        if(key_period_press && catalog_ready) begin
            auto_period_sel<=(auto_period_sel==2)?2'd0:auto_period_sel+1'b1;
            auto_cnt<=0;
        end

        case(recovery_state)
            R_RESET: begin
                auto_cnt<=0;
                if(reset_hold_count==31) recovery_state<=R_MEM_ACK;
                else reset_hold_count<=reset_hold_count+1'b1;
            end
            R_MEM_ACK: begin
                auto_cnt<=0;
                // ACK means current burst drained and write engine/FIFO cleared.
                // Never bypass this ACK: a failed memory domain cannot be reused safely.
                if(write_abort_ack) begin
                    write_abort_req<=0;recovery_state<=R_MEM_RELEASE;
                end
            end
            R_MEM_RELEASE: begin
                if(!write_abort_ack) begin
                    recovery_state<=R_INIT;init_timeout_cnt<=0;
                end
            end
            R_INIT: begin
                if(sd_init_done && bmp_ready) begin
                    recovery_state<=R_PAUSE;recovery_ms<=0;init_timeout_cnt<=0;
                end else if(ms_tick) begin
                    if(init_timeout_cnt>=INIT_TIMEOUT_MS-1) begin_recovery;
                    else init_timeout_cnt<=init_timeout_cnt+1'b1;
                end
            end
            R_PAUSE: begin
                if(ms_tick) begin
                    if(recovery_ms>=RECOVERY_PAUSE_MS-1) begin
                        recovery_state<=R_RUN;recovery_ms<=0;
                    end else recovery_ms<=recovery_ms+1'b1;
                end
            end
            R_RUN: begin
                if(!sd_init_done) begin
                    auto_cnt<=0;
                    if(load_busy || catalog_ready) begin_recovery;
                    else if(ms_tick) begin
                        if(init_timeout_cnt>=INIT_TIMEOUT_MS-1) begin_recovery;
                        else init_timeout_cnt<=init_timeout_cnt+1'b1;
                    end
                end else begin
                    init_timeout_cnt<=0;
                    if(!catalog_ready) begin
                        if(!scan_kicked && bmp_ready) begin
                            scan_start_pulse<=1;scan_kicked<=1;scan_timeout_cnt<=0;
                            img_found_count<=0;
                        end
                        if(scan_found_valid && scan_kicked) begin
                            case(img_found_count)
                                0:img_sector0<=scan_found_sector;
                                1:img_sector1<=scan_found_sector;
                                2:img_sector2<=scan_found_sector;
                                3:img_sector3<=scan_found_sector;
                                default:;
                            endcase
                            if(img_found_count<4) img_found_count<=img_found_count+1'b1;
                        end
                        if(scan_kicked && scan_done) begin
                            catalog_ready<=1;scan_timeout_cnt<=0;
                        end else if(scan_kicked && ms_tick) begin
                            if(scan_timeout_cnt>=SCAN_TIMEOUT_MS-1) begin_recovery;
                            else scan_timeout_cnt<=scan_timeout_cnt+1'b1;
                        end
                    end else begin
                        // 显示发布和后台加载相互独立。热缓存命中不等待正在读的另一张图。
                        if(auto_play_en && display_valid && img_found_count>1 && !manual_request && !quiz_hold &&
                           !auto_tick && !key_auto_press && !key_period_press) auto_cnt<=auto_cnt+1'b1;
                        else if(!auto_play_en || manual_request || quiz_hold) auto_cnt<=0;

                        if(display_idle) begin
                            if(!first_image_committed && cache_valid[0]) commit_image(2'd0);
                            else if(display_valid && manual_request && !quiz_hold) begin
                                if(manual_target==img_idx) next_req_pending<=0;
                                else if(cache_valid[manual_target]) begin
                                    commit_image(manual_target);emit_manual_event(manual_target);
                                end
                            end else if(display_valid && auto_play_en && auto_tick && img_found_count>1 && !quiz_hold &&
                                        !key_auto_press && !key_period_press && cache_valid[next_from_current])
                                commit_image(next_from_current);
                        end

                        if(load_busy) begin
                            if(EXTERNAL_SCALER) begin
                                if(ext_source_done) source_done_seen<=1;
                            end else begin
                                if(!bmp_ready) source_started_seen<=1;
                                if(source_started_seen && bmp_ready) source_done_seen<=1;
                            end
                            if(write_finish_pulse) write_done_seen<=1;
                            if(pixel_increment) pixels_sent<=pixels_after_inc;
                            if(EXTERNAL_SCALER && ext_source_error) fail_load;
                            else if(source_complete && memory_complete && pixels_to_check==expected_pixels) begin
                                cache_valid[load_idx]<=1;cache_blocked[load_idx]<=0;
                                load_busy<=0;prefetch_busy<=0;source_done_seen<=0;
                                source_started_seen<=0;write_done_seen<=0;load_timeout_cnt<=0;retry_count<=0;
                            end else if((source_complete && pixels_to_check!=expected_pixels) ||
                                        (ms_tick && load_timeout_cnt>=LOAD_TIMEOUT_MS-1)) fail_load;
                            else if(ms_tick) load_timeout_cnt<=load_timeout_cnt+1'b1;
                        end else if(bmp_ready && img_found_count!=0) begin
                            load_timeout_cnt<=0;
                            if(load_plan_valid) launch_planned_load;
                            else if(retry_pending) begin
                                // 新手动目标优先于旧失败请求，但只写尚未有效的独立槽。
                                if(manual_request && !cache_valid[manual_target] && manual_target!=load_idx) begin
                                    start_load(manual_target,manual_target,1'b0);retry_count<=0;
                                end else if(!cache_valid[load_idx]) start_load(load_idx,load_idx,load_is_prefetch);
                                retry_pending<=0;
                            end else if(!first_image_committed && !cache_valid[0] && !cache_blocked[0]) begin
                                start_load(2'd0,2'd0,1'b0);retry_count<=0;
                            end else if(manual_request && !cache_valid[manual_target] && !cache_blocked[manual_target]) begin
                                start_load(manual_target,manual_target,1'b0);retry_count<=0;
                            end else if(auto_play_en && auto_tick && !manual_request &&
                                        !cache_valid[next_from_current] && !cache_blocked[next_from_current]) begin
                                start_load(next_from_current,next_from_current,1'b0);retry_count<=0;
                            end else if(PREFETCH_ENABLE && background_valid) begin
                                start_load(background_idx,background_idx,1'b1);retry_count<=0;
                            end
                        end
                    end
                end
            end
            default: begin_recovery;
        endcase
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (bmp_local_reset),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (EXTERNAL_SCALER ? 1'b0 : load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (bmp_state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (bmp_write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (io_local_reset),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read_mux),
    .sd_sec_read_addr       (sd_sec_read_addr_mux),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module my_key_press_debounce #(
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire tick_ms,
    input  wire button_in,
    output reg  press_pulse
);

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [4:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 5'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 5'd0;
        end else if (tick_ms) begin
            if (cnt >= DEBOUNCE_MS - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 5'd0;
            end else begin
                cnt <= cnt + 5'd1;
            end
        end
    end
end

endmodule

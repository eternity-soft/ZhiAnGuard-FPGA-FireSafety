`timescale 1ns/1ps
//=============================================================================
// contest_fire_audio_linkage_engine.v
//-----------------------------------------------------------------------------
// FIRE 音频主题：消防警报（扫频警笛）联动引擎，Verilog-2001。
//
// 端口/参数与参考模块 contest_audio_linkage_engine 完全一致（模块名除外），
// 仅把「固定频率提示音 + C-E-G-C 琶音背景」替换为「三角波扫频警笛 + 低音
// 持续警笛背景」：
//   - 图片 IMG1/2/3/4  触发不同频率范围的警报 sweep（500~800 / 600~1000 /
//                       700~1200 / 800~1400 Hz，单程 200 ms）
//   - 周期 1s/2s/4s    触发不同频率范围的警报（450~700 / 650~1000 /
//                       850~1300 Hz，单程 150 ms）
//   - 自动 ON/OFF      触发宽范围长扫警报（400~1200 / 300~500 Hz，单程 250 ms）
//   - 背景 BGM         低音持续警笛 180~220 Hz 缓慢扫频（单程 1 s）
//
// 保留参考模块的框架：分数分频 48 kHz、CDC toggle+payload 协议、
// AUTO>PERIOD>IMAGE 事件仲裁、软抢占、ADSR 包络、平滑 ducking、
// 混音、总音量、饱和限幅、256 点正弦 LUT、输出流水线。
//
// 扫频实现：瞬时相位增量 = inc_low + sweep_cnt，sweep_cnt 以固定步进
// sweep_step 在 [0, delta] 间三角波往返（delta = inc_high - inc_low），
// 无乘除法，纯加法即可综合。
//=============================================================================
module contest_fire_audio_linkage_engine #(
    parameter integer CLK_HZ      = 25000000,
    parameter integer SAMPLE_RATE = 48000,
    parameter integer BGM_ENABLE  = 1,
    parameter integer DRILL_SUPPORT = 0
)(
    input  wire               I_clk,
    input  wire               I_rst,
    input  wire               I_image_event_toggle,
    input  wire [1:0]         I_image_event_idx,
    input  wire               I_period_event_toggle,
    input  wire [1:0]         I_period_sel,
    input  wire               I_auto_state,
    input  wire [1:0]         I_vol,
    input  wire [1:0]         I_bgm_mode, // 0=normal, 1=drill siren, 2=drill mute
    output reg                O_audio_valid,
    output reg signed [23:0] O_audio_left,
    output reg signed [23:0] O_audio_right,
    output reg signed [23:0] O_sfx_meter_sample,
    output reg signed [23:0] O_bgm_meter_sample
);

    wire [1:0] drill_mode=(DRILL_SUPPORT!=0) ? I_bgm_mode : 2'd0;
    wire drill_active=(drill_mode!=2'd0);
    wire drill_siren=(drill_mode==2'd1);

    // ===================== 音效配置区 BEGIN =====================
    // 频率单位 mHz：500000 表示 500.000 Hz。增益为 Q15：0=静音，8192=25%，
    // 16384=50%，32768=100%。SAMPLE_RATE 保持 48000；需 CLK_HZ > SAMPLE_RATE*8。
    function [31:0] cfg_phase;
        input integer frequency_mhz;
        reg [63:0] numerator, denominator;
        begin
            denominator = SAMPLE_RATE * 64'd1000;
            numerator = frequency_mhz * 64'd4294967296;
            cfg_phase = (numerator + denominator/2) / denominator;
        end
    endfunction
    function [31:0] cfg_samples;
        input integer milliseconds;
        begin
            cfg_samples = (SAMPLE_RATE * 64'd1 * milliseconds + 500)/1000;
        end
    endfunction
    // sweep 单程 = 提示音总时长的一半；sweep_step = delta / (total_n/2)，四舍五入。
    function [31:0] sweep_step_calc;
        input [31:0] lo;
        input [31:0] hi;
        input integer total_n;
        reg [63:0] delta;
        begin
            delta = hi - lo;
            sweep_step_calc = (delta + (total_n/4)) / (total_n/2);
        end
    endfunction

    // ---- 图片警报音调范围（f_low / f_high, mHz）----
    localparam [31:0] IMG0_LO = cfg_phase(500000);
    localparam [31:0] IMG0_HI = cfg_phase(800000);
    localparam [31:0] IMG1_LO = cfg_phase(600000);
    localparam [31:0] IMG1_HI = cfg_phase(1000000);
    localparam [31:0] IMG2_LO = cfg_phase(700000);
    localparam [31:0] IMG2_HI = cfg_phase(1200000);
    localparam [31:0] IMG3_LO = cfg_phase(800000);
    localparam [31:0] IMG3_HI = cfg_phase(1400000);

    // ---- 周期警报音调范围 ----
    localparam [31:0] PER0_LO = cfg_phase(450000);
    localparam [31:0] PER0_HI = cfg_phase(700000);
    localparam [31:0] PER1_LO = cfg_phase(650000);
    localparam [31:0] PER1_HI = cfg_phase(1000000);
    localparam [31:0] PER2_LO = cfg_phase(850000);
    localparam [31:0] PER2_HI = cfg_phase(1300000);

    // ---- 自动播放警报音调范围 ----
    localparam [31:0] AUTO_ON_LO  = cfg_phase(400000);
    localparam [31:0] AUTO_ON_HI  = cfg_phase(1200000);
    localparam [31:0] AUTO_OFF_LO = cfg_phase(300000);
    localparam [31:0] AUTO_OFF_HI = cfg_phase(500000);

    // ---- 背景低音持续警笛 180~220 Hz，单程 1 s ----
    localparam [31:0] BGM_LO = cfg_phase(180000);
    localparam [31:0] BGM_HI = cfg_phase(220000);
    localparam integer BGM_SWEEP_MS = 1000;
    localparam [31:0] DRILL_LO = cfg_phase(500000);
    localparam [31:0] DRILL_HI = cfg_phase(900000);
    localparam integer DRILL_SWEEP_MS = 100;

    // ---- 提示音总时长（含起音和尾部释放），须大于起音+释放时长 ----
    localparam integer CFG_IMAGE_MS    = 400;
    localparam integer CFG_PERIOD_MS   = 300;
    localparam integer CFG_AUTO_ON_MS  = 500;
    localparam integer CFG_AUTO_OFF_MS = 500;
    localparam integer CFG_SFX_ATTACK_MS  = 1;
    localparam integer CFG_SFX_RELEASE_MS = 4; // 自然结束/被抢占均软释放
    localparam integer CFG_SFX_DECAY_SHIFT = 12; // 大=衰减慢；0=保持音量

    // ---- 各路峰值增益（Q15）----
    localparam [15:0] CFG_IMAGE_GAIN_Q15  = 16'd16384; // 50%
    localparam [15:0] CFG_PERIOD_GAIN_Q15 = 16'd16384; // 50%
    localparam [15:0] CFG_AUTO_GAIN_Q15   = 16'd16384; // 50%
    // Background melody raised from 25% to 50%.  SFX remains at 50%; during
    // prompts the existing ducking ramp still reduces BGM to 25% of this level.
    localparam [15:0] CFG_BGM_GAIN_Q15    = 16'd16384; // 50%
    localparam [15:0] CFG_DUCK_RATIO_Q15  = 16'd8192;  // 提示期间背景剩 25%
    localparam integer CFG_DUCK_DOWN_MS = 8;
    localparam integer CFG_DUCK_UP_MS   = 8;

    // 背景波形每 CFG_BGM_UPDATE_DIV 个 PCM 采样更新一次（12 kHz）。
    // 背景音调应低于 SAMPLE_RATE/(2*CFG_BGM_UPDATE_DIV)。
    localparam integer CFG_BGM_UPDATE_DIV = 4;
    // ===================== 音效配置区 END =======================

    function integer bits_for;
        input integer n;
        integer v;
        begin
            bits_for=1; v=n-1;
            while(v>1) begin bits_for=bits_for+1; v=v>>1; end
        end
    endfunction
    function integer max2;
        input integer a,b;
        begin max2=(a>b)?a:b; end
    endfunction

    localparam integer IMAGE_N    = cfg_samples(CFG_IMAGE_MS);
    localparam integer PERIOD_N   = cfg_samples(CFG_PERIOD_MS);
    localparam integer AUTO_ON_N  = cfg_samples(CFG_AUTO_ON_MS);
    localparam integer AUTO_OFF_N = cfg_samples(CFG_AUTO_OFF_MS);
    localparam integer SFX_MAX_N  = max2(max2(IMAGE_N,PERIOD_N),max2(AUTO_ON_N,AUTO_OFF_N));
    localparam integer SFX_BITS   = bits_for(SFX_MAX_N+1);
    localparam integer ATTACK_N   = max2(1,cfg_samples(CFG_SFX_ATTACK_MS));
    localparam integer RELEASE_N  = max2(1,cfg_samples(CFG_SFX_RELEASE_MS));
    localparam integer ATTACK_BITS  = bits_for(ATTACK_N+1);
    localparam integer RELEASE_BITS = bits_for(RELEASE_N+1);

    localparam integer DUCK_DOWN_N = max2(1,cfg_samples(CFG_DUCK_DOWN_MS));
    localparam integer DUCK_UP_N   = max2(1,cfg_samples(CFG_DUCK_UP_MS));
    localparam integer DUCK_DOWN_STEP=(32768-CFG_DUCK_RATIO_Q15+DUCK_DOWN_N-1)/DUCK_DOWN_N;
    localparam integer DUCK_UP_STEP  =(32768-CFG_DUCK_RATIO_Q15+DUCK_UP_N-1)/DUCK_UP_N;

    // 各事件 sweep 步进（相位增量单位/采样）
    localparam [31:0] IMG0_STEP = sweep_step_calc(IMG0_LO, IMG0_HI, IMAGE_N);
    localparam [31:0] IMG1_STEP = sweep_step_calc(IMG1_LO, IMG1_HI, IMAGE_N);
    localparam [31:0] IMG2_STEP = sweep_step_calc(IMG2_LO, IMG2_HI, IMAGE_N);
    localparam [31:0] IMG3_STEP = sweep_step_calc(IMG3_LO, IMG3_HI, IMAGE_N);
    localparam [31:0] PER0_STEP = sweep_step_calc(PER0_LO, PER0_HI, PERIOD_N);
    localparam [31:0] PER1_STEP = sweep_step_calc(PER1_LO, PER1_HI, PERIOD_N);
    localparam [31:0] PER2_STEP = sweep_step_calc(PER2_LO, PER2_HI, PERIOD_N);
    localparam [31:0] AUTO_ON_STEP  = sweep_step_calc(AUTO_ON_LO, AUTO_ON_HI, AUTO_ON_N);
    localparam [31:0] AUTO_OFF_STEP = sweep_step_calc(AUTO_OFF_LO, AUTO_OFF_HI, AUTO_OFF_N);

    localparam integer BGM_SWEEP_N   = cfg_samples(BGM_SWEEP_MS);
    localparam [31:0] BGM_DELTA      = BGM_HI - BGM_LO;
    localparam [31:0] BGM_SWEEP_STEP = (BGM_DELTA + BGM_SWEEP_N/2) / BGM_SWEEP_N;
    localparam integer DRILL_SWEEP_N = cfg_samples(DRILL_SWEEP_MS);
    localparam [31:0] DRILL_DELTA = DRILL_HI - DRILL_LO;
    localparam [31:0] DRILL_SWEEP_STEP = (DRILL_DELTA + DRILL_SWEEP_N/2) / DRILL_SWEEP_N;

    function [31:0] image_inc_lo;
        input [1:0] idx;
        begin
            case(idx)
                0:image_inc_lo=IMG0_LO; 1:image_inc_lo=IMG1_LO;
                2:image_inc_lo=IMG2_LO; default:image_inc_lo=IMG3_LO;
            endcase
        end
    endfunction
    function [31:0] image_inc_hi;
        input [1:0] idx;
        begin
            case(idx)
                0:image_inc_hi=IMG0_HI; 1:image_inc_hi=IMG1_HI;
                2:image_inc_hi=IMG2_HI; default:image_inc_hi=IMG3_HI;
            endcase
        end
    endfunction
    function [31:0] image_sweep_step;
        input [1:0] idx;
        begin
            case(idx)
                0:image_sweep_step=IMG0_STEP; 1:image_sweep_step=IMG1_STEP;
                2:image_sweep_step=IMG2_STEP; default:image_sweep_step=IMG3_STEP;
            endcase
        end
    endfunction
    function [31:0] period_inc_lo;
        input [1:0] sel;
        begin
            case(sel)
                0:period_inc_lo=PER0_LO; 1:period_inc_lo=PER1_LO;
                default:period_inc_lo=PER2_LO;
            endcase
        end
    endfunction
    function [31:0] period_inc_hi;
        input [1:0] sel;
        begin
            case(sel)
                0:period_inc_hi=PER0_HI; 1:period_inc_hi=PER1_HI;
                default:period_inc_hi=PER2_HI;
            endcase
        end
    endfunction
    function [31:0] period_sweep_step;
        input [1:0] sel;
        begin
            case(sel)
                0:period_sweep_step=PER0_STEP; 1:period_sweep_step=PER1_STEP;
                default:period_sweep_step=PER2_STEP;
            endcase
        end
    endfunction

    // 分数分频：默认间隔 520/521 clk，每 6 个采样周期恰为 3125 clk。
    // 不用声音状态、BGM_ENABLE 或音量门控采样节拍。
    localparam integer DIV_BASE=CLK_HZ/SAMPLE_RATE;
    localparam integer DIV_REM=CLK_HZ%SAMPLE_RATE;
    reg [bits_for(DIV_BASE+1)-1:0] sample_count;
    reg [bits_for(SAMPLE_RATE)-1:0] fraction;
    wire long_interval=(DIV_REM!=0) && (fraction>=SAMPLE_RATE-DIV_REM);
    wire sample_tick=(sample_count==DIV_BASE-1+long_interval);
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin sample_count<=0; fraction<=0; end
        else if(sample_tick) begin
            sample_count<=0;
            if(long_interval) fraction<=fraction+DIV_REM-SAMPLE_RATE;
            else fraction<=fraction+DIV_REM;
        end else sample_count<=sample_count+1'b1;
    end

    // CDC 协议：payload 与 toggle 同时更新或提前更新，并保持到下一事件。
    // 无 ACK 的固定接口不支持无限速事件；源端相邻事件至少间隔 8 个 I_clk。
    // 复位后前 4 clk 建立基线，期间事件不处理；源端应等至少 8 clk 再发事件。
    reg [2:0] image_sync,period_sync,auto_sync;
    reg [1:0] image_meta,image_payload,period_meta,period_payload;
    reg [1:0] vol_meta,vol_sync,vol_previous,vol_stable;
    reg image_seen,period_seen,auto_seen;
    reg [3:0] sync_ready;
    wire image_event=sync_ready[3] && (image_sync[2]!=image_seen);
    wire period_event=sync_ready[3] && (period_sync[2]!=period_seen);
    wire auto_event=sync_ready[3] && (auto_sync[2]!=auto_seen);
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            image_sync<=0;period_sync<=0;auto_sync<=0;
            image_meta<=0;image_payload<=0;period_meta<=0;period_payload<=0;
            image_seen<=0;period_seen<=0;auto_seen<=0;sync_ready<=0;
            vol_meta<=0;vol_sync<=0;vol_previous<=0;vol_stable<=0;
        end else begin
            image_sync<={image_sync[1:0],I_image_event_toggle};
            period_sync<={period_sync[1:0],I_period_event_toggle};
            auto_sync<={auto_sync[1:0],I_auto_state};
            image_meta<=I_image_event_idx;image_payload<=image_meta;
            period_meta<=I_period_sel;period_payload<=period_meta;
            image_seen<=image_sync[2];period_seen<=period_sync[2];auto_seen<=auto_sync[2];
            sync_ready<={sync_ready[2:0],1'b1};
            vol_meta<=I_vol;vol_sync<=vol_meta;vol_previous<=vol_sync;
            if(vol_previous==vol_sync) vol_stable<=vol_sync;
        end
    end

    localparam [1:0] IDLE=0,ATTACK=1,DECAY=2,RELEASE=3;
    reg [1:0] sfx_state,sfx_priority;
    reg [3:0] sfx_tag;
    reg [31:0] sfx_phase;
    reg [31:0] sfx_inc_lo,sfx_inc_hi,sfx_sweep_step;
    reg [31:0] sfx_sweep_cnt;
    reg        sfx_sweep_dir;
    reg [15:0] sfx_env,sfx_peak,sfx_attack_step,sfx_release_step;
    reg [SFX_BITS-1:0] samples_left;
    reg [ATTACK_BITS-1:0] attack_left;
    reg [RELEASE_BITS-1:0] release_left;
    reg sfx_start;
    reg pending;
    reg [1:0] pending_priority;
    reg [3:0] pending_tag;
    reg [31:0] pending_inc_lo,pending_inc_hi,pending_sweep_step;
    reg [15:0] pending_gain;
    reg [SFX_BITS-1:0] pending_duration;
    reg event_valid;
    reg [1:0] event_priority;
    reg [3:0] event_tag;
    reg [31:0] event_inc_lo,event_inc_hi,event_sweep_step;
    reg [15:0] event_gain;
    reg [SFX_BITS-1:0] event_duration;
    reg request_valid;
    reg [1:0] request_priority;
    reg [3:0] request_tag;
    reg [31:0] request_inc_lo,request_inc_hi,request_sweep_step;
    reg [15:0] request_gain;
    reg [SFX_BITS-1:0] request_duration;

    // 单提示音 + 一个待播槽。AUTO > PERIOD > IMAGE。
    // 同时到达只取最高；更高/同级的新事件先释放旧音再播；低级忙时丢弃。
    // 待播槽同级以最新为准，不堆积过时按键提示。所有 toggle 都会被确认。
    // 先合并本拍事件再由 sample_tick 消费，避免采样边界覆盖/丢失新事件。
    always @* begin
        event_valid=1'b0;event_priority=0;event_tag=0;
        event_inc_lo=0;event_inc_hi=0;event_sweep_step=0;
        event_gain=0;event_duration=0;
        if(auto_event) begin
            event_valid=1;event_priority=3;
            if(auto_sync[2]) begin
                event_tag=4'd7;
                event_inc_lo=AUTO_ON_LO;event_inc_hi=AUTO_ON_HI;
                event_sweep_step=AUTO_ON_STEP;event_duration=AUTO_ON_N;
            end else begin
                event_tag=4'd8;
                event_inc_lo=AUTO_OFF_LO;event_inc_hi=AUTO_OFF_HI;
                event_sweep_step=AUTO_OFF_STEP;event_duration=AUTO_OFF_N;
            end
            event_gain=CFG_AUTO_GAIN_Q15;
        end else if(period_event) begin
            event_valid=1;event_priority=2;
            event_tag=(period_payload<2)?(4'd4+period_payload):4'd6;
            event_inc_lo=period_inc_lo(period_payload);
            event_inc_hi=period_inc_hi(period_payload);
            event_sweep_step=period_sweep_step(period_payload);
            event_gain=CFG_PERIOD_GAIN_Q15;event_duration=PERIOD_N;
        end else if(image_event) begin
            event_valid=1;event_priority=1;event_tag={2'b00,image_payload};
            event_inc_lo=image_inc_lo(image_payload);
            event_inc_hi=image_inc_hi(image_payload);
            event_sweep_step=image_sweep_step(image_payload);
            event_gain=CFG_IMAGE_GAIN_Q15;event_duration=IMAGE_N;
        end
        if(drill_active) event_valid=1'b0;
        request_valid=pending;request_priority=pending_priority;request_tag=pending_tag;
        request_inc_lo=pending_inc_lo;request_inc_hi=pending_inc_hi;
        request_sweep_step=pending_sweep_step;
        request_gain=pending_gain;request_duration=pending_duration;
        if(event_valid && ((sfx_state==IDLE)||(event_priority>=sfx_priority)) &&
            (!pending || event_priority>=pending_priority)) begin
            request_valid=1;request_priority=event_priority;request_tag=event_tag;
            request_inc_lo=event_inc_lo;request_inc_hi=event_inc_hi;
            request_sweep_step=event_sweep_step;
            request_gain=event_gain;request_duration=event_duration;
        end
    end
    wire [15:0] decay_step=(sfx_env>>CFG_SFX_DECAY_SHIFT)==0 ?
        16'd1 : (sfx_env>>CFG_SFX_DECAY_SHIFT);
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            sfx_state<=IDLE;sfx_priority<=0;sfx_tag<=0;sfx_start<=0;
            sfx_phase<=0;sfx_inc_lo<=0;sfx_inc_hi<=0;sfx_sweep_step<=0;
            sfx_sweep_cnt<=0;sfx_sweep_dir<=1'b0;
            sfx_env<=0;sfx_peak<=0;sfx_attack_step<=0;sfx_release_step<=0;
            samples_left<=0;attack_left<=0;release_left<=0;
            pending<=0;pending_priority<=0;pending_tag<=0;
            pending_inc_lo<=0;pending_inc_hi<=0;pending_sweep_step<=0;
            pending_gain<=0;pending_duration<=0;
        end else if(drill_active) begin
            sfx_state<=IDLE;sfx_priority<=0;sfx_tag<=0;sfx_start<=0;
            sfx_phase<=0;sfx_inc_lo<=0;sfx_inc_hi<=0;sfx_sweep_step<=0;
            sfx_sweep_cnt<=0;sfx_sweep_dir<=1'b0;
            sfx_env<=0;sfx_peak<=0;sfx_attack_step<=0;sfx_release_step<=0;
            samples_left<=0;attack_left<=0;release_left<=0;
            pending<=0;pending_priority<=0;pending_tag<=0;
            pending_inc_lo<=0;pending_inc_hi<=0;pending_sweep_step<=0;
            pending_gain<=0;pending_duration<=0;
        end else begin
            sfx_start<=0;
            pending<=request_valid;pending_priority<=request_priority;pending_tag<=request_tag;
            pending_inc_lo<=request_inc_lo;pending_inc_hi<=request_inc_hi;
            pending_sweep_step<=request_sweep_step;
            pending_gain<=request_gain;pending_duration<=request_duration;
            if(sample_tick) begin
                if(sfx_state==IDLE) begin
                    sfx_env<=0;
                    if(request_valid) begin
                        pending<=0;sfx_start<=1;sfx_state<=ATTACK;
                        sfx_priority<=request_priority;sfx_tag<=request_tag;
                        sfx_phase<=0;
                        sfx_inc_lo<=request_inc_lo;sfx_inc_hi<=request_inc_hi;
                        sfx_sweep_step<=request_sweep_step;
                        sfx_sweep_cnt<=0;sfx_sweep_dir<=1'b1;
                        sfx_peak<=request_gain;
                        sfx_attack_step<=(request_gain+ATTACK_N-1)/ATTACK_N;
                        attack_left<=ATTACK_N;samples_left<=request_duration;
                    end
                end else begin
                    // 扫频相位：instant_inc = inc_lo + sweep_cnt
                    sfx_phase<=sfx_phase+sfx_inc_lo+sfx_sweep_cnt;
                    // sweep_cnt 三角波往返
                    if(sfx_sweep_dir) begin
                        if(sfx_sweep_cnt+sfx_sweep_step>=sfx_inc_hi-sfx_inc_lo) begin
                            sfx_sweep_cnt<=sfx_inc_hi-sfx_inc_lo;
                            sfx_sweep_dir<=1'b0;
                        end else sfx_sweep_cnt<=sfx_sweep_cnt+sfx_sweep_step;
                    end else begin
                        if(sfx_sweep_cnt<=sfx_sweep_step) begin
                            sfx_sweep_cnt<=32'd0;sfx_sweep_dir<=1'b1;
                        end else sfx_sweep_cnt<=sfx_sweep_cnt-sfx_sweep_step;
                    end
                    if(samples_left!=0) samples_left<=samples_left-1'b1;
                    case(sfx_state)
                        ATTACK: begin
                            if(attack_left<=1 || sfx_env+sfx_attack_step>=sfx_peak) begin
                                sfx_env<=sfx_peak;sfx_state<=DECAY;
                            end else begin
                                sfx_env<=sfx_env+sfx_attack_step;
                                attack_left<=attack_left-1'b1;
                            end
                        end
                        DECAY: if(CFG_SFX_DECAY_SHIFT!=0) begin
                            if(sfx_env>decay_step) sfx_env<=sfx_env-decay_step;
                            else sfx_env<=0;
                        end
                        RELEASE: begin
                            if(sfx_env>sfx_release_step) sfx_env<=sfx_env-sfx_release_step;
                            else sfx_env<=0;
                            if(release_left<=1) begin sfx_env<=0;sfx_state<=IDLE;end
                            else release_left<=release_left-1'b1;
                        end
                        default:begin sfx_state<=IDLE;sfx_env<=0;end
                    endcase
                    if(sfx_state!=RELEASE && (request_valid || samples_left<=RELEASE_N+1)) begin
                        sfx_state<=RELEASE;release_left<=RELEASE_N;
                        sfx_release_step<=(sfx_env+RELEASE_N-1)/RELEASE_N;
                        sfx_env<=sfx_env;
                    end
                end
            end
        end
    end

    // 背景：低音持续警笛 180~220 Hz 缓慢扫频。ducking 与参考模块一致。
    reg [31:0] bgm_phase;
    reg [31:0] bgm_sweep_cnt;
    reg        bgm_sweep_dir;
    reg [15:0] bgm_env;
    reg [15:0] duck_gain;
    reg [bits_for(CFG_BGM_UPDATE_DIV)-1:0] bgm_subcount;
    reg [1:0] bgm_mode_prev;
    wire bgm_update=(bgm_subcount==0);
    wire duck_active=(sfx_state!=IDLE) || request_valid;
    wire bgm_enabled=drill_siren || (!drill_active && (BGM_ENABLE!=0));
    wire [31:0] active_bgm_lo=drill_siren ? DRILL_LO : BGM_LO;
    wire [31:0] active_bgm_delta=drill_siren ? DRILL_DELTA : BGM_DELTA;
    wire [31:0] active_bgm_step=drill_siren ? DRILL_SWEEP_STEP : BGM_SWEEP_STEP;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            bgm_phase<=0;bgm_sweep_cnt<=0;bgm_sweep_dir<=1'b1;
            bgm_env<=0;duck_gain<=16'd32768;bgm_subcount<=0;bgm_mode_prev<=0;
        end else if(sample_tick) begin
            bgm_mode_prev<=drill_mode;
            if(drill_siren) begin
                duck_gain<=16'd32768;
            end else if(duck_active) begin
                if(duck_gain<=CFG_DUCK_RATIO_Q15+DUCK_DOWN_STEP) duck_gain<=CFG_DUCK_RATIO_Q15;
                else duck_gain<=duck_gain-DUCK_DOWN_STEP;
            end else begin
                if(duck_gain>=32768-DUCK_UP_STEP) duck_gain<=16'd32768;
                else duck_gain<=duck_gain+DUCK_UP_STEP;
            end
            if(drill_mode!=bgm_mode_prev) begin
                bgm_phase<=0;bgm_sweep_cnt<=0;bgm_sweep_dir<=1'b1;
                bgm_env<=bgm_enabled ? CFG_BGM_GAIN_Q15 : 16'd0;bgm_subcount<=0;
            end else if(!bgm_enabled) begin
                bgm_phase<=0;bgm_sweep_cnt<=0;bgm_sweep_dir<=1'b1;
                bgm_env<=0;bgm_subcount<=0;
            end else begin
                if(bgm_subcount==CFG_BGM_UPDATE_DIV-1) bgm_subcount<=0;
                else bgm_subcount<=bgm_subcount+1'b1;
                if(bgm_sweep_dir) begin
                    if(bgm_sweep_cnt+active_bgm_step>=active_bgm_delta) begin
                        bgm_sweep_cnt<=active_bgm_delta;bgm_sweep_dir<=1'b0;
                    end else bgm_sweep_cnt<=bgm_sweep_cnt+active_bgm_step;
                end else begin
                    if(bgm_sweep_cnt<=active_bgm_step) begin
                        bgm_sweep_cnt<=32'd0;bgm_sweep_dir<=1'b1;
                    end else bgm_sweep_cnt<=bgm_sweep_cnt-active_bgm_step;
                end
                if(bgm_update)
                    bgm_phase<=bgm_phase+(active_bgm_lo+bgm_sweep_cnt)*CFG_BGM_UPDATE_DIV;
                bgm_env<=CFG_BGM_GAIN_Q15;
            end
        end
    end

    // 256 点正弦，仅存四分之一；普通 case，无厂商 ROM 或初始化文件。
    function signed [15:0] sine256;
        input [7:0] angle;
        reg [6:0] index;
        reg signed [15:0] magnitude;
        begin
            index=angle[6] ? (7'd64-{1'b0,angle[5:0]}) : {1'b0,angle[5:0]};
            case(index)
                7'd0:magnitude=16'sd0;
                7'd1:magnitude=16'sd804;
                7'd2:magnitude=16'sd1608;
                7'd3:magnitude=16'sd2410;
                7'd4:magnitude=16'sd3212;
                7'd5:magnitude=16'sd4011;
                7'd6:magnitude=16'sd4808;
                7'd7:magnitude=16'sd5602;
                7'd8:magnitude=16'sd6393;
                7'd9:magnitude=16'sd7179;
                7'd10:magnitude=16'sd7962;
                7'd11:magnitude=16'sd8739;
                7'd12:magnitude=16'sd9512;
                7'd13:magnitude=16'sd10278;
                7'd14:magnitude=16'sd11039;
                7'd15:magnitude=16'sd11793;
                7'd16:magnitude=16'sd12539;
                7'd17:magnitude=16'sd13279;
                7'd18:magnitude=16'sd14010;
                7'd19:magnitude=16'sd14732;
                7'd20:magnitude=16'sd15446;
                7'd21:magnitude=16'sd16151;
                7'd22:magnitude=16'sd16846;
                7'd23:magnitude=16'sd17530;
                7'd24:magnitude=16'sd18204;
                7'd25:magnitude=16'sd18868;
                7'd26:magnitude=16'sd19519;
                7'd27:magnitude=16'sd20159;
                7'd28:magnitude=16'sd20787;
                7'd29:magnitude=16'sd21403;
                7'd30:magnitude=16'sd22005;
                7'd31:magnitude=16'sd22594;
                7'd32:magnitude=16'sd23170;
                7'd33:magnitude=16'sd23731;
                7'd34:magnitude=16'sd24279;
                7'd35:magnitude=16'sd24811;
                7'd36:magnitude=16'sd25329;
                7'd37:magnitude=16'sd25832;
                7'd38:magnitude=16'sd26319;
                7'd39:magnitude=16'sd26790;
                7'd40:magnitude=16'sd27245;
                7'd41:magnitude=16'sd27683;
                7'd42:magnitude=16'sd28105;
                7'd43:magnitude=16'sd28510;
                7'd44:magnitude=16'sd28898;
                7'd45:magnitude=16'sd29268;
                7'd46:magnitude=16'sd29621;
                7'd47:magnitude=16'sd29956;
                7'd48:magnitude=16'sd30273;
                7'd49:magnitude=16'sd30571;
                7'd50:magnitude=16'sd30852;
                7'd51:magnitude=16'sd31113;
                7'd52:magnitude=16'sd31356;
                7'd53:magnitude=16'sd31580;
                7'd54:magnitude=16'sd31785;
                7'd55:magnitude=16'sd31971;
                7'd56:magnitude=16'sd32137;
                7'd57:magnitude=16'sd32285;
                7'd58:magnitude=16'sd32412;
                7'd59:magnitude=16'sd32521;
                7'd60:magnitude=16'sd32609;
                7'd61:magnitude=16'sd32678;
                7'd62:magnitude=16'sd32728;
                7'd63:magnitude=16'sd32757;
                7'd64:magnitude=16'sd32767;
                default:magnitude=16'sd0;
            endcase
            sine256=angle[7] ? -magnitude : magnitude;
        end
    endfunction
    function signed [23:0] clip24;
        input signed [26:0] value;
        begin
            if(value>27'sd8388607) clip24=24'sh7fffff;
            else if(value< -27'sd8388608) clip24=24'sh800000;
            else clip24=value[23:0];
        end
    endfunction

    // 有使能的流水线：查表 -> 增益乘法 -> 波形乘法/PCM -> 混音 -> 总音量 -> 饱和。
    // 背景保留 12 kHz 更新，提示为 48 kHz；所有寄存器只由 I_clk 驱动。
    reg [4:0] pcm_valid;
    reg [1:0] bgm_valid;
    reg [1:0] vol_p0,vol_p1,vol_p2,vol_p3;
    reg signed [15:0] sfx_sine_p0,bgm_sine_p0,bgm_sine_p1;
    reg signed [16:0] sfx_gain_p0;
    reg [15:0] bgm_env_p0,duck_p0;
    reg signed [32:0] sfx_product,bgm_product;
    reg [31:0] bgm_gain_product;
    reg signed [23:0] sfx_pcm;
    wire signed [23:0] bgm_pcm=bgm_product >>> 7;
    reg signed [24:0] mixed_pcm;
    reg signed [26:0] volume_pcm;
    reg signed [23:0] meter_sfx_p2,meter_bgm_p2;
    reg signed [26:0] meter_sfx_volume,meter_bgm_volume;
    function signed [26:0] meter_volume;
        input signed [23:0] pcm;
        input [1:0] vol;
        reg signed [26:0] wide;
        begin
            wide={{3{pcm[23]}},pcm};
            case(vol)
                0:meter_volume=0;
                1:meter_volume=wide >>> 1;
                2:meter_volume=((wide <<< 1)+wide) >>> 2;
                default:meter_volume=wide;
            endcase
        end
    endfunction
    wire signed [26:0] mixed_wide={{2{mixed_pcm[24]}},mixed_pcm};
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            pcm_valid<=0;bgm_valid<=0;O_audio_valid<=0;
            vol_p0<=0;vol_p1<=0;vol_p2<=0;vol_p3<=0;
            sfx_sine_p0<=0;sfx_gain_p0<=0;bgm_sine_p0<=0;bgm_sine_p1<=0;
            bgm_env_p0<=0;duck_p0<=0;sfx_product<=0;bgm_product<=0;
            bgm_gain_product<=0;sfx_pcm<=0;mixed_pcm<=0;volume_pcm<=0;
            O_audio_left<=0;O_audio_right<=0;
            meter_sfx_p2<=0;meter_bgm_p2<=0;meter_sfx_volume<=0;meter_bgm_volume<=0;
            O_sfx_meter_sample<=0;O_bgm_meter_sample<=0;
        end else begin
            pcm_valid<={pcm_valid[3:0],sample_tick};
            bgm_valid<={bgm_valid[0],(sample_tick && bgm_update && bgm_enabled)};
            O_audio_valid<=pcm_valid[4];
            if(sample_tick) begin
                sfx_sine_p0<=(sfx_state==IDLE)?16'sd0:sine256(sfx_phase[31:24]);
                sfx_gain_p0<=$signed({1'b0,sfx_env});vol_p0<=vol_stable;
                if(bgm_update && bgm_enabled) begin
                    bgm_sine_p0<=sine256(bgm_phase[31:24]);
                    bgm_env_p0<=bgm_env;duck_p0<=duck_gain;
                end else if(!bgm_enabled) begin
                    // 演练完成阶段要求真正静音。清空各级寄存器，避免流水线中
                    // 上一个警报音采样继续残留到 HDMI 音频输出。
                    bgm_sine_p0<=0;bgm_env_p0<=0;duck_p0<=0;
                end
            end
            if(pcm_valid[0]) begin
                sfx_product<=sfx_sine_p0*sfx_gain_p0;vol_p1<=vol_p0;
            end
            if(bgm_valid[0]) begin
                bgm_gain_product<=bgm_env_p0*duck_p0;bgm_sine_p1<=bgm_sine_p0;
            end else if(!bgm_enabled) begin
                bgm_gain_product<=0;bgm_sine_p1<=0;
            end
            if(pcm_valid[1]) begin sfx_pcm<=sfx_product >>> 7;vol_p2<=vol_p1;end
            if(bgm_valid[1]) bgm_product<=bgm_sine_p1*$signed({1'b0,bgm_gain_product[30:15]});
            else if(!bgm_enabled) bgm_product<=0;
            if(pcm_valid[2]) begin
                meter_sfx_p2<=sfx_pcm;meter_bgm_p2<=bgm_pcm;
                mixed_pcm<=$signed({sfx_pcm[23],sfx_pcm})+$signed({bgm_pcm[23],bgm_pcm});
                vol_p3<=vol_p2;
            end
            if(pcm_valid[3]) begin
                meter_sfx_volume<=meter_volume(meter_sfx_p2,vol_p3);
                meter_bgm_volume<=meter_volume(meter_bgm_p2,vol_p3);
                case(vol_p3)
                    0:volume_pcm<=0;
                    1:volume_pcm<=mixed_wide >>> 1;
                    2:volume_pcm<=((mixed_wide <<< 1)+mixed_wide) >>> 2;
                    default:volume_pcm<=mixed_wide;
                endcase
            end
            if(pcm_valid[4]) begin
                O_audio_left<=clip24(volume_pcm);O_audio_right<=clip24(volume_pcm);
                O_sfx_meter_sample<=clip24(meter_sfx_volume);
                O_bgm_meter_sample<=clip24(meter_bgm_volume);
            end
        end
    end
endmodule

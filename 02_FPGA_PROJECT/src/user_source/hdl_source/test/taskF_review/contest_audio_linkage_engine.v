`timescale 1ns/1ps
// V04 独立音频联动模块，Verilog-2001。
// 已实现：图片/周期/轮播音、并行背景、平滑 ducking、饱和混音、连续 PCM。
// 仿真：Icarus Verilog -g2001，25 MHz 默认配置及 1 MHz 加速回归均通过。
// 未进行 TD 综合、顶层融合、位流或实板验证。
// 固定接口保持任务包原样；本模块不处理按键，不修改任何工程文件。
module contest_audio_linkage_engine #(
    parameter integer CLK_HZ      = 25000000,
    parameter integer SAMPLE_RATE = 48000,
    parameter integer BGM_ENABLE  = 1
)(
    input  wire               I_clk,
    input  wire               I_rst,
    input  wire               I_image_event_toggle,
    input  wire [1:0]         I_image_event_idx,
    input  wire               I_period_event_toggle,
    input  wire [1:0]         I_period_sel,
    input  wire               I_auto_state,
    input  wire [1:0]         I_vol,
    output reg                O_audio_valid,
    output reg signed [23:0] O_audio_left,
    output reg signed [23:0] O_audio_right
);

    // ===================== 音效配置区 BEGIN =====================
    // 更换合成音效时只改本区。频率单位 mHz：523250 表示 523.250 Hz。
    // 增益为 Q15：0=静音，8192=25%，16384=50%，32768=100%。
    // 图片 payload 已经是目标图号，直接查表，绝不能再加 1。
    // SAMPLE_RATE 在 HDMI 工程中保持 48000；需 CLK_HZ > SAMPLE_RATE*8。
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

    // 图片音调表：IMG1/2/3/4 = do/re/mi/fa。
    localparam [31:0] CFG_IMAGE_0 = cfg_phase(523250);
    localparam [31:0] CFG_IMAGE_1 = cfg_phase(587330);
    localparam [31:0] CFG_IMAGE_2 = cfg_phase(659250);
    localparam [31:0] CFG_IMAGE_3 = cfg_phase(698460);
    // 周期音调表：1/2/4 秒；非法档位 3 也使用 4 秒档。
    localparam [31:0] CFG_PERIOD_0 = cfg_phase(329630);
    localparam [31:0] CFG_PERIOD_1 = cfg_phase(523250);
    localparam [31:0] CFG_PERIOD_2 = cfg_phase(783990);
    localparam [31:0] CFG_AUTO_ON  = cfg_phase(1046500);
    localparam [31:0] CFG_AUTO_OFF = cfg_phase(440000);

    // 提示音总时长（包含起音和尾部释放）。须大于起音+释放时长。
    localparam integer CFG_IMAGE_MS    = 120;
    localparam integer CFG_PERIOD_MS   = 80;
    localparam integer CFG_AUTO_ON_MS  = 100;
    localparam integer CFG_AUTO_OFF_MS = 150;
    localparam integer CFG_SFX_ATTACK_MS  = 1;
    localparam integer CFG_SFX_RELEASE_MS = 4; // 自然结束/被抢占均软释放
    localparam integer CFG_SFX_DECAY_SHIFT = 12; // 大=衰减慢；0=保持音量

    // 各路峰值增益；背景正常峰值沿用 V04 的约 25% 满幅。
    localparam [15:0] CFG_IMAGE_GAIN_Q15    = 16'd16384;
    localparam [15:0] CFG_PERIOD_GAIN_Q15   = 16'd16384;
    localparam [15:0] CFG_AUTO_ON_GAIN_Q15  = 16'd16384;
    localparam [15:0] CFG_AUTO_OFF_GAIN_Q15 = 16'd16384;
    localparam [15:0] CFG_BGM_GAIN_Q15      = 16'd8192;
    localparam [15:0] CFG_DUCK_RATIO_Q15    = 16'd8192; // 提示期间背景剩 25%
    localparam integer CFG_DUCK_DOWN_MS = 8;
    localparam integer CFG_DUCK_UP_MS   = 8;
    localparam integer CFG_BGM_ATTACK_MS  = 5;
    localparam integer CFG_BGM_RELEASE_MS = 10;

    // 背景旋律：最多 8 步，长度 1..8；每项 {时长采样数, DDS 相位增量}。
    // 修改 cfg_samples(ms)、cfg_phase(mHz) 即可换旋律/节奏；频率 0=休止。
    // 每步时长应大于背景起音+释放；增删步只改 LENGTH 和对应项。
    localparam integer CFG_BGM_LENGTH = 4;
    localparam [63:0] CFG_BGM_NOTE_0 = {cfg_samples(300), cfg_phase(261626)};
    localparam [63:0] CFG_BGM_NOTE_1 = {cfg_samples(300), cfg_phase(329628)};
    localparam [63:0] CFG_BGM_NOTE_2 = {cfg_samples(300), cfg_phase(391995)};
    localparam [63:0] CFG_BGM_NOTE_3 = {cfg_samples(300), cfg_phase(523251)};
    localparam [63:0] CFG_BGM_NOTE_4 = {cfg_samples(300), cfg_phase(0)};
    localparam [63:0] CFG_BGM_NOTE_5 = {cfg_samples(300), cfg_phase(0)};
    localparam [63:0] CFG_BGM_NOTE_6 = {cfg_samples(300), cfg_phase(0)};
    localparam [63:0] CFG_BGM_NOTE_7 = {cfg_samples(300), cfg_phase(0)};
    // V04 的背景波形每 4 个 PCM 样本更新一次（12 kHz），保持到下一次。
    // 可设 1/2/4；旋律计时、提示音及 HDMI 输出始终是 SAMPLE_RATE。
    // 背景音调应低于 SAMPLE_RATE/(2*CFG_BGM_UPDATE_DIV)。
    localparam integer CFG_BGM_UPDATE_DIV = 4;
    // 总音量 I_vol 固定协议：0/50/75/100%，在混音后执行，不在此改映射。
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
    localparam integer IMAGE_N = cfg_samples(CFG_IMAGE_MS);
    localparam integer PERIOD_N = cfg_samples(CFG_PERIOD_MS);
    localparam integer AUTO_ON_N = cfg_samples(CFG_AUTO_ON_MS);
    localparam integer AUTO_OFF_N = cfg_samples(CFG_AUTO_OFF_MS);
    localparam integer SFX_MAX_N=max2(max2(IMAGE_N,PERIOD_N),max2(AUTO_ON_N,AUTO_OFF_N));
    localparam integer SFX_BITS=bits_for(SFX_MAX_N+1);
    localparam integer ATTACK_N=max2(1,cfg_samples(CFG_SFX_ATTACK_MS));
    localparam integer RELEASE_N=max2(1,cfg_samples(CFG_SFX_RELEASE_MS));
    localparam integer ATTACK_BITS=bits_for(ATTACK_N+1);
    localparam integer RELEASE_BITS=bits_for(RELEASE_N+1);
    localparam integer BGM_MAX_N=max2(max2(max2(CFG_BGM_NOTE_0[63:32],CFG_BGM_NOTE_1[63:32]),
        max2(CFG_BGM_NOTE_2[63:32],CFG_BGM_NOTE_3[63:32])),
        max2(max2(CFG_BGM_NOTE_4[63:32],CFG_BGM_NOTE_5[63:32]),
        max2(CFG_BGM_NOTE_6[63:32],CFG_BGM_NOTE_7[63:32])));
    localparam integer BGM_BITS=bits_for(BGM_MAX_N);
    localparam integer BGM_ATTACK_N=max2(1,cfg_samples(CFG_BGM_ATTACK_MS));
    localparam integer BGM_RELEASE_N=max2(1,cfg_samples(CFG_BGM_RELEASE_MS));
    localparam integer BGM_ATTACK_STEP=(CFG_BGM_GAIN_Q15+BGM_ATTACK_N-1)/BGM_ATTACK_N;
    localparam integer BGM_RELEASE_STEP=(CFG_BGM_GAIN_Q15+BGM_RELEASE_N-1)/BGM_RELEASE_N;
    localparam integer DUCK_DOWN_N=max2(1,cfg_samples(CFG_DUCK_DOWN_MS));
    localparam integer DUCK_UP_N=max2(1,cfg_samples(CFG_DUCK_UP_MS));
    localparam integer DUCK_DOWN_STEP=(32768-CFG_DUCK_RATIO_Q15+DUCK_DOWN_N-1)/DUCK_DOWN_N;
    localparam integer DUCK_UP_STEP=(32768-CFG_DUCK_RATIO_Q15+DUCK_UP_N-1)/DUCK_UP_N;

    function [31:0] image_increment;
        input [1:0] idx;
        begin
            case(idx)
                0:image_increment=CFG_IMAGE_0; 1:image_increment=CFG_IMAGE_1;
                2:image_increment=CFG_IMAGE_2; default:image_increment=CFG_IMAGE_3;
            endcase
        end
    endfunction
    function [31:0] period_increment;
        input [1:0] sel;
        begin
            case(sel)
                0:period_increment=CFG_PERIOD_0; 1:period_increment=CFG_PERIOD_1;
                default:period_increment=CFG_PERIOD_2;
            endcase
        end
    endfunction
    function [63:0] bgm_note;
        input [2:0] idx;
        begin
            case(idx)
                0:bgm_note=CFG_BGM_NOTE_0; 1:bgm_note=CFG_BGM_NOTE_1;
                2:bgm_note=CFG_BGM_NOTE_2; 3:bgm_note=CFG_BGM_NOTE_3;
                4:bgm_note=CFG_BGM_NOTE_4; 5:bgm_note=CFG_BGM_NOTE_5;
                6:bgm_note=CFG_BGM_NOTE_6; default:bgm_note=CFG_BGM_NOTE_7;
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
    // 第三级 toggle 给两级 payload 额外稳定时间，不宣称可解决任意总线偏斜。
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
    reg [3:0] sfx_tag; // 仅内部标识，供仿真观察，不增加接口
    reg [31:0] sfx_phase,sfx_increment;
    reg [15:0] sfx_env,sfx_peak,sfx_attack_step,sfx_release_step;
    reg [SFX_BITS-1:0] samples_left;
    reg [ATTACK_BITS-1:0] attack_left;
    reg [RELEASE_BITS-1:0] release_left;
    reg sfx_start;
    reg pending;
    reg [1:0] pending_priority;
    reg [3:0] pending_tag;
    reg [31:0] pending_increment;
    reg [15:0] pending_gain;
    reg [SFX_BITS-1:0] pending_duration;
    reg event_valid;
    reg [1:0] event_priority;
    reg [3:0] event_tag;
    reg [31:0] event_increment;
    reg [15:0] event_gain;
    reg [SFX_BITS-1:0] event_duration;
    reg request_valid;
    reg [1:0] request_priority;
    reg [3:0] request_tag;
    reg [31:0] request_increment;
    reg [15:0] request_gain;
    reg [SFX_BITS-1:0] request_duration;

    // 单提示音 + 一个待播槽。AUTO > PERIOD > IMAGE。
    // 同时到达只取最高；更高/同级的新事件先释放旧音再播；低级忙时丢弃。
    // 待播槽同级以最新为准，不堆积过时按键提示。所有 toggle 都会被确认。
    // 先合并本拍事件再由 sample_tick 消费，避免采样边界覆盖/丢失新事件。
    always @* begin
        event_valid=1'b0;event_priority=0;event_tag=0;
        event_increment=0;event_gain=0;event_duration=0;
        if(auto_event) begin
            event_valid=1;event_priority=3;
            event_tag=auto_sync[2]?4'd7:4'd8;
            event_increment=auto_sync[2]?CFG_AUTO_ON:CFG_AUTO_OFF;
            event_gain=auto_sync[2]?CFG_AUTO_ON_GAIN_Q15:CFG_AUTO_OFF_GAIN_Q15;
            event_duration=auto_sync[2]?AUTO_ON_N:AUTO_OFF_N;
        end else if(period_event) begin
            event_valid=1;event_priority=2;
            event_tag=(period_payload<2)?(4'd4+period_payload):4'd6;
            event_increment=period_increment(period_payload);
            event_gain=CFG_PERIOD_GAIN_Q15;event_duration=PERIOD_N;
        end else if(image_event) begin
            event_valid=1;event_priority=1;event_tag={2'b00,image_payload};
            event_increment=image_increment(image_payload);
            event_gain=CFG_IMAGE_GAIN_Q15;event_duration=IMAGE_N;
        end
        request_valid=pending;request_priority=pending_priority;request_tag=pending_tag;
        request_increment=pending_increment;request_gain=pending_gain;
        request_duration=pending_duration;
        if(event_valid && ((sfx_state==IDLE)||(event_priority>=sfx_priority)) &&
            (!pending || event_priority>=pending_priority)) begin
            request_valid=1;request_priority=event_priority;request_tag=event_tag;
            request_increment=event_increment;request_gain=event_gain;
            request_duration=event_duration;
        end
    end
    wire [15:0] decay_step=(sfx_env>>CFG_SFX_DECAY_SHIFT)==0 ?
        16'd1 : (sfx_env>>CFG_SFX_DECAY_SHIFT);
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            sfx_state<=IDLE;sfx_priority<=0;sfx_tag<=0;sfx_start<=0;
            sfx_phase<=0;sfx_increment<=0;sfx_env<=0;sfx_peak<=0;
            sfx_attack_step<=0;sfx_release_step<=0;
            samples_left<=0;attack_left<=0;release_left<=0;
            pending<=0;pending_priority<=0;pending_tag<=0;
            pending_increment<=0;pending_gain<=0;pending_duration<=0;
        end else begin
            sfx_start<=0;
            pending<=request_valid;pending_priority<=request_priority;pending_tag<=request_tag;
            pending_increment<=request_increment;pending_gain<=request_gain;
            pending_duration<=request_duration;
            if(sample_tick) begin
                if(sfx_state==IDLE) begin
                    sfx_env<=0;
                    if(request_valid) begin
                        pending<=0;sfx_start<=1;sfx_state<=ATTACK;
                        sfx_priority<=request_priority;sfx_tag<=request_tag;
                        sfx_phase<=0;sfx_increment<=request_increment;
                        sfx_peak<=request_gain;
                        sfx_attack_step<=(request_gain+ATTACK_N-1)/ATTACK_N;
                        attack_left<=ATTACK_N;samples_left<=request_duration;
                    end
                end else begin
                    sfx_phase<=sfx_phase+sfx_increment;
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

    reg [2:0] bgm_idx;
    reg [BGM_BITS-1:0] bgm_count;
    reg [bits_for(CFG_BGM_UPDATE_DIV)-1:0] bgm_subcount;
    reg [31:0] bgm_phase;
    reg [15:0] bgm_env,duck_gain;
    wire [63:0] bgm_current=bgm_note(bgm_idx);
    wire bgm_update=(bgm_subcount==0);
    wire duck_active=(sfx_state!=IDLE) || request_valid;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            bgm_idx<=0;bgm_count<=0;bgm_subcount<=0;
            bgm_phase<=0;bgm_env<=0;duck_gain<=16'd32768;
        end else if(sample_tick) begin
            if(duck_active) begin
                if(duck_gain<=CFG_DUCK_RATIO_Q15+DUCK_DOWN_STEP) duck_gain<=CFG_DUCK_RATIO_Q15;
                else duck_gain<=duck_gain-DUCK_DOWN_STEP;
            end else begin
                if(duck_gain>=32768-DUCK_UP_STEP) duck_gain<=16'd32768;
                else duck_gain<=duck_gain+DUCK_UP_STEP;
            end
            if(BGM_ENABLE==0) begin
                bgm_idx<=0;bgm_count<=0;bgm_subcount<=0;bgm_phase<=0;bgm_env<=0;
            end else begin
                if(bgm_subcount==CFG_BGM_UPDATE_DIV-1) bgm_subcount<=0;
                else bgm_subcount<=bgm_subcount+1'b1;
                if(bgm_count>=bgm_current[63:32]-1) begin
                    bgm_count<=0;bgm_phase<=0;bgm_env<=0;bgm_subcount<=0;
                    if(bgm_idx==CFG_BGM_LENGTH-1) bgm_idx<=0;
                    else bgm_idx<=bgm_idx+1'b1;
                end else begin
                    bgm_count<=bgm_count+1'b1;
                    if(bgm_update) bgm_phase<=bgm_phase+bgm_current[31:0]*CFG_BGM_UPDATE_DIV;
                    if(bgm_count>=bgm_current[63:32]-BGM_RELEASE_N) begin
                        if(bgm_env>BGM_RELEASE_STEP) bgm_env<=bgm_env-BGM_RELEASE_STEP;
                        else bgm_env<=0;
                    end else if(bgm_count<BGM_ATTACK_N) begin
                        if(bgm_env+BGM_ATTACK_STEP>=CFG_BGM_GAIN_Q15) bgm_env<=CFG_BGM_GAIN_Q15;
                        else bgm_env<=bgm_env+BGM_ATTACK_STEP;
                    end else bgm_env<=CFG_BGM_GAIN_Q15;
                end
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
    // Q15 包络可等于 32768，转乘法前必须补 0 成有符号 17 bit。
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
    wire signed [26:0] mixed_wide={{2{mixed_pcm[24]}},mixed_pcm};
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            pcm_valid<=0;bgm_valid<=0;O_audio_valid<=0;
            vol_p0<=0;vol_p1<=0;vol_p2<=0;vol_p3<=0;
            sfx_sine_p0<=0;sfx_gain_p0<=0;bgm_sine_p0<=0;bgm_sine_p1<=0;
            bgm_env_p0<=0;duck_p0<=0;sfx_product<=0;bgm_product<=0;
            bgm_gain_product<=0;sfx_pcm<=0;mixed_pcm<=0;volume_pcm<=0;
            O_audio_left<=0;O_audio_right<=0;
        end else begin
            pcm_valid<={pcm_valid[3:0],sample_tick};
            bgm_valid<={bgm_valid[0],(sample_tick && bgm_update && BGM_ENABLE!=0)};
            O_audio_valid<=pcm_valid[4];
            if(sample_tick) begin
                sfx_sine_p0<=(sfx_state==IDLE)?16'sd0:sine256(sfx_phase[31:24]);
                sfx_gain_p0<=$signed({1'b0,sfx_env});vol_p0<=vol_stable;
                if(bgm_update && BGM_ENABLE!=0) begin
                    bgm_sine_p0<=(bgm_current[31:0]==0)?16'sd0:sine256(bgm_phase[31:24]);
                    bgm_env_p0<=bgm_env;duck_p0<=duck_gain;
                end
            end
            if(pcm_valid[0]) begin
                sfx_product<=sfx_sine_p0*sfx_gain_p0;vol_p1<=vol_p0;
            end
            if(bgm_valid[0]) begin
                bgm_gain_product<=bgm_env_p0*duck_p0;bgm_sine_p1<=bgm_sine_p0;
            end
            if(pcm_valid[1]) begin sfx_pcm<=sfx_product >>> 7;vol_p2<=vol_p1;end
            if(bgm_valid[1]) bgm_product<=bgm_sine_p1*$signed({1'b0,bgm_gain_product[30:15]});
            if(pcm_valid[2]) begin
                mixed_pcm<=$signed({sfx_pcm[23],sfx_pcm})+$signed({bgm_pcm[23],bgm_pcm});
                vol_p3<=vol_p2;
            end
            if(pcm_valid[3]) begin
                case(vol_p3)
                    0:volume_pcm<=0;
                    1:volume_pcm<=mixed_wide >>> 1;
                    2:volume_pcm<=((mixed_wide <<< 1)+mixed_wide) >>> 2;
                    default:volume_pcm<=mixed_wide;
                endcase
            end
            if(pcm_valid[4]) begin
                O_audio_left<=clip24(volume_pcm);O_audio_right<=clip24(volume_pcm);
            end
        end
    end
endmodule

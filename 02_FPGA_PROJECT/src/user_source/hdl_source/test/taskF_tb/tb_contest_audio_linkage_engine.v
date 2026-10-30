`timescale 1ns/1ps
// 独立 Verilog-2001 自动验收，无厂商库、无外部数据文件。
// 默认实际 25 MHz；可改 TB_CLK_HZ=1000000 加速完整回归，采样仍为 48 kHz。
// ModelSim:
//   vlib work
//   vlog -work work contest_audio_linkage_engine.v tb_contest_audio_linkage_engine.v
//   vsim -c work.tb_contest_audio_linkage_engine -do "run -all; quit -f"
// Icarus:
//   iverilog -g2001 -s tb_contest_audio_linkage_engine -o audio_sim \
//     contest_audio_linkage_engine.v tb_contest_audio_linkage_engine.v
//   vvp audio_sim
// +WAVES 可选生成 VCD（默认不生成庞大的时钟波形文件）。
// 必须出现 ALL TESTS PASSED 才算通过；任一 FAIL 或超时均失败。
// 已运行：Icarus Verilog -g2001，25 MHz 和 1 MHz 完整回归均通过。
// 默认回归检查 103118 个有效采样、21 次提示启动；100 ms 恰为 4800 个采样。
// 自检针对交付的默认配置。修改音效后，同步改期望频率/时长/增益。
// 仅模块仿真；未进行 TD 综合、顶层融合或实板验证。
module tb_contest_audio_linkage_engine;
    parameter integer TB_CLK_HZ=25000000;
    localparam integer FS=48000;
    localparam real HALF_PERIOD_NS=500000000.0/TB_CLK_HZ;
    reg clk,rst;
    reg image_toggle,period_toggle,auto_state;
    reg [1:0] image_idx,period_sel,vol;
    wire audio_valid,solo_valid;
    wire signed [23:0] audio_left,audio_right,solo_left,solo_right;

    contest_audio_linkage_engine #(.CLK_HZ(TB_CLK_HZ),.SAMPLE_RATE(FS),.BGM_ENABLE(1)) dut (
        .I_clk(clk),.I_rst(rst),
        .I_image_event_toggle(image_toggle),.I_image_event_idx(image_idx),
        .I_period_event_toggle(period_toggle),.I_period_sel(period_sel),
        .I_auto_state(auto_state),.I_vol(vol),
        .O_audio_valid(audio_valid),.O_audio_left(audio_left),.O_audio_right(audio_right)
    );
    // 相同事件、背景关闭：从最终 PCM 测提示频率和结束后的严格零采样。
    contest_audio_linkage_engine #(.CLK_HZ(TB_CLK_HZ),.SAMPLE_RATE(FS),.BGM_ENABLE(0)) solo (
        .I_clk(clk),.I_rst(rst),
        .I_image_event_toggle(image_toggle),.I_image_event_idx(image_idx),
        .I_period_event_toggle(period_toggle),.I_period_sel(period_sel),
        .I_auto_state(auto_state),.I_vol(vol),
        .O_audio_valid(solo_valid),.O_audio_left(solo_left),.O_audio_right(solo_right)
    );
    always #(HALF_PERIOD_NS) clk=~clk;

    task fail;
        input [1023:0] message;
        begin
            $display("FAIL at simulation time %0t: %0s",$time,message);
            $finish;
        end
    endtask
    task wait_samples;
        input integer count;
        integer j;
        begin
            for(j=0;j<count;j=j+1) begin @(posedge audio_valid); #2; end
        end
    endtask
    task reset_inputs;
        input integer volume;
        input integer initial_high;
        begin
            @(negedge clk);rst=1;
            image_toggle=(initial_high!=0);period_toggle=(initial_high!=0);
            auto_state=(initial_high!=0);image_idx=3;period_sel=2;vol=volume;
            repeat(12) @(negedge clk);
            #7;rst=0;
            repeat(10) @(negedge clk);
        end
    endtask
    task send_image;
        input [1:0] idx;
        begin
            // 总线与 toggle 在同一异步时刻更新，验证三/两级相对延迟。
            #137;image_idx=idx;image_toggle=~image_toggle;
        end
    endtask
    task send_period;
        input [1:0] sel;
        begin #173;period_sel=sel;period_toggle=~period_toggle;end
    endtask

    integer cycles,total_samples,ticks,starts,event_images,event_periods,event_autos;
    integer last_valid_cycle,gap,short_gaps,long_gaps;
    integer active_start_tick,last_duration,last_finished_tag;
    integer previous_state,previous_duck,old_tick;
    integer old_bgm_count,old_bgm_idx,bgm_transitions;
    reg previous_valid;
    integer previous_left,previous_right;
    integer bgm_previous_sample,bgm_measure_idx,bgm_crossings,bgm_first,bgm_last;
    integer bgm_checked;
    real measured_bgm,expected_bgm;

    function real bgm_frequency;
        input integer idx;
        begin
            case(idx)
                0:bgm_frequency=261.626; 1:bgm_frequency=329.628;
                2:bgm_frequency=391.995; default:bgm_frequency=523.251;
            endcase
        end
    endfunction

    // 全程检查采样、数据保持、双声道、包络步进及独立背景时轴。
    always @(posedge clk) begin
        old_tick=dut.sample_tick;
        old_bgm_count=dut.bgm_count;old_bgm_idx=dut.bgm_idx;
        #1;
        if(rst) begin
            cycles=0;last_valid_cycle=0;previous_valid=0;
            previous_state=0;previous_duck=32768;ticks=0;active_start_tick=0;
            previous_left=0;previous_right=0;
            bgm_previous_sample=0;bgm_measure_idx=0;bgm_crossings=0;bgm_first=0;bgm_last=0;
        end else begin
            cycles=cycles+1;
            if(old_tick) ticks=ticks+1;
            if(dut.image_event) event_images=event_images+1;
            if(dut.period_event) event_periods=event_periods+1;
            if(dut.auto_event) event_autos=event_autos+1;
            if(dut.sfx_start) begin starts=starts+1;active_start_tick=ticks;end
            if(previous_state!=0 && dut.sfx_state==0) begin
                last_duration=ticks-active_start_tick;last_finished_tag=dut.sfx_tag;
                if(dut.sfx_env!==0) fail("SFX did not finish with zero envelope");
            end
            previous_state=dut.sfx_state;
            if(dut.duck_gain<8192 || dut.duck_gain>32768) fail("Ducking gain out of range");
            if(dut.duck_gain>previous_duck+64 || dut.duck_gain+64<previous_duck)
                fail("Ducking changed abruptly instead of ramping");
            previous_duck=dut.duck_gain;
            if(old_tick && dut.BGM_ENABLE!=0) begin
                if(old_bgm_count==14399) begin
                    if(dut.bgm_count!==0 || dut.bgm_idx!==((old_bgm_idx+1)%4))
                        fail("BGM note boundary/sequence is wrong");
                    bgm_transitions=bgm_transitions+1;
                end else if(dut.bgm_count!==old_bgm_count+1)
                    fail("BGM timeline paused or skipped during a cue");
            end
            if(audio_valid!==solo_valid) fail("BGM_ENABLE changed the PCM cadence");
            if(audio_valid) begin
                if(previous_valid) fail("audio_valid is wider than one clock");
                if(last_valid_cycle!=0) begin
                    gap=cycles-last_valid_cycle;
                    if(gap!=TB_CLK_HZ/FS && gap!=(TB_CLK_HZ+FS-1)/FS)
                        fail("PCM interval is not floor/ceil(CLK_HZ/48000)");
                    if(gap==TB_CLK_HZ/FS) short_gaps=short_gaps+1;
                    else long_gaps=long_gaps+1;
                end
                last_valid_cycle=cycles;total_samples=total_samples+1;
                if((^audio_left)===1'bx || (^solo_left)===1'bx) fail("Unknown PCM sample");
                if(audio_left!==audio_right || solo_left!==solo_right) fail("L/R differ");
                // 监测独立背景分量的过零，不让并行提示音污染背景估频。
                if(dut.bgm_idx!=bgm_measure_idx) begin
                    if(bgm_crossings>=4) begin
                        measured_bgm=48000.0*(bgm_crossings-1)/(bgm_last-bgm_first);
                        expected_bgm=bgm_frequency(bgm_measure_idx);
                        if(measured_bgm<expected_bgm*0.98 || measured_bgm>expected_bgm*1.02)
                            fail("BGM frequency error exceeds 2 percent");
                        bgm_checked=bgm_checked+1;
                    end
                    bgm_measure_idx=dut.bgm_idx;bgm_crossings=0;
                    bgm_first=0;bgm_last=0;bgm_previous_sample=0;
                end
                if(dut.bgm_count>960 && dut.bgm_count<12000) begin
                    if(bgm_previous_sample<=0 && $signed(dut.bgm_pcm)>0) begin
                        if(bgm_crossings==0) bgm_first=total_samples;
                        bgm_last=total_samples;bgm_crossings=bgm_crossings+1;
                    end
                end
                bgm_previous_sample=$signed(dut.bgm_pcm);
            end else if(audio_left!==previous_left || audio_right!==previous_right)
                fail("PCM changed outside audio_valid");
            previous_valid=audio_valid;previous_left=audio_left;previous_right=audio_right;
        end
    end

    // 2048 个有效样本内，按首末正向过零间隔估频，避免整数周期计数误差。
    task check_frequency;
        input real target;
        integer n,crossings,first_cross,last_cross,previous_sample;
        real observed;
        begin
            crossings=0;first_cross=0;last_cross=0;previous_sample=0;
            wait_samples(240); // 起音之后开始测量
            previous_sample=solo_left;
            for(n=0;n<2048;n=n+1) begin
                @(posedge solo_valid);#2;
                if(previous_sample<=0 && solo_left>0) begin
                    if(crossings==0) first_cross=n;
                    last_cross=n;crossings=crossings+1;
                end
                previous_sample=solo_left;
            end
            if(crossings<4) fail("Too few zero crossings / missing SFX");
            observed=48000.0*(crossings-1)/(last_cross-first_cross);
            if(observed<target*0.98 || observed>target*1.02) begin
                $display("expected=%0.3f Hz measured=%0.3f Hz",target,observed);
                fail("SFX frequency error exceeds 2 percent");
            end
            if(dut.duck_gain!==16'd8192) fail("BGM did not duck to 25 percent");
            $display("  frequency PASS: expected %0.3f Hz, measured %0.3f Hz",target,observed);
        end
    endtask
    task finish_single;
        input integer expected_samples;
        input integer before_starts;
        integer j;
        begin
            wait(dut.sfx_state==0);#2;
            if(last_duration!=expected_samples) begin
                $display("expected duration=%0d measured=%0d",expected_samples,last_duration);
                fail("SFX duration is wrong");
            end
            wait_samples(400);
            if(dut.duck_gain!==16'd32768) fail("BGM gain did not recover within 8.34 ms");
            for(j=0;j<32;j=j+1) begin
                wait_samples(1);
                if(solo_left!==24'sd0 || solo_right!==24'sd0) fail("SFX tail is not exactly zero");
            end
            if(starts!=before_starts+1) fail("Event produced missing/duplicate cue");
        end
    endtask
    task image_case;
        input [1:0] idx;
        input real hz;
        integer before_starts,before_events;
        begin
            before_starts=starts;before_events=event_images;
            send_image(idx);
            @(posedge dut.sfx_start);#2;
            if(dut.sfx_tag!=={2'b00,idx}) fail("Wrong image payload captured");
            check_frequency(hz);finish_single(5760,before_starts);
            if(event_images!=before_events+1) fail("Image toggle was not detected exactly once");
        end
    endtask
    task period_case;
        input [1:0] sel;
        input real hz;
        integer before_starts,before_events,tag;
        begin
            before_starts=starts;before_events=event_periods;
            tag=(sel<2)?(4+sel):6;
            send_period(sel);
            @(posedge dut.sfx_start);#2;
            if(dut.sfx_tag!==tag) fail("Wrong period payload captured");
            check_frequency(hz);finish_single(3840,before_starts);
            if(event_periods!=before_events+1) fail("Period toggle was not detected exactly once");
        end
    endtask

    reg signed [23:0] volume_reference [0:1023];
    integer i,j,before_starts,before_events,begin_cycle,delta_cycles;
    integer expected_sample,nonzero_count,preempt_wait;
    real measured;
    initial begin
        clk=0;rst=1;image_toggle=0;period_toggle=0;auto_state=0;
        image_idx=0;period_sel=0;vol=3;
        cycles=0;total_samples=0;ticks=0;starts=0;
        event_images=0;event_periods=0;event_autos=0;
        short_gaps=0;long_gaps=0;last_duration=0;last_finished_tag=0;
        bgm_transitions=0;bgm_checked=0;
        if($test$plusargs("WAVES")) begin
            $dumpfile("tb_contest_audio_linkage_engine.vcd");
            $dumpvars(0,tb_contest_audio_linkage_engine);
        end
        $display("Running audio regression: clock=%0d Hz, PCM=48000 Hz",TB_CLK_HZ);

        $display("T01: reset with initial toggles/state HIGH, no false cue");
        reset_inputs(3,1);before_starts=starts;
        wait_samples(600);
        if(starts!=before_starts || dut.sfx_state!=0 || dut.pending)
            fail("Initial nonzero state triggered a false cue");
        if(event_images!=0 || event_periods!=0 || event_autos!=0)
            fail("CDC reset baseline created an event");
        if(solo_left!==0) fail("BGM disabled is not silent at startup");
        nonzero_count=0;
        for(i=0;i<256;i=i+1) begin
            wait_samples(1);if(audio_left!=0) nonzero_count=nonzero_count+1;
        end
        if(nonzero_count<200) fail("Default background is missing");

        $display("T06/T07: 100 ms mute, exact sample rate, no cadence interruption");
        vol=0;wait_samples(4);begin_cycle=cycles;
        for(i=0;i<4800;i=i+1) begin
            wait_samples(1);
            if(audio_left!==0 || audio_right!==0 || solo_left!==0) fail("Mute is not zero PCM");
        end
        delta_cycles=cycles-begin_cycle;
        if(delta_cycles!=TB_CLK_HZ/10) fail("4800 samples are not exactly 100 ms");
        if(short_gaps==0 || long_gaps==0) fail("Fractional divider did not alternate intervals");
        $display("  4800 sample intervals = %0d clocks PASS",delta_cycles);

        reset_inputs(3,0);wait_samples(600);
        $display("T02/T10: four image tones, asynchronous payload+toggle");
        image_case(0,523.250);image_case(1,587.330);
        image_case(2,659.250);image_case(3,698.460);
        $display("T03: period tones, including reserved selector 3 -> 4-second tone");
        period_case(0,329.630);period_case(1,523.250);
        period_case(2,783.990);period_case(3,783.990);
        $display("T04/T05: auto ON/OFF, durations, ducking and recovery");
        before_starts=starts;before_events=event_autos;
        #211;auto_state=1;@(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=7) fail("Auto ON selection failed");
        check_frequency(1046.500);finish_single(4800,before_starts);
        if(event_autos!=before_events+1) fail("Auto ON event count is wrong");
        before_starts=starts;before_events=event_autos;
        #193;auto_state=0;@(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=8) fail("Auto OFF selection failed");
        check_frequency(440.000);finish_single(7200,before_starts);
        if(event_autos!=before_events+1) fail("Auto OFF event count is wrong");
        // 前述短提示累计可能不足一整轮 1.2 秒，等到背景第 4 步自然结束。
        wait(bgm_checked>=4);#2;
        if(bgm_transitions<4) fail("Full BGM melody was not verified");
        $display("  four BGM notes and uninterrupted note timeline PASS");

        $display("T09: simultaneous AUTO > PERIOD > IMAGE, no stale replay");
        before_starts=starts;
        #157;image_idx=2;period_sel=1;
        image_toggle=~image_toggle;period_toggle=~period_toggle;auto_state=1;
        @(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=7) fail("AUTO did not win simultaneous events");
        wait(dut.sfx_state==0);wait_samples(500);
        if(starts!=before_starts+1 || dut.pending) fail("Lower simultaneous event was replayed");
        before_starts=starts;
        #179;image_idx=0;period_sel=0;
        image_toggle=~image_toggle;period_toggle=~period_toggle;
        @(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=4) fail("PERIOD did not win over IMAGE");
        // 忙时低级图片音不得中断周期音，也不得在其结束后补播。
        wait_samples(500);send_image(3);
        wait(dut.sfx_state==0);wait_samples(500);
        if(starts!=before_starts+1) fail("Lower-priority event interrupted/queued behind active cue");

        $display("T09 extension: higher/equal priority soft preemption and latest payload");
        send_image(0);@(posedge dut.sfx_start);wait_samples(700);
        before_starts=starts;send_period(2);
        // 在 4 ms 释放期间再来一个更高优先级事件，它应替换待播周期音。
        wait_samples(24);#113;auto_state=0;
        preempt_wait=ticks;
        @(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=8) fail("Highest pending event did not replace lower pending event");
        if(ticks-preempt_wait<150 || ticks-preempt_wait>200)
            fail("Preemption did not finish the short release before starting");
        wait(dut.sfx_state==0);wait_samples(500);
        if(starts!=before_starts+1) fail("Preemption produced duplicate playback");
        send_image(1);@(posedge dut.sfx_start);wait_samples(500);
        before_starts=starts;send_image(3);
        @(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=3) fail("Equal-priority retrigger did not use latest payload");
        check_frequency(698.460);finish_single(5760,before_starts);

        // 与 sample_tick 同拍消费的 CDC 事件：toggle 到第三级后比较，再消费。
        $display("T10 boundary: event arrives on the sample-consumption edge");
        wait(dut.sample_count==20);@(negedge clk);
        // 找到距当前分频终点 3 拍的位置；本次任意分频长短都适用。
        wait(dut.sample_count==dut.DIV_BASE-4+dut.long_interval);
        @(negedge clk);#3;image_idx=2;image_toggle=~image_toggle;
        before_starts=starts;
        @(posedge dut.sfx_start);#2;
        if(dut.sfx_tag!=2) fail("Sample-boundary event lost its payload");
        wait(dut.sfx_state==0);wait_samples(500);
        if(starts!=before_starts+1) fail("Sample-boundary event lost or duplicated");

        $display("T08: exact post-mix volume ratios by deterministic PCM replay");
        // 同一复位/事件/背景时轴，先保存满音量混音，再比对 50/75/0%。
        for(j=3;j>=0;j=j-1) begin
            reset_inputs(j,0);wait_samples(600);send_image(2);
            @(posedge dut.sfx_start);wait_samples(240);
            nonzero_count=0;
            for(i=0;i<1024;i=i+1) begin
                wait_samples(1);
                if(j==3) volume_reference[i]=audio_left;
                else begin
                    case(j)
                        0:expected_sample=0;
                        1:expected_sample=$signed(volume_reference[i]) >>> 1;
                        2:expected_sample=($signed(volume_reference[i])*3) >>> 2;
                        default:expected_sample=volume_reference[i];
                    endcase
                    if(audio_left!==expected_sample) begin
                        $display("volume=%0d sample=%0d expected=%0d got=%0d",j,i,expected_sample,audio_left);
                        fail("Master volume scaling mismatch");
                    end
                    if(j==0 && solo_left!==0) fail("Muted SFX is not zero");
                end
                if(audio_left!=0) nonzero_count=nonzero_count+1;
            end
            if(j!=0 && nonzero_count<1000) fail("Missing nonzero volume test samples");
        end

        $display("Overflow: stress the actual widened mixer and final saturation");
        // 默认混音峰值仅约 75%，不会自然触发限幅；用 TB force 注入边界分量。
        // force 仅存在于 testbench，验证生产 RTL 的混音/总音量/限幅整条路径。
        vol=3;
        force dut.sfx_pcm=24'sh7fffff;
        force dut.bgm_pcm=24'sh7fffff;
        wait_samples(8);
        if(audio_left!==24'sh7fffff) fail("Positive overflow wrapped instead of saturating");
        force dut.sfx_pcm=24'sh800000;
        force dut.bgm_pcm=24'sh800000;
        wait_samples(8);
        if(audio_left!==24'sh800000) fail("Negative overflow wrapped instead of saturating");
        vol=0;wait_samples(8);
        if(audio_left!==0) fail("Mute failed during overload");
        release dut.sfx_pcm;release dut.bgm_pcm;

        $display("Reset during playback: flush PCM pipeline and re-baseline HIGH inputs");
        reset_inputs(3,1);before_starts=starts;wait_samples(1000);
        if(starts!=before_starts || solo_left!==0 || dut.sfx_state!=0)
            fail("Reset during playback did not clear/re-baseline safely");
        $display("ALL TESTS PASSED: T01-T10, BGM, CDC, priority, fractional 48 kHz, mute, volume, saturation.");
        $display("Checked valid samples=%0d, cue starts=%0d; no TD/board validation claimed.",total_samples,starts);
        $finish;
    end
    initial begin
        #6000000000;
        fail("Watchdog timeout: missing valid pulse or stuck event/state");
    end
endmodule

`timescale 1ns/1ps
// V08 控制通路 CDC，Verilog-2001。sd_clk=100MHz，video_clk=25MHz。
// 共同复位，异步置位、各域同步释放；源 LBA 从请求到确认期间保持。
// pixel toggle 最快每 40ns 翻转一次，目的域每 10ns 采样，禁止改变该频率约定。
module contest_scaler_cdc (
    input wire sd_clk, video_clk, rst,
    input wire io_reset_sd, // 仅事务恢复；finish同步器仍只接受系统rst
    input wire load_start_sd,
    input wire [31:0] load_sector_sd,
    output wire load_ready_sd,
    output reg load_overrun_sd,
    input wire bridge_ready_v,
    output reg load_start_v,
    output reg [31:0] load_sector_v,
    input wire pixel_en_v,
    output reg pixel_inc_sd,
    input wire bridge_done_v, bridge_loaded_v,
    output reg source_done_sd, source_error_sd,
    input wire finish_toggle_mem,
    output wire finish_pulse_v
);
    (* ASYNC_REG="TRUE" *) reg [1:0] rst_sd_sync, rst_v_sync;
    wire transaction_reset=rst || io_reset_sd;
    always @(posedge sd_clk or posedge transaction_reset)
        if(transaction_reset) rst_sd_sync<=2'b11; else rst_sd_sync<={rst_sd_sync[0],1'b0};
    always @(posedge video_clk or posedge transaction_reset)
        if(transaction_reset) rst_v_sync<=2'b11; else rst_v_sync<={rst_v_sync[0],1'b0};
    wire rst_sd=rst_sd_sync[1], rst_v=rst_v_sync[1];
    reg request_toggle, acknowledge_toggle;
    reg [31:0] sector_hold;
    (* ASYNC_REG="TRUE" *) reg [1:0] request_sync_v, acknowledge_sync_sd;
    reg pixel_toggle_v, done_toggle_v, done_ok_hold;
    (* ASYNC_REG="TRUE" *) reg [2:0] pixel_sync_sd, done_sync_sd;
    (* ASYNC_REG="TRUE" *) reg [2:0] finish_sync_v;
    assign load_ready_sd=!rst_sd && (request_toggle==acknowledge_sync_sd[1]);
    wire done_pulse_sd=done_sync_sd[2]^done_sync_sd[1];
    assign finish_pulse_v=!rst_v && (finish_sync_v[2]^finish_sync_v[1]);

    always @(posedge sd_clk or posedge rst_sd) begin
        if(rst_sd) begin
            request_toggle<=0;sector_hold<=0;acknowledge_sync_sd<=0;
            pixel_sync_sd<=0;done_sync_sd<=0;load_overrun_sd<=0;
            pixel_inc_sd<=0;source_done_sd<=0;source_error_sd<=0;
        end else begin
            acknowledge_sync_sd<={acknowledge_sync_sd[0],acknowledge_toggle};
            pixel_sync_sd<={pixel_sync_sd[1:0],pixel_toggle_v};
            done_sync_sd<={done_sync_sd[1:0],done_toggle_v};
            // 目的域寄存事件，隔开toggle译码与管理器32位计数/提交判断路径。
            pixel_inc_sd<=pixel_sync_sd[2]^pixel_sync_sd[1];
            source_done_sd<=done_pulse_sd && done_ok_hold;
            source_error_sd<=done_pulse_sd && !done_ok_hold;
            load_overrun_sd<=0;
            if(load_start_sd) begin
                if(load_ready_sd) begin
                    sector_hold<=load_sector_sd;request_toggle<=~request_toggle;
                end else load_overrun_sd<=1;
            end
        end
    end
    always @(posedge video_clk or posedge rst_v) begin
        if(rst_v) begin
            request_sync_v<=0;acknowledge_toggle<=0;load_start_v<=0;load_sector_v<=0;
            pixel_toggle_v<=0;done_toggle_v<=0;done_ok_hold<=0;
        end else begin
            request_sync_v<={request_sync_v[0],request_toggle};
            load_start_v<=0;
            // 请求不丢弃：即使桥接暂时不 ready，也一直挂起至可以接受。
            if(request_sync_v[1]!=acknowledge_toggle && bridge_ready_v) begin
                load_sector_v<=sector_hold;load_start_v<=1;
                acknowledge_toggle<=request_sync_v[1];
            end
            if(pixel_en_v) pixel_toggle_v<=~pixel_toggle_v;
            if(bridge_done_v) begin
                done_ok_hold<=bridge_loaded_v;done_toggle_v<=~done_toggle_v;
            end
        end
    end
    // 完成 toggle 来自 mem 域，只能随系统复位清零；桥接局部恢复不能清零
    // 这个同步器，否则 mem 仍为 1 时会伪造一次完成事件。
    always @(posedge video_clk or posedge rst)
        if(rst) finish_sync_v<=0;
        else finish_sync_v<={finish_sync_v[1:0],finish_toggle_mem};
endmodule

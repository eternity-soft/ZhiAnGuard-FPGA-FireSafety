`timescale 1ns/1ps
// 完整淡入淡出：手动与自动均为15帧淡出+15帧淡入，约0.5秒。
// 发布者先稳定 disp_idx_new 并翻转请求，直到转场结束的ACK返回才可再改目标。
// 目标双级同步，请求三级同步，避免任意四缓存跳转时将多位索引读成中间值。
// 淡出到黑以后必须等待 SDRAM 读引擎确认目标缓存，再开始淡入。
module my_fade #(parameter [7:0] FADE_FRAMES=8'd15)(
    input wire clk,rst,de_in,vs_in,
    input wire [23:0] rgb_in,
    input wire [1:0] disp_idx_new,
    input wire display_req_toggle,
    input wire read_bank_valid,
    input wire [1:0] read_bank_active,
    output reg display_ack_toggle,
    output wire [1:0] disp_idx_disp,
    output wire [23:0] rgb_out,
    output wire [7:0] fade_level,
    output wire fade_active
);
localparam [1:0] S_IDLE=0,S_OUT=1,S_WAIT_READ=2,S_IN=3;
localparam [7:0] N=(FADE_FRAMES==0)?8'd1:FADE_FRAMES;
localparam [7:0] STEP=(255+N-1)/N;
reg [1:0] state,buf_disp,buf_target,buf_s1,buf_s2;
reg [2:0] req_sync;
reg active_req_toggle;
reg [7:0] fade_cnt,frame_cnt;
reg vs_d1,vs_d2;
wire frame_edge=vs_d2 && !vs_d1;
always @(posedge clk) begin
    if(rst) begin
        state<=S_IDLE;buf_disp<=0;buf_target<=0;buf_s1<=0;buf_s2<=0;
        req_sync<=0;active_req_toggle<=0;display_ack_toggle<=0;
        fade_cnt<=255;frame_cnt<=0;vs_d1<=0;vs_d2<=0;
    end else begin
        buf_s1<=disp_idx_new;buf_s2<=buf_s1;
        req_sync<={req_sync[1:0],display_req_toggle};
        vs_d1<=vs_in;vs_d2<=vs_d1;
        case(state)
            S_IDLE: begin
                fade_cnt<=255;frame_cnt<=0;
                if(req_sync[2]!=display_ack_toggle) begin
                    if(buf_s2==buf_disp) display_ack_toggle<=req_sync[2];
                    else begin
                        active_req_toggle<=req_sync[2];buf_target<=buf_s2;state<=S_OUT;
                    end
                end
            end
            S_OUT: if(frame_edge) begin
                if(frame_cnt==N-1'b1) begin
                    // buf_disp changes only while fully black.  The video request
                    // logic sees this new bank on the next frame request; do not
                    // expose its FIFO until the memory-domain ACK returns.
                    fade_cnt<=0;frame_cnt<=0;buf_disp<=buf_target;state<=S_WAIT_READ;
                end else begin
                    fade_cnt<=(fade_cnt<=STEP)?8'd0:fade_cnt-STEP;
                    frame_cnt<=frame_cnt+1'b1;
                end
            end
            S_WAIT_READ: begin
                fade_cnt<=0;frame_cnt<=0;
                // Sampling only at a frame edge also gives the newly selected
                // FIFO one full frame interval to refill before fade-in starts.
                if(frame_edge && read_bank_valid && read_bank_active==buf_target)
                    state<=S_IN;
            end
            S_IN: if(frame_edge) begin
                if(frame_cnt==N-1'b1) begin
                    fade_cnt<=255;frame_cnt<=0;state<=S_IDLE;
                    display_ack_toggle<=active_req_toggle;
                end else begin
                    fade_cnt<=(fade_cnt>=255-STEP)?8'd255:fade_cnt+STEP;
                    frame_cnt<=frame_cnt+1'b1;
                end
            end
            default: begin state<=S_IDLE;fade_cnt<=255;end
        endcase
    end
end
wire [15:0] r_full={8'd0,rgb_in[23:16]}*{8'd0,fade_cnt};
wire [15:0] g_full={8'd0,rgb_in[15:8]}*{8'd0,fade_cnt};
wire [15:0] b_full={8'd0,rgb_in[7:0]}*{8'd0,fade_cnt};
assign rgb_out=!de_in?24'd0:((fade_cnt==255)?rgb_in:{r_full[15:8],g_full[15:8],b_full[15:8]});
assign fade_level=fade_cnt;
assign fade_active=(state!=S_IDLE);
assign disp_idx_disp=buf_disp;
endmodule

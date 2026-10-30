`timescale 1ns/1ps
// 亮度调节模块：RGB888 按亮度档位缩放（移位近似），饱和截断到 8bit
// 档位：0=暗(×0.50) 1=较暗(×0.75) 2=标准(×1.00) 3=亮(×1.25)
// 纯组合输出，不改变时序关系（与 my_fade 输出对齐使用）
module my_brightness (
    input  wire [23:0] rgb_in,   // 24bit RGB888（来自 my_fade 输出）
    input  wire [1:0]  br_sel,   // 亮度档（来自拨码 SW3/SW4）
    output wire [23:0] rgb_out   // 调亮后的 RGB
);
    function [7:0] scale_ch;
        input [7:0] v;
        input [1:0] sel;
        integer t;
        begin
            case(sel)
                2'd0: t = v >> 1;            // ×0.50
                2'd1: t = v - (v >> 2);      // ×0.75
                2'd2: t = v;                 // ×1.00
                default: t = v + (v >> 2);   // ×1.25
            endcase
            scale_ch = (t > 255) ? 8'd255 : t[7:0];
        end
    endfunction

    assign rgb_out = {scale_ch(rgb_in[23:16], br_sel),
                      scale_ch(rgb_in[15:8],  br_sel),
                      scale_ch(rgb_in[7:0],   br_sel)};
endmodule

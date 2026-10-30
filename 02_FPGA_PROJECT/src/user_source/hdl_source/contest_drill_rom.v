// 火灾模拟模块字模/文本 ROM（由 gen_drill_font.py 生成，勿手改）。
module contest_drill_rom (
    input  wire        I_clk,
    input  wire [9:0]  I_text_addr,
    output reg  [7:0]  O_text_data,
    input  wire [9:0]  I_font_addr,
    output reg  [15:0] O_font_data
);
    reg [7:0]  text_mem [0:767];
    reg [15:0] font_mem [0:607];

    initial begin
        $readmemh("drill_text.hex", text_mem);
        $readmemh("drill_font.hex", font_mem);
    end

    always @(posedge I_clk) O_text_data <= text_mem[I_text_addr];
    always @(posedge I_clk) O_font_data <= font_mem[I_font_addr];
endmodule

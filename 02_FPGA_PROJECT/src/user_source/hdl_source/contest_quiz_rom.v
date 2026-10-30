`timescale 1ns/1ps
//=============================================================================
// contest_quiz_rom.v
//-----------------------------------------------------------------------------
// Dedicated BRAM ROM for V25 Knowledge Quiz Interactive System.
// Stores screen character layouts (quiz_text.hex, 4096x8) and 16x16 Chinese/ASCII
// glyph bitmaps (quiz_font.hex, 4096x16).
// Inferred directly into Anlogic B9K Block RAM primitives with zero LUT logic.
//=============================================================================
module contest_quiz_rom (
    input  wire        I_clk,
    input  wire [11:0] I_text_addr,
    output reg  [7:0]  O_text_data,
    input  wire [11:0] I_font_addr,
    output reg  [15:0] O_font_data
);

    (* ram_style = "bram" *) reg [7:0]  text_mem [0:4095];
    (* ram_style = "bram" *) reg [15:0] font_mem [0:4095];

    initial begin
        $readmemh("quiz_text.hex", text_mem);
        $readmemh("quiz_font.hex", font_mem);
    end

    always @(posedge I_clk) begin
        O_text_data <= text_mem[I_text_addr];
    end

    always @(posedge I_clk) begin
        O_font_data <= font_mem[I_font_addr];
    end

endmodule

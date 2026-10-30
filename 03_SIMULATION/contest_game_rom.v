// contest_game_rom.v (20x15 Map, 32x32 Tiles)
module contest_game_rom (
    input  wire        I_clk,
    input  wire [11:0] I_tile_addr,
    output reg  [7:0]  O_tile_data,
    input  wire [10:0] I_sprite_addr,
    output reg  [7:0]  O_sprite_data,
    input  wire [8:0]  I_map_a_addr,
    output reg  [7:0]  O_map_a_data,
    input  wire [8:0]  I_map_b_addr,
    output reg  [7:0]  O_map_b_data,
    input  wire        I_map_b_wen,
    input  wire [8:0]  I_map_b_waddr,
    input  wire [7:0]  I_map_b_wdata,
    input  wire [9:0]  I_font_addr,
    output reg  [15:0] O_font_data
);
    reg [7:0]  tile_mem   [0:3199];   // 25 x 128 bytes
    reg [7:0]  sprite_mem [0:1535];   // 12 x 128 bytes
    reg [7:0]  map_mem    [0:299];    // 20 x 15 cells = 300 bytes
    reg [15:0] font_mem   [0:1023];   // 64 chars x 16 words

    initial begin
        $readmemh("game_tiles.hex",   tile_mem);
        $readmemh("game_sprites.hex", sprite_mem);
        $readmemh("game_map.hex",     map_mem);
        $readmemh("game_font.hex",    font_mem);
    end

    always @(posedge I_clk) begin
        O_tile_data   <= tile_mem[I_tile_addr];
        O_sprite_data <= sprite_mem[I_sprite_addr];
        O_map_a_data  <= map_mem[I_map_a_addr];
        O_font_data   <= font_mem[I_font_addr];
    end
    always @(posedge I_clk) begin
        if (I_map_b_wen) map_mem[I_map_b_waddr] <= I_map_b_wdata;
        O_map_b_data <= map_mem[I_map_b_addr];
    end
endmodule

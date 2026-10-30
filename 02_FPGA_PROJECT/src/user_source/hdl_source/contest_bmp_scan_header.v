`timescale 1ns/1ps
// V08扫描专用100MHz头解析器；在通用格式规则上增加赛题最小尺寸检查。
// 几何计算分拍，收满54字节后等待6拍流水稳定再发布结果。
// 数据流水寄存器无需复位；IDLE/COLLECT/WAIT保证未稳定数据不会发布。
module contest_bmp_scan_header #(
    parameter integer MIN_WIDTH  = 1,
    parameter integer MIN_HEIGHT = 1,
    parameter integer MAX_WIDTH  = 1280,
    parameter integer MAX_HEIGHT = 1024
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        abort,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_data,
    input  wire        s_last,
    output wire        ready,
    output wire        busy,
    output reg         done,
    output reg         o_format_valid,
    output wire        o_format_error,
    output reg  [3:0]  o_error_code,
    output reg  [15:0] o_width,
    output reg  [15:0] o_height,
    output reg         o_top_down,
    output reg  [31:0] file_size,
    output reg  [31:0] o_pixel_offset,
    output reg  [31:0] dib_size,
    output reg  [15:0] o_row_stride,
    output reg  [1:0]  row_padding,
    output reg  [31:0] pixel_bytes,
    output reg  [31:0] pixel_count
);
    localparam [1:0] IDLE=2'd0, COLLECT=2'd1, CHECK=2'd2, WAIT_CALC=2'd3;
    reg [2:0] settle_count;
    reg [1:0] state;
    reg [5:0] byte_index;
    reg [15:0] h_signature, h_planes, h_bpp;
    reg [31:0] h_file_size, h_reserved, h_offset, h_dib;
    reg [31:0] h_width, h_height, h_compression, h_image_size, h_colors;

    // Width and height are checked in their full signed 32-bit encoding before
    // narrowing. The widened arithmetic also checks the BMP 32-bit file limit.
    reg [31:0] abs_height;
    reg [17:0] rgb_row, stride_calc, padding_calc;
    reg [33:0] payload_calc;
    reg [31:0] count_calc;
    reg [63:0] header_end, data_end;
    reg header_extent_bad, data_extent_bad, image_size_bad;
    always @(posedge clk) begin
        abs_height <= h_height[31] ? (~h_height+32'd1) : h_height;
        rgb_row <= ({2'd0,h_width[15:0]} << 1)+{2'd0,h_width[15:0]};
        stride_calc <= (rgb_row+18'd3) & 18'h3fffc;
        payload_calc <= stride_calc * abs_height[15:0];
        count_calc <= h_width[15:0] * abs_height[15:0];
        header_end <= 64'd14+{32'd0,h_dib}+({32'd0,h_colors} << 2);
        data_end <= {32'd0,h_offset}+payload_calc;
        padding_calc <= stride_calc-rgb_row;
        // 宽比较结果单独寄存，避免比较/错误优先级/元数据使能串成100MHz长路径。
        // 最迟第五拍稳定，仍在六拍等待窗之内。
        header_extent_bad <= header_end > 64'h00000000ffffffff || {32'd0,h_offset} < header_end;
        data_extent_bad <= stride_calc > 18'd65535 || payload_calc > 64'h00000000ffffffff ||
                           data_end > 64'h00000000ffffffff || {32'd0,h_file_size} < data_end;
        image_size_bad <= h_image_size != 0 && {32'd0,h_image_size} != payload_calc;
    end
    reg [3:0] check_error;

    assign ready = (state == IDLE) && !rst && !abort;
    assign busy = (state != IDLE);
    assign s_ready = (state == COLLECT) && !rst && !abort;
    assign o_format_error = (o_error_code != 4'd0);

    always @* begin
        check_error = 4'd0;
        if (h_signature != 16'h4d42)
            check_error = 4'd2;
        else if (h_reserved != 32'd0)
            check_error = 4'd11;
        else if (h_dib != 32'd40 && h_dib != 32'd108 && h_dib != 32'd124)
            check_error = 4'd3;
        else if (h_planes != 16'd1)
            check_error = 4'd4;
        else if (h_bpp != 16'd24)
            check_error = 4'd5;
        else if (h_compression != 32'd0)
            check_error = 4'd6;
        else if (h_width == 0 || h_width[31] || h_width > 32'd65535 ||
                 h_width < MIN_WIDTH || h_width > MAX_WIDTH || abs_height < MIN_HEIGHT ||
                 h_height == 32'h80000000 || abs_height > 32'd65535 ||
                 abs_height > MAX_HEIGHT)
            check_error = 4'd7;
        else if (header_extent_bad)
            check_error = 4'd8;
        else if (data_extent_bad)
            check_error = 4'd9;
        else if (image_size_bad)
            check_error = 4'd10;
    end

    // Clear result separately from the private header registers so rejected
    // input can never be mistaken for valid output metadata.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            byte_index <= 0;
            settle_count <= 0;
            done <= 0;
            o_format_valid <= 0;
            o_error_code <= 0;
            o_width <= 0;
            o_height <= 0;
            o_top_down <= 0;
            file_size <= 0;
            o_pixel_offset <= 0;
            dib_size <= 0;
            o_row_stride <= 0;
            row_padding <= 0;
            pixel_bytes <= 0;
            pixel_count <= 0;
            h_signature <= 0;
            h_file_size <= 0;
            h_reserved <= 0;
            h_offset <= 0;
            h_dib <= 0;
            h_width <= 0;
            h_height <= 0;
            h_planes <= 0;
            h_bpp <= 0;
            h_compression <= 0;
            h_image_size <= 0;
            h_colors <= 0;
        end else begin
            done <= 0;
            if (abort || (start && ready)) begin
                state <= abort ? IDLE : COLLECT;
                byte_index <= 0;
                settle_count <= 0;
                o_format_valid <= 0;
                o_error_code <= 0;
                o_width <= 0;
                o_height <= 0;
                o_top_down <= 0;
                file_size <= 0;
                o_pixel_offset <= 0;
                dib_size <= 0;
                o_row_stride <= 0;
                row_padding <= 0;
                pixel_bytes <= 0;
                pixel_count <= 0;
                h_signature <= 0;
                h_file_size <= 0;
                h_reserved <= 0;
                h_offset <= 0;
                h_dib <= 0;
                h_width <= 0;
                h_height <= 0;
                h_planes <= 0;
                h_bpp <= 0;
                h_compression <= 0;
                h_image_size <= 0;
                h_colors <= 0;
            end else if (state == COLLECT && s_valid && s_ready) begin
                case (byte_index)
                    0: h_signature[7:0] <= s_data;
                    1: h_signature[15:8] <= s_data;
                    2: h_file_size[7:0] <= s_data;
                    3: h_file_size[15:8] <= s_data;
                    4: h_file_size[23:16] <= s_data;
                    5: h_file_size[31:24] <= s_data;
                    6: h_reserved[7:0] <= s_data;
                    7: h_reserved[15:8] <= s_data;
                    8: h_reserved[23:16] <= s_data;
                    9: h_reserved[31:24] <= s_data;
                    10: h_offset[7:0] <= s_data;
                    11: h_offset[15:8] <= s_data;
                    12: h_offset[23:16] <= s_data;
                    13: h_offset[31:24] <= s_data;
                    14: h_dib[7:0] <= s_data;
                    15: h_dib[15:8] <= s_data;
                    16: h_dib[23:16] <= s_data;
                    17: h_dib[31:24] <= s_data;
                    18: h_width[7:0] <= s_data;
                    19: h_width[15:8] <= s_data;
                    20: h_width[23:16] <= s_data;
                    21: h_width[31:24] <= s_data;
                    22: h_height[7:0] <= s_data;
                    23: h_height[15:8] <= s_data;
                    24: h_height[23:16] <= s_data;
                    25: h_height[31:24] <= s_data;
                    26: h_planes[7:0] <= s_data;
                    27: h_planes[15:8] <= s_data;
                    28: h_bpp[7:0] <= s_data;
                    29: h_bpp[15:8] <= s_data;
                    30: h_compression[7:0] <= s_data;
                    31: h_compression[15:8] <= s_data;
                    32: h_compression[23:16] <= s_data;
                    33: h_compression[31:24] <= s_data;
                    34: h_image_size[7:0] <= s_data;
                    35: h_image_size[15:8] <= s_data;
                    36: h_image_size[23:16] <= s_data;
                    37: h_image_size[31:24] <= s_data;
                    46: h_colors[7:0] <= s_data;
                    47: h_colors[15:8] <= s_data;
                    48: h_colors[23:16] <= s_data;
                    49: h_colors[31:24] <= s_data;
                    default: ; // resolutions and biClrImportant are not used
                endcase
                if (byte_index == 6'd53) begin
                    state <= WAIT_CALC;
                    settle_count <= 0;
                end else if (s_last) begin
                    state <= IDLE;
                    o_error_code <= 4'd1;
                    done <= 1;
                end else begin
                    byte_index <= byte_index + 6'd1;
                end
            end else if (state == WAIT_CALC) begin
                if(settle_count==5) state<=CHECK;
                else settle_count<=settle_count+1'b1;
            end else if (state == CHECK) begin
                state <= IDLE;
                done <= 1;
                o_error_code <= check_error;
                if (check_error == 0) begin
                    o_format_valid <= 1;
                    o_width <= h_width[15:0];
                    o_height <= abs_height[15:0];
                    o_top_down <= h_height[31];
                    file_size <= h_file_size;
                    o_pixel_offset <= h_offset;
                    dib_size <= h_dib;
                    o_row_stride <= stride_calc[15:0];
                    row_padding <= padding_calc[1:0];
                    pixel_bytes <= payload_calc[31:0];
                    pixel_count <= count_calc[31:0];
                end
            end
        end
    end
endmodule

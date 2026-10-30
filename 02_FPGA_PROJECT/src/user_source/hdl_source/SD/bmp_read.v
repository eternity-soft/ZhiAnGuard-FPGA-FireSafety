`timescale 1ns/1ps
module bmp_read #(
    parameter integer MIN_WIDTH=1,
    parameter integer MIN_HEIGHT=1,
    parameter integer MAX_WIDTH=1280,
    parameter integer MAX_HEIGHT=1024,
    // Read the FAT32 BPB first and begin the raw BMP scan at the first data
    // sector.  Invalid/non-FAT32 media automatically falls back to the legacy
    // scan_start_sector path, so existing cards remain usable.
    parameter integer FAST_FAT32_START=1
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam [3:0] ST_IDLE        = 4'd0;
localparam [3:0] ST_SCAN        = 4'd1;
localparam [3:0] ST_LOAD_HDR    = 4'd2;
localparam [3:0] ST_LOAD_WAIT   = 4'd3;
localparam [3:0] ST_LOAD_DATA   = 4'd4;
localparam [3:0] ST_SCAN_EVAL   = 4'd5;
localparam [3:0] ST_PROBE0      = 4'd6;
localparam [3:0] ST_PROBE0_EVAL = 4'd7;
localparam [3:0] ST_PROBE1      = 4'd8;
localparam [3:0] ST_PROBE1_EVAL = 4'd9;

reg [3:0]  state;
reg [9:0]  rd_cnt;

// FAT32 boot locator.  Only the small BPB/MBR fields required to calculate
// first_data_sector are retained; no directory or FAT table is stored.
reg [9:0]  probe_count;
reg [15:0] probe_bytes_per_sector;
reg [7:0]  probe_sectors_per_cluster;
reg [15:0] probe_reserved_sectors;
reg [7:0]  probe_num_fats;
reg [31:0] probe_fat_size;
reg [15:0] probe_signature;
reg [7:0]  probe_partition_type;
reg [31:0] probe_partition_start;
reg [31:0] probe_partition_base;
wire probe_bpb_valid=(probe_signature==16'haa55) &&
                     (probe_bytes_per_sector==16'd512) &&
                     (probe_sectors_per_cluster!=0) &&
                     ((probe_sectors_per_cluster & (probe_sectors_per_cluster-1'b1))==0) &&
                     (probe_reserved_sectors!=0) &&
                     ((probe_num_fats==1)||(probe_num_fats==2)) &&
                     (probe_fat_size!=0);
wire probe_mbr_valid=(probe_signature==16'haa55) &&
                     ((probe_partition_type==8'h0b)||(probe_partition_type==8'h0c)) &&
                     (probe_partition_start!=0);
wire [31:0] probe_fat_area=(probe_num_fats==2) ?
                           (probe_fat_size<<1) : probe_fat_size;
wire [32:0] probe_data_start_wide={1'b0,probe_partition_base}+
                                  {17'd0,probe_reserved_sectors}+
                                  {1'b0,probe_fat_area};
wire [31:0] probe_data_start=probe_data_start_wide[31:0];

wire [31:0] file_len;
wire [31:0] pixel_offset;
wire [15:0] width;
wire [15:0] height;
wire top_down;
wire [15:0] row_stride;
wire [31:0] pixel_bytes;
wire header_match;
wire header_parser_ready;
wire header_start=((state==ST_SCAN)||(state==ST_LOAD_HDR)) && !sd_sec_read;
contest_bmp_scan_header #(
    .MIN_WIDTH(MIN_WIDTH),.MIN_HEIGHT(MIN_HEIGHT),
    .MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)
) u_contest_bmp_scan_header(
    .clk(clk),.rst(rst),.start(header_start),.abort(1'b0),
    .s_valid(((state==ST_SCAN)||(state==ST_LOAD_HDR)) &&
             sd_sec_read_data_valid && rd_cnt<54),
    .s_ready(header_parser_ready),.s_data(sd_sec_read_data),.s_last(rd_cnt==53),
    .ready(),.busy(),.done(),.o_format_valid(header_match),
    .o_format_error(),.o_error_code(),.o_width(width),.o_height(height),
    .o_top_down(top_down),.file_size(file_len),.o_pixel_offset(pixel_offset),
    .dib_size(),.o_row_stride(row_stride),.row_padding(),
    .pixel_bytes(pixel_bytes),.pixel_count()
);

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;
reg [15:0] row_byte_index;

wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
wire [32:0] next_scan_sector_wide={1'b0,scan_sector}+{1'b0,file_sector_count};
reg scan_match_latched;
reg scan_overflow_latched;
reg [31:0] scan_next_latched;

assign ready = (state == ST_IDLE);
wire [15:0] row_rgb_bytes=width*16'd3;
wire in_payload=(bmp_len_cnt>=pixel_offset) &&
                (bmp_len_cnt-pixel_offset<pixel_bytes);
assign bmp_data_valid = sd_sec_read_data_valid && in_payload &&
                        row_byte_index<row_rgb_bytes;
assign file_sector_count = (file_len == 32'd0) ? 32'd1 :
                           ((file_len>>9)+((file_len[8:0]!=0)?32'd1:32'd0));
assign next_scan_sector_if_match = next_scan_sector_wide[31:0];
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        probe_count<=0;
    end else if((state==ST_PROBE0)||(state==ST_PROBE1)) begin
        if(sd_sec_read_data_valid) probe_count<=probe_count+1'b1;
        else if(sd_sec_read_end) probe_count<=0;
    end else begin
        probe_count<=0;
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        probe_bytes_per_sector<=0;probe_sectors_per_cluster<=0;
        probe_reserved_sectors<=0;probe_num_fats<=0;probe_fat_size<=0;
        probe_signature<=0;probe_partition_type<=0;probe_partition_start<=0;
    end else if(!sd_init_done ||
                ((state==ST_IDLE) && scan_start) ||
                ((state==ST_PROBE0_EVAL) && probe_mbr_valid)) begin
        probe_bytes_per_sector<=0;probe_sectors_per_cluster<=0;
        probe_reserved_sectors<=0;probe_num_fats<=0;probe_fat_size<=0;
        probe_signature<=0;probe_partition_type<=0;probe_partition_start<=0;
    end else if(((state==ST_PROBE0)||(state==ST_PROBE1)) &&
                sd_sec_read_data_valid) begin
        case(probe_count)
            10'd11: probe_bytes_per_sector[7:0]<=sd_sec_read_data;
            10'd12: probe_bytes_per_sector[15:8]<=sd_sec_read_data;
            10'd13: probe_sectors_per_cluster<=sd_sec_read_data;
            10'd14: probe_reserved_sectors[7:0]<=sd_sec_read_data;
            10'd15: probe_reserved_sectors[15:8]<=sd_sec_read_data;
            10'd16: probe_num_fats<=sd_sec_read_data;
            10'd36: probe_fat_size[7:0]<=sd_sec_read_data;
            10'd37: probe_fat_size[15:8]<=sd_sec_read_data;
            10'd38: probe_fat_size[23:16]<=sd_sec_read_data;
            10'd39: probe_fat_size[31:24]<=sd_sec_read_data;
            10'd450:probe_partition_type<=sd_sec_read_data;
            10'd454:probe_partition_start[7:0]<=sd_sec_read_data;
            10'd455:probe_partition_start[15:8]<=sd_sec_read_data;
            10'd456:probe_partition_start[23:16]<=sd_sec_read_data;
            10'd457:probe_partition_start[31:24]<=sd_sec_read_data;
            10'd510:probe_signature[7:0]<=sd_sec_read_data;
            10'd511:probe_signature[15:8]<=sd_sec_read_data;
            default: begin end
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) row_byte_index<=0;
    else if(state!=ST_LOAD_DATA) row_byte_index<=0;
    else if(sd_sec_read_data_valid && in_payload) begin
        if(row_byte_index==row_stride-1'b1) row_byte_index<=0;
        else row_byte_index<=row_byte_index+1'b1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        scan_match_latched <= 1'b0;
        scan_overflow_latched <= 1'b0;
        scan_next_latched <= 32'd0;
        probe_partition_base<=0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        scan_match_latched <= 1'b0;
        scan_overflow_latched <= 1'b0;
        scan_next_latched <= 32'd0;
        probe_partition_base<=0;
    end else begin
        scan_found_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    probe_partition_base<=0;
                    if(FAST_FAT32_START && (scan_start_sector==0)) begin
                        scan_sector      <= 0;
                        sd_sec_read_addr <= 0;
                        state            <= ST_PROBE0;
                    end else begin
                        scan_sector      <= scan_start_sector;
                        sd_sec_read_addr <= scan_start_sector;
                        state            <= ST_SCAN;
                    end
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_PROBE0: begin
                state_code<=4'd2;
                sd_sec_read<=1'b1;
                if(sd_sec_read_end) begin
                    sd_sec_read<=1'b0;
                    state<=ST_PROBE0_EVAL;
                end
            end

            ST_PROBE0_EVAL: begin
                if(probe_bpb_valid && !probe_data_start_wide[32]) begin
                    scan_sector<=probe_data_start;
                    sd_sec_read_addr<=probe_data_start;
                    state<=ST_SCAN;
                end else if(probe_mbr_valid) begin
                    probe_partition_base<=probe_partition_start;
                    sd_sec_read_addr<=probe_partition_start;
                    state<=ST_PROBE1;
                end else begin
                    scan_sector<=scan_start_sector;
                    sd_sec_read_addr<=scan_start_sector;
                    state<=ST_SCAN;
                end
            end

            ST_PROBE1: begin
                state_code<=4'd2;
                sd_sec_read<=1'b1;
                if(sd_sec_read_end) begin
                    sd_sec_read<=1'b0;
                    state<=ST_PROBE1_EVAL;
                end
            end

            ST_PROBE1_EVAL: begin
                if(probe_bpb_valid && !probe_data_start_wide[32]) begin
                    scan_sector<=probe_data_start;
                    sd_sec_read_addr<=probe_data_start;
                end else begin
                    scan_sector<=scan_start_sector;
                    sd_sec_read_addr<=scan_start_sector;
                end
                state<=ST_SCAN;
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    scan_match_latched<=header_match;
                    scan_overflow_latched<=next_scan_sector_wide[32];
                    scan_next_latched<=next_scan_sector_if_match;
                    state<=ST_SCAN_EVAL;
                end
            end

            // Registered evaluation breaks the 100MHz parser/file-size path
            // before it reaches scan_done and the next SD address.
            ST_SCAN_EVAL: begin
                    if (scan_match_latched) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) ||
                            scan_overflow_latched || (scan_next_latched > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= scan_next_latched;
                            scan_sector      <= scan_next_latched;
                        end else begin
                            sd_sec_read_addr <= scan_next_latched;
                            scan_sector      <= scan_next_latched;
                            state            <= ST_SCAN;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                            state            <= ST_SCAN;
                        end
                    end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (bmp_len_cnt+(sd_sec_read_data_valid?32'd1:32'd0) >=
                        pixel_offset+pixel_bytes) begin
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule

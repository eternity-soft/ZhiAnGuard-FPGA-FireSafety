`timescale 1ns/1ps
// Serialize a scaled-frame write against the HDMI SDRAM reader.
//
// The first image is written before video reads start, but later images used to
// be produced while a complete 640x480 read transaction was still in flight.
// The 512-word write FIFO can overflow during that overlap, leaving isolated
// stale pixels in the destination frame. This guard first blocks new video
// reads, waits for the current read transaction to finish, arms the writer, and
// keeps video reads paused until the complete frame write has committed.
module contest_frame_load_guard #(
    parameter integer PAUSE_GUARD_CYCLES = 128,
    parameter integer QUIET_CYCLES       = 8
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        load_start,
    input  wire [31:0] load_sector,
    input  wire        load_busy,
    input  wire        read_active_async,
    input  wire        write_req_ack,
    input  wire        scaler_start_ready,
    output reg         read_pause,
    output wire        write_req,
    output wire        scaler_start,
    output reg  [31:0] sector_latched,
    output wire [2:0]  state_debug
);

localparam [2:0] S_IDLE      = 3'd0;
localparam [2:0] S_GUARD     = 3'd1;
localparam [2:0] S_WAIT_IDLE = 3'd2;
localparam [2:0] S_REQ       = 3'd3;
localparam [2:0] S_ACK_LOW   = 3'd4;
localparam [2:0] S_FIRE      = 3'd5;
localparam [2:0] S_ACTIVE    = 3'd6;

function integer count_bits;
    input integer value;
    integer v;
    begin
        count_bits=1;
        v=(value<2)?1:value-1;
        while(v>1) begin count_bits=count_bits+1; v=v>>1; end
    end
endfunction

reg [2:0] state;
reg [1:0] read_active_sync;
reg [count_bits(PAUSE_GUARD_CYCLES)-1:0] guard_count;
reg [count_bits(QUIET_CYCLES)-1:0] quiet_count;

assign write_req    = (state==S_REQ);
assign scaler_start = (state==S_FIRE) && scaler_start_ready;
assign state_debug  = state;

always @(posedge clk or posedge rst) begin
    if(rst)
        read_active_sync <= 2'b00;
    else
        read_active_sync <= {read_active_sync[0],read_active_async};
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        state          <= S_IDLE;
        read_pause     <= 1'b0;
        sector_latched <= 32'd0;
        guard_count    <= 0;
        quiet_count    <= 0;
    end else begin
        case(state)
            S_IDLE: begin
                read_pause  <= 1'b0;
                guard_count <= 0;
                quiet_count <= 0;
                if(load_start) begin
                    sector_latched <= load_sector;
                    read_pause     <= 1'b1;
                    state          <= S_GUARD;
                end
            end
            S_GUARD: begin
                read_pause <= 1'b1;
                if(guard_count==PAUSE_GUARD_CYCLES-1) begin
                    guard_count <= 0;
                    quiet_count <= 0;
                    state       <= S_WAIT_IDLE;
                end else begin
                    guard_count <= guard_count+1'b1;
                end
            end
            S_WAIT_IDLE: begin
                read_pause <= 1'b1;
                if(read_active_sync[1]) begin
                    quiet_count <= 0;
                end else if(quiet_count==QUIET_CYCLES-1) begin
                    quiet_count <= 0;
                    state       <= S_REQ;
                end else begin
                    quiet_count <= quiet_count+1'b1;
                end
            end
            S_REQ: begin
                read_pause <= 1'b1;
                if(write_req_ack)
                    state <= S_ACK_LOW;
            end
            S_ACK_LOW: begin
                read_pause <= 1'b1;
                if(!write_req_ack)
                    state <= S_FIRE;
            end
            S_FIRE: begin
                read_pause <= 1'b1;
                if(scaler_start_ready)
                    state <= S_ACTIVE;
            end
            S_ACTIVE: begin
                read_pause <= 1'b1;
                if(!load_busy) begin
                    read_pause <= 1'b0;
                    state      <= S_IDLE;
                end
            end
            default: begin
                state      <= S_IDLE;
                read_pause <= 1'b0;
            end
        endcase
    end
end

endmodule

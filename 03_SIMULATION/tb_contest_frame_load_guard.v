`timescale 1ns/1ps
module tb_contest_frame_load_guard;
reg clk=0,rst=1;
reg load_start=0,load_busy=0,read_active_async=0;
reg write_req_ack=0,scaler_start_ready=1;
reg [31:0] load_sector=0;
wire read_pause,write_req,scaler_start;
wire [31:0] sector_latched;
wire [2:0] state_debug;
integer scaler_pulses=0;

always #5 clk=~clk;
always @(posedge clk) if(scaler_start) scaler_pulses=scaler_pulses+1;

contest_frame_load_guard #(
    .PAUSE_GUARD_CYCLES(4),
    .QUIET_CYCLES(3)
) dut(
    .clk(clk),.rst(rst),.load_start(load_start),.load_sector(load_sector),
    .load_busy(load_busy),.read_active_async(read_active_async),
    .write_req_ack(write_req_ack),.scaler_start_ready(scaler_start_ready),
    .read_pause(read_pause),.write_req(write_req),.scaler_start(scaler_start),
    .sector_latched(sector_latched),.state_debug(state_debug)
);

task fail;
    input [8*120-1:0] msg;
    begin $display("FAIL tb_contest_frame_load_guard: %0s",msg); $finish; end
endtask

task pulse_load;
    input [31:0] sector;
    begin
        @(negedge clk); load_sector=sector;load_busy=1;load_start=1;
        @(negedge clk); load_start=0;
    end
endtask

initial begin
    repeat(4) @(negedge clk);rst=0;

    // A load arriving during an active video read must pause immediately and
    // must not arm the writer until the complete read transaction is over.
    read_active_async=1;
    pulse_load(32'h1234_5678);
    repeat(14) begin
        @(negedge clk);
        if(!read_pause) fail("pause dropped while prior read was active");
        if(write_req) fail("writer armed before prior read completed");
    end
    if(sector_latched!==32'h1234_5678) fail("sector was not latched");

    read_active_async=0;
    wait(write_req===1'b1);
    @(negedge clk);write_req_ack=1;
    wait(write_req===1'b0);
    repeat(2) @(negedge clk);write_req_ack=0;
    wait(scaler_start===1'b1);
    @(negedge clk);
    if(!read_pause) fail("pause dropped when scaler started");
    repeat(8) begin
        @(negedge clk);
        if(!read_pause) fail("pause dropped during frame write");
        if(write_req) fail("write request repeated during active frame");
    end
    load_busy=0;
    repeat(3) @(negedge clk);
    if(read_pause) fail("pause did not release after committed frame");
    if(state_debug!==3'd0) fail("guard did not return idle");
    if(scaler_pulses!=1) fail("first load did not emit exactly one start");

    // Reader already idle: the same four-phase writer handshake is preserved.
    pulse_load(32'h89ab_cdef);
    wait(write_req===1'b1);
    @(negedge clk);write_req_ack=1;
    wait(write_req===1'b0);
    @(negedge clk);write_req_ack=0;
    wait(scaler_start===1'b1);
    @(negedge clk);load_busy=0;
    repeat(3) @(negedge clk);
    if(sector_latched!==32'h89ab_cdef) fail("second sector mismatch");
    if(scaler_pulses!=2) fail("second load did not emit exactly one start");
    if(read_pause) fail("second load pause did not release");

    $display("PASS tb_contest_frame_load_guard serialized read/write ownership");
    $finish;
end
endmodule

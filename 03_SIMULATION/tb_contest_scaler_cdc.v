`timescale 1ns/1ps
module tb_contest_scaler_cdc;
    reg sd_clk=0,video_clk=0,rst=1,io_reset=0;
    always #5 sd_clk=~sd_clk;
    initial begin #3;forever #20 video_clk=~video_clk;end
    reg start_sd=0,bridge_ready=0,pixel_en=0,done_v=0,loaded_v=0,finish_toggle=0;
    reg [31:0] sector_sd=0;
    wire ready_sd,overrun,start_v,pixel_inc,done_sd,error_sd,finish_v;
    wire [31:0] sector_v;
    integer received=0,sent=0,pixels=0,ok=0,err=0,finishes=0,overruns=0,i,j;
    reg [31:0] expected[0:255];
    contest_scaler_cdc dut (
        .sd_clk(sd_clk),.video_clk(video_clk),.rst(rst),.io_reset_sd(io_reset),
        .load_start_sd(start_sd),.load_sector_sd(sector_sd),.load_ready_sd(ready_sd),.load_overrun_sd(overrun),
        .bridge_ready_v(bridge_ready),.load_start_v(start_v),.load_sector_v(sector_v),
        .pixel_en_v(pixel_en),.pixel_inc_sd(pixel_inc),.bridge_done_v(done_v),.bridge_loaded_v(loaded_v),
        .source_done_sd(done_sd),.source_error_sd(error_sd),.finish_toggle_mem(finish_toggle),.finish_pulse_v(finish_v)
    );
    task fail;input [8*128-1:0] msg;begin $display("FAIL CDC %0s",msg);$finish;end endtask
    always @(posedge video_clk) if(!rst) begin
        if(start_v) begin
            if(received>=sent || sector_v!==expected[received])fail("lost/duplicated request or torn LBA");
            received=received+1;
        end
        if(finish_v)finishes=finishes+1;
    end
    always @(posedge sd_clk) if(!rst) begin
        if(pixel_inc)pixels=pixels+1;
        if(done_sd)ok=ok+1;
        if(error_sd)err=err+1;
        if(overrun)overruns=overruns+1;
    end
    task send_start;input [31:0] lba;begin
        while(!ready_sd)@(negedge sd_clk);
        @(negedge sd_clk);sector_sd=lba;expected[sent]=lba;sent=sent+1;start_sd=1;
        @(negedge sd_clk);start_sd=0;sector_sd=32'hdeadbeef;
    end endtask
    initial begin
        #301;rst=0;repeat(10)@(negedge sd_clk);
        send_start(32'h12345678);
        repeat(30)@(negedge sd_clk);
        if(received!=0 || ready_sd)fail("pending request was not held while bridge unready");
        start_sd=1;@(negedge sd_clk);start_sd=0;repeat(3)@(negedge sd_clk);
        if(overruns!=1)fail("busy mailbox overwrite not detected");
        bridge_ready=1;
        for(i=0;i<100;i=i+1)begin
            repeat(i%5)@(negedge sd_clk);
            send_start(32'hf0120000+i);
        end
        repeat(20)@(negedge video_clk);
        if(received!=101 || sent!=101 || !ready_sd)fail("10ns requests were lost across phases");
        $display("PASS CDC narrow_start_requests=%0d queued_while_unready busy_overrun=%0d",received,overruns);
        // 连续640像素/行，模拟write_en持续高640拍，不以电平上升沿代替逐像素事件。
        for(i=0;i<480;i=i+1)begin
            @(negedge video_clk);pixel_en=1;
            repeat(640)@(negedge video_clk);
            pixel_en=0;repeat(i%4+1)@(negedge video_clk);
        end
        repeat(10)@(negedge video_clk);
        if(pixels!=307200)fail("25MHz pixels not counted exactly once in 100MHz domain");
        $display("PASS CDC pixel_toggle sent=307200 received=%0d",pixels);
        @(negedge video_clk);done_v=1;loaded_v=1;
        @(negedge video_clk);done_v=0;loaded_v=0;
        repeat(10)@(negedge video_clk);
        @(negedge video_clk);done_v=1;
        @(negedge video_clk);done_v=0;
        repeat(10)@(negedge video_clk);
        if(ok!=1 || err!=1)fail("completion status crossed incoherently");
        #7;finish_toggle=1;repeat(10)@(negedge video_clk);
        if(finishes!=1)fail("memory finish toggle lost");
        io_reset=1;repeat(12)@(negedge video_clk);io_reset=0;
        repeat(12)@(negedge video_clk);
        if(finishes!=1)fail("local recovery manufactured an old finish event");
        #7;finish_toggle=0;repeat(10)@(negedge video_clk);
        if(finishes!=2 || !ready_sd)fail("recovery failed to rearm CDC");
        $display("PASS CDC done_success=%0d done_error=%0d finish_events=%0d local_reset_no_replay",ok,err,finishes);
        $display("PASS tb_contest_scaler_cdc");$finish;
    end
    initial begin #20000000;fail("watchdog");end
endmodule

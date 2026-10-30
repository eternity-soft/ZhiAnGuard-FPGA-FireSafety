`timescale 1ns/1ps
// 真实 manager/消抖/fade/SDRAM 读调度器；SD扫描与写帧完成为行为模型。
// 加速毫秒/视频帧周期，仅检查控制协议。实际像素链路由 tb_v08_chain 验证。
module tb_smooth_cache;
reg clk=0,video_clk=0,mem_clk=0,rst=1;
always #5 clk=~clk;
initial begin #3;forever #20 video_clk=~video_clk;end
initial begin #1;forever #4 mem_clk=~mem_clk;end
reg key_next=1,key_auto=1,key_period=1;
wire [1:0] image_idx,disp_buf,write_buf,load_idx,actual_read_buf,fade_buf;
wire display_valid,load_start,load_busy,req_toggle,ack_toggle,fade_active,read_valid;
wire [7:0] fade_level;
wire [31:0] load_sector;
wire [3:0] cache_mask;
reg finish_toggle=0,source_done=0,pixel_inc=0,source_error=0;
reg allow_finish=1,allow_memory=1,pause_reads=0,finish_on_key=0;
reg [31:0] load_delay=4500;
wire abort_req,io_reset;
reg abort_ack=0;
wire source_done_mux=source_done;
contest_sd_card_bmp #(.CLK_FREQ_HZ(10000),.EXTERNAL_SCALER(1),
 .PREFETCH_GUARD_MS(0),.RECOVERY_PAUSE_MS(1),.LOAD_TIMEOUT_MS(100000)) manager(
 .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.key_period(key_period),
 .state_code(),.auto_period_sel(),.bmp_width(16'd2),.bmp_height(16'd2),
 .display_valid(display_valid),.auto_play_active(),.current_image_idx(image_idx),
 .manual_audio_toggle(),.manual_audio_image_idx(),.write_finish_toggle(finish_toggle),
 .write_abort_req(abort_req),.write_abort_ack(abort_ack),.write_buf_idx(write_buf),.disp_buf_idx(disp_buf),
 .display_req_toggle(req_toggle),.display_ack_toggle_video(ack_toggle),.cache_valid_mask(cache_mask),
 .write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
 .load_sector_out(load_sector),.load_start_pulse_out(load_start),.load_busy_out(load_busy),.load_idx_out(load_idx),
 .catalog_ready_out(),.sd_init_done_out(),.sd_sec_read_o(),.sd_sec_read_addr_o(),
 .sd_sec_read_i(1'b0),.sd_sec_read_addr_i(32'd0),.sd_bus_takeover(load_busy),
 .ext_pixel_inc(pixel_inc),.ext_source_done(source_done_mux),.ext_source_error(source_error),
 .bridge_reset_out(io_reset),.sd_sec_read_data_o(),.sd_sec_read_data_valid_o(),.sd_sec_read_end_o());
reg vs=1,read_req=0,read_req_mem=0;
reg [1:0] read_bank=0;
wire read_ack,rd_en;
wire [20:0] rd_addr;
integer video_count=0;
reg [1:0] ack_sync=0;
always @(posedge video_clk) begin
 if(rst) begin vs<=1;video_count<=0;read_req<=0;ack_sync<=0;read_req_mem<=0;read_bank<=0;end
 else begin
  ack_sync<={ack_sync[0],read_ack};
  read_req_mem<=read_req;
  if(read_req && !read_req_mem) read_bank<=fade_buf;
  if(video_count==599) begin
   video_count<=0;vs<=0;
   if(!pause_reads) read_req<=1;
  end else begin
   video_count<=video_count+1;
   if(video_count==20) vs<=1;
   if(ack_sync[1]) read_req<=0;
  end
 end
end
my_fade fade(.clk(video_clk),.rst(rst),.de_in(1'b1),.vs_in(vs),.rgb_in(24'hffffff),
 .disp_idx_new(disp_buf),.display_req_toggle(req_toggle),.display_ack_toggle(ack_toggle),.disp_idx_disp(fade_buf),
 .read_bank_valid(read_valid),.read_bank_active(actual_read_buf),
 .rgb_out(),.fade_level(fade_level),.fade_active(fade_active));
// 读帧长度缩小为 32，突发为 8，仍执行真实 ACK、突发以及返回延迟状态机。
frame_fifo_read #(.BURST_SIZE(8)) reader(.rst(rst),.mem_clk(mem_clk),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b0),
 .O_rd_busy(),.App_rd_en(rd_en),.App_rd_addr(rd_addr),.read_req(read_req_mem),.read_req_ack(read_ack),
 .read_finish(),.active_read_buf(actual_read_buf),.active_read_valid(read_valid),
 .read_transaction_active(),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
 .read_addr_index(read_bank),.read_len(21'd32),.fifo_aclr(),.wrusedw(10'd0));
integer model_state=0,delay_count=0,n=0,starts=0,commits=0,presses=0;
integer loads[0:127];
reg [1:0] model_buf=0,prev_img=0;
integer tests=0,saved_starts,saved_commits,t,k;
task fail; input [8*160-1:0] msg; begin
 $display("FAIL tb_smooth_cache time=%0t image=%0d target=%0d load=%0d state=%0d %0s",
  $time,image_idx,manager.manual_target,load_idx,model_state,msg);$finish;
end endtask
task check;input ok;input [8*160-1:0] msg;begin if(ok!==1'b1)fail(msg);end endtask
task pass;input [8*120-1:0] msg;begin tests=tests+1;$display("PASS smooth_cache case=%0d %0s",tests,msg);end endtask
task next_key;begin
 @(negedge clk);key_next=0;repeat(210)@(negedge clk);
 key_next=1;repeat(210)@(negedge clk);
end endtask
task wait_image;input [1:0] idx;begin
 t=0;while((image_idx!=idx || !display_valid) && t<500000)begin @(negedge clk);t=t+1;end
 check(image_idx==idx && display_valid,"target image timeout");
end endtask
task wait_free;begin
 t=0;while(!manager.display_idle && t<500000)begin @(negedge clk);t=t+1;end
 check(manager.display_idle,"buffer release timeout");
 repeat(2)@(negedge video_clk);
end endtask
task wait_cache;begin
 t=0;while(!manager.prefetch_done && t<500000)begin @(negedge clk);t=t+1;end
 check(manager.prefetch_done,"prefetch timeout");
end endtask
integer overlap_cycles=0,transitions=0,out_edges=0,in_edges=0;
reg [1:0] last_state=0;
reg [3:0] old_mask=0;
always @(posedge clk) if(!rst && manager.key_next_press) presses=presses+1;
always @(negedge mem_clk) if(!rst && display_valid && model_state!=0 && rd_en) begin
 if(rd_addr/307200==model_buf) fail("SDRAM read burst overlaps active write slot");
 if(rd_addr>=1228800)fail("read address outside four-cache allocation");
end
always @(posedge video_clk) if(!rst) begin
 if(fade.state==1 && fade.frame_edge)out_edges=out_edges+1;
 if(fade.state==3 && fade.frame_edge)in_edges=in_edges+1;
end
always @(negedge video_clk)begin
 if(rst)begin last_state=0;out_edges=0;in_edges=0;end
 else begin
  if(last_state==1 && fade.state==2)begin
   check(out_edges==15 && fade_level==0,"full 15-frame fade-out was shortened");
  end
  if(last_state==2 && fade.state==3)begin
   check(read_valid && actual_read_buf==fade_buf,"fade-in started before SDRAM reader accepted target bank");
  end
  if(last_state==3 && fade.state==0)begin
   check(in_edges==15 && fade_level==255,"full 15-frame fade-in was shortened");
   transitions=transitions+1;out_edges=0;in_edges=0;
  end
  last_state=fade.state;
 end
end
always @(negedge clk) begin
 source_done=0;pixel_inc=0;abort_ack=abort_req;
 if(rst || io_reset) begin model_state=0;delay_count=0;n=0;if(rst)old_mask=0;end
 else begin
  if(fade_active && model_state!=0)overlap_cycles=overlap_cycles+1;
  check((cache_mask & old_mask)==old_mask,"valid cache lost during local recovery");old_mask=cache_mask;
  if(image_idx!=prev_img) begin commits=commits+1;prev_img=image_idx;end
  if(load_start) begin
   check(model_state==0,"new writer transaction while previous transaction active");
   if(display_valid) begin
    check(write_buf!=actual_read_buf,"writing buffer still latched by reader");
    check(write_buf!=fade_buf,"writing buffer used by fade");
   end
   check(write_buf==load_idx && !cache_mask[load_idx],"rewriting valid cache or wrong image slot");

   loads[starts]=load_idx;starts=starts+1;
   model_buf=write_buf;delay_count=load_delay;model_state=1;n=0;
  end else case(model_state)
   1: if(delay_count!=0)delay_count=delay_count-1;
      else if(allow_finish)model_state=2;
   2: begin pixel_inc=1;n=n+1;if(n==4)begin delay_count=20;model_state=3;end end
   3: if(delay_count!=0)delay_count=delay_count-1;
      else if(allow_memory)begin finish_toggle=~finish_toggle;delay_count=20;model_state=4;end
   4: if(delay_count!=0)delay_count=delay_count-1;
      else if(finish_on_key)model_state=5;
      else begin source_done=1;model_state=0;end
   5: if(manager.key_next_press)begin source_done=1;model_state=0;end
  endcase
 end
end
task all_cached;begin
 t=0;while(cache_mask!=15 && t<500000)begin @(negedge clk);t=t+1;end
 check(cache_mask==15,"four images not cached");
end endtask
task inject_error;begin
 @(negedge clk);source_error=1;@(negedge clk);source_error=0;
 wait(manager.recovery_state!=0);wait(manager.recovery_state==0);
end endtask
initial begin
 #501;rst=0;
 wait(display_valid);check(image_idx==0,"first image");
 wait(load_start && load_idx==1);allow_finish=0;
 next_key;next_key;
 finish_on_key=1;allow_finish=1;wait(model_state==5);next_key;finish_on_key=0;
 check(manager.requested_img_idx==3,"three presses did not accumulate");
 wait_image(3);
 check(loads[0]==0 && loads[1]==1 && loads[2]==3,"latest missing target not prioritized");
 pass("latest target 3 prioritized, including a key on source completion");
 all_cached;check(starts==4,"each healthy image must load once");
 check(overlap_cycles>0,"background read did not overlap full transition");
 pass("four independent frames filled once; background read overlaps fade");
 // 在完整淡入淡出期间累计三个按键，最终目标从3回绕至2。
 next_key;next_key;next_key;wait_image(2);wait_free;
 check(starts==4,"warm cache switch reread SD");
 pass("keys during full transition retained without SD rereads");
 // 12次热缓存切图。每次均完整15+15帧，缓存写事务总数保持4。
 for(k=0;k<12;k=k+1)begin
  saved_starts=(image_idx+1)%4;next_key;wait_image(saved_starts);wait_free;
 end
 $display("INFO warm switches starts=%0d transitions=%0d",starts,transitions);
 check(starts==4 && transitions>=14,"warm switches caused extra loads or skipped fade");
 pass("12 warm switches: zero new loads, each has all 30 fade frames");
 // 转场未确认时不改发布的数据；四次连按回到已发布目标不积压动画。
 next_key;wait(fade_active);saved_commits=commits;
 next_key;next_key;next_key;next_key;wait_free;repeat(100)@(negedge clk);
 check(commits==saved_commits,"full-circle burst queued unnecessary transitions");
 pass("full-circle press burst has no extra transition queue");
 @(negedge clk);key_period=0;repeat(210)@(negedge clk);key_period=1;repeat(210)@(negedge clk);
 check(manager.auto_period_sel==1,"period key regressed");
 saved_starts=(image_idx+1)%4;
 @(negedge clk);key_auto=0;repeat(210)@(negedge clk);key_auto=1;repeat(210)@(negedge clk);
 wait_image(saved_starts);
 @(negedge clk);key_auto=0;repeat(210)@(negedge clk);key_auto=1;repeat(210)@(negedge clk);
 wait_free;check(starts==4,"automatic playback reread warm images");
 pass("automatic playback uses warm cache and preserves full fade");
 // 冷启动后坏图连续失败，验证有限重试、其他缓存保持及重新按键重试。
 @(negedge clk);rst=1;repeat(30)@(negedge clk);rst=0;allow_finish=1;
 wait(display_valid);wait(load_busy && load_idx==1);allow_finish=0;next_key;
 inject_error;wait(load_busy && load_idx==1);inject_error;
 check(manager.cache_blocked[1] && !cache_mask[1],"failed image published or retries not bounded");
 allow_finish=1;
 wait(cache_mask==13);check(display_valid && image_idx==0,"good displayed cache lost on bad image");
 next_key;wait_image(1);wait_free;all_cached;
 pass("bad image bounded retries preserve good caches; fresh key retries successfully");
 k=presses;
 repeat(5)begin key_next=0;repeat(10)@(negedge clk);key_next=1;repeat(10)@(negedge clk);end
 repeat(250)@(negedge clk);check(presses==k,"contact bounce counted as key presses");
 pass("debounce still rejects short contacts");
 $display("PASS tb_smooth_cache cases=%0d full_transitions=%0d warm_switch_loads=0 overlap_cycles=%0d",tests,transitions,overlap_cycles);$finish;
end
initial begin #100000000;fail("watchdog");end
endmodule

// 扫描/SD 的控制面模型，仅用于本专项；综合使用正式模块。
module bmp_read(input clk,rst,scan_start,input [31:0] scan_start_sector,scan_max_sector,
 input [2:0] scan_target_count,output reg scan_done,scan_found_valid,
 output reg [31:0] scan_found_sector,output reg [2:0] scan_found_total,
 input load_start,input [31:0] load_sector,input sd_init_done,
 output ready,output [3:0] state_code,input [15:0] bmp_width,bmp_height,
 output write_req,input write_req_ack,output sd_sec_read,output [31:0] sd_sec_read_addr,
 input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,sd_sec_read_end,
 output bmp_data_wr_en,output [23:0] bmp_data);
 assign ready=1'b1;assign state_code=0;assign write_req=0;assign sd_sec_read=0;
 assign sd_sec_read_addr=0;assign bmp_data_wr_en=0;assign bmp_data=0;
 integer c=-1;
 always @(posedge clk)begin
  if(rst)begin c=-1;scan_done<=0;scan_found_valid<=0;scan_found_total<=0;scan_found_sector<=0;end
  else begin
   scan_done<=0;scan_found_valid<=0;
   if(scan_start)c=0;
   else if(c>=0 && c<4)begin scan_found_valid<=1;scan_found_sector<=c*2048;scan_found_total<=c+1;c=c+1;end
   else if(c==4)begin scan_done<=1;c=-1;end
  end
 end
endmodule
module sd_card_top(input clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
 input [31:0] sd_sec_read_addr,sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output SD_nCS,SD_DCLK,SD_MOSI,sd_init_done,output [7:0] sd_sec_read_data,
 output sd_sec_read_data_valid,sd_sec_read_end,sd_sec_write_data_req,sd_sec_write_end);
 assign sd_init_done=!rst;assign SD_nCS=1;assign SD_DCLK=clk;assign SD_MOSI=0;
 assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;
 assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule

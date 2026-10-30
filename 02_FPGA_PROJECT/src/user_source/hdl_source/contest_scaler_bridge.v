`timescale 1ns/1ps
// BMP 行调度桥接，Verilog-2001，无厂家 IP。
// 文件必须按连续扇区存放，BMP 文件头位于 bmp_start_sector 的第 0 字节。
// 本模块接收已有扫描/选图控制器给出的 LBA，不自行实现 FAT、按键或轮播。
// 512 字节扇区邮箱：SD 域完整写入 -> 应答 toggle -> video 域只读 -> 下一请求。
// 每次只允许一个在途扇区；多位地址/状态在握手期间保持，不能逐位同步数据脉冲。
// SD 请求保持到本次有效 end 或超时；忽略首字节前的遗留 end。
// 支持最后 data_valid 与 end 同拍或 end 延后一拍。
// 格式错误可重新 start；I/O 错误、超时或 abort 锁定，须协调复位 SD/桥接/写 FIFO。
module contest_scaler_bridge #(
    parameter integer MIN_SRC_WIDTH = 1,  // 允许小图放大
    parameter integer MIN_SRC_HEIGHT = 1, // 允许大图缩小；缩放器保持宽高比
    parameter integer SD_TIMEOUT_CYCLES = 10000000,   // 100 MHz 下 100 ms；0 禁用
    parameter integer VIDEO_TIMEOUT_CYCLES = 25000000 // 25 MHz 下无进展 1 s；0 禁用
)(
    input wire video_clk,
    input wire sd_clk,
    input wire rst,                 // 两域共同异步复位，内部各自同步释放
    input wire load_start,          // video_clk 域，ready 时脉冲
    input wire [31:0] bmp_start_sector,
    input wire abort,               // video_clk 域，取消后进入故障锁定
    output wire ready,
    output wire busy,
    output reg done,
    output reg img_loaded,          // 仅源输出完成且 write_finish 已到达才置 1
    output reg format_error,
    output reg [7:0] error_code,
    output reg write_abort_req,     // scaler 启动后故障，保守要求取消/清空可能的目标帧
    output reg sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input wire [7:0] sd_sec_read_data,
    input wire sd_sec_read_data_valid,
    input wire sd_sec_read_end,
    output wire write_req,
    input wire write_req_ack,       // 必须已在 video_clk 域同步
    output wire write_en,
    output wire [31:0] write_data,
    input wire write_finish,        // video_clk 域的一拍提交完成脉冲
    output wire [9:0] o_x,
    output wire [8:0] o_y,
    output wire o_border_flag,
    output wire o_last,
    output wire [4:0] debug_state
);
    // 复位异步拉高、各域同步释放。禁止只复位其中一个邮箱端点。
    (* ASYNC_REG="TRUE" *) reg [1:0] vr_sync, sr_sync;
    always @(posedge video_clk or posedge rst)
        if(rst) vr_sync<=2'b11; else vr_sync<={vr_sync[0],1'b0};
    always @(posedge sd_clk or posedge rst)
        if(rst) sr_sync<=2'b11; else sr_sync<={sr_sync[0],1'b0};
    wire vr=vr_sync[1];
    wire sr=sr_sync[1];

    reg [7:0] sector_ram [0:511]; // 不复位数组，意图推断双时钟简单双口 RAM
    reg [7:0] sector_q;
    reg req_toggle;
    reg [31:0] request_lba;       // 发请求后保持，直到扇区完全消费完毕
    reg rsp_toggle;
    reg [1:0] response_status;   // 0 正常，1 字节数异常，2 超时
    (* ASYNC_REG="TRUE" *) reg [1:0] req_sync, rsp_sync;
    reg req_seen, rsp_seen;
    reg sd_active, sd_fault, sd_overflow;
    reg sd_end_d;               // SD 域上一拍 end，识别新的结束沿，隔离遗留高电平
    reg [9:0] sd_count;
    reg [31:0] sd_timer;
    wire [10:0] sd_total={1'b0,sd_count}+(sd_sec_read_data_valid ? 11'd1 : 11'd0);
    // 已收到首字节（或本拍正收到首字节）才允许结束当前事务。
    // 首字节前的 end 不发响应、不清计数、不撤请求；持续的旧 end 也不能跨越首字节结算。
    wire sd_current_end=sd_sec_read_end && !sd_end_d &&
                        ((sd_count!=0) || sd_sec_read_data_valid);

    always @(posedge sd_clk or posedge rst)
        if(rst || sr) sd_end_d<=0;
        else sd_end_d<=sd_sec_read_end;

    always @(posedge sd_clk or posedge rst) begin
        if(rst || sr) req_sync<=0;
        else req_sync<={req_sync[0],req_toggle};
    end
    always @(posedge video_clk or posedge rst) begin
        if(rst || vr) rsp_sync<=0;
        else rsp_sync<={rsp_sync[0],rsp_toggle};
    end
    // RAM 仅在活动扇区的前 512 个有效字节写入，后续多余字节只记错。
    always @(posedge sd_clk)
        if(!sr && sd_active && sd_sec_read_data_valid && sd_count<512)
            sector_ram[sd_count[8:0]]<=sd_sec_read_data;

    always @(posedge sd_clk or posedge rst) begin
        if(rst || sr) begin
            req_seen<=0; rsp_toggle<=0; response_status<=0;
            sd_active<=0; sd_fault<=0; sd_overflow<=0;
            sd_count<=0; sd_timer<=0; sd_sec_read<=0; sd_sec_read_addr<=0;
        end else if(sd_active) begin
            sd_timer<=sd_timer+1'b1;
            if(sd_sec_read_data_valid) begin
                if(sd_count<513) sd_count<=sd_count+1'b1;
                if(sd_count>=512) sd_overflow<=1;
            end
            if(sd_current_end) begin
                sd_active<=0; sd_sec_read<=0;
                response_status<=((sd_total==512) && !sd_overflow) ? 2'd0 : 2'd1;
                if(sd_total!=512 || sd_overflow) sd_fault<=1;
                rsp_toggle<=~rsp_toggle;
            end else if(SD_TIMEOUT_CYCLES>0 && sd_timer>=SD_TIMEOUT_CYCLES-1) begin
                // 超时后忽略迟到字节，不复用邮箱，不给下一事务旧数据。
                sd_active<=0; sd_sec_read<=0; sd_fault<=1;
                response_status<=2'd2; rsp_toggle<=~rsp_toggle;
            end
        end else begin
            sd_sec_read<=0;
            if(req_sync[1]!=req_seen) begin
                req_seen<=req_sync[1];
                if(sd_fault) begin
                    response_status<=2'd2; rsp_toggle<=~rsp_toggle;
                end else begin
                    // request_lba 已随请求在 video 域锁定，并经过两级 toggle 延迟。
                    sd_sec_read_addr<=request_lba;
                    sd_sec_read<=1; sd_active<=1;
                    sd_count<=0; sd_timer<=0; sd_overflow<=0;
                end
            end
        end
    end

    localparam [4:0] V_IDLE=0, V_HEADER_START=1, V_HEADER_GAP=2,
        V_SELECT=3, V_WAIT_SECTOR=4, V_READ=5, V_USE=6, V_META=7,
        V_SCALE_START=8, V_RUN=9, V_ROW_RELEASE=10, V_COMMIT=11, V_FATAL=12;
    reg [4:0] state;
    reg [4:0] fault_state_latched; // 进入故障时保存原状态，保持到共同复位
    reg [31:0] base_lba, byte_address;
    reg cache_valid;
    reg [31:0] cache_lba;
    reg header_mode;
    reg [5:0] header_index;
    reg [11:0] row_remaining;
    reg [1:0] component;
    reg [7:0] blue, green;
    reg pixel_valid;
    reg [23:0] pixel_rgb;
    reg parser_start, scaler_start;
    reg frame_active, source_complete, commit_seen;
    reg finish_d;
    reg [31:0] video_timer;
    wire finish_rise=write_finish && !finish_d;

    wire parser_ready, parser_busy, parser_done, parser_valid, parser_bad;
    wire [3:0] parser_error;
    wire [15:0] image_w,image_h,stride;
    wire top_down;
    wire [31:0] pixel_offset, file_size;
    wire scaler_ready, scaler_busy, scaler_done, scaler_bad;
    wire [3:0] scaler_error;
    wire line_ready;
    wire [15:0] source_y;
    wire sc_req,sc_en,sc_last,sc_border;
    wire [23:0] sc_rgb;
    wire [9:0] sc_x;
    wire [8:0] sc_y;
    wire local_abort=abort || (state==V_FATAL);
    wire parser_byte_ready;
    wire parser_byte_valid=(state==V_USE) && header_mode && !local_abort;

    // 实际交付 parser 的 padding 端口名为 row_padding，保持原模块不变。
    contest_bmp_meta_parser meta_parser (
        .clk(video_clk),.rst(vr),.start(parser_start),.abort(local_abort),
        .s_valid(parser_byte_valid),.s_ready(parser_byte_ready),.s_data(sector_q),
        .s_last(header_index==53),.ready(parser_ready),.busy(parser_busy),.done(parser_done),
        .o_format_valid(parser_valid),.o_format_error(parser_bad),.o_error_code(parser_error),
        .o_width(image_w),.o_height(image_h),.o_top_down(top_down),
        .file_size(file_size),.o_pixel_offset(pixel_offset),.dib_size(),
        .o_row_stride(stride),.row_padding(),.pixel_bytes(),.pixel_count()
    );
    contest_image_scaler image_scaler (
        .clk(video_clk),.rst(vr),.start(scaler_start),.abort(local_abort),
        .cfg_src_width(image_w),.cfg_src_height(image_h),.cfg_format_valid(parser_valid),
        .bmp_data_wr_en(pixel_valid),.bmp_data(pixel_rgb),.write_req_ack(write_req_ack),
        .ready(scaler_ready),.busy(scaler_busy),.done(scaler_done),
        .o_format_error(scaler_bad),.error(scaler_error),.o_line_ready(line_ready),.o_src_y(source_y),
        .write_req(sc_req),.write_en(sc_en),.write_data(sc_rgb),.o_x(sc_x),.o_y(sc_y),
        .o_border_flag(sc_border),.o_sof(),.o_eol(),.o_last(sc_last),
        .scaled_width(),.scaled_height(),.offset_x(),.offset_y()
    );

    assign ready=(state==V_IDLE) && !vr && !abort && !write_req_ack && !write_finish;
    assign busy=(state!=V_IDLE) && !vr; // 故障锁定也保持 busy，禁止自动重用旧事务
    // 正常时显示实时状态；故障时显示出错位置，内部状态仍保持 V_FATAL。
    assign debug_state=(state==V_FATAL) ? fault_state_latched : state;
    assign write_req=sc_req && frame_active && !vr && !local_abort;
    assign write_en=sc_en && frame_active && !vr && !local_abort;
    assign write_data={sc_rgb,8'h00};
    assign o_x=sc_x;
    assign o_y=sc_y;
    assign o_border_flag=write_en && sc_border;
    assign o_last=write_en && sc_last;

    wire [15:0] file_row=top_down ? source_y : (image_h-16'd1-source_y);
    wire [31:0] row_byte_address=pixel_offset+(file_row*stride);
    wire [32:0] wanted_lba={1'b0,base_lba}+{10'd0,byte_address[31:9]};
    wire [31:0] last_file_byte=file_size-32'd1;
    wire [32:0] last_lba={1'b0,base_lba}+{10'd0,last_file_byte[31:9]};
    wire last_pixel_now=write_en && sc_last;
    // READ 只为每段数据预取首字节。USE 消费当前 q 的同时，同步读取下一字节，
    // 同扇区内每个 video_clk 消费 1 字节（每 3 拍组成 1 个 RGB）。
    // parser 停顿、段末或扇区末禁止预读，避免覆写未消费数据/越界回卷。
    wire byte_consumed=(state==V_USE) && !local_abort &&
                       (!header_mode || parser_byte_ready);
    wire more_bytes=header_mode ? (header_index!=53) : (row_remaining>1);
    wire prefetch_next=byte_consumed && more_bytes && (byte_address[8:0]!=9'd511);
    wire ram_read_enable=!vr && !local_abort && ((state==V_READ) || prefetch_next);
    wire [8:0] ram_read_address=(state==V_READ) ? byte_address[8:0] :
                                                      (byte_address[8:0]+9'd1);
    wire watchdog_progress=byte_consumed || (state==V_WAIT_SECTOR && rsp_sync[1]!=rsp_seen) || write_en;
    always @(posedge video_clk)
        if(ram_read_enable) sector_q<=sector_ram[ram_read_address];

    // 故障不会假冒 img_loaded。请求可能已被存储域接收而 ACK 尚未同步回来，
    // 因此 scaler 一旦启动，故障即要求取消目标帧，不能只凭本地 ACK 判断。
    task fatal;
        input [7:0] code;
        begin
            // 0x24 只说明视频域一秒内没有写入进展。V_RUN 内再细分
            // 写帧握手阶段，便于仅靠数码管判断故障点：
            //   D = write_req 已拉高，仍在等待 ACK 拉高；
            //   E = write_req 已拉低，仍在等待 ACK 拉低；
            //   F = 不在上述两个握手等待阶段，为缩放器内部其它停顿。
            // 其它错误仍保存原来的桥接状态编号。
            if((code==8'h24) && (state==V_RUN)) begin
                if(write_req && !write_req_ack)
                    fault_state_latched<=5'h0D;
                else if(!write_req && write_req_ack)
                    fault_state_latched<=5'h0E;
                else
                    fault_state_latched<=5'h0F;
            end else begin
                fault_state_latched<=state;
            end
            state<=V_FATAL; error_code<=code; done<=1;
            img_loaded<=0; pixel_valid<=0; parser_start<=0; scaler_start<=0;
            write_abort_req<=frame_active;
        end
    endtask

    always @(posedge video_clk or posedge rst) begin
        if(rst || vr) begin
            fault_state_latched<=0;
            state<=V_IDLE; done<=0; img_loaded<=0; format_error<=0; error_code<=0;
            write_abort_req<=0; req_toggle<=0; request_lba<=0; rsp_seen<=0;
            base_lba<=0; byte_address<=0; cache_valid<=0; cache_lba<=0;
            header_mode<=0; header_index<=0; row_remaining<=0; component<=0;
            blue<=0; green<=0; pixel_valid<=0; pixel_rgb<=0;
            parser_start<=0; scaler_start<=0; frame_active<=0;
            source_complete<=0; commit_seen<=0; finish_d<=0; video_timer<=0;
        end else begin
            done<=0; parser_start<=0; scaler_start<=0; pixel_valid<=0;
            finish_d<=write_finish;
            if(state==V_IDLE || state==V_FATAL || watchdog_progress) video_timer<=0;
            else video_timer<=video_timer+1'b1;
            if(frame_active && (last_pixel_now || scaler_done)) source_complete<=1;
            // 忽略源输出结束以前的过期完成脉冲；最后像素同拍完成也不丢。
            if(frame_active && finish_rise && (source_complete || last_pixel_now || scaler_done)) commit_seen<=1;
            if(state==V_FATAL) begin
                // 只允许共同复位恢复；保持 SD 请求邮箱不变，隔离所有迟到数据。
                frame_active<=0;
            end else if(abort && state!=V_IDLE) begin
                fatal(8'h30);
            end else if(VIDEO_TIMEOUT_CYCLES>0 && state!=V_IDLE &&
                        !watchdog_progress && video_timer>=VIDEO_TIMEOUT_CYCLES-1) begin
                fatal(8'h24);
            end else if(frame_active && scaler_bad) begin
                fatal(8'h23);
            end else if(frame_active && (source_complete || last_pixel_now || scaler_done) &&
                        (commit_seen || (finish_rise && (source_complete || last_pixel_now || scaler_done)))) begin
                state<=V_IDLE; frame_active<=0; img_loaded<=1; done<=1;
            end else case(state)
                V_IDLE: if(load_start && ready) begin
                    base_lba<=bmp_start_sector; cache_valid<=0;
                    img_loaded<=0; format_error<=0; error_code<=0; write_abort_req<=0;
                    frame_active<=0; source_complete<=0; commit_seen<=0;
                    byte_address<=0; header_index<=0; header_mode<=1;
                    state<=V_HEADER_START;
                end
                V_HEADER_START: if(parser_ready && scaler_ready) begin
                    parser_start<=1; state<=V_HEADER_GAP;
                end
                V_HEADER_GAP: state<=V_SELECT;
                V_SELECT: begin
                    if(wanted_lba[32]) fatal(8'h22);
                    else if(cache_valid && cache_lba==wanted_lba[31:0]) state<=V_READ;
                    else begin
                        request_lba<=wanted_lba[31:0]; req_toggle<=~req_toggle;
                        cache_valid<=0; state<=V_WAIT_SECTOR;
                    end
                end
                V_WAIT_SECTOR: if(rsp_sync[1]!=rsp_seen) begin
                    rsp_seen<=rsp_sync[1];
                    // response_status 在 SD 响应后保持到下一次请求，随 toggle 安全采样。
                    if(response_status!=0) fatal(response_status==1 ? 8'h20 : 8'h21);
                    else begin cache_valid<=1; cache_lba<=request_lba; state<=V_READ; end
                end
                V_READ: state<=V_USE; // 同步 RAM 首字节预取，后续在 USE 中流水消费
                V_USE: begin
                    if(header_mode) begin
                        if(parser_byte_ready) begin
                            if(header_index==53) state<=V_META;
                            else begin
                                header_index<=header_index+1'b1;
                                byte_address<=byte_address+1'b1;
                                // 本模块只读前 54 字节；保留通用扇区边界保护。
                                if(byte_address[8:0]==9'd511) state<=V_SELECT;
                            end
                        end
                    end else begin
                        byte_address<=byte_address+1'b1;
                        row_remaining<=row_remaining-1'b1;
                        case(component)
                            0: begin blue<=sector_q; component<=1; end
                            1: begin green<=sector_q; component<=2; end
                            2: begin pixel_rgb<={sector_q,green,blue}; pixel_valid<=1; component<=0; end
                            default: component<=0;
                        endcase
                        if(row_remaining==1) state<=V_ROW_RELEASE;
                        else if(byte_address[8:0]==9'd511) state<=V_SELECT;
                        // 否则保持 USE，下一拍 q 已是下一字节；B/G 跨扇区保留。
                    end
                end
                V_META: if(parser_done) begin
                    if(!parser_valid) begin
                        format_error<=1; error_code<={4'h1,parser_error}; done<=1; state<=V_IDLE;
                    end else if(image_w<MIN_SRC_WIDTH || image_h<MIN_SRC_HEIGHT) begin
                        format_error<=1; error_code<=8'h17; done<=1; state<=V_IDLE;
                    end else if(last_lba[32]) begin
                        format_error<=1; error_code<=8'h22; done<=1; state<=V_IDLE;
                    end else begin header_mode<=0; state<=V_SCALE_START; end
                end
                V_SCALE_START: begin scaler_start<=1; frame_active<=1; state<=V_RUN; end
                V_RUN: begin
                    if(scaler_done || source_complete) state<=V_COMMIT;
                    else if(line_ready) begin
                        byte_address<=row_byte_address;
                        row_remaining<=image_w*12'd3; component<=0;
                        state<=V_SELECT;
                    end
                end
                // 最后 RGB 脉冲在下一上升沿被 scaler 接收；等请求撤销再调度下一行。
                V_ROW_RELEASE: if(!line_ready) state<=V_RUN;
                V_COMMIT: ; // 全局完成条件等待真实存储提交事件
                default: state<=V_IDLE;
            endcase
        end
    end
endmodule

`timescale 1ns/1ps
// Quality-selected RGB24 aspect-fit scaler for 640x480 output.
// 1:1/thin images use nearest fallback; enlargement uses bilinear;
// reduction uses a 2x2 box average. Four BRAM-friendly line copies provide
// p00/p10/p01/p11, and two arithmetic stages sustain one pixel per clock.
module contest_image_scaler (
    input wire clk,input wire rst,input wire start,input wire abort,
    input wire [15:0] cfg_src_width,input wire [15:0] cfg_src_height,
    input wire cfg_format_valid,input wire bmp_data_wr_en,
    input wire [23:0] bmp_data,input wire write_req_ack,
    output wire ready,output wire busy,output reg done,
    output wire o_format_error,output reg [3:0] error,
    output wire o_line_ready,output wire [15:0] o_src_y,
    output wire write_req,output wire write_en,output wire [23:0] write_data,
    output wire [9:0] o_x,output wire [8:0] o_y,
    output wire o_border_flag,output wire o_sof,output wire o_eol,output wire o_last,
    output reg [9:0] scaled_width,output reg [8:0] scaled_height,
    output reg [9:0] offset_x,output reg [8:0] offset_y
);
    localparam [3:0] ST_IDLE=4'd0,ST_DIV=4'd1,ST_REQ=4'd2,ST_ACK_LOW=4'd3,
                     ST_ROW_PREP=4'd4,ST_LOAD0=4'd5,ST_LOAD_GAP=4'd6,
                     ST_LOAD1=4'd7,ST_STREAM=4'd8,ST_FLUSH=4'd9;
    localparam [1:0] MODE_NEAREST=2'd0,MODE_BILINEAR=2'd1,MODE_BOX=2'd2;
    localparam [23:0] BORDER_RGB=24'h001030;
    reg [3:0] state;
    reg [15:0] src_width,src_height;
    reg width_limited;
    reg [1:0] quality_mode;

    // Two logical rows, each duplicated for two synchronous read addresses.
    // Sized to max image width 640 (depth 0:639) to fit in 1024-deep B9K BRAMs (saves 12 BRAMs).
    (* ram_style="bram" *) reg [23:0] line0[0:1279];
    (* ram_style="bram" *) reg [23:0] line1[0:1279];
    reg [10:0] capture_x;
    // Insert one deliberate LUT on each line-buffer write address.  During a
    // valid write abort is low, therefore this is logically identical to
    // capture_x; the extra physical delay prevents TD 6.2 from creating a
    // sub-10 ps hold-fix loop on the inferred BRAM address pins.
    (* keep="true" *) wire [10:0] capture_addr_safe=capture_x^{11{abort}};
    reg [15:0] requested_row,row0_y,row1_y;

    // 16.16 source-coordinate increments, computed once per image.
    reg [31:0] x_step_q16,y_step_q16,x_phase_q16,y_phase_q16;
    reg [9:0] scan_x;
    reg [8:0] scan_y;

    // Shared setup divider.
    reg [31:0] div_shift,div_quotient;
    reg [16:0] div_remainder;
    reg [15:0] div_denominator;
    reg [5:0] div_count;
    reg [1:0] div_phase;
    wire [16:0] div_trial={div_remainder[15:0],div_shift[31]};
    wire div_subtract=div_trial>={1'b0,div_denominator};
    wire [16:0] div_remainder_next=div_subtract ?
                 div_trial-{1'b0,div_denominator}:div_trial;
    wire [31:0] div_quotient_next={div_quotient[30:0],div_subtract};
    wire [15:0] fit_dimension=(div_quotient_next==0)?16'd1:div_quotient_next[15:0];

    wire [10:0] image_end_x={1'b0,offset_x}+{1'b0,scaled_width};
    wire [9:0] image_end_y={1'b0,offset_y}+{1'b0,scaled_height};
    wire active_row=(scan_y>=offset_y)&&({1'b0,scan_y}<image_end_y);
    wire scan_border=!active_row||(scan_x<offset_x)||({1'b0,scan_x}>=image_end_x);
    wire issue_enable=(state==ST_STREAM)&&!rst&&!abort;
    wire source_violation=bmp_data_wr_en&&(state!=ST_IDLE)&&
                          (state!=ST_LOAD0)&&(state!=ST_LOAD1);
    wire last_active_x=active_row&&({1'b0,scan_x}==image_end_x-11'd1);
    wire last_active_y=active_row&&({1'b0,scan_y}==image_end_y-10'd1);
    wire [15:0] phase_x_raw=x_phase_q16[31:16];
    wire [15:0] sample_x0=last_active_x ? src_width-16'd1 :
                            ((phase_x_raw>=src_width)?src_width-16'd1:phase_x_raw);
    wire [15:0] sample_x1=(sample_x0+16'd1>=src_width)?sample_x0:sample_x0+16'd1;
    wire [15:0] phase_y_raw=y_phase_q16[31:16];
    wire [15:0] prep_y0=last_active_y ? src_height-16'd1 :
                          ((phase_y_raw>=src_height)?src_height-16'd1:phase_y_raw);
    wire [15:0] prep_y1=(prep_y0+16'd1>=src_height)?prep_y0:prep_y0+16'd1;

    assign ready=(state==ST_IDLE)&&!rst&&!abort;
    assign busy=(state!=ST_IDLE)&&!rst&&!abort;
    assign o_format_error=(error!=0);
    assign o_line_ready=((state==ST_LOAD0)||(state==ST_LOAD1))&&!rst&&!abort;
    assign o_src_y=requested_row;
    assign write_req=(state==ST_REQ)&&!rst&&!abort&&!source_violation;

    reg [23:0] p00, p01;
    wire [23:0] p10 = p00;
    wire [23:0] p11 = p01;

    wire line0_wr = o_line_ready && bmp_data_wr_en && (state == ST_LOAD0);
    wire line1_wr = o_line_ready && bmp_data_wr_en && ((state != ST_LOAD0) || (row0_y == row1_y));

    // Dedicated synchronous BRAM blocks (1 write port, 1 read port each for clean SDP BRAM inference)
    always @(posedge clk) begin
        if(line0_wr)
            line0[capture_addr_safe] <= bmp_data;
        if(issue_enable && !scan_border)
            p00 <= line0[sample_x0[10:0]];
    end

    always @(posedge clk) begin
        if(line1_wr)
            line1[capture_addr_safe] <= bmp_data;
        if(issue_enable && !scan_border)
            p01 <= line1[sample_x0[10:0]];
    end
    reg s0_valid,s0_border,s0_sof,s0_eol,s0_last;
    reg [9:0] s0_x;
    reg [8:0] s0_y;
    reg [7:0] s0_wx,s0_wy;
    reg [1:0] s0_mode;
    reg s1_valid,s1_border,s1_sof,s1_eol,s1_last;
    reg [9:0] s1_x;
    reg [8:0] s1_y;
    reg [7:0] s1_wy;
    reg [1:0] s1_mode;
    reg [16:0] h0_r,h0_g,h0_b,h1_r,h1_g,h1_b;
    wire [8:0] wx_inv=9'd256-{1'b0,s0_wx};

    reg output_valid,out_border,out_sof,out_eol,out_last;
    reg [9:0] out_x;
    reg [8:0] out_y;
    reg [23:0] out_rgb;
    wire [8:0] wy_inv=9'd256-{1'b0,s1_wy};
    wire [25:0] blend_r=h0_r*wy_inv+h1_r*{1'b0,s1_wy}+26'd32768;
    wire [25:0] blend_g=h0_g*wy_inv+h1_g*{1'b0,s1_wy}+26'd32768;
    wire [25:0] blend_b=h0_b*wy_inv+h1_b*{1'b0,s1_wy}+26'd32768;
    wire [17:0] box_r=h0_r+h1_r+18'd2;
    wire [17:0] box_g=h0_g+h1_g+18'd2;
    wire [17:0] box_b=h0_b+h1_b+18'd2;
    assign write_en=output_valid&&!rst&&!abort&&!source_violation;
    assign write_data=write_en?out_rgb:24'd0;
    assign o_x=write_en?out_x:10'd0;
    assign o_y=write_en?out_y:9'd0;
    assign o_border_flag=write_en&&out_border;
    assign o_sof=write_en&&out_sof;
    assign o_eol=write_en&&out_eol;
    assign o_last=write_en&&out_last;

    // Line buffering and the two-stage quality pipeline.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            s0_valid<=0;s1_valid<=0;output_valid<=0;out_rgb<=0;
            out_x<=0;out_y<=0;out_border<=0;out_sof<=0;out_eol<=0;out_last<=0;
        end else if(abort||source_violation) begin
            s0_valid<=0;s1_valid<=0;output_valid<=0;
        end else begin
            s0_valid<=issue_enable;
            if(issue_enable) begin
                s0_x<=scan_x;s0_y<=scan_y;s0_border<=scan_border;
                s0_sof<=(scan_x==0)&&(scan_y==0);s0_eol<=(scan_x==10'd639);
                s0_last<=(scan_x==10'd639)&&(scan_y==9'd479);
                s0_wx<=last_active_x?8'd0:x_phase_q16[15:8];
                s0_wy<=last_active_y?8'd0:y_phase_q16[15:8];s0_mode<=quality_mode;
            end
            s1_valid<=s0_valid;s1_border<=s0_border;s1_sof<=s0_sof;
            s1_eol<=s0_eol;s1_last<=s0_last;s1_x<=s0_x;s1_y<=s0_y;
            s1_wy<=s0_wy;s1_mode<=s0_mode;
            if(s0_mode==MODE_BILINEAR) begin
                h0_r<=p00[23:16]*wx_inv+p10[23:16]*{1'b0,s0_wx};
                h0_g<=p00[15:8]*wx_inv+p10[15:8]*{1'b0,s0_wx};
                h0_b<=p00[7:0]*wx_inv+p10[7:0]*{1'b0,s0_wx};
                h1_r<=p01[23:16]*wx_inv+p11[23:16]*{1'b0,s0_wx};
                h1_g<=p01[15:8]*wx_inv+p11[15:8]*{1'b0,s0_wx};
                h1_b<=p01[7:0]*wx_inv+p11[7:0]*{1'b0,s0_wx};
            end else if(s0_mode==MODE_BOX) begin
                h0_r<={9'd0,p00[23:16]}+{9'd0,p10[23:16]};
                h0_g<={9'd0,p00[15:8]}+{9'd0,p10[15:8]};
                h0_b<={9'd0,p00[7:0]}+{9'd0,p10[7:0]};
                h1_r<={9'd0,p01[23:16]}+{9'd0,p11[23:16]};
                h1_g<={9'd0,p01[15:8]}+{9'd0,p11[15:8]};
                h1_b<={9'd0,p01[7:0]}+{9'd0,p11[7:0]};
            end else begin
                h0_r<={1'b0,p00[23:16],8'd0};h0_g<={1'b0,p00[15:8],8'd0};
                h0_b<={1'b0,p00[7:0],8'd0};h1_r<=0;h1_g<=0;h1_b<=0;
            end
            output_valid<=s1_valid;out_border<=s1_border;out_sof<=s1_sof;
            out_eol<=s1_eol;out_last<=s1_last;out_x<=s1_x;out_y<=s1_y;
            if(s1_border) out_rgb<=BORDER_RGB;
            else if(s1_mode==MODE_BILINEAR)
                out_rgb<={blend_r[23:16],blend_g[23:16],blend_b[23:16]};
            else if(s1_mode==MODE_BOX)
                out_rgb<={box_r[9:2],box_g[9:2],box_b[9:2]};
            else out_rgb<={h0_r[15:8],h0_g[15:8],h0_b[15:8]};
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=ST_IDLE;done<=0;error<=0;scaled_width<=0;scaled_height<=0;
            offset_x<=0;offset_y<=0;src_width<=0;src_height<=0;width_limited<=0;
            quality_mode<=MODE_NEAREST;capture_x<=0;requested_row<=0;row0_y<=0;row1_y<=0;
            x_step_q16<=0;y_step_q16<=0;x_phase_q16<=0;y_phase_q16<=0;
            scan_x<=0;scan_y<=0;div_shift<=0;div_quotient<=0;div_remainder<=0;
            div_denominator<=0;div_count<=0;div_phase<=0;
        end else if(abort) begin
            state<=ST_IDLE;done<=0;error<=0;scaled_width<=0;scaled_height<=0;
            offset_x<=0;offset_y<=0;x_phase_q16<=0;y_phase_q16<=0;scan_x<=0;scan_y<=0;
        end else if(source_violation) begin
            state<=ST_IDLE;done<=1;error<=4'd3;
        end else begin
            done<=0;
            case(state)
                ST_IDLE: if(start) begin
                    error<=0;scaled_width<=0;scaled_height<=0;offset_x<=0;offset_y<=0;
                    capture_x<=0;x_phase_q16<=0;y_phase_q16<=0;scan_x<=0;scan_y<=0;
                    if(!cfg_format_valid) begin error<=4'd1;done<=1;end
                    else if((cfg_src_width==0)||(cfg_src_height==0)||
                            (cfg_src_width>1280)||(cfg_src_height>1024)) begin
                        error<=4'd2;done<=1;
                    end else begin
                        src_width<=cfg_src_width;src_height<=cfg_src_height;
                        div_quotient<=0;div_remainder<=0;div_count<=0;div_phase<=0;
                        if((cfg_src_width*32'd480)>=(cfg_src_height*32'd640)) begin
                            width_limited<=1;div_shift<=cfg_src_height*32'd640;
                            div_denominator<=cfg_src_width;
                        end else begin
                            width_limited<=0;div_shift<=cfg_src_width*32'd480;
                            div_denominator<=cfg_src_height;
                        end
                        state<=ST_DIV;
                    end
                end
                ST_DIV: begin
                    div_shift<={div_shift[30:0],1'b0};div_quotient<=div_quotient_next;
                    div_remainder<=div_remainder_next;
                    if(div_count==6'd31) begin
                        div_count<=0;div_quotient<=0;div_remainder<=0;
                        if(div_phase==0) begin
                            if(width_limited) begin
                                scaled_width<=10'd640;scaled_height<=fit_dimension[8:0];
                                offset_x<=0;offset_y<=(9'd480-fit_dimension[8:0])>>1;
                                if((src_width==640)&&(src_height==fit_dimension)) quality_mode<=MODE_NEAREST;
                                else if((src_width<=640)&&(src_height<=fit_dimension)&&
                                        (src_width>1)&&(src_height>1)) quality_mode<=MODE_BILINEAR;
                                else if((src_width>1)&&(src_height>1)) quality_mode<=MODE_BOX;
                                else quality_mode<=MODE_NEAREST;
                                div_denominator<=16'd639;
                            end else begin
                                scaled_width<=fit_dimension[9:0];scaled_height<=9'd480;
                                offset_x<=(10'd640-fit_dimension[9:0])>>1;offset_y<=0;
                                if((src_width==fit_dimension)&&(src_height==480)) quality_mode<=MODE_NEAREST;
                                else if((src_width<=fit_dimension)&&(src_height<=480)&&
                                        (src_width>1)&&(src_height>1)) quality_mode<=MODE_BILINEAR;
                                else if((src_width>1)&&(src_height>1)) quality_mode<=MODE_BOX;
                                else quality_mode<=MODE_NEAREST;
                                div_denominator<=(fit_dimension>1)?fit_dimension-16'd1:16'd1;
                            end
                            div_shift<=(src_width>1)?{src_width-16'd1,16'd0}:32'd0;
                            div_phase<=1;
                        end else if(div_phase==1) begin
                            x_step_q16<=div_quotient_next;
                            div_shift<=(src_height>1)?{src_height-16'd1,16'd0}:32'd0;
                            div_denominator<=(scaled_height>1)?{7'd0,scaled_height-9'd1}:16'd1;
                            div_phase<=2;
                        end else begin y_step_q16<=div_quotient_next;state<=ST_REQ;end
                    end else div_count<=div_count+1'b1;
                end
                ST_REQ: if(write_req_ack) state<=ST_ACK_LOW;
                ST_ACK_LOW: if(!write_req_ack) state<=ST_ROW_PREP;
                ST_ROW_PREP: begin
                    scan_x<=0;x_phase_q16<=0;
                    if(active_row) begin
                        row0_y<=prep_y0;row1_y<=prep_y1;requested_row<=prep_y0;
                        capture_x<=0;state<=ST_LOAD0;
                    end else state<=ST_STREAM;
                end
                ST_LOAD0: if(bmp_data_wr_en) begin
                    if(capture_x==src_width-16'd1) begin
                        capture_x<=0;
                        if(row0_y==row1_y) state<=ST_STREAM;
                        else begin requested_row<=row1_y;state<=ST_LOAD_GAP;end
                    end else capture_x<=capture_x+1'b1;
                end
                ST_LOAD_GAP: state<=ST_LOAD1;
                ST_LOAD1: if(bmp_data_wr_en) begin
                    if(capture_x==src_width-16'd1) begin capture_x<=0;state<=ST_STREAM;end
                    else capture_x<=capture_x+1'b1;
                end
                ST_STREAM: begin
                    if(scan_x==10'd639) state<=ST_FLUSH;
                    else scan_x<=scan_x+1'b1;
                    if(!scan_border&&({1'b0,scan_x}!=image_end_x-11'd1))
                        x_phase_q16<=x_phase_q16+x_step_q16;
                end
                ST_FLUSH: if(write_en&&out_eol) begin
                    if(out_y==9'd479) begin done<=1;state<=ST_IDLE;end
                    else begin
                        if(active_row&&({1'b0,scan_y}!=image_end_y-10'd1))
                            y_phase_q16<=y_phase_q16+y_step_q16;
                        scan_y<=scan_y+1'b1;state<=ST_ROW_PREP;
                    end
                end
                default: state<=ST_IDLE;
            endcase
        end
    end
endmodule

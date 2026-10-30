`timescale 1ns/1ps
// Self-checking Verilog-2001 testbench. The golden model uses widened integer
// arithmetic and modulo padding, independently of the RTL implementation.
module tb_contest_bmp_meta_parser;
    reg clk, rst, start, abort, s_valid, s_last;
    reg [7:0] s_data;
    wire ready, busy, s_ready, done, meta_valid, top_down, format_error;
    wire [3:0] error;
    wire [15:0] width, height, row_stride;
    wire [31:0] file_size, pixel_offset, dib_size;
    wire [31:0] pixel_bytes, pixel_count;
    wire [1:0] row_padding;
    wire lim_ready, lim_busy, lim_s_ready, lim_done, lim_valid, lim_top, lim_format_error;
    wire [3:0] lim_error;
    wire [15:0] lim_width, lim_height, lim_stride;
    wire [31:0] lim_file, lim_offset, lim_dib, lim_bytes, lim_count;
    wire [1:0] lim_padding;

    contest_bmp_meta_parser #(.MAX_WIDTH(65535), .MAX_HEIGHT(65535)) dut (
        .clk(clk), .rst(rst), .start(start), .abort(abort),
        .s_valid(s_valid), .s_data(s_data), .s_last(s_last), .s_ready(s_ready),
        .ready(ready), .busy(busy), .done(done), .o_format_valid(meta_valid),
        .o_format_error(format_error), .o_error_code(error), .o_width(width), .o_height(height),
        .o_top_down(top_down), .file_size(file_size), .o_pixel_offset(pixel_offset),
        .dib_size(dib_size), .o_row_stride(row_stride), .row_padding(row_padding),
        .pixel_bytes(pixel_bytes), .pixel_count(pixel_count)
    );
    // No override here: this also verifies the inclusive production defaults
    // MAX_WIDTH=1280 and MAX_HEIGHT=1024, separately from the wide-limit DUT.
    contest_bmp_meta_parser limited_dut (
        .clk(clk), .rst(rst), .start(start), .abort(abort),
        .s_valid(s_valid), .s_data(s_data), .s_last(s_last), .s_ready(lim_s_ready),
        .ready(lim_ready), .busy(lim_busy), .done(lim_done), .o_format_valid(lim_valid),
        .o_format_error(lim_format_error), .o_error_code(lim_error), .o_width(lim_width), .o_height(lim_height),
        .o_top_down(lim_top), .file_size(lim_file), .o_pixel_offset(lim_offset),
        .dib_size(lim_dib), .o_row_stride(lim_stride), .row_padding(lim_padding),
        .pixel_bytes(lim_bytes), .pixel_count(lim_count)
    );

    reg [7:0] header [0:53];
    reg [31:0] rng;
    reg [3:0] expected_main, expected_limited;
    reg [11:0] error_coverage;
    reg [3:0] padding_coverage;
    reg previous_done;
    integer cases, successes, failures, accepted_bytes, start_count;
    integer aborted_count, async_reset_count, cycles, base_case;
    integer i, j, choice, random_w, random_h, random_dib;
    reg [31:0] random_colors, random_offset;
    reg [8*80-1:0] case_name;

    task fail;
        input [8*160-1:0] reason;
        begin
            $display("FAIL tb_contest_bmp_meta_parser case=%0d label=%0s cycle=%0d: %0s",
                     cases + 1, case_name, cycles, reason);
            $finish;
        end
    endtask

    function [31:0] rd32;
        input integer index;
        begin rd32 = {header[index+3],header[index+2],header[index+1],header[index]}; end
    endfunction

    function [15:0] rd16;
        input integer index;
        begin rd16 = {header[index+1],header[index]}; end
    endfunction

    function [31:0] random_next;
        input integer unused;
        begin
            rng = rng * 32'd1664525 + 32'd1013904223;
            random_next = rng;
        end
    endfunction

    task wr32;
        input integer index;
        input [31:0] value;
        begin
            header[index] = value[7:0]; header[index+1] = value[15:8];
            header[index+2] = value[23:16]; header[index+3] = value[31:24];
        end
    endtask

    task wr16;
        input integer index;
        input [15:0] value;
        begin header[index] = value[7:0]; header[index+1] = value[15:8]; end
    endtask

    function [3:0] reference_error;
        input integer max_w;
        input integer max_h;
        reg [31:0] w, signed_h, h, dib, offset, colors;
        reg [63:0] raw_row, stride, bytes_required, header_required, file_required;
        begin
            w = rd32(18); signed_h = rd32(22);
            h = signed_h[31] ? (32'd0 - signed_h) : signed_h;
            dib = rd32(14); offset = rd32(10); colors = rd32(46);
            raw_row = {32'd0,w} * 64'd3;
            stride = raw_row + ((64'd4 - (raw_row % 64'd4)) % 64'd4);
            bytes_required = stride * {32'd0,h};
            header_required = 64'd14 + {32'd0,dib} + 64'd4 * {32'd0,colors};
            file_required = {32'd0,offset} + bytes_required;
            if (rd16(0) != 16'h4d42) reference_error = 2;
            else if (rd32(6) != 0) reference_error = 11;
            else if (!(dib == 40 || dib == 108 || dib == 124)) reference_error = 3;
            else if (rd16(26) != 1) reference_error = 4;
            else if (rd16(28) != 24) reference_error = 5;
            else if (rd32(30) != 0) reference_error = 6;
            else if (w == 0 || w[31] || w > 65535 || w > max_w ||
                     h == 0 || signed_h == 32'h80000000 || h > 65535 || h > max_h)
                reference_error = 7;
            else if (header_required > 64'd4294967295 || {32'd0,offset} < header_required)
                reference_error = 8;
            else if (stride > 64'd65535 || bytes_required > 64'd4294967295 || file_required > 64'd4294967295 ||
                     {32'd0,rd32(2)} < file_required)
                reference_error = 9;
            else if (rd32(34) != 0 && {32'd0,rd32(34)} != bytes_required)
                reference_error = 10;
            else reference_error = 0;
        end
    endfunction

    task make_header;
        input [31:0] w;
        input [31:0] h_signed;
        input [31:0] dib;
        input [31:0] colors;
        input [31:0] offset;
        input integer zero_image_size;
        input [31:0] trailing_bytes;
        integer k;
        reg [31:0] h;
        reg [63:0] raw, stride, payload, extent;
        begin
            for (k=0; k<54; k=k+1) header[k]=0;
            h = h_signed[31] ? 32'd0-h_signed : h_signed;
            raw = {32'd0,w} * 64'd3;
            stride = raw + ((64'd4 - (raw % 64'd4)) % 64'd4);
            payload = stride * {32'd0,h};
            extent = {32'd0,offset} + payload + {32'd0,trailing_bytes};
            wr16(0,16'h4d42); wr32(2,extent[31:0]); wr32(10,offset);
            wr32(14,dib); wr32(18,w); wr32(22,h_signed);
            wr16(26,1); wr16(28,24); wr32(30,0);
            if (zero_image_size) wr32(34,0); else wr32(34,payload[31:0]);
            wr32(38,32'h00000b13); wr32(42,32'h00000b13);
            wr32(46,colors); wr32(50,32'hcafed00d);
        end
    endtask

    task assert_zero_metadata;
        begin
            if ({width,height,top_down,file_size,pixel_offset,dib_size,row_stride,
                 row_padding,pixel_bytes,pixel_count} !== 211'b0)
                fail("primary metadata is not cleared");
            if ({lim_width,lim_height,lim_top,lim_file,lim_offset,lim_dib,lim_stride,
                 lim_padding,lim_bytes,lim_count} !== 211'b0)
                fail("default-limit metadata is not cleared");
        end
    endtask

    task assert_cleared;
        begin
            assert_zero_metadata;
            if ({meta_valid,error,done,lim_valid,lim_error,lim_done} !== 12'b0)
                fail("status was not cleared");
        end
    endtask

    task cycle;
        input start_value, abort_value, valid_value, last_value;
        input [7:0] data_value;
        begin
            @(negedge clk);
            start=start_value; abort=abort_value; s_valid=valid_value;
            s_last=last_value; s_data=data_value;
            @(posedge clk); #1;
        end
    endtask

    task begin_transaction;
        begin
            if (ready !== 1 || busy !== 0 || s_ready !== 0)
                fail("transaction began outside idle");
            // Deliberately present a bogus byte and EOF on start: neither counts.
            cycle(1,0,1,1,8'hff);
            start_count=start_count+1;
            assert_cleared;
            if (ready !== 0 || busy !== 1 || s_ready !== 1)
                fail("start did not enter collection");
        end
    endtask

    task check_result;
        input [3:0] expected;
        input integer limited;
        input integer done_expected;
        reg [15:0] aw, ah, ast;
        reg at, av, ad;
        reg [3:0] ae;
        reg [31:0] af, ao, adi, ab, ac, h, w;
        reg [1:0] ap;
        reg [63:0] raw, stride, padding, bytes_expected, count_expected;
        begin
            if (limited) begin
                aw=lim_width; ah=lim_height; at=lim_top; av=lim_valid; ad=lim_done;
                ae=lim_error; af=lim_file; ao=lim_offset; adi=lim_dib; ast=lim_stride;
                ap=lim_padding; ab=lim_bytes; ac=lim_count;
            end else begin
                aw=width; ah=height; at=top_down; av=meta_valid; ad=done;
                ae=error; af=file_size; ao=pixel_offset; adi=dib_size; ast=row_stride;
                ap=row_padding; ab=pixel_bytes; ac=pixel_count;
            end
            if (ad !== done_expected[0]) fail("done timing or sticky pulse mismatch");
            if (ae !== expected) begin
                $display("DETAIL limited=%0d expected_error=%0d actual_error=%0d",limited,expected,ae);
                fail("wrong error code");
            end
            if (av !== (expected == 0)) fail("format-valid disagrees with result");
            if (expected != 0) begin
                if ({aw,ah,at,af,ao,adi,ast,ap,ab,ac} !== 211'b0)
                    fail("rejected header published metadata");
            end else begin
                w=rd32(18); h=rd32(22);
                if (h[31]) h=32'd0-h;
                raw={32'd0,w}*64'd3;
                padding=(64'd4-(raw%64'd4))%64'd4;
                stride=raw+padding;
                bytes_expected=stride*{32'd0,h}; count_expected={32'd0,w}*{32'd0,h};
                if (aw !== w[15:0] || ah !== h[15:0] || at !== header[25][7] ||
                    af !== rd32(2) || ao !== rd32(10) || adi !== rd32(14) ||
                    stride[63:16] !== 48'b0 || ast !== stride[15:0] || ap !== padding[1:0] ||
                    ab !== bytes_expected[31:0] || ac !== count_expected[31:0]) begin
                    $display("DETAIL limited=%0d width=%0d height=%0d stride=%0d bytes=%0d",
                             limited,aw,ah,ast,ab);
                    fail("success metadata disagrees with golden arithmetic");
                end
            end
        end
    endtask

    task finish_transaction;
        integer wait_cycles, k;
        begin
            wait_cycles=0;
            while (done !== 1 && wait_cycles < 3) begin
                if (s_ready !== 0) fail("accepted input after last header byte or EOF");
                cycle(0,0,1,1,8'h5a);
                wait_cycles=wait_cycles+1;
            end
            if (done !== 1) fail("missing completion");
            if (ready !== 1 || busy !== 0 || s_ready !== 0)
                fail("completion not idle");
            check_result(expected_main,0,1); check_result(expected_limited,1,1);
            cases=cases+1;
            error_coverage[expected_main]=1'b1;
            if (expected_main == 0) begin
                successes=successes+1; padding_coverage[row_padding]=1'b1;
            end else failures=failures+1;
            // More source bytes while idle must not modify sticky results.
            for (k=0; k<3; k=k+1) begin
                cycle(0,0,1,1,8'ha0+k);
                check_result(expected_main,0,0); check_result(expected_limited,1,0);
                if (ready !== 1 || busy !== 0 || s_ready !== 0)
                    fail("idle source data changed stream state");
            end
        end
    endtask

    task run_case;
        input integer length;
        input integer last_at_end;
        input integer bubbles;
        input integer busy_start;
        integer k;
        begin
            expected_main = reference_error(65535,65535);
            expected_limited = reference_error(1280,1024);
            if (length < 54 && last_at_end) begin expected_main=1; expected_limited=1; end
            begin_transaction;
            for (k=0; k<length; k=k+1) begin
                if (bubbles && (k%5 == 0 || k%11 == 0)) begin
                    cycle(0,0,0,1,8'haa);
                    assert_cleared;
                    if (busy !== 1 || s_ready !== 1) fail("bubble or nontransfer EOF changed state");
                end
                cycle(busy_start && k%7==0,0,1,last_at_end && k==length-1,header[k]);
                if (k < length-1) begin
                    assert_cleared;
                    if (busy !== 1 || s_ready !== 1) fail("early end or busy start reset stream");
                end
            end
            if (length == 54) begin
                assert_cleared;
                if (busy !== 1 || s_ready !== 0 || ready !== 0)
                    fail("byte53 must enter one-cycle evaluation");
                cycle(0,0,1,1,8'hff);
                if (done !== 1) fail("result not produced on cycle after byte53");
            end
            finish_transaction;
        end
    endtask

    task run_default_checked;
        input [3:0] intended_default_error;
        input integer bubbles;
        begin
            if (reference_error(1280,1024) !== intended_default_error)
                fail("resolution scenario has wrong default-limit reference error");
            run_full(0,bubbles);
        end
    endtask

    task run_full;
        input [3:0] intended_error;
        input integer bubbles;
        begin
            if (reference_error(65535,65535) !== intended_error)
                fail("directed scenario does not have intended reference error");
            run_case(54,cases%2,bubbles,1);
        end
    endtask

    task make_random_valid;
        begin
            random_w=(random_next(0)%2048)+1;
            random_h=(random_next(0)%1024)+1;
            choice=random_next(0)%3;
            if (choice==0) random_dib=40; else if (choice==1) random_dib=108; else random_dib=124;
            random_colors=random_next(0)%16;
            random_offset=14+random_dib+4*random_colors+(random_next(0)%17);
            choice=random_next(0)%2;
            if (choice) random_h=0-random_h;
            make_header(random_w,random_h,random_dib,random_colors,random_offset,
                        random_next(0)%2,random_next(0)%64);
            wr32(38,random_next(0)); wr32(42,random_next(0)); wr32(50,random_next(0));
        end
    endtask

    always #20 clk=~clk; // Single 25 MHz video clock.
    always @(posedge clk) begin
        cycles=cycles+1;
        if (!rst && !abort && s_valid && s_ready) accepted_bytes=accepted_bytes+1;
        #1;
        if (done === 1 && previous_done === 1) fail("done lasted more than one cycle");
        previous_done=done;
        if ({ready,busy,s_ready,done} !== {lim_ready,lim_busy,lim_s_ready,lim_done})
            fail("default limits changed stream-control timing");
        if (!rst && !abort && ready === busy) fail("ready/busy are not complementary");
        if (s_ready && !busy) fail("input ready while idle");
        if (format_error !== (error != 0) || lim_format_error !== (lim_error != 0))
            fail("format-error flag disagrees with error code");
    end

    initial begin
        #20000000;
        $display("FAIL tb_contest_bmp_meta_parser global watchdog");
        $finish;
    end

    initial begin
        clk=0; rst=1; start=0; abort=0; s_valid=0; s_last=0; s_data=0;
        rng=32'hb17b24a5; cases=0; successes=0; failures=0; accepted_bytes=0;
        start_count=0; aborted_count=0; async_reset_count=0; cycles=0;
        previous_done=0; error_coverage=0; padding_coverage=0; case_name="reset_and_idle";
        cycle(0,0,0,0,0); assert_cleared;
        @(negedge clk); rst=0;
        cycle(0,0,1,1,8'hff); assert_cleared;
        if (ready !== 1 || s_ready !== 0 || busy !== 0) fail("idle input was consumed");

        base_case=cases; case_name="valid_directed";
        make_header(640,480,40,0,54,0,0); run_full(0,1);
        make_header(640,-480,40,0,54,1,27); run_full(0,0);
        for (i=1; i<=8; i=i+1) begin
            make_header(i,7+i,40,0,54,i%2,0); run_full(0,1);
        end
        make_header(13,-9,108,3,134,0,0); run_full(0,1);
        make_header(17,11,124,2,151,1,31); run_full(0,0);
        make_header(65535,1,40,0,54,0,0); run_full(9,1);
        make_header(1,65535,40,0,54,0,0); run_full(0,0);
        make_header(65535,-2,40,0,54,1,0); run_full(9,1);
        make_header(21844,65535,40,0,54,0,0); run_full(0,0);
        make_header(21844,-65535,40,0,54,1,0); run_full(0,1);
        make_header(641,480,40,0,54,0,0); run_full(0,0);
        make_header(640,481,40,0,54,0,0); run_full(0,1);
        make_header(1,-481,40,0,54,0,0); run_full(0,1);
        make_header(21843,1,40,0,54,0,0); run_full(0,0);
        make_header(21844,1,40,0,54,0,0); run_full(0,1);
        make_header(21845,1,40,0,54,0,0); run_full(9,0);
        $display("PASS parser metadata/padding/signed height/DIB108/124/16bit stride boundary/near4GiB cases=%0d",cases-base_case);

        base_case=cases; case_name="required_resolutions_and_inclusive_defaults";
        make_header(640,480,40,0,54,0,0); run_default_checked(0,1);
        make_header(320,240,40,0,54,1,0); run_default_checked(0,0);
        make_header(800,600,40,0,54,0,0); run_default_checked(0,1);
        make_header(1024,768,40,0,54,1,0); run_default_checked(0,0);
        make_header(480,480,40,0,54,0,0); run_default_checked(0,1);
        make_header(1280,1024,40,0,54,1,0); run_default_checked(0,0);
        make_header(1280,-1024,40,0,54,0,0); run_default_checked(0,1);
        make_header(1281,1025,40,0,54,0,0); run_default_checked(7,0);
        make_header(1281,1024,40,0,54,0,0); run_default_checked(7,1);
        make_header(1280,1025,40,0,54,0,0); run_default_checked(7,0);
        make_header(1280,-1025,40,0,54,0,0); run_default_checked(7,1);
        $display("PASS parser required resolutions default1280x1024 inclusive and over-limit rejection cases=%0d",cases-base_case);

        base_case=cases; case_name="all_truncated_prefix_lengths";
        for (i=1; i<=53; i=i+1) begin
            make_header(640,480,40,0,54,0,0);
            // Header faults cannot override early EOF's highest priority.
            if (i%2) begin header[0]=0; wr16(28,32); end
            run_case(i,1,i%2,1);
        end
        $display("PASS parser early EOF lengths1..53 and truncation priority cases=%0d",cases-base_case);

        base_case=cases; case_name="directed_format_and_full_width_errors";
        make_header(7,9,40,0,54,0,0); header[0]=8'h4d; run_full(2,1);
        make_header(7,9,40,0,54,0,0); header[1]=8'h42; run_full(2,0);
        for (i=6;i<=9;i=i+1) begin
            make_header(7,9,40,0,54,0,0); header[i]=8'h80; run_full(11,1);
        end
        make_header(7,9,12,0,54,0,0); run_full(3,0);
        make_header(7,9,0,0,54,0,0); run_full(3,1);
        make_header(7,9,41,0,54,0,0); run_full(3,0);
        make_header(7,9,32'hfffffffc,0,54,0,0); run_full(3,1);
        make_header(7,9,40,0,54,0,0); wr16(26,0); run_full(4,0);
        make_header(7,9,40,0,54,0,0); wr16(26,257); run_full(4,1);
        make_header(7,9,40,0,54,0,0); wr16(28,32); run_full(5,0);
        make_header(7,9,40,0,54,0,0); wr16(28,16'h0118); run_full(5,1);
        make_header(7,9,40,0,54,0,0); wr32(30,1); run_full(6,0);
        make_header(7,9,40,0,54,0,0); wr32(30,32'h80000000); run_full(6,1);
        make_header(0,9,40,0,54,0,0); run_full(7,1);
        make_header(-1,9,40,0,54,0,0); run_full(7,0);
        make_header(32'h80000001,9,40,0,54,0,0); run_full(7,1);
        make_header(32'h00010001,9,40,0,54,0,0); run_full(7,0);
        make_header(65536,9,40,0,54,0,0); run_full(7,1);
        make_header(32'h7fffffff,9,40,0,54,0,0); run_full(7,0);
        make_header(7,0,40,0,54,0,0); run_full(7,1);
        make_header(7,32'h80000000,40,0,54,0,0); run_full(7,0);
        make_header(7,32'hffff0000,40,0,54,0,0); run_full(7,1);
        make_header(7,32'h00010001,40,0,54,0,0); run_full(7,0);
        make_header(7,32'h7fffffff,40,0,54,0,0); run_full(7,1);
        $display("PASS parser signature/reserved/DIB/planes/bpp/compression/full32bit dimensions cases=%0d",cases-base_case);

        base_case=cases; case_name="offset_size_and_arithmetic_errors";
        make_header(7,9,40,0,53,0,0); run_full(8,1);
        make_header(7,9,108,0,121,0,0); run_full(8,0);
        make_header(7,9,124,0,137,0,0); run_full(8,1);
        make_header(7,9,40,3,65,0,0); run_full(8,0);
        make_header(7,9,40,32'h40000000,54,0,0); run_full(8,1);
        make_header(7,9,40,32'h3fffffff,32'hffffffff,0,0); run_full(8,0);
        make_header(7,9,40,0,54,0,0); wr32(2,rd32(2)-1); run_full(9,1);
        make_header(7,9,40,0,54,0,0); wr32(2,0); run_full(9,0);
        make_header(65535,65535,40,0,54,1,0); wr32(2,32'hffffffff); run_full(9,1);
        make_header(21846,65535,40,0,54,1,0); wr32(2,32'hffffffff); run_full(9,0);
        make_header(1,1,40,0,32'hfffffffc,1,0); wr32(2,32'hffffffff); run_full(9,1);
        make_header(1,1,40,0,32'hffffffff,1,0); wr32(2,32'hffffffff); run_full(9,0);
        make_header(7,9,40,0,54,0,0); wr32(34,1); run_full(10,1);
        make_header(7,9,40,0,54,0,0); wr32(34,rd32(34)-1); run_full(10,0);
        make_header(7,9,40,0,54,0,0); wr32(34,32'hffffffff); run_full(10,1);
        make_header(1,1,40,0,32'hfffffffB,0,0); run_full(0,0);
        $display("PASS parser offsets/palette/size declarations/payload and extent overflow cases=%0d",cases-base_case);

        base_case=cases; case_name="error_priority_chain";
        make_header(0,0,12,0,0,0,0);
        header[0]=0; header[6]=1; wr16(26,2); wr16(28,32); wr32(30,1); wr32(34,1);
        run_full(2,1); header[0]=8'h42; run_full(11,0);
        header[6]=0; run_full(3,1); wr32(14,40); run_full(4,0);
        wr16(26,1); run_full(5,1); wr16(28,24); run_full(6,0);
        wr32(30,0); run_full(7,1); wr32(18,1); wr32(22,1); run_full(8,0);
        wr32(10,54); run_full(9,1); wr32(2,58); run_full(10,0);
        wr32(34,4); run_full(0,1);
        $display("PASS parser complete error priority chain cases=%0d",cases-base_case);

        base_case=cases; case_name="deterministic_random_valid";
        for (i=0;i<200;i=i+1) begin make_random_valid; run_full(0,i%2); end
        $display("PASS parser deterministic random valid headers cases=%0d seed=b17b24a5",cases-base_case);

        base_case=cases; case_name="deterministic_random_mutations";
        for (i=0;i<132;i=i+1) begin
            make_random_valid;
            case (i%11)
                0: header[0]=header[0]^8'h01;
                1: header[6+(random_next(0)%4)]=8'h01;
                2: wr32(14,41);
                3: wr16(26,16'h0101);
                4: wr16(28,8);
                5: wr32(30,32'h00010000);
                6: wr32(18,rd32(18)|32'h00010000);
                7: wr32(22,32'h80000000);
                8: wr32(10,13+rd32(14)+4*rd32(46));
                9: wr32(2,rd32(10));
                10: wr32(34,32'hffffffff);
            endcase
            run_case(54,i%2,1,1);
        end
        $display("PASS parser deterministic random field mutations cases=%0d",cases-base_case);

        base_case=cases; case_name="abort_restart_and_async_reset";
        // A silent source is allowed to stall indefinitely; s_last without a
        // transfer must not create an EOF, even before the very first byte.
        make_header(3,5,40,0,54,0,0); begin_transaction;
        for (j=0;j<20;j=j+1) begin
            cycle(0,0,0,1,8'hff); assert_cleared;
            if (busy !== 1 || s_ready !== 1) fail("zero-byte stall caused false completion");
        end
        cycle(0,1,1,1,8'hfe); aborted_count=aborted_count+1; assert_cleared;
        cycle(0,0,1,1,8'hfe); assert_cleared;
        make_header(11,13,40,0,54,0,0); begin_transaction;
        for (j=0;j<17;j=j+1) cycle(0,0,1,0,header[j]);
        cycle(1,1,1,1,8'hfe); aborted_count=aborted_count+1;
        assert_cleared;
        if (busy !== 0 || s_ready !== 0) fail("abort did not cancel collection");
        cycle(0,0,1,1,8'hfe); assert_cleared;
        make_header(23,-17,124,0,138,1,0); run_full(0,1);

        make_header(11,13,40,0,54,0,0); begin_transaction;
        for (j=0;j<54;j=j+1) cycle(0,0,1,0,header[j]);
        cycle(1,1,1,1,8'hfe); aborted_count=aborted_count+1;
        assert_cleared;
        cycle(0,0,1,1,8'hfe); assert_cleared;
        make_header(29,31,40,0,54,0,0); run_full(0,0);
        cycle(1,1,1,1,8'hfe); aborted_count=aborted_count+1; assert_cleared;
        cycle(0,0,1,1,8'hfe); assert_cleared;
        if (ready !== 1 || busy !== 0) fail("abort/start priority failed");

        make_header(33,35,40,0,54,0,0); begin_transaction;
        for (j=0;j<19;j=j+1) cycle(0,0,1,0,header[j]);
        @(negedge clk); rst=1; start=1; abort=1; s_valid=1; s_last=1;
        #1; assert_cleared; async_reset_count=async_reset_count+1;
        if (busy !== 0 || s_ready !== 0) fail("asynchronous reset did not act before clock");
        @(posedge clk); #1; assert_cleared;
        @(negedge clk); rst=0; start=0; abort=0; s_valid=0; s_last=0;
        cycle(0,0,1,1,8'hff); assert_cleared;
        make_header(640,-480,40,0,54,0,0); run_full(0,1);
        $display("PASS parser abort/restart collection/evaluation/idle and async midstream reset completed_cases=%0d aborts=%0d resets=%0d",cases-base_case,aborted_count,async_reset_count);

        if (error_coverage !== 12'hfff) fail("not all success/error codes covered");
        if (padding_coverage !== 4'hf) fail("not all row-padding values covered");
        $display("PASS tb_contest_bmp_meta_parser cases=%0d dut_checks=%0d successes=%0d rejected=%0d starts=%0d accepted_bytes=%0d cycles=%0d",
                 cases,2*cases,successes,failures,start_count,accepted_bytes,cycles);
        $finish;
    end
endmodule


// Integration fixture: real BMP bytes -> metadata -> row-addressed RGB source.
// BGR unpacking, padding removal and file-row addressing here are TESTBENCH
// reader behavior, not an additional RTL decoder delivered in this package.
module tb_bmp_scaler_pipeline;
    reg clk=0;
    always #20 clk=~clk;
    reg rst=1, abort=0, p_start=0, s_valid=0, s_last=0, start=0;
    reg [7:0] s_data=0;
    wire p_ready,p_busy,p_s_ready,p_done,fmt_valid,fmt_error,top_down;
    wire [3:0] p_error;
    wire [15:0] width,height,row_stride;
    wire [31:0] pixel_offset;
    reg bmp_data_wr_en=0;
    reg [23:0] bmp_data=0;
    wire ready,busy,done,write_req,write_en,sc_error,line_ready;
    wire [15:0] source_y;
    reg write_req_ack=0;
    wire [3:0] error;
    wire [23:0] write_data;
    wire [9:0] o_x,scaled_width,offset_x;
    wire [8:0] o_y,scaled_height,offset_y;
    wire o_border_flag,o_sof,o_eol,o_last;

    contest_bmp_meta_parser parser (
        .clk(clk),.rst(rst),.abort(abort),.start(p_start),
        .s_valid(s_valid),.s_data(s_data),.s_last(s_last),.s_ready(p_s_ready),
        .ready(p_ready),.busy(p_busy),.done(p_done),
        .o_format_valid(fmt_valid),.o_format_error(fmt_error),.o_error_code(p_error),
        .o_width(width),.o_height(height),.o_top_down(top_down),
        .o_pixel_offset(pixel_offset),.o_row_stride(row_stride),
        .file_size(),.dib_size(),.row_padding(),.pixel_bytes(),.pixel_count()
    );
    contest_image_scaler scaler (
        .clk(clk),.rst(rst),.abort(abort),.start(start),
        .cfg_src_width(width),.cfg_src_height(height),.cfg_format_valid(fmt_valid),
        .bmp_data_wr_en(bmp_data_wr_en),.bmp_data(bmp_data),
        .ready(ready),.busy(busy),.done(done),.error(error),.o_format_error(sc_error),
        .o_line_ready(line_ready),.o_src_y(source_y),
        .write_req(write_req),.write_req_ack(write_req_ack),.write_en(write_en),
        .write_data(write_data),.o_x(o_x),.o_y(o_y),
        .o_border_flag(o_border_flag),.o_sof(o_sof),.o_eol(o_eol),.o_last(o_last),
        .scaled_width(scaled_width),.scaled_height(scaled_height),
        .offset_x(offset_x),.offset_y(offset_y)
    );

    reg [7:0] bmp_file [0:8191];
    integer fw,fh,sw,sh,left,top,seed,frames=0,rejection_cases=0;
    integer count=0,cycles=0,all_pixels=0,borders=0,active_pixels=0;
    integer expected_x,expected_y,sx,sy,reqs=0;
    integer feed_x=0,feed_y=-1,base,stored_y;
    reg checking=0,feed_enable=0;
    reg expected_border,prev_en=0;
    reg [9:0] prev_x;
    reg [23:0] expected_rgb;

    task pipe_fail;
        input [8*160-1:0] reason;
        begin
            $display("FAIL tb_bmp_scaler_pipeline frame=%0d output=%0d cycle=%0d: %0s",frames+1,count,cycles,reason);
            $finish;
        end
    endtask
    function [23:0] color;
        input integer x,y;
        reg [7:0] r,g,b;
        begin
            r=(x*53+y*17+seed)&255;g=(x*13+y*71+seed*3)&255;b=(x*97+y*29+seed*7)&255;
            color=(x==0 && y==0) ? 24'h001030 : {r,g,b};
        end
    endfunction
    task put32;
        input integer at;
        input [31:0] value;
        begin
            bmp_file[at]=value[7:0];bmp_file[at+1]=value[15:8];
            bmp_file[at+2]=value[23:16];bmp_file[at+3]=value[31:24];
        end
    endtask

    // Reader responds to requested VISUAL row, converting to the BMP file row.
    always @(negedge clk) begin
        bmp_data_wr_en=0;
        if (!rst && feed_enable && line_ready) begin
            if (feed_x==0) begin
                if(feed_y>=0 && source_y<=feed_y) pipe_fail("source row was needlessly requested again or reversed");
                feed_y=source_y;reqs=reqs+1;
            end
            if (source_y!=feed_y || source_y>=height) pipe_fail("unstable/out of range source row request");
            stored_y=top_down ? source_y : height-1-source_y;
            base=pixel_offset+stored_y*row_stride+feed_x*3;
            bmp_data={bmp_file[base+2],bmp_file[base+1],bmp_file[base]};
            bmp_data_wr_en=1;
        end
    end
    always @(posedge clk) begin
        cycles=cycles+1;
        if (!rst && feed_enable && bmp_data_wr_en) begin
            if(!line_ready) pipe_fail("source was not admitted");
            if(feed_x==width-1) feed_x=0;else feed_x=feed_x+1;
        end
        if (!rst && checking) begin
            if (write_req_ack && write_en) pipe_fail("output while destination FIFO is held in ack/reset");
            if(prev_en && prev_x!=639 && !write_en) pipe_fail("bubble inside output row");
            prev_en=write_en;prev_x=o_x;
            if (write_en) begin
                if (count>=307200) pipe_fail("extra output pixel");
                expected_x=count%640;expected_y=count/640;
                expected_border=(expected_x<left || expected_x>=left+sw || expected_y<top || expected_y>=top+sh);
                if (expected_border) expected_rgb=24'h001030;
                else begin
                    sx=((expected_x-left)*fw)/sw;sy=((expected_y-top)*fh)/sh;
                    expected_rgb=color(sx,sy);
                end
                if(o_x!==expected_x || o_y!==expected_y) pipe_fail("not row-major640x480");
                if(o_border_flag!==expected_border) pipe_fail("border flag mismatch");
                if(write_data!==expected_rgb) pipe_fail("RGB differs from independent BMP/geometry model");
                if(o_sof!==(count==0) || o_eol!==(expected_x==639) || o_last!==(count==307199))
                    pipe_fail("raster marker mismatch");
                count=count+1;all_pixels=all_pixels+1;
                if(expected_border) borders=borders+1;else active_pixels=active_pixels+1;
            end
        end
    end

    task run_bmp;
        input integer w,h,is_top,off;
        integer i,j,fy,vy,b,stride,wait_count;
        reg [23:0] rgb;
        begin
            @(negedge clk);
            fw=w;fh=h;seed=37+frames*19;
            count=0;borders=0;active_pixels=0;feed_x=0;feed_y=-1;reqs=0;
            prev_en=0;checking=1;feed_enable=0;
            if(w*480 >= h*640) begin sw=640;sh=(h*640)/w;end
            else begin sh=480;sw=(w*480)/h;end
            if(sw<1) sw=1;if(sh<1) sh=1;
            left=(640-sw)/2;top=(480-sh)/2;stride=((w*3+3)/4)*4;
            for(i=0;i<8192;i=i+1) bmp_file[i]=8'ha5;
            for(i=0;i<54;i=i+1) bmp_file[i]=0;
            bmp_file[0]=8'h42;bmp_file[1]=8'h4d;
            put32(2,off+stride*h);put32(10,off);put32(14,40);put32(18,w);put32(22,is_top ? -h : h);
            bmp_file[26]=1;bmp_file[28]=24;put32(34,stride*h);
            for(fy=0;fy<h;fy=fy+1) begin
                vy=is_top ? fy : h-1-fy;
                for(j=0;j<w;j=j+1) begin
                    rgb=color(j,vy);b=off+fy*stride+j*3;
                    bmp_file[b]=rgb[7:0];bmp_file[b+1]=rgb[15:8];bmp_file[b+2]=rgb[23:16];
                end
            end
            if(!p_ready || !ready) pipe_fail("not ready for next transaction");
            p_start=1;@(negedge clk);p_start=0;
            for(i=0;i<54;i=i+1) begin
                s_valid=1;s_data=bmp_file[i];s_last=(i==53);
                if(!p_s_ready) pipe_fail("parser stopped early");
                @(negedge clk);
            end
            s_valid=0;s_last=0;@(negedge clk);
            if(!fmt_valid || fmt_error || p_error || width!=w || height!=h || top_down!=is_top || pixel_offset!=off || row_stride!=stride)
                pipe_fail("parser metadata mismatch");
            start=1;@(negedge clk);start=0;
            wait_count=0;
            while(!write_req && wait_count<400) begin @(negedge clk);wait_count=wait_count+1;end
            if(!write_req) pipe_fail("no destination frame request");
            repeat(11) @(negedge clk);write_req_ack=1;
            wait_count=0;
            while(write_req && wait_count<10) begin @(negedge clk);wait_count=wait_count+1;end
            if(write_req) pipe_fail("frame request did not drop after ack");
            repeat(9) @(negedge clk);
            if(write_en) pipe_fail("output before ack release");
            write_req_ack=0;feed_enable=1;
            wait_count=0;
            while(!done && wait_count<600000) begin @(posedge clk);#1;wait_count=wait_count+1;end
            if(!done || count!=307200 || error!=0 || sc_error || !ready || busy)
                pipe_fail("frame completion/count/status mismatch");
            if(scaled_width!=sw || scaled_height!=sh || offset_x!=left || offset_y!=top)
                pipe_fail("reported rectangle mismatch");
            if(active_pixels!=sw*sh || borders!=307200-sw*sh) pipe_fail("active/border count mismatch");
            repeat(3) @(negedge clk);
            if(done || write_en || write_req || line_ready) pipe_fail("completion status leaked");
            checking=0;feed_enable=0;frames=frames+1;
            $display("PASS pipeline BMP=%0dx%0d top_down=%0d padding=%0d offset=%0d fit=%0dx%0d active=%0d border=%0d source_rows=%0d",w,h,is_top,stride-w*3,off,sw,sh,active_pixels,borders,reqs);
        end
    endtask
    task reject_bmp;
        input integer bpp,compression,expected_parser_error;
        integer i;
        begin
            @(negedge clk);
            for(i=0;i<54;i=i+1) bmp_file[i]=0;
            bmp_file[0]=8'h42;bmp_file[1]=8'h4d;
            put32(2,150);put32(10,54);put32(14,40);put32(18,8);put32(22,4);
            bmp_file[26]=1;bmp_file[28]=bpp;put32(30,compression);
            p_start=1;@(negedge clk);p_start=0;
            for(i=0;i<54;i=i+1) begin
                s_valid=1;s_data=bmp_file[i];s_last=(i==53);@(negedge clk);
            end
            s_valid=0;s_last=0;@(negedge clk);
            if(fmt_valid || !fmt_error || p_error!=expected_parser_error)
                pipe_fail("unsupported BMP was not rejected by parser");
            start=1;@(posedge clk);#1;
            if(!done || !sc_error || error!=1 || write_req || write_en || line_ready)
                pipe_fail("invalid parser result was not rejected by scaler");
            @(negedge clk);start=0;
            repeat(5) begin
                @(negedge clk);
                if(write_req || write_en || line_ready || done || !ready)
                    pipe_fail("rejected BMP produced activity");
            end
            rejection_cases=rejection_cases+1;
            $display("PASS pipeline rejected bpp=%0d compression=%0d parser_error=%0d scaler_error=1 no_output",bpp,compression,expected_parser_error);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        reject_bmp(32,0,5);reject_bmp(24,1,6);
        run_bmp(3,2,0,78);run_bmp(2,3,1,70);run_bmp(7,5,0,54);
        $display("PASS tb_bmp_scaler_pipeline frames=%0d rejected_formats=%0d checked_pixels=%0d cycles=%0d",frames,rejection_cases,all_pixels,cycles);
        $finish;
    end
    initial begin
        #100000000;
        $display("FAIL tb_bmp_scaler_pipeline global watchdog");$finish;
    end
endmodule

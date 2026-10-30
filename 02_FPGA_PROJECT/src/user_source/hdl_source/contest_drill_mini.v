//=============================================================================
// contest_drill_mini.v
//-----------------------------------------------------------------------------
// V27 消防演练 8x16 标准清晰数字点阵库 (VGA CP437 标准无失真字模)
// 用于 S3 疏散倒计时 2x2 放大渲染 (16x32 大字)，彻底消除残缺与笔画丢失。
//=============================================================================
function [7:0] drill_digit_row;
    input [3:0] g; // Digit 0..9
    input [3:0] r; // Row 0..15
    begin
        case (g)
        4'd0: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h38;
            4'd4: drill_digit_row = 8'h44;
            4'd5: drill_digit_row = 8'h44;
            4'd6: drill_digit_row = 8'h44;
            4'd7: drill_digit_row = 8'h44;
            4'd8: drill_digit_row = 8'h44;
            4'd9: drill_digit_row = 8'h44;
            4'd10: drill_digit_row = 8'h44;
            4'd11: drill_digit_row = 8'h38;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd1: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h10;
            4'd4: drill_digit_row = 8'h30;
            4'd5: drill_digit_row = 8'h10;
            4'd6: drill_digit_row = 8'h10;
            4'd7: drill_digit_row = 8'h10;
            4'd8: drill_digit_row = 8'h10;
            4'd9: drill_digit_row = 8'h10;
            4'd10: drill_digit_row = 8'h10;
            4'd11: drill_digit_row = 8'h38;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd2: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h38;
            4'd4: drill_digit_row = 8'h44;
            4'd5: drill_digit_row = 8'h04;
            4'd6: drill_digit_row = 8'h04;
            4'd7: drill_digit_row = 8'h08;
            4'd8: drill_digit_row = 8'h10;
            4'd9: drill_digit_row = 8'h20;
            4'd10: drill_digit_row = 8'h40;
            4'd11: drill_digit_row = 8'h7C;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd3: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h38;
            4'd4: drill_digit_row = 8'h44;
            4'd5: drill_digit_row = 8'h04;
            4'd6: drill_digit_row = 8'h04;
            4'd7: drill_digit_row = 8'h18;
            4'd8: drill_digit_row = 8'h04;
            4'd9: drill_digit_row = 8'h04;
            4'd10: drill_digit_row = 8'h44;
            4'd11: drill_digit_row = 8'h38;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd4: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h08;
            4'd4: drill_digit_row = 8'h18;
            4'd5: drill_digit_row = 8'h28;
            4'd6: drill_digit_row = 8'h48;
            4'd7: drill_digit_row = 8'h7C;
            4'd8: drill_digit_row = 8'h08;
            4'd9: drill_digit_row = 8'h08;
            4'd10: drill_digit_row = 8'h08;
            4'd11: drill_digit_row = 8'h1C;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd5: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h7C;
            4'd4: drill_digit_row = 8'h40;
            4'd5: drill_digit_row = 8'h40;
            4'd6: drill_digit_row = 8'h78;
            4'd7: drill_digit_row = 8'h04;
            4'd8: drill_digit_row = 8'h04;
            4'd9: drill_digit_row = 8'h04;
            4'd10: drill_digit_row = 8'h44;
            4'd11: drill_digit_row = 8'h38;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd6: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h18;
            4'd4: drill_digit_row = 8'h20;
            4'd5: drill_digit_row = 8'h40;
            4'd6: drill_digit_row = 8'h78;
            4'd7: drill_digit_row = 8'h44;
            4'd8: drill_digit_row = 8'h44;
            4'd9: drill_digit_row = 8'h44;
            4'd10: drill_digit_row = 8'h44;
            4'd11: drill_digit_row = 8'h38;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd7: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h7C;
            4'd4: drill_digit_row = 8'h44;
            4'd5: drill_digit_row = 8'h04;
            4'd6: drill_digit_row = 8'h04;
            4'd7: drill_digit_row = 8'h08;
            4'd8: drill_digit_row = 8'h08;
            4'd9: drill_digit_row = 8'h10;
            4'd10: drill_digit_row = 8'h10;
            4'd11: drill_digit_row = 8'h10;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd8: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h38;
            4'd4: drill_digit_row = 8'h44;
            4'd5: drill_digit_row = 8'h44;
            4'd6: drill_digit_row = 8'h44;
            4'd7: drill_digit_row = 8'h38;
            4'd8: drill_digit_row = 8'h44;
            4'd9: drill_digit_row = 8'h44;
            4'd10: drill_digit_row = 8'h44;
            4'd11: drill_digit_row = 8'h38;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        4'd9: case (r)
            4'd0: drill_digit_row = 8'h00;
            4'd1: drill_digit_row = 8'h00;
            4'd2: drill_digit_row = 8'h00;
            4'd3: drill_digit_row = 8'h38;
            4'd4: drill_digit_row = 8'h44;
            4'd5: drill_digit_row = 8'h44;
            4'd6: drill_digit_row = 8'h44;
            4'd7: drill_digit_row = 8'h3C;
            4'd8: drill_digit_row = 8'h04;
            4'd9: drill_digit_row = 8'h04;
            4'd10: drill_digit_row = 8'h08;
            4'd11: drill_digit_row = 8'h30;
            4'd12: drill_digit_row = 8'h00;
            4'd13: drill_digit_row = 8'h00;
            4'd14: drill_digit_row = 8'h00;
            4'd15: drill_digit_row = 8'h00;
            default: drill_digit_row = 8'h00;
        endcase
        default: drill_digit_row = 8'h00;
        endcase
    end
endfunction

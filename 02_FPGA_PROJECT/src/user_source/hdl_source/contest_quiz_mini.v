// V21 8x16 小字库（由 gen_quiz_font.py 生成，勿手改）。
// 字模索引：0:'1' 1:'2' 2:'3' 3:'/' 4:'A' 5:'B' 6:'C' 7:'▶'
function [7:0] mini_row;
    input [3:0] g;
    input [3:0] r;
    begin
        case (g)
        4'd0: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h00;
            4'd3: mini_row = 8'h10;
            4'd4: mini_row = 8'h30;
            4'd5: mini_row = 8'h10;
            4'd6: mini_row = 8'h10;
            4'd7: mini_row = 8'h10;
            4'd8: mini_row = 8'h10;
            4'd9: mini_row = 8'h10;
            4'd10: mini_row = 8'h10;
            4'd11: mini_row = 8'h38;
            4'd12: mini_row = 8'h00;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd1: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h00;
            4'd3: mini_row = 8'h38;
            4'd4: mini_row = 8'h44;
            4'd5: mini_row = 8'h44;
            4'd6: mini_row = 8'h04;
            4'd7: mini_row = 8'h08;
            4'd8: mini_row = 8'h10;
            4'd9: mini_row = 8'h20;
            4'd10: mini_row = 8'h44;
            4'd11: mini_row = 8'h7C;
            4'd12: mini_row = 8'h00;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd2: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h00;
            4'd3: mini_row = 8'h38;
            4'd4: mini_row = 8'h44;
            4'd5: mini_row = 8'h04;
            4'd6: mini_row = 8'h04;
            4'd7: mini_row = 8'h18;
            4'd8: mini_row = 8'h04;
            4'd9: mini_row = 8'h04;
            4'd10: mini_row = 8'h44;
            4'd11: mini_row = 8'h38;
            4'd12: mini_row = 8'h00;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd3: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h04;
            4'd3: mini_row = 8'h08;
            4'd4: mini_row = 8'h08;
            4'd5: mini_row = 8'h10;
            4'd6: mini_row = 8'h10;
            4'd7: mini_row = 8'h20;
            4'd8: mini_row = 8'h20;
            4'd9: mini_row = 8'h20;
            4'd10: mini_row = 8'h40;
            4'd11: mini_row = 8'h40;
            4'd12: mini_row = 8'h80;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd4: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h00;
            4'd3: mini_row = 8'h10;
            4'd4: mini_row = 8'h10;
            4'd5: mini_row = 8'h28;
            4'd6: mini_row = 8'h28;
            4'd7: mini_row = 8'h28;
            4'd8: mini_row = 8'h38;
            4'd9: mini_row = 8'h44;
            4'd10: mini_row = 8'h44;
            4'd11: mini_row = 8'hEE;
            4'd12: mini_row = 8'h00;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd5: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h00;
            4'd3: mini_row = 8'hF8;
            4'd4: mini_row = 8'h44;
            4'd5: mini_row = 8'h44;
            4'd6: mini_row = 8'h44;
            4'd7: mini_row = 8'h78;
            4'd8: mini_row = 8'h44;
            4'd9: mini_row = 8'h44;
            4'd10: mini_row = 8'h44;
            4'd11: mini_row = 8'hF8;
            4'd12: mini_row = 8'h00;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd6: case (r)
            4'd0: mini_row = 8'h00;
            4'd1: mini_row = 8'h00;
            4'd2: mini_row = 8'h00;
            4'd3: mini_row = 8'h3C;
            4'd4: mini_row = 8'h44;
            4'd5: mini_row = 8'h80;
            4'd6: mini_row = 8'h80;
            4'd7: mini_row = 8'h80;
            4'd8: mini_row = 8'h80;
            4'd9: mini_row = 8'h80;
            4'd10: mini_row = 8'h44;
            4'd11: mini_row = 8'h38;
            4'd12: mini_row = 8'h00;
            4'd13: mini_row = 8'h00;
            4'd14: mini_row = 8'h00;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        4'd7: case (r)
            4'd0: mini_row = 8'h80;
            4'd1: mini_row = 8'hC0;
            4'd2: mini_row = 8'hE0;
            4'd3: mini_row = 8'hF0;
            4'd4: mini_row = 8'hF8;
            4'd5: mini_row = 8'hFC;
            4'd6: mini_row = 8'hFE;
            4'd7: mini_row = 8'hFF;
            4'd8: mini_row = 8'hFE;
            4'd9: mini_row = 8'hFC;
            4'd10: mini_row = 8'hF8;
            4'd11: mini_row = 8'hF0;
            4'd12: mini_row = 8'hE0;
            4'd13: mini_row = 8'hC0;
            4'd14: mini_row = 8'h80;
            4'd15: mini_row = 8'h00;
            default: mini_row = 8'h00;
        endcase
        default: mini_row = 8'h00;
        endcase
    end
endfunction

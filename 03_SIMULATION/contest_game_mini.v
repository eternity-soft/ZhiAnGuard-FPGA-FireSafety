function [7:0] game_mini_row;
    input [5:0] g;
    input [3:0] r;
    begin
        if (r < 4'd2 || r > 4'd12) begin
            game_mini_row = 8'h00;
        end else begin
            case (g)
            6'd1:
                case (r)
                    4'd3: game_mini_row = 8'h10;
                    4'd4: game_mini_row = 8'h30;
                    4'd5: game_mini_row = 8'h10;
                    4'd6: game_mini_row = 8'h10;
                    4'd7: game_mini_row = 8'h10;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h10;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h38;
                    default: game_mini_row = 8'h00;
                endcase
            6'd2:
                case (r)
                    4'd3: game_mini_row = 8'h38;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h44;
                    4'd6: game_mini_row = 8'h04;
                    4'd7: game_mini_row = 8'h08;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h20;
                    4'd10: game_mini_row = 8'h44;
                    4'd11: game_mini_row = 8'h7C;
                    default: game_mini_row = 8'h00;
                endcase
            6'd3:
                case (r)
                    4'd3: game_mini_row = 8'h38;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h04;
                    4'd6: game_mini_row = 8'h04;
                    4'd7: game_mini_row = 8'h18;
                    4'd8: game_mini_row = 8'h04;
                    4'd9: game_mini_row = 8'h04;
                    4'd10: game_mini_row = 8'h44;
                    4'd11: game_mini_row = 8'h38;
                    default: game_mini_row = 8'h00;
                endcase
            6'd4:
                case (r)
                    4'd3: game_mini_row = 8'h08;
                    4'd4: game_mini_row = 8'h08;
                    4'd5: game_mini_row = 8'h18;
                    4'd6: game_mini_row = 8'h28;
                    4'd7: game_mini_row = 8'h28;
                    4'd8: game_mini_row = 8'h48;
                    4'd9: game_mini_row = 8'h7C;
                    4'd10: game_mini_row = 8'h08;
                    4'd11: game_mini_row = 8'h1C;
                    default: game_mini_row = 8'h00;
                endcase
            6'd10:
                case (r)
                    4'd3: game_mini_row = 8'h10;
                    4'd4: game_mini_row = 8'h10;
                    4'd5: game_mini_row = 8'h28;
                    4'd6: game_mini_row = 8'h28;
                    4'd7: game_mini_row = 8'h28;
                    4'd8: game_mini_row = 8'h38;
                    4'd9: game_mini_row = 8'h44;
                    4'd10: game_mini_row = 8'h44;
                    4'd11: game_mini_row = 8'hEE;
                    default: game_mini_row = 8'h00;
                endcase
            6'd12:
                case (r)
                    4'd3: game_mini_row = 8'h3C;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h80;
                    4'd6: game_mini_row = 8'h80;
                    4'd7: game_mini_row = 8'h80;
                    4'd8: game_mini_row = 8'h80;
                    4'd9: game_mini_row = 8'h80;
                    4'd10: game_mini_row = 8'h44;
                    4'd11: game_mini_row = 8'h38;
                    default: game_mini_row = 8'h00;
                endcase
            6'd14:
                case (r)
                    4'd3: game_mini_row = 8'hFC;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h40;
                    4'd6: game_mini_row = 8'h48;
                    4'd7: game_mini_row = 8'h78;
                    4'd8: game_mini_row = 8'h48;
                    4'd9: game_mini_row = 8'h40;
                    4'd10: game_mini_row = 8'h44;
                    4'd11: game_mini_row = 8'hFC;
                    default: game_mini_row = 8'h00;
                endcase
            6'd16:
                case (r)
                    4'd3: game_mini_row = 8'h38;
                    4'd4: game_mini_row = 8'h48;
                    4'd5: game_mini_row = 8'h80;
                    4'd6: game_mini_row = 8'h80;
                    4'd7: game_mini_row = 8'h80;
                    4'd8: game_mini_row = 8'h9C;
                    4'd9: game_mini_row = 8'h88;
                    4'd10: game_mini_row = 8'h48;
                    4'd11: game_mini_row = 8'h30;
                    default: game_mini_row = 8'h00;
                endcase
            6'd18:
                case (r)
                    4'd3: game_mini_row = 8'h7C;
                    4'd4: game_mini_row = 8'h10;
                    4'd5: game_mini_row = 8'h10;
                    4'd6: game_mini_row = 8'h10;
                    4'd7: game_mini_row = 8'h10;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h10;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h7C;
                    default: game_mini_row = 8'h00;
                endcase
            6'd20:
                case (r)
                    4'd3: game_mini_row = 8'hEC;
                    4'd4: game_mini_row = 8'h48;
                    4'd5: game_mini_row = 8'h50;
                    4'd6: game_mini_row = 8'h60;
                    4'd7: game_mini_row = 8'h70;
                    4'd8: game_mini_row = 8'h50;
                    4'd9: game_mini_row = 8'h48;
                    4'd10: game_mini_row = 8'h48;
                    4'd11: game_mini_row = 8'hEC;
                    default: game_mini_row = 8'h00;
                endcase
            6'd22:
                case (r)
                    4'd3: game_mini_row = 8'hEE;
                    4'd4: game_mini_row = 8'h6C;
                    4'd5: game_mini_row = 8'h6C;
                    4'd6: game_mini_row = 8'h6C;
                    4'd7: game_mini_row = 8'h54;
                    4'd8: game_mini_row = 8'h54;
                    4'd9: game_mini_row = 8'h54;
                    4'd10: game_mini_row = 8'h54;
                    4'd11: game_mini_row = 8'hD6;
                    default: game_mini_row = 8'h00;
                endcase
            6'd24:
                case (r)
                    4'd3: game_mini_row = 8'h30;
                    4'd4: game_mini_row = 8'h48;
                    4'd5: game_mini_row = 8'h84;
                    4'd6: game_mini_row = 8'h84;
                    4'd7: game_mini_row = 8'h84;
                    4'd8: game_mini_row = 8'h84;
                    4'd9: game_mini_row = 8'h84;
                    4'd10: game_mini_row = 8'h48;
                    4'd11: game_mini_row = 8'h30;
                    default: game_mini_row = 8'h00;
                endcase
            6'd27:
                case (r)
                    4'd3: game_mini_row = 8'hF8;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h44;
                    4'd6: game_mini_row = 8'h78;
                    4'd7: game_mini_row = 8'h50;
                    4'd8: game_mini_row = 8'h48;
                    4'd9: game_mini_row = 8'h48;
                    4'd10: game_mini_row = 8'h44;
                    4'd11: game_mini_row = 8'hE6;
                    default: game_mini_row = 8'h00;
                endcase
            6'd29:
                case (r)
                    4'd3: game_mini_row = 8'h7C;
                    4'd4: game_mini_row = 8'h54;
                    4'd5: game_mini_row = 8'h10;
                    4'd6: game_mini_row = 8'h10;
                    4'd7: game_mini_row = 8'h10;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h10;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h38;
                    default: game_mini_row = 8'h00;
                endcase
            6'd31:
                case (r)
                    4'd3: game_mini_row = 8'hEE;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h44;
                    4'd6: game_mini_row = 8'h28;
                    4'd7: game_mini_row = 8'h28;
                    4'd8: game_mini_row = 8'h28;
                    4'd9: game_mini_row = 8'h28;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h10;
                    default: game_mini_row = 8'h00;
                endcase
            6'd34:
                case (r)
                    4'd3: game_mini_row = 8'hEE;
                    4'd4: game_mini_row = 8'h44;
                    4'd5: game_mini_row = 8'h28;
                    4'd6: game_mini_row = 8'h28;
                    4'd7: game_mini_row = 8'h10;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h10;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h38;
                    default: game_mini_row = 8'h00;
                endcase
            6'd36:
                case (r)
                    4'd5: game_mini_row = 8'h20;
                    4'd10: game_mini_row = 8'h20;
                    default: game_mini_row = 8'h00;
                endcase
            6'd37:
                case (r)
                    4'd2: game_mini_row = 8'h1C;
                    4'd3: game_mini_row = 8'h10;
                    4'd4: game_mini_row = 8'h10;
                    4'd5: game_mini_row = 8'h10;
                    4'd6: game_mini_row = 8'h10;
                    4'd7: game_mini_row = 8'h10;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h10;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h10;
                    4'd12: game_mini_row = 8'h1C;
                    default: game_mini_row = 8'h00;
                endcase
            6'd38:
                case (r)
                    4'd2: game_mini_row = 8'h70;
                    4'd3: game_mini_row = 8'h10;
                    4'd4: game_mini_row = 8'h10;
                    4'd5: game_mini_row = 8'h10;
                    4'd6: game_mini_row = 8'h10;
                    4'd7: game_mini_row = 8'h10;
                    4'd8: game_mini_row = 8'h10;
                    4'd9: game_mini_row = 8'h10;
                    4'd10: game_mini_row = 8'h10;
                    4'd11: game_mini_row = 8'h10;
                    4'd12: game_mini_row = 8'h70;
                    default: game_mini_row = 8'h00;
                endcase
            6'd42:
                case (r)
                    default: game_mini_row = 8'h00;
                endcase
            default: game_mini_row = 8'h00;
            endcase
        end
    end
endfunction
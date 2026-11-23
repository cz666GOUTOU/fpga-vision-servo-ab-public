module osd_char_lib #(
    parameter integer SMALL_CNT = 0
)(
    input wire [7:0] I_char,
    input wire [3:0] I_row,
    output reg [15:0] O_row_bits
);

    localparam CHAR_AN    = 8'h80;
    localparam CHAR_LU    = 8'h81;
    localparam CHAR_A     = 8'h41;
    localparam CHAR_B     = 8'h42;
    localparam CHAR_C     = 8'h43;
    localparam CHAR_D     = 8'h44;
    localparam CHAR_E     = 8'h45;
    localparam CHAR_F     = 8'h46;
    localparam CHAR_G     = 8'h47;
    localparam CHAR_H     = 8'h48;
    localparam CHAR_I     = 8'h49;
    localparam CHAR_J     = 8'h4a;
    localparam CHAR_K     = 8'h4b;
    localparam CHAR_L     = 8'h4c;
    localparam CHAR_M     = 8'h4d;
    localparam CHAR_N     = 8'h4e;
    localparam CHAR_O     = 8'h4f;
    localparam CHAR_P     = 8'h50;
    localparam CHAR_Q     = 8'h51;
    localparam CHAR_R     = 8'h52;
    localparam CHAR_S     = 8'h53;
    localparam CHAR_T     = 8'h54;
    localparam CHAR_U     = 8'h55;
    localparam CHAR_V     = 8'h56;
    localparam CHAR_W     = 8'h57;
    localparam CHAR_X     = 8'h58;
    localparam CHAR_Y     = 8'h59;
    localparam CHAR_Z     = 8'h5a;
    localparam CHAR_0     = 8'h30;
    localparam CHAR_1     = 8'h31;
    localparam CHAR_2     = 8'h32;
    localparam CHAR_3     = 8'h33;
    localparam CHAR_4     = 8'h34;
    localparam CHAR_5     = 8'h35;
    localparam CHAR_6     = 8'h36;
    localparam CHAR_7     = 8'h37;
    localparam CHAR_8     = 8'h38;
    localparam CHAR_9     = 8'h39;
    localparam CHAR_COLON = 8'h3a;

    always @(*) begin
        case(I_char)
            CHAR_AN: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0200;
                    4'd1: O_row_bits = 16'h7ff0;
                    4'd2: O_row_bits = 16'h4410;
                    4'd3: O_row_bits = 16'h0400;
                    4'd4: O_row_bits = 16'h7ff0;
                    4'd5: O_row_bits = 16'h0840;
                    4'd6: O_row_bits = 16'h1040;
                    4'd7: O_row_bits = 16'h1c80;
                    4'd8: O_row_bits = 16'h0300;
                    4'd9: O_row_bits = 16'h0cc0;
                    4'd10: O_row_bits = 16'h7020;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_LU: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h79e0;
                    4'd1: O_row_bits = 16'h4a20;
                    4'd2: O_row_bits = 16'h4d40;
                    4'd3: O_row_bits = 16'h7880;
                    4'd4: O_row_bits = 16'h1140;
                    4'd5: O_row_bits = 16'h1630;
                    4'd6: O_row_bits = 16'h5be0;
                    4'd7: O_row_bits = 16'h5220;
                    4'd8: O_row_bits = 16'h5220;
                    4'd9: O_row_bits = 16'h5be0;
                    4'd10: O_row_bits = 16'h6220;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_A: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h1c00;
                    4'd3: O_row_bits = 16'h1400;
                    4'd4: O_row_bits = 16'h1400;
                    4'd5: O_row_bits = 16'h1400;
                    4'd6: O_row_bits = 16'h3600;
                    4'd7: O_row_bits = 16'h3e00;
                    4'd8: O_row_bits = 16'h2200;
                    4'd9: O_row_bits = 16'h2200;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_B: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h3300;
                    4'd4: O_row_bits = 16'h3300;
                    4'd5: O_row_bits = 16'h3e00;
                    4'd6: O_row_bits = 16'h3300;
                    4'd7: O_row_bits = 16'h3300;
                    4'd8: O_row_bits = 16'h3300;
                    4'd9: O_row_bits = 16'h3e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_C: begin
                if(SMALL_CNT) begin
                    case(I_row)
                        4'd2: O_row_bits = 16'h1e00;
                        4'd3: O_row_bits = 16'h3300;
                        4'd4: O_row_bits = 16'h3000;
                        4'd5: O_row_bits = 16'h3000;
                        4'd6: O_row_bits = 16'h3000;
                        4'd7: O_row_bits = 16'h3000;
                        4'd8: O_row_bits = 16'h3300;
                        4'd9: O_row_bits = 16'h1e00;
                        default: O_row_bits = 16'h0000;
                    endcase
                end else begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h03f0;
                    4'd3: O_row_bits = 16'h0c0c;
                    4'd4: O_row_bits = 16'h1800;
                    4'd5: O_row_bits = 16'h3000;
                    4'd6: O_row_bits = 16'h3000;
                    4'd7: O_row_bits = 16'h3000;
                    4'd8: O_row_bits = 16'h3000;
                    4'd9: O_row_bits = 16'h3000;
                    4'd10: O_row_bits = 16'h1800;
                    4'd11: O_row_bits = 16'h0c0c;
                    4'd12: O_row_bits = 16'h03f0;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
                end
            end
            CHAR_D: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h3300;
                    4'd4: O_row_bits = 16'h3300;
                    4'd5: O_row_bits = 16'h3300;
                    4'd6: O_row_bits = 16'h3300;
                    4'd7: O_row_bits = 16'h3300;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h3c00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_E: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h3000;
                    4'd4: O_row_bits = 16'h3000;
                    4'd5: O_row_bits = 16'h3e00;
                    4'd6: O_row_bits = 16'h3000;
                    4'd7: O_row_bits = 16'h3000;
                    4'd8: O_row_bits = 16'h3000;
                    4'd9: O_row_bits = 16'h3e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_F: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h3000;
                    4'd4: O_row_bits = 16'h3000;
                    4'd5: O_row_bits = 16'h3000;
                    4'd6: O_row_bits = 16'h3e00;
                    4'd7: O_row_bits = 16'h3000;
                    4'd8: O_row_bits = 16'h3000;
                    4'd9: O_row_bits = 16'h3000;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_G: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h1c00;
                    4'd3: O_row_bits = 16'h3200;
                    4'd4: O_row_bits = 16'h6000;
                    4'd5: O_row_bits = 16'h6000;
                    4'd6: O_row_bits = 16'h6e00;
                    4'd7: O_row_bits = 16'h6600;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h1e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_H: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3300;
                    4'd3: O_row_bits = 16'h3300;
                    4'd4: O_row_bits = 16'h3300;
                    4'd5: O_row_bits = 16'h3f00;
                    4'd6: O_row_bits = 16'h3300;
                    4'd7: O_row_bits = 16'h3300;
                    4'd8: O_row_bits = 16'h3300;
                    4'd9: O_row_bits = 16'h3300;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_I: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h1e00;
                    4'd3: O_row_bits = 16'h0c00;
                    4'd4: O_row_bits = 16'h0c00;
                    4'd5: O_row_bits = 16'h0c00;
                    4'd6: O_row_bits = 16'h0c00;
                    4'd7: O_row_bits = 16'h0c00;
                    4'd8: O_row_bits = 16'h0c00;
                    4'd9: O_row_bits = 16'h1e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_J: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h0600;
                    4'd4: O_row_bits = 16'h0600;
                    4'd5: O_row_bits = 16'h0600;
                    4'd6: O_row_bits = 16'h0600;
                    4'd7: O_row_bits = 16'h0600;
                    4'd8: O_row_bits = 16'h2600;
                    4'd9: O_row_bits = 16'h1c00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_K: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3300;
                    4'd3: O_row_bits = 16'h3600;
                    4'd4: O_row_bits = 16'h3400;
                    4'd5: O_row_bits = 16'h3c00;
                    4'd6: O_row_bits = 16'h3c00;
                    4'd7: O_row_bits = 16'h3400;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h3300;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_L: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3000;
                    4'd3: O_row_bits = 16'h3000;
                    4'd4: O_row_bits = 16'h3000;
                    4'd5: O_row_bits = 16'h3000;
                    4'd6: O_row_bits = 16'h3000;
                    4'd7: O_row_bits = 16'h3000;
                    4'd8: O_row_bits = 16'h3000;
                    4'd9: O_row_bits = 16'h3e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_M: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3600;
                    4'd3: O_row_bits = 16'h3600;
                    4'd4: O_row_bits = 16'h3600;
                    4'd5: O_row_bits = 16'h3600;
                    4'd6: O_row_bits = 16'h2a00;
                    4'd7: O_row_bits = 16'h2a00;
                    4'd8: O_row_bits = 16'h2200;
                    4'd9: O_row_bits = 16'h2200;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_N: begin
                if(SMALL_CNT) begin
                    case(I_row)
                        4'd2: O_row_bits = 16'h3300;
                        4'd3: O_row_bits = 16'h3b00;
                        4'd4: O_row_bits = 16'h3b00;
                        4'd5: O_row_bits = 16'h3f00;
                        4'd6: O_row_bits = 16'h3700;
                        4'd7: O_row_bits = 16'h3700;
                        4'd8: O_row_bits = 16'h3300;
                        4'd9: O_row_bits = 16'h3300;
                        default: O_row_bits = 16'h0000;
                    endcase
                end else begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h300c;
                    4'd3: O_row_bits = 16'h380c;
                    4'd4: O_row_bits = 16'h3c0c;
                    4'd5: O_row_bits = 16'h360c;
                    4'd6: O_row_bits = 16'h330c;
                    4'd7: O_row_bits = 16'h318c;
                    4'd8: O_row_bits = 16'h30cc;
                    4'd9: O_row_bits = 16'h306c;
                    4'd10: O_row_bits = 16'h303c;
                    4'd11: O_row_bits = 16'h301c;
                    4'd12: O_row_bits = 16'h300c;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
                end
            end
            CHAR_O: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h1e00;
                    4'd3: O_row_bits = 16'h3200;
                    4'd4: O_row_bits = 16'h6300;
                    4'd5: O_row_bits = 16'h6300;
                    4'd6: O_row_bits = 16'h6300;
                    4'd7: O_row_bits = 16'h6300;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h3c00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_P: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h3300;
                    4'd4: O_row_bits = 16'h3300;
                    4'd5: O_row_bits = 16'h3300;
                    4'd6: O_row_bits = 16'h3e00;
                    4'd7: O_row_bits = 16'h3000;
                    4'd8: O_row_bits = 16'h3000;
                    4'd9: O_row_bits = 16'h3000;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_Q: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h1e00;
                    4'd3: O_row_bits = 16'h3200;
                    4'd4: O_row_bits = 16'h6300;
                    4'd5: O_row_bits = 16'h6300;
                    4'd6: O_row_bits = 16'h6300;
                    4'd7: O_row_bits = 16'h6300;
                    4'd8: O_row_bits = 16'h7600;
                    4'd9: O_row_bits = 16'h3c00;
                    4'd10: O_row_bits = 16'h0c00;
                    4'd11: O_row_bits = 16'h0700;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_R: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h3300;
                    4'd4: O_row_bits = 16'h3300;
                    4'd5: O_row_bits = 16'h3300;
                    4'd6: O_row_bits = 16'h3c00;
                    4'd7: O_row_bits = 16'h3600;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h3200;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_S: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h1e00;
                    4'd3: O_row_bits = 16'h3000;
                    4'd4: O_row_bits = 16'h3000;
                    4'd5: O_row_bits = 16'h3c00;
                    4'd6: O_row_bits = 16'h0f00;
                    4'd7: O_row_bits = 16'h0300;
                    4'd8: O_row_bits = 16'h0300;
                    4'd9: O_row_bits = 16'h3e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_T: begin
                if(SMALL_CNT) begin
                    case(I_row)
                        4'd2: O_row_bits = 16'h3f00;
                        4'd3: O_row_bits = 16'h0c00;
                        4'd4: O_row_bits = 16'h0c00;
                        4'd5: O_row_bits = 16'h0c00;
                        4'd6: O_row_bits = 16'h0c00;
                        4'd7: O_row_bits = 16'h0c00;
                        4'd8: O_row_bits = 16'h0c00;
                        4'd9: O_row_bits = 16'h0c00;
                        default: O_row_bits = 16'h0000;
                    endcase
                end else begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3ffc;
                    4'd3: O_row_bits = 16'h03c0;
                    4'd4: O_row_bits = 16'h03c0;
                    4'd5: O_row_bits = 16'h03c0;
                    4'd6: O_row_bits = 16'h03c0;
                    4'd7: O_row_bits = 16'h03c0;
                    4'd8: O_row_bits = 16'h03c0;
                    4'd9: O_row_bits = 16'h03c0;
                    4'd10: O_row_bits = 16'h03c0;
                    4'd11: O_row_bits = 16'h03c0;
                    4'd12: O_row_bits = 16'h03c0;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
                end
            end
            CHAR_U: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3300;
                    4'd3: O_row_bits = 16'h3300;
                    4'd4: O_row_bits = 16'h3300;
                    4'd5: O_row_bits = 16'h3300;
                    4'd6: O_row_bits = 16'h3300;
                    4'd7: O_row_bits = 16'h3300;
                    4'd8: O_row_bits = 16'h3300;
                    4'd9: O_row_bits = 16'h1e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_V: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h2200;
                    4'd3: O_row_bits = 16'h2200;
                    4'd4: O_row_bits = 16'h3600;
                    4'd5: O_row_bits = 16'h3600;
                    4'd6: O_row_bits = 16'h1400;
                    4'd7: O_row_bits = 16'h1400;
                    4'd8: O_row_bits = 16'h1c00;
                    4'd9: O_row_bits = 16'h1c00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_W: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h2200;
                    4'd3: O_row_bits = 16'h2200;
                    4'd4: O_row_bits = 16'h2a00;
                    4'd5: O_row_bits = 16'h2a00;
                    4'd6: O_row_bits = 16'h3600;
                    4'd7: O_row_bits = 16'h3600;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h3600;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_X: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h1c00;
                    4'd4: O_row_bits = 16'h1c00;
                    4'd5: O_row_bits = 16'h0800;
                    4'd6: O_row_bits = 16'h1c00;
                    4'd7: O_row_bits = 16'h1400;
                    4'd8: O_row_bits = 16'h3600;
                    4'd9: O_row_bits = 16'h3200;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_Y: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3180;
                    4'd3: O_row_bits = 16'h1300;
                    4'd4: O_row_bits = 16'h1b00;
                    4'd5: O_row_bits = 16'h1e00;
                    4'd6: O_row_bits = 16'h0c00;
                    4'd7: O_row_bits = 16'h0c00;
                    4'd8: O_row_bits = 16'h0c00;
                    4'd9: O_row_bits = 16'h0c00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_Z: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h3e00;
                    4'd3: O_row_bits = 16'h0400;
                    4'd4: O_row_bits = 16'h0c00;
                    4'd5: O_row_bits = 16'h0800;
                    4'd6: O_row_bits = 16'h0800;
                    4'd7: O_row_bits = 16'h1800;
                    4'd8: O_row_bits = 16'h1000;
                    4'd9: O_row_bits = 16'h3e00;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_0: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h300c;
                    4'd4: O_row_bits = 16'h300c;
                    4'd5: O_row_bits = 16'h300c;
                    4'd6: O_row_bits = 16'h0000;
                    4'd7: O_row_bits = 16'h0000;
                    4'd8: O_row_bits = 16'h300c;
                    4'd9: O_row_bits = 16'h300c;
                    4'd10: O_row_bits = 16'h300c;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_1: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h000c;
                    4'd2: O_row_bits = 16'h000c;
                    4'd3: O_row_bits = 16'h000c;
                    4'd4: O_row_bits = 16'h000c;
                    4'd5: O_row_bits = 16'h000c;
                    4'd6: O_row_bits = 16'h0000;
                    4'd7: O_row_bits = 16'h0000;
                    4'd8: O_row_bits = 16'h000c;
                    4'd9: O_row_bits = 16'h000c;
                    4'd10: O_row_bits = 16'h000c;
                    4'd11: O_row_bits = 16'h000c;
                    4'd12: O_row_bits = 16'h000c;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_2: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h000c;
                    4'd4: O_row_bits = 16'h000c;
                    4'd5: O_row_bits = 16'h000c;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h3000;
                    4'd9: O_row_bits = 16'h3000;
                    4'd10: O_row_bits = 16'h3000;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_3: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h000c;
                    4'd4: O_row_bits = 16'h000c;
                    4'd5: O_row_bits = 16'h000c;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h000c;
                    4'd9: O_row_bits = 16'h000c;
                    4'd10: O_row_bits = 16'h000c;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_4: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h300c;
                    4'd2: O_row_bits = 16'h300c;
                    4'd3: O_row_bits = 16'h300c;
                    4'd4: O_row_bits = 16'h300c;
                    4'd5: O_row_bits = 16'h300c;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h000c;
                    4'd9: O_row_bits = 16'h000c;
                    4'd10: O_row_bits = 16'h000c;
                    4'd11: O_row_bits = 16'h000c;
                    4'd12: O_row_bits = 16'h000c;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_5: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h3000;
                    4'd4: O_row_bits = 16'h3000;
                    4'd5: O_row_bits = 16'h3000;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h000c;
                    4'd9: O_row_bits = 16'h000c;
                    4'd10: O_row_bits = 16'h000c;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_6: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h3000;
                    4'd4: O_row_bits = 16'h3000;
                    4'd5: O_row_bits = 16'h3000;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h300c;
                    4'd9: O_row_bits = 16'h300c;
                    4'd10: O_row_bits = 16'h300c;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_7: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h000c;
                    4'd4: O_row_bits = 16'h000c;
                    4'd5: O_row_bits = 16'h000c;
                    4'd6: O_row_bits = 16'h0000;
                    4'd7: O_row_bits = 16'h0000;
                    4'd8: O_row_bits = 16'h000c;
                    4'd9: O_row_bits = 16'h000c;
                    4'd10: O_row_bits = 16'h000c;
                    4'd11: O_row_bits = 16'h000c;
                    4'd12: O_row_bits = 16'h000c;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_8: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h300c;
                    4'd4: O_row_bits = 16'h300c;
                    4'd5: O_row_bits = 16'h300c;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h300c;
                    4'd9: O_row_bits = 16'h300c;
                    4'd10: O_row_bits = 16'h300c;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_9: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h1ff8;
                    4'd2: O_row_bits = 16'h1ff8;
                    4'd3: O_row_bits = 16'h300c;
                    4'd4: O_row_bits = 16'h300c;
                    4'd5: O_row_bits = 16'h300c;
                    4'd6: O_row_bits = 16'h1ff8;
                    4'd7: O_row_bits = 16'h1ff8;
                    4'd8: O_row_bits = 16'h000c;
                    4'd9: O_row_bits = 16'h000c;
                    4'd10: O_row_bits = 16'h000c;
                    4'd11: O_row_bits = 16'h1ff8;
                    4'd12: O_row_bits = 16'h1ff8;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_COLON: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0000;
                    4'd1: O_row_bits = 16'h0000;
                    4'd2: O_row_bits = 16'h0000;
                    4'd3: O_row_bits = 16'h0000;
                    4'd4: O_row_bits = 16'h0000;
                    4'd5: O_row_bits = 16'h0000;
                    4'd6: O_row_bits = 16'h0180;
                    4'd7: O_row_bits = 16'h0180;
                    4'd8: O_row_bits = 16'h0000;
                    4'd9: O_row_bits = 16'h0000;
                    4'd10: O_row_bits = 16'h0180;
                    4'd11: O_row_bits = 16'h0180;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            default: O_row_bits = 16'h0000;
        endcase
    end

endmodule


// Compact fixed 8x16 HUD font. Offline raster, bit7 is the left pixel.
module hud_font(input [7:0] character,input [3:0] row,output reg [7:0] bits);
always @* begin
 bits=0;
 case({character,row})
  12'h324,12'h333,12'h336,12'h337,12'h2f1,12'h2f2: bits=8'h04;
  12'h4a1,12'h4a2,12'h4a3,12'h4a4,12'h4a5,12'h4a6,12'h4a7,12'h4a8,12'h537,12'h538,12'h5a2,12'h356,12'h357,12'h2f0: bits=8'h06;
  12'h313,12'h314,12'h315,12'h316,12'h317,12'h318,12'h319,12'h31a,12'h375,12'h397,12'h2f4,12'h2f5: bits=8'h08;
  12'h5a3,12'h5a4,12'h325,12'h334,12'h34a,12'h374,12'h2f3: bits=8'h0c;
  12'h411,12'h543,12'h544,12'h545,12'h546,12'h547,12'h548,12'h549,12'h54a,12'h56a,12'h585,12'h5a6,12'h327,12'h342,12'h343,12'h362,12'h378,12'h399,12'h3a3,12'h3a4,12'h3a9,12'h3aa,12'h2e9,12'h2ea,12'h2ca,12'h2cb,12'h2cc,12'h2f7: bits=8'h10;
  12'h412,12'h491,12'h492,12'h493,12'h494,12'h495,12'h496,12'h497,12'h498,12'h499,12'h49a,12'h569,12'h5a5,12'h311,12'h312,12'h326,12'h335,12'h341,12'h361,12'h376,12'h377,12'h398,12'h2f6,12'h2b4,12'h2b5,12'h2b7,12'h2b8: bits=8'h18;
  12'h536: bits=8'h1c;
  12'h5a8,12'h364,12'h2fa: bits=8'h20;
  12'h385: bits=8'h24;
  12'h414,12'h415: bits=8'h28;
  12'h4a9,12'h566,12'h345: bits=8'h2c;
  12'h542,12'h586,12'h595,12'h596,12'h597,12'h598,12'h599,12'h59a,12'h5a7,12'h328,12'h344,12'h363,12'h379,12'h37a,12'h39a,12'h2f8,12'h2f9: bits=8'h30;
  12'h413,12'h431,12'h43a,12'h567,12'h568,12'h584,12'h587,12'h321,12'h331,12'h33a,12'h36a,12'h391: bits=8'h38;
  12'h4aa,12'h531,12'h301,12'h30a,12'h35a,12'h381,12'h386,12'h38a,12'h396: bits=8'h3c;
  12'h533: bits=8'h40;
  12'h563,12'h589,12'h323,12'h338,12'h367,12'h368,12'h393,12'h394: bits=8'h44;
  12'h419,12'h562,12'h304,12'h305,12'h306,12'h307,12'h358,12'h388: bits=8'h46;
  12'h593: bits=8'h48;
  12'h582,12'h372,12'h373: bits=8'h4c;
  12'h575: bits=8'h54;
  12'h534,12'h5a9,12'h329,12'h352,12'h353,12'h2fb,12'h2fc: bits=8'h60;
  12'h532,12'h564,12'h302,12'h309,12'h382: bits=8'h64;
  12'h539,12'h303,12'h308,12'h383,12'h384,12'h387,12'h389: bits=8'h66;
  12'h583: bits=8'h68;
  12'h416,12'h417,12'h432,12'h439,12'h565,12'h577,12'h578,12'h579,12'h57a,12'h588,12'h322,12'h332,12'h339,12'h346,12'h347,12'h355,12'h359,12'h366,12'h369,12'h392,12'h395: bits=8'h6c;
  12'h471,12'h47a,12'h4f1,12'h4fa,12'h511,12'h535,12'h55a,12'h594: bits=8'h78;
  12'h418,12'h53a,12'h559,12'h576,12'h348,12'h349,12'h351,12'h354,12'h365,12'h371,12'h2d7: bits=8'h7c;
  12'h51a,12'h5a1,12'h5aa,12'h32a,12'h2b6: bits=8'h7e;
  12'h474,12'h475: bits=8'h80;
  12'h4da: bits=8'h82;
  12'h477,12'h4f4,12'h4f5,12'h4f6,12'h4f7,12'h514,12'h515,12'h516,12'h551,12'h552,12'h553,12'h554,12'h555,12'h556,12'h557: bits=8'h84;
  12'h4d1: bits=8'h86;
  12'h517: bits=8'h8c;
  12'h4b4: bits=8'h90;
  12'h4d8,12'h4d9,12'h571,12'h572,12'h573: bits=8'h92;
  12'h4e6: bits=8'h96;
  12'h476: bits=8'h9c;
  12'h4e5: bits=8'hb6;
  12'h4d7: bits=8'hba;
  12'h434,12'h435,12'h436,12'h437,12'h452,12'h453,12'h454,12'h455,12'h457,12'h458,12'h459,12'h462,12'h463,12'h464,12'h465,12'h467,12'h468,12'h469,12'h46a,12'h4c1,12'h4c2,12'h4c3,12'h4c4,12'h4c5,12'h4c6,12'h4c7,12'h4c8,12'h4c9,12'h507,12'h508,12'h509,12'h50a: bits=8'hc0;
  12'h423,12'h427,12'h428,12'h443,12'h444,12'h445,12'h446,12'h447,12'h448,12'h478,12'h481,12'h482,12'h483,12'h484,12'h485,12'h487,12'h488,12'h489,12'h48a,12'h4b1,12'h503,12'h504,12'h523,12'h524,12'h52a,12'h558,12'h591: bits=8'hc4;
  12'h41a,12'h433,12'h438,12'h4ba,12'h4d2,12'h4d3,12'h4e1,12'h4e2,12'h4e9,12'h4ea,12'h561,12'h581,12'h58a: bits=8'hc6;
  12'h4b2,12'h528: bits=8'hc8;
  12'h422,12'h424,12'h426,12'h429,12'h442,12'h449,12'h472,12'h473,12'h479,12'h4b8,12'h4b9,12'h4f3,12'h4f8,12'h502,12'h505,12'h513,12'h522,12'h525,12'h529,12'h592: bits=8'hcc;
  12'h4d4,12'h4e8: bits=8'hce;
  12'h574: bits=8'hd4;
  12'h4b3,12'h4b7,12'h527: bits=8'hd8;
  12'h518: bits=8'hdc;
  12'h4e7: bits=8'hde;
  12'h4e3,12'h4e4: bits=8'he6;
  12'h4d5,12'h4d6: bits=8'hee;
  12'h4b5: bits=8'hf0;
  12'h421,12'h425,12'h42a,12'h441,12'h44a,12'h4b6,12'h501,12'h506,12'h521,12'h526: bits=8'hf8;
  12'h456,12'h466,12'h486,12'h4f2,12'h4f9,12'h512,12'h519: bits=8'hfc;
  12'h451,12'h45a,12'h461,12'h4ca,12'h541: bits=8'hfe;
  default:bits=0;
 endcase
end
endmodule

// One synchronous 8192-bit main-HUD ROM. Original combinational consumers above
// retain their interface. ASCII outside 32..95 remains blank; no external file.
// Private-font compatibility; the unused second read port is pruned.
module hud_font_sync(input clk,input [7:0] character,input [3:0] row,output wire [7:0] bits);
    wire [7:0] unused_bits;
    hud_font_dual_sync rom(.clk(clk),.character(character),.row(row),.bits(bits),
        .character_b(8'd32),.row_b(4'd0),.bits_b(unused_bits));
endmodule

module hud_font_dual_sync(
    input clk,input [7:0] character,input [3:0] row,output wire [7:0] bits,
    input [7:0] character_b,input [3:0] row_b,output wire [7:0] bits_b
);
    (* ram_style="bram" *) reg [7:0] glyph_rows[0:1023];
    reg [7:0] row_q,row_b_q;
    reg supported_q,supported_b_q;
    integer address;
    initial begin
        for(address=0;address<1024;address=address+1)glyph_rows[address]=0;
        glyph_rows[10'd692]=8'h18;
        glyph_rows[10'd693]=8'h18;
        glyph_rows[10'd694]=8'h7e;
        glyph_rows[10'd695]=8'h18;
        glyph_rows[10'd696]=8'h18;
        glyph_rows[10'd714]=8'h10;
        glyph_rows[10'd715]=8'h10;
        glyph_rows[10'd716]=8'h10;
        glyph_rows[10'd727]=8'h7c;
        glyph_rows[10'd745]=8'h10;
        glyph_rows[10'd746]=8'h10;
        glyph_rows[10'd752]=8'h06;
        glyph_rows[10'd753]=8'h04;
        glyph_rows[10'd754]=8'h04;
        glyph_rows[10'd755]=8'h0c;
        glyph_rows[10'd756]=8'h08;
        glyph_rows[10'd757]=8'h08;
        glyph_rows[10'd758]=8'h18;
        glyph_rows[10'd759]=8'h10;
        glyph_rows[10'd760]=8'h30;
        glyph_rows[10'd761]=8'h30;
        glyph_rows[10'd762]=8'h20;
        glyph_rows[10'd763]=8'h60;
        glyph_rows[10'd764]=8'h60;
        glyph_rows[10'd769]=8'h3c;
        glyph_rows[10'd770]=8'h64;
        glyph_rows[10'd771]=8'h66;
        glyph_rows[10'd772]=8'h46;
        glyph_rows[10'd773]=8'h46;
        glyph_rows[10'd774]=8'h46;
        glyph_rows[10'd775]=8'h46;
        glyph_rows[10'd776]=8'h66;
        glyph_rows[10'd777]=8'h64;
        glyph_rows[10'd778]=8'h3c;
        glyph_rows[10'd785]=8'h18;
        glyph_rows[10'd786]=8'h18;
        glyph_rows[10'd787]=8'h08;
        glyph_rows[10'd788]=8'h08;
        glyph_rows[10'd789]=8'h08;
        glyph_rows[10'd790]=8'h08;
        glyph_rows[10'd791]=8'h08;
        glyph_rows[10'd792]=8'h08;
        glyph_rows[10'd793]=8'h08;
        glyph_rows[10'd794]=8'h08;
        glyph_rows[10'd801]=8'h38;
        glyph_rows[10'd802]=8'h6c;
        glyph_rows[10'd803]=8'h44;
        glyph_rows[10'd804]=8'h04;
        glyph_rows[10'd805]=8'h0c;
        glyph_rows[10'd806]=8'h18;
        glyph_rows[10'd807]=8'h10;
        glyph_rows[10'd808]=8'h30;
        glyph_rows[10'd809]=8'h60;
        glyph_rows[10'd810]=8'h7e;
        glyph_rows[10'd817]=8'h38;
        glyph_rows[10'd818]=8'h6c;
        glyph_rows[10'd819]=8'h04;
        glyph_rows[10'd820]=8'h0c;
        glyph_rows[10'd821]=8'h18;
        glyph_rows[10'd822]=8'h04;
        glyph_rows[10'd823]=8'h04;
        glyph_rows[10'd824]=8'h44;
        glyph_rows[10'd825]=8'h6c;
        glyph_rows[10'd826]=8'h38;
        glyph_rows[10'd833]=8'h18;
        glyph_rows[10'd834]=8'h10;
        glyph_rows[10'd835]=8'h10;
        glyph_rows[10'd836]=8'h30;
        glyph_rows[10'd837]=8'h2c;
        glyph_rows[10'd838]=8'h6c;
        glyph_rows[10'd839]=8'h6c;
        glyph_rows[10'd840]=8'h7c;
        glyph_rows[10'd841]=8'h7c;
        glyph_rows[10'd842]=8'h0c;
        glyph_rows[10'd849]=8'h7c;
        glyph_rows[10'd850]=8'h60;
        glyph_rows[10'd851]=8'h60;
        glyph_rows[10'd852]=8'h7c;
        glyph_rows[10'd853]=8'h6c;
        glyph_rows[10'd854]=8'h06;
        glyph_rows[10'd855]=8'h06;
        glyph_rows[10'd856]=8'h46;
        glyph_rows[10'd857]=8'h6c;
        glyph_rows[10'd858]=8'h3c;
        glyph_rows[10'd865]=8'h18;
        glyph_rows[10'd866]=8'h10;
        glyph_rows[10'd867]=8'h30;
        glyph_rows[10'd868]=8'h20;
        glyph_rows[10'd869]=8'h7c;
        glyph_rows[10'd870]=8'h6c;
        glyph_rows[10'd871]=8'h44;
        glyph_rows[10'd872]=8'h44;
        glyph_rows[10'd873]=8'h6c;
        glyph_rows[10'd874]=8'h38;
        glyph_rows[10'd881]=8'h7c;
        glyph_rows[10'd882]=8'h4c;
        glyph_rows[10'd883]=8'h4c;
        glyph_rows[10'd884]=8'h0c;
        glyph_rows[10'd885]=8'h08;
        glyph_rows[10'd886]=8'h18;
        glyph_rows[10'd887]=8'h18;
        glyph_rows[10'd888]=8'h10;
        glyph_rows[10'd889]=8'h30;
        glyph_rows[10'd890]=8'h30;
        glyph_rows[10'd897]=8'h3c;
        glyph_rows[10'd898]=8'h64;
        glyph_rows[10'd899]=8'h66;
        glyph_rows[10'd900]=8'h66;
        glyph_rows[10'd901]=8'h24;
        glyph_rows[10'd902]=8'h3c;
        glyph_rows[10'd903]=8'h66;
        glyph_rows[10'd904]=8'h46;
        glyph_rows[10'd905]=8'h66;
        glyph_rows[10'd906]=8'h3c;
        glyph_rows[10'd913]=8'h38;
        glyph_rows[10'd914]=8'h6c;
        glyph_rows[10'd915]=8'h44;
        glyph_rows[10'd916]=8'h44;
        glyph_rows[10'd917]=8'h6c;
        glyph_rows[10'd918]=8'h3c;
        glyph_rows[10'd919]=8'h08;
        glyph_rows[10'd920]=8'h18;
        glyph_rows[10'd921]=8'h10;
        glyph_rows[10'd922]=8'h30;
        glyph_rows[10'd931]=8'h10;
        glyph_rows[10'd932]=8'h10;
        glyph_rows[10'd937]=8'h10;
        glyph_rows[10'd938]=8'h10;
        glyph_rows[10'd17]=8'h10;
        glyph_rows[10'd18]=8'h18;
        glyph_rows[10'd19]=8'h38;
        glyph_rows[10'd20]=8'h28;
        glyph_rows[10'd21]=8'h28;
        glyph_rows[10'd22]=8'h6c;
        glyph_rows[10'd23]=8'h6c;
        glyph_rows[10'd24]=8'h7c;
        glyph_rows[10'd25]=8'h46;
        glyph_rows[10'd26]=8'hc6;
        glyph_rows[10'd33]=8'hf8;
        glyph_rows[10'd34]=8'hcc;
        glyph_rows[10'd35]=8'hc4;
        glyph_rows[10'd36]=8'hcc;
        glyph_rows[10'd37]=8'hf8;
        glyph_rows[10'd38]=8'hcc;
        glyph_rows[10'd39]=8'hc4;
        glyph_rows[10'd40]=8'hc4;
        glyph_rows[10'd41]=8'hcc;
        glyph_rows[10'd42]=8'hf8;
        glyph_rows[10'd49]=8'h38;
        glyph_rows[10'd50]=8'h6c;
        glyph_rows[10'd51]=8'hc6;
        glyph_rows[10'd52]=8'hc0;
        glyph_rows[10'd53]=8'hc0;
        glyph_rows[10'd54]=8'hc0;
        glyph_rows[10'd55]=8'hc0;
        glyph_rows[10'd56]=8'hc6;
        glyph_rows[10'd57]=8'h6c;
        glyph_rows[10'd58]=8'h38;
        glyph_rows[10'd65]=8'hf8;
        glyph_rows[10'd66]=8'hcc;
        glyph_rows[10'd67]=8'hc4;
        glyph_rows[10'd68]=8'hc4;
        glyph_rows[10'd69]=8'hc4;
        glyph_rows[10'd70]=8'hc4;
        glyph_rows[10'd71]=8'hc4;
        glyph_rows[10'd72]=8'hc4;
        glyph_rows[10'd73]=8'hcc;
        glyph_rows[10'd74]=8'hf8;
        glyph_rows[10'd81]=8'hfe;
        glyph_rows[10'd82]=8'hc0;
        glyph_rows[10'd83]=8'hc0;
        glyph_rows[10'd84]=8'hc0;
        glyph_rows[10'd85]=8'hc0;
        glyph_rows[10'd86]=8'hfc;
        glyph_rows[10'd87]=8'hc0;
        glyph_rows[10'd88]=8'hc0;
        glyph_rows[10'd89]=8'hc0;
        glyph_rows[10'd90]=8'hfe;
        glyph_rows[10'd97]=8'hfe;
        glyph_rows[10'd98]=8'hc0;
        glyph_rows[10'd99]=8'hc0;
        glyph_rows[10'd100]=8'hc0;
        glyph_rows[10'd101]=8'hc0;
        glyph_rows[10'd102]=8'hfc;
        glyph_rows[10'd103]=8'hc0;
        glyph_rows[10'd104]=8'hc0;
        glyph_rows[10'd105]=8'hc0;
        glyph_rows[10'd106]=8'hc0;
        glyph_rows[10'd113]=8'h78;
        glyph_rows[10'd114]=8'hcc;
        glyph_rows[10'd115]=8'hcc;
        glyph_rows[10'd116]=8'h80;
        glyph_rows[10'd117]=8'h80;
        glyph_rows[10'd118]=8'h9c;
        glyph_rows[10'd119]=8'h84;
        glyph_rows[10'd120]=8'hc4;
        glyph_rows[10'd121]=8'hcc;
        glyph_rows[10'd122]=8'h78;
        glyph_rows[10'd129]=8'hc4;
        glyph_rows[10'd130]=8'hc4;
        glyph_rows[10'd131]=8'hc4;
        glyph_rows[10'd132]=8'hc4;
        glyph_rows[10'd133]=8'hc4;
        glyph_rows[10'd134]=8'hfc;
        glyph_rows[10'd135]=8'hc4;
        glyph_rows[10'd136]=8'hc4;
        glyph_rows[10'd137]=8'hc4;
        glyph_rows[10'd138]=8'hc4;
        glyph_rows[10'd145]=8'h18;
        glyph_rows[10'd146]=8'h18;
        glyph_rows[10'd147]=8'h18;
        glyph_rows[10'd148]=8'h18;
        glyph_rows[10'd149]=8'h18;
        glyph_rows[10'd150]=8'h18;
        glyph_rows[10'd151]=8'h18;
        glyph_rows[10'd152]=8'h18;
        glyph_rows[10'd153]=8'h18;
        glyph_rows[10'd154]=8'h18;
        glyph_rows[10'd161]=8'h06;
        glyph_rows[10'd162]=8'h06;
        glyph_rows[10'd163]=8'h06;
        glyph_rows[10'd164]=8'h06;
        glyph_rows[10'd165]=8'h06;
        glyph_rows[10'd166]=8'h06;
        glyph_rows[10'd167]=8'h06;
        glyph_rows[10'd168]=8'h06;
        glyph_rows[10'd169]=8'h2c;
        glyph_rows[10'd170]=8'h3c;
        glyph_rows[10'd177]=8'hc4;
        glyph_rows[10'd178]=8'hc8;
        glyph_rows[10'd179]=8'hd8;
        glyph_rows[10'd180]=8'h90;
        glyph_rows[10'd181]=8'hf0;
        glyph_rows[10'd182]=8'hf8;
        glyph_rows[10'd183]=8'hd8;
        glyph_rows[10'd184]=8'hcc;
        glyph_rows[10'd185]=8'hcc;
        glyph_rows[10'd186]=8'hc6;
        glyph_rows[10'd193]=8'hc0;
        glyph_rows[10'd194]=8'hc0;
        glyph_rows[10'd195]=8'hc0;
        glyph_rows[10'd196]=8'hc0;
        glyph_rows[10'd197]=8'hc0;
        glyph_rows[10'd198]=8'hc0;
        glyph_rows[10'd199]=8'hc0;
        glyph_rows[10'd200]=8'hc0;
        glyph_rows[10'd201]=8'hc0;
        glyph_rows[10'd202]=8'hfe;
        glyph_rows[10'd209]=8'h86;
        glyph_rows[10'd210]=8'hc6;
        glyph_rows[10'd211]=8'hc6;
        glyph_rows[10'd212]=8'hce;
        glyph_rows[10'd213]=8'hee;
        glyph_rows[10'd214]=8'hee;
        glyph_rows[10'd215]=8'hba;
        glyph_rows[10'd216]=8'h92;
        glyph_rows[10'd217]=8'h92;
        glyph_rows[10'd218]=8'h82;
        glyph_rows[10'd225]=8'hc6;
        glyph_rows[10'd226]=8'hc6;
        glyph_rows[10'd227]=8'he6;
        glyph_rows[10'd228]=8'he6;
        glyph_rows[10'd229]=8'hb6;
        glyph_rows[10'd230]=8'h96;
        glyph_rows[10'd231]=8'hde;
        glyph_rows[10'd232]=8'hce;
        glyph_rows[10'd233]=8'hc6;
        glyph_rows[10'd234]=8'hc6;
        glyph_rows[10'd241]=8'h78;
        glyph_rows[10'd242]=8'hfc;
        glyph_rows[10'd243]=8'hcc;
        glyph_rows[10'd244]=8'h84;
        glyph_rows[10'd245]=8'h84;
        glyph_rows[10'd246]=8'h84;
        glyph_rows[10'd247]=8'h84;
        glyph_rows[10'd248]=8'hcc;
        glyph_rows[10'd249]=8'hfc;
        glyph_rows[10'd250]=8'h78;
        glyph_rows[10'd257]=8'hf8;
        glyph_rows[10'd258]=8'hcc;
        glyph_rows[10'd259]=8'hc4;
        glyph_rows[10'd260]=8'hc4;
        glyph_rows[10'd261]=8'hcc;
        glyph_rows[10'd262]=8'hf8;
        glyph_rows[10'd263]=8'hc0;
        glyph_rows[10'd264]=8'hc0;
        glyph_rows[10'd265]=8'hc0;
        glyph_rows[10'd266]=8'hc0;
        glyph_rows[10'd273]=8'h78;
        glyph_rows[10'd274]=8'hfc;
        glyph_rows[10'd275]=8'hcc;
        glyph_rows[10'd276]=8'h84;
        glyph_rows[10'd277]=8'h84;
        glyph_rows[10'd278]=8'h84;
        glyph_rows[10'd279]=8'h8c;
        glyph_rows[10'd280]=8'hdc;
        glyph_rows[10'd281]=8'hfc;
        glyph_rows[10'd282]=8'h7e;
        glyph_rows[10'd289]=8'hf8;
        glyph_rows[10'd290]=8'hcc;
        glyph_rows[10'd291]=8'hc4;
        glyph_rows[10'd292]=8'hc4;
        glyph_rows[10'd293]=8'hcc;
        glyph_rows[10'd294]=8'hf8;
        glyph_rows[10'd295]=8'hd8;
        glyph_rows[10'd296]=8'hc8;
        glyph_rows[10'd297]=8'hcc;
        glyph_rows[10'd298]=8'hc4;
        glyph_rows[10'd305]=8'h3c;
        glyph_rows[10'd306]=8'h64;
        glyph_rows[10'd307]=8'h40;
        glyph_rows[10'd308]=8'h60;
        glyph_rows[10'd309]=8'h78;
        glyph_rows[10'd310]=8'h1c;
        glyph_rows[10'd311]=8'h06;
        glyph_rows[10'd312]=8'h06;
        glyph_rows[10'd313]=8'h66;
        glyph_rows[10'd314]=8'h7c;
        glyph_rows[10'd321]=8'hfe;
        glyph_rows[10'd322]=8'h30;
        glyph_rows[10'd323]=8'h10;
        glyph_rows[10'd324]=8'h10;
        glyph_rows[10'd325]=8'h10;
        glyph_rows[10'd326]=8'h10;
        glyph_rows[10'd327]=8'h10;
        glyph_rows[10'd328]=8'h10;
        glyph_rows[10'd329]=8'h10;
        glyph_rows[10'd330]=8'h10;
        glyph_rows[10'd337]=8'h84;
        glyph_rows[10'd338]=8'h84;
        glyph_rows[10'd339]=8'h84;
        glyph_rows[10'd340]=8'h84;
        glyph_rows[10'd341]=8'h84;
        glyph_rows[10'd342]=8'h84;
        glyph_rows[10'd343]=8'h84;
        glyph_rows[10'd344]=8'hc4;
        glyph_rows[10'd345]=8'h7c;
        glyph_rows[10'd346]=8'h78;
        glyph_rows[10'd353]=8'hc6;
        glyph_rows[10'd354]=8'h46;
        glyph_rows[10'd355]=8'h44;
        glyph_rows[10'd356]=8'h64;
        glyph_rows[10'd357]=8'h6c;
        glyph_rows[10'd358]=8'h2c;
        glyph_rows[10'd359]=8'h38;
        glyph_rows[10'd360]=8'h38;
        glyph_rows[10'd361]=8'h18;
        glyph_rows[10'd362]=8'h10;
        glyph_rows[10'd369]=8'h92;
        glyph_rows[10'd370]=8'h92;
        glyph_rows[10'd371]=8'h92;
        glyph_rows[10'd372]=8'hd4;
        glyph_rows[10'd373]=8'h54;
        glyph_rows[10'd374]=8'h7c;
        glyph_rows[10'd375]=8'h6c;
        glyph_rows[10'd376]=8'h6c;
        glyph_rows[10'd377]=8'h6c;
        glyph_rows[10'd378]=8'h6c;
        glyph_rows[10'd385]=8'hc6;
        glyph_rows[10'd386]=8'h4c;
        glyph_rows[10'd387]=8'h68;
        glyph_rows[10'd388]=8'h38;
        glyph_rows[10'd389]=8'h10;
        glyph_rows[10'd390]=8'h30;
        glyph_rows[10'd391]=8'h38;
        glyph_rows[10'd392]=8'h6c;
        glyph_rows[10'd393]=8'h44;
        glyph_rows[10'd394]=8'hc6;
        glyph_rows[10'd401]=8'hc4;
        glyph_rows[10'd402]=8'hcc;
        glyph_rows[10'd403]=8'h48;
        glyph_rows[10'd404]=8'h78;
        glyph_rows[10'd405]=8'h30;
        glyph_rows[10'd406]=8'h30;
        glyph_rows[10'd407]=8'h30;
        glyph_rows[10'd408]=8'h30;
        glyph_rows[10'd409]=8'h30;
        glyph_rows[10'd410]=8'h30;
        glyph_rows[10'd417]=8'h7e;
        glyph_rows[10'd418]=8'h06;
        glyph_rows[10'd419]=8'h0c;
        glyph_rows[10'd420]=8'h0c;
        glyph_rows[10'd421]=8'h18;
        glyph_rows[10'd422]=8'h10;
        glyph_rows[10'd423]=8'h30;
        glyph_rows[10'd424]=8'h20;
        glyph_rows[10'd425]=8'h60;
        glyph_rows[10'd426]=8'h7e;
    end
    always @(posedge clk)begin
        row_q<=glyph_rows[{character[5:0],row}];
        row_b_q<=glyph_rows[{character_b[5:0],row_b}];
        case(character_b[7:5])
            3'b001,3'b010:supported_b_q<=1'b1;
            default:supported_b_q<=1'b0;
        endcase
        case(character[7:5])
            3'b001,3'b010:supported_q<=1'b1;
            default:supported_q<=1'b0;
        endcase
    end
    assign bits=supported_q?row_q:8'd0;
    assign bits_b=supported_b_q?row_b_q:8'd0;
endmodule

// Compact 16x16 Chinese mode titles: 64 glyphs x 16 rows x 16 bits.
// Glyphs are embedded; no external font/mem file is used by the FPGA.
module hud_mode_font_sync(input clk,input [5:0] glyph,input [3:0] row,output reg [15:0] bits);
    (* ram_style="bram" *) reg [15:0] glyph_rows[0:1023];
    integer address;
    initial begin
        for(address=0;address<1024;address=address+1)glyph_rows[address]=0;
        // Glyph 0: 原
        glyph_rows[10'd1]=16'h1ffe;
        glyph_rows[10'd2]=16'h10c0;
        glyph_rows[10'd3]=16'h1080;
        glyph_rows[10'd4]=16'h17fc;
        glyph_rows[10'd5]=16'h1404;
        glyph_rows[10'd6]=16'h17fc;
        glyph_rows[10'd7]=16'h1404;
        glyph_rows[10'd8]=16'h17fc;
        glyph_rows[10'd9]=16'h1040;
        glyph_rows[10'd10]=16'h3258;
        glyph_rows[10'd11]=16'h224c;
        glyph_rows[10'd12]=16'h2446;
        glyph_rows[10'd13]=16'h6842;
        glyph_rows[10'd14]=16'h01c0;
        // Glyph 1: 始
        glyph_rows[10'd17]=16'h1020;
        glyph_rows[10'd18]=16'h1020;
        glyph_rows[10'd19]=16'h1040;
        glyph_rows[10'd20]=16'h10c8;
        glyph_rows[10'd21]=16'h7e84;
        glyph_rows[10'd22]=16'h15fe;
        glyph_rows[10'd23]=16'h2400;
        glyph_rows[10'd24]=16'h24fc;
        glyph_rows[10'd25]=16'h2484;
        glyph_rows[10'd26]=16'h2484;
        glyph_rows[10'd27]=16'h0884;
        glyph_rows[10'd28]=16'h1684;
        glyph_rows[10'd29]=16'h20fc;
        glyph_rows[10'd30]=16'h4084;
        // Glyph 2: 画
        glyph_rows[10'd33]=16'h3ffc;
        glyph_rows[10'd36]=16'h0ff0;
        glyph_rows[10'd37]=16'h0910;
        glyph_rows[10'd38]=16'h2914;
        glyph_rows[10'd39]=16'h2ff4;
        glyph_rows[10'd40]=16'h2914;
        glyph_rows[10'd41]=16'h2914;
        glyph_rows[10'd42]=16'h2ff4;
        glyph_rows[10'd43]=16'h2004;
        glyph_rows[10'd44]=16'h2004;
        glyph_rows[10'd45]=16'h3ffc;
        glyph_rows[10'd46]=16'h0004;
        // Glyph 3: 面
        glyph_rows[10'd49]=16'h7ffe;
        glyph_rows[10'd50]=16'h0180;
        glyph_rows[10'd51]=16'h0100;
        glyph_rows[10'd52]=16'h3ffc;
        glyph_rows[10'd53]=16'h2244;
        glyph_rows[10'd54]=16'h2244;
        glyph_rows[10'd55]=16'h23c4;
        glyph_rows[10'd56]=16'h2244;
        glyph_rows[10'd57]=16'h23c4;
        glyph_rows[10'd58]=16'h2244;
        glyph_rows[10'd59]=16'h2244;
        glyph_rows[10'd60]=16'h3ffc;
        glyph_rows[10'd61]=16'h2004;
        // Glyph 4: 灰
        glyph_rows[10'd64]=16'h0400;
        glyph_rows[10'd65]=16'h0400;
        glyph_rows[10'd66]=16'h7ffe;
        glyph_rows[10'd67]=16'h0400;
        glyph_rows[10'd68]=16'h0440;
        glyph_rows[10'd69]=16'h0440;
        glyph_rows[10'd70]=16'h0648;
        glyph_rows[10'd71]=16'h0a48;
        glyph_rows[10'd72]=16'h0a58;
        glyph_rows[10'd73]=16'h0e50;
        glyph_rows[10'd74]=16'h10a0;
        glyph_rows[10'd75]=16'h30b0;
        glyph_rows[10'd76]=16'h6318;
        glyph_rows[10'd77]=16'h460e;
        glyph_rows[10'd78]=16'h0802;
        // Glyph 5: 度
        glyph_rows[10'd80]=16'h0080;
        glyph_rows[10'd81]=16'h0040;
        glyph_rows[10'd82]=16'h1ffe;
        glyph_rows[10'd83]=16'h1110;
        glyph_rows[10'd84]=16'h1ffe;
        glyph_rows[10'd85]=16'h1110;
        glyph_rows[10'd86]=16'h1110;
        glyph_rows[10'd87]=16'h11f0;
        glyph_rows[10'd88]=16'h17f8;
        glyph_rows[10'd89]=16'h1110;
        glyph_rows[10'd90]=16'h11a0;
        glyph_rows[10'd91]=16'h20e0;
        glyph_rows[10'd92]=16'h20e0;
        glyph_rows[10'd93]=16'h673e;
        glyph_rows[10'd94]=16'h4c06;
        // Glyph 6: 模
        glyph_rows[10'd97]=16'h1058;
        glyph_rows[10'd98]=16'h1050;
        glyph_rows[10'd99]=16'h13fe;
        glyph_rows[10'd100]=16'h7cd0;
        glyph_rows[10'd101]=16'h11fc;
        glyph_rows[10'd102]=16'h19fc;
        glyph_rows[10'd103]=16'h3d04;
        glyph_rows[10'd104]=16'h31fc;
        glyph_rows[10'd105]=16'h5020;
        glyph_rows[10'd106]=16'h53fe;
        glyph_rows[10'd107]=16'h1070;
        glyph_rows[10'd108]=16'h10d8;
        glyph_rows[10'd109]=16'h138c;
        glyph_rows[10'd110]=16'h1202;
        // Glyph 7: 式
        glyph_rows[10'd112]=16'h0040;
        glyph_rows[10'd113]=16'h0048;
        glyph_rows[10'd114]=16'h0040;
        glyph_rows[10'd115]=16'h7ffe;
        glyph_rows[10'd116]=16'h0040;
        glyph_rows[10'd117]=16'h0040;
        glyph_rows[10'd118]=16'h3fe0;
        glyph_rows[10'd119]=16'h0420;
        glyph_rows[10'd120]=16'h0420;
        glyph_rows[10'd121]=16'h0420;
        glyph_rows[10'd122]=16'h0410;
        glyph_rows[10'd123]=16'h0592;
        glyph_rows[10'd124]=16'h3e0a;
        glyph_rows[10'd125]=16'h2006;
        // Glyph 8: 二
        glyph_rows[10'd130]=16'h3ffc;
        glyph_rows[10'd139]=16'h7ffe;
        // Glyph 9: 值
        glyph_rows[10'd144]=16'h0840;
        glyph_rows[10'd145]=16'h1840;
        glyph_rows[10'd146]=16'h17fe;
        glyph_rows[10'd147]=16'h1040;
        glyph_rows[10'd148]=16'h33f8;
        glyph_rows[10'd149]=16'h7208;
        glyph_rows[10'd150]=16'h53f8;
        glyph_rows[10'd151]=16'h1208;
        glyph_rows[10'd152]=16'h13f8;
        glyph_rows[10'd153]=16'h1208;
        glyph_rows[10'd154]=16'h13f8;
        glyph_rows[10'd155]=16'h1208;
        glyph_rows[10'd156]=16'h1208;
        glyph_rows[10'd157]=16'h1ffe;
        glyph_rows[10'd158]=16'h1000;
        // Glyph 10: 对
        glyph_rows[10'd161]=16'h0008;
        glyph_rows[10'd162]=16'h0008;
        glyph_rows[10'd163]=16'h7e08;
        glyph_rows[10'd164]=16'h0208;
        glyph_rows[10'd165]=16'h23fe;
        glyph_rows[10'd166]=16'h3208;
        glyph_rows[10'd167]=16'h1408;
        glyph_rows[10'd168]=16'h0cc8;
        glyph_rows[10'd169]=16'h0c48;
        glyph_rows[10'd170]=16'h0c08;
        glyph_rows[10'd171]=16'h1208;
        glyph_rows[10'd172]=16'h3308;
        glyph_rows[10'd173]=16'h6008;
        glyph_rows[10'd174]=16'h0038;
        // Glyph 11: 比
        glyph_rows[10'd177]=16'h0040;
        glyph_rows[10'd178]=16'h3040;
        glyph_rows[10'd179]=16'h2040;
        glyph_rows[10'd180]=16'h2044;
        glyph_rows[10'd181]=16'h204c;
        glyph_rows[10'd182]=16'h3e70;
        glyph_rows[10'd183]=16'h2040;
        glyph_rows[10'd184]=16'h2040;
        glyph_rows[10'd185]=16'h2040;
        glyph_rows[10'd186]=16'h2040;
        glyph_rows[10'd187]=16'h2240;
        glyph_rows[10'd188]=16'h2642;
        glyph_rows[10'd189]=16'h3846;
        glyph_rows[10'd190]=16'h207c;
        // Glyph 12: 拉
        glyph_rows[10'd193]=16'h1040;
        glyph_rows[10'd194]=16'h1020;
        glyph_rows[10'd195]=16'h1030;
        glyph_rows[10'd196]=16'h7dfe;
        glyph_rows[10'd197]=16'h1000;
        glyph_rows[10'd198]=16'h1008;
        glyph_rows[10'd199]=16'h1588;
        glyph_rows[10'd200]=16'h1888;
        glyph_rows[10'd201]=16'h7088;
        glyph_rows[10'd202]=16'h10d0;
        glyph_rows[10'd203]=16'h1050;
        glyph_rows[10'd204]=16'h1010;
        glyph_rows[10'd205]=16'h13fe;
        glyph_rows[10'd206]=16'h3000;
        // Glyph 13: 伸
        glyph_rows[10'd208]=16'h0820;
        glyph_rows[10'd209]=16'h0820;
        glyph_rows[10'd210]=16'h1820;
        glyph_rows[10'd211]=16'h13fe;
        glyph_rows[10'd212]=16'h3222;
        glyph_rows[10'd213]=16'h3222;
        glyph_rows[10'd214]=16'h7222;
        glyph_rows[10'd215]=16'h53fe;
        glyph_rows[10'd216]=16'h1222;
        glyph_rows[10'd217]=16'h1222;
        glyph_rows[10'd218]=16'h13fe;
        glyph_rows[10'd219]=16'h1222;
        glyph_rows[10'd220]=16'h1020;
        glyph_rows[10'd221]=16'h1020;
        glyph_rows[10'd222]=16'h1020;
        glyph_rows[10'd223]=16'h1020;
        // Glyph 14: 边
        glyph_rows[10'd224]=16'h0040;
        glyph_rows[10'd225]=16'h2040;
        glyph_rows[10'd226]=16'h1840;
        glyph_rows[10'd227]=16'h03fc;
        glyph_rows[10'd228]=16'h00c4;
        glyph_rows[10'd229]=16'h0084;
        glyph_rows[10'd230]=16'h7084;
        glyph_rows[10'd231]=16'h1084;
        glyph_rows[10'd232]=16'h118c;
        glyph_rows[10'd233]=16'h1108;
        glyph_rows[10'd234]=16'h1218;
        glyph_rows[10'd235]=16'h1610;
        glyph_rows[10'd236]=16'h2c00;
        glyph_rows[10'd237]=16'h43fe;
        // Glyph 15: 缘
        glyph_rows[10'd241]=16'h1080;
        glyph_rows[10'd242]=16'h10fc;
        glyph_rows[10'd243]=16'h2088;
        glyph_rows[10'd244]=16'h65f8;
        glyph_rows[10'd245]=16'h7808;
        glyph_rows[10'd246]=16'h1bfe;
        glyph_rows[10'd247]=16'h1040;
        glyph_rows[10'd248]=16'h21cc;
        glyph_rows[10'd249]=16'h7a78;
        glyph_rows[10'd250]=16'h40a8;
        glyph_rows[10'd251]=16'h0368;
        glyph_rows[10'd252]=16'h08a4;
        glyph_rows[10'd253]=16'h7b26;
        glyph_rows[10'd254]=16'h4622;
        glyph_rows[10'd255]=16'h00e0;
        // Glyph 16: 检
        glyph_rows[10'd257]=16'h1820;
        glyph_rows[10'd258]=16'h1060;
        glyph_rows[10'd259]=16'h1070;
        glyph_rows[10'd260]=16'h1090;
        glyph_rows[10'd261]=16'h7d8c;
        glyph_rows[10'd262]=16'h1306;
        glyph_rows[10'd263]=16'h1afc;
        glyph_rows[10'd264]=16'h3c04;
        glyph_rows[10'd265]=16'h304c;
        glyph_rows[10'd266]=16'h5128;
        glyph_rows[10'd267]=16'h1088;
        glyph_rows[10'd268]=16'h1010;
        glyph_rows[10'd269]=16'h13fe;
        glyph_rows[10'd270]=16'h1800;
        // Glyph 17: 测
        glyph_rows[10'd273]=16'h2006;
        glyph_rows[10'd274]=16'h17c6;
        glyph_rows[10'd275]=16'h0456;
        glyph_rows[10'd276]=16'h0456;
        glyph_rows[10'd277]=16'h4556;
        glyph_rows[10'd278]=16'h3556;
        glyph_rows[10'd279]=16'h0556;
        glyph_rows[10'd280]=16'h0556;
        glyph_rows[10'd281]=16'h0556;
        glyph_rows[10'd282]=16'h1556;
        glyph_rows[10'd283]=16'h3286;
        glyph_rows[10'd284]=16'h2246;
        glyph_rows[10'd285]=16'h4c24;
        glyph_rows[10'd286]=16'h080c;
        // Glyph 18: 高
        glyph_rows[10'd288]=16'h0100;
        glyph_rows[10'd289]=16'h0180;
        glyph_rows[10'd290]=16'h7ffe;
        glyph_rows[10'd292]=16'h0ff0;
        glyph_rows[10'd293]=16'h0810;
        glyph_rows[10'd294]=16'h0ff0;
        glyph_rows[10'd296]=16'h3ffc;
        glyph_rows[10'd297]=16'h2004;
        glyph_rows[10'd298]=16'h27e4;
        glyph_rows[10'd299]=16'h2424;
        glyph_rows[10'd300]=16'h2fe4;
        glyph_rows[10'd301]=16'h2004;
        glyph_rows[10'd302]=16'h2018;
        // Glyph 19: 斯
        glyph_rows[10'd305]=16'h3204;
        glyph_rows[10'd306]=16'h227c;
        glyph_rows[10'd307]=16'h7f40;
        glyph_rows[10'd308]=16'h2240;
        glyph_rows[10'd309]=16'h3e40;
        glyph_rows[10'd310]=16'h227e;
        glyph_rows[10'd311]=16'h3e48;
        glyph_rows[10'd312]=16'h2248;
        glyph_rows[10'd313]=16'h2248;
        glyph_rows[10'd314]=16'h7fc8;
        glyph_rows[10'd315]=16'h0048;
        glyph_rows[10'd316]=16'h3288;
        glyph_rows[10'd317]=16'h6188;
        glyph_rows[10'd318]=16'h4108;
        // Glyph 20: 滤
        glyph_rows[10'd320]=16'h0040;
        glyph_rows[10'd321]=16'h207c;
        glyph_rows[10'd322]=16'h1040;
        glyph_rows[10'd323]=16'h0ffe;
        glyph_rows[10'd324]=16'h0444;
        glyph_rows[10'd325]=16'h6440;
        glyph_rows[10'd326]=16'h35f0;
        glyph_rows[10'd327]=16'h0444;
        glyph_rows[10'd328]=16'h0478;
        glyph_rows[10'd329]=16'h1420;
        glyph_rows[10'd330]=16'h1474;
        glyph_rows[10'd331]=16'h1556;
        glyph_rows[10'd332]=16'h2d42;
        glyph_rows[10'd333]=16'h2a48;
        glyph_rows[10'd334]=16'h3878;
        // Glyph 21: 波
        glyph_rows[10'd336]=16'h2060;
        glyph_rows[10'd337]=16'h1840;
        glyph_rows[10'd338]=16'h03fc;
        glyph_rows[10'd339]=16'h0244;
        glyph_rows[10'd340]=16'h6240;
        glyph_rows[10'd341]=16'h3240;
        glyph_rows[10'd342]=16'h03f8;
        glyph_rows[10'd343]=16'h0388;
        glyph_rows[10'd344]=16'h1288;
        glyph_rows[10'd345]=16'h12d0;
        glyph_rows[10'd346]=16'h1470;
        glyph_rows[10'd347]=16'h2430;
        glyph_rows[10'd348]=16'h2478;
        glyph_rows[10'd349]=16'h498e;
        glyph_rows[10'd350]=16'h0302;
        // Glyph 22: 腐
        glyph_rows[10'd352]=16'h0080;
        glyph_rows[10'd353]=16'h3ffe;
        glyph_rows[10'd354]=16'h2200;
        glyph_rows[10'd355]=16'h2208;
        glyph_rows[10'd356]=16'h25fe;
        glyph_rows[10'd357]=16'h3c08;
        glyph_rows[10'd358]=16'h2448;
        glyph_rows[10'd359]=16'h24d8;
        glyph_rows[10'd360]=16'h2ffc;
        glyph_rows[10'd361]=16'h29c4;
        glyph_rows[10'd362]=16'h2bb4;
        glyph_rows[10'd363]=16'h28c4;
        glyph_rows[10'd364]=16'h2964;
        glyph_rows[10'd365]=16'h4a14;
        glyph_rows[10'd366]=16'h4808;
        // Glyph 23: 蚀
        glyph_rows[10'd369]=16'h1020;
        glyph_rows[10'd370]=16'h1020;
        glyph_rows[10'd371]=16'h3020;
        glyph_rows[10'd372]=16'h3ffc;
        glyph_rows[10'd373]=16'h2524;
        glyph_rows[10'd374]=16'h5524;
        glyph_rows[10'd375]=16'h1124;
        glyph_rows[10'd376]=16'h1124;
        glyph_rows[10'd377]=16'h11fc;
        glyph_rows[10'd378]=16'h1020;
        glyph_rows[10'd379]=16'h1420;
        glyph_rows[10'd380]=16'h1c24;
        glyph_rows[10'd381]=16'h1bfe;
        glyph_rows[10'd382]=16'h0302;
        // Glyph 24: 处
        glyph_rows[10'd385]=16'h0860;
        glyph_rows[10'd386]=16'h0860;
        glyph_rows[10'd387]=16'h0860;
        glyph_rows[10'd388]=16'h1f60;
        glyph_rows[10'd389]=16'h1160;
        glyph_rows[10'd390]=16'h3178;
        glyph_rows[10'd391]=16'h326c;
        glyph_rows[10'd392]=16'h7a62;
        glyph_rows[10'd393]=16'h4a60;
        glyph_rows[10'd394]=16'h0c60;
        glyph_rows[10'd395]=16'h0e60;
        glyph_rows[10'd396]=16'h0be0;
        glyph_rows[10'd397]=16'h307e;
        glyph_rows[10'd398]=16'h6000;
        // Glyph 25: 理
        glyph_rows[10'd400]=16'h01fc;
        glyph_rows[10'd401]=16'h7d24;
        glyph_rows[10'd402]=16'h1124;
        glyph_rows[10'd403]=16'h11fc;
        glyph_rows[10'd404]=16'h1124;
        glyph_rows[10'd405]=16'h1124;
        glyph_rows[10'd406]=16'h7d24;
        glyph_rows[10'd407]=16'h11fc;
        glyph_rows[10'd408]=16'h1020;
        glyph_rows[10'd409]=16'h1020;
        glyph_rows[10'd410]=16'h11fe;
        glyph_rows[10'd411]=16'h1c20;
        glyph_rows[10'd412]=16'h7020;
        glyph_rows[10'd413]=16'h07fe;
        // Glyph 26: 反
        glyph_rows[10'd417]=16'h00f8;
        glyph_rows[10'd418]=16'h1fe0;
        glyph_rows[10'd419]=16'h1000;
        glyph_rows[10'd420]=16'h1000;
        glyph_rows[10'd421]=16'h1000;
        glyph_rows[10'd422]=16'h1ff8;
        glyph_rows[10'd423]=16'h1410;
        glyph_rows[10'd424]=16'h1210;
        glyph_rows[10'd425]=16'h1120;
        glyph_rows[10'd426]=16'h10e0;
        glyph_rows[10'd427]=16'h30e0;
        glyph_rows[10'd428]=16'h21b0;
        glyph_rows[10'd429]=16'h660e;
        glyph_rows[10'd430]=16'h4800;
        // Glyph 27: 色
        glyph_rows[10'd433]=16'h0200;
        glyph_rows[10'd434]=16'h07e0;
        glyph_rows[10'd435]=16'h0820;
        glyph_rows[10'd436]=16'h0040;
        glyph_rows[10'd437]=16'h7ff8;
        glyph_rows[10'd438]=16'h1108;
        glyph_rows[10'd439]=16'h1108;
        glyph_rows[10'd440]=16'h1108;
        glyph_rows[10'd441]=16'h1ff8;
        glyph_rows[10'd442]=16'h1000;
        glyph_rows[10'd443]=16'h1000;
        glyph_rows[10'd444]=16'h1002;
        glyph_rows[10'd445]=16'h1006;
        glyph_rows[10'd446]=16'h1ffc;
        // Glyph 28: 裁
        glyph_rows[10'd449]=16'h0460;
        glyph_rows[10'd450]=16'h0458;
        glyph_rows[10'd451]=16'h3fcc;
        glyph_rows[10'd452]=16'h0440;
        glyph_rows[10'd453]=16'h7ffe;
        glyph_rows[10'd454]=16'h0c20;
        glyph_rows[10'd455]=16'h7fac;
        glyph_rows[10'd456]=16'h0828;
        glyph_rows[10'd457]=16'h0b28;
        glyph_rows[10'd458]=16'h1b30;
        glyph_rows[10'd459]=16'h3910;
        glyph_rows[10'd460]=16'h4ab0;
        glyph_rows[10'd461]=16'h0c4a;
        glyph_rows[10'd462]=16'h0886;
        // Glyph 29: 剪
        glyph_rows[10'd465]=16'h0620;
        glyph_rows[10'd466]=16'h7ffe;
        glyph_rows[10'd468]=16'h1f28;
        glyph_rows[10'd469]=16'h1128;
        glyph_rows[10'd470]=16'h1f28;
        glyph_rows[10'd471]=16'h1f28;
        glyph_rows[10'd472]=16'h1128;
        glyph_rows[10'd473]=16'h1108;
        glyph_rows[10'd474]=16'h1318;
        glyph_rows[10'd475]=16'h1ff8;
        glyph_rows[10'd476]=16'h0208;
        glyph_rows[10'd477]=16'h0c08;
        glyph_rows[10'd478]=16'h3070;
        // Glyph 30: 伽
        glyph_rows[10'd481]=16'h0a00;
        glyph_rows[10'd482]=16'h1a00;
        glyph_rows[10'd483]=16'h121e;
        glyph_rows[10'd484]=16'h17d2;
        glyph_rows[10'd485]=16'h3252;
        glyph_rows[10'd486]=16'h7252;
        glyph_rows[10'd487]=16'h5252;
        glyph_rows[10'd488]=16'h1252;
        glyph_rows[10'd489]=16'h1252;
        glyph_rows[10'd490]=16'h1252;
        glyph_rows[10'd491]=16'h1252;
        glyph_rows[10'd492]=16'h145e;
        glyph_rows[10'd493]=16'h1492;
        glyph_rows[10'd494]=16'h1180;
        // Glyph 31: 马
        glyph_rows[10'd497]=16'h1ff0;
        glyph_rows[10'd498]=16'h0010;
        glyph_rows[10'd499]=16'h0010;
        glyph_rows[10'd500]=16'h0810;
        glyph_rows[10'd501]=16'h0810;
        glyph_rows[10'd502]=16'h0810;
        glyph_rows[10'd503]=16'h0830;
        glyph_rows[10'd504]=16'h0ffe;
        glyph_rows[10'd505]=16'h0006;
        glyph_rows[10'd506]=16'h0004;
        glyph_rows[10'd507]=16'h7ff4;
        glyph_rows[10'd508]=16'h0004;
        glyph_rows[10'd509]=16'h0004;
        glyph_rows[10'd510]=16'h0038;
        // Glyph 32: 校
        glyph_rows[10'd512]=16'h0840;
        glyph_rows[10'd513]=16'h0820;
        glyph_rows[10'd514]=16'h0810;
        glyph_rows[10'd515]=16'h09fe;
        glyph_rows[10'd516]=16'h7c40;
        glyph_rows[10'd517]=16'h18cc;
        glyph_rows[10'd518]=16'h1986;
        glyph_rows[10'd519]=16'h3c00;
        glyph_rows[10'd520]=16'h2c88;
        glyph_rows[10'd521]=16'h6858;
        glyph_rows[10'd522]=16'h4870;
        glyph_rows[10'd523]=16'h0830;
        glyph_rows[10'd524]=16'h0858;
        glyph_rows[10'd525]=16'h098c;
        glyph_rows[10'd526]=16'h0b02;
        // Glyph 33: 正
        glyph_rows[10'd529]=16'h3ffc;
        glyph_rows[10'd530]=16'h0080;
        glyph_rows[10'd531]=16'h0080;
        glyph_rows[10'd532]=16'h0880;
        glyph_rows[10'd533]=16'h0880;
        glyph_rows[10'd534]=16'h08f8;
        glyph_rows[10'd535]=16'h0880;
        glyph_rows[10'd536]=16'h0880;
        glyph_rows[10'd537]=16'h0880;
        glyph_rows[10'd538]=16'h0880;
        glyph_rows[10'd539]=16'h0880;
        glyph_rows[10'd540]=16'h7ffe;
        // Glyph 34: 伪
        glyph_rows[10'd545]=16'h0820;
        glyph_rows[10'd546]=16'h0920;
        glyph_rows[10'd547]=16'h11a0;
        glyph_rows[10'd548]=16'h1020;
        glyph_rows[10'd549]=16'h37fe;
        glyph_rows[10'd550]=16'h7042;
        glyph_rows[10'd551]=16'h5042;
        glyph_rows[10'd552]=16'h1042;
        glyph_rows[10'd553]=16'h10e6;
        glyph_rows[10'd554]=16'h1094;
        glyph_rows[10'd555]=16'h1184;
        glyph_rows[10'd556]=16'h1104;
        glyph_rows[10'd557]=16'h1604;
        glyph_rows[10'd558]=16'h1418;
        // Glyph 35: 彩
        glyph_rows[10'd561]=16'h0308;
        glyph_rows[10'd562]=16'h7808;
        glyph_rows[10'd563]=16'h0910;
        glyph_rows[10'd564]=16'h2920;
        glyph_rows[10'd565]=16'h3640;
        glyph_rows[10'd566]=16'h040c;
        glyph_rows[10'd567]=16'h7f98;
        glyph_rows[10'd568]=16'h0c20;
        glyph_rows[10'd569]=16'h0e02;
        glyph_rows[10'd570]=16'h1504;
        glyph_rows[10'd571]=16'h2408;
        glyph_rows[10'd572]=16'h6410;
        glyph_rows[10'd573]=16'h4460;
        glyph_rows[10'd574]=16'h04c0;
        // Glyph 36: 卡
        glyph_rows[10'd576]=16'h0300;
        glyph_rows[10'd577]=16'h0300;
        glyph_rows[10'd578]=16'h03f8;
        glyph_rows[10'd579]=16'h0300;
        glyph_rows[10'd580]=16'h0300;
        glyph_rows[10'd581]=16'h0300;
        glyph_rows[10'd582]=16'h7ffe;
        glyph_rows[10'd583]=16'h0100;
        glyph_rows[10'd584]=16'h0100;
        glyph_rows[10'd585]=16'h0180;
        glyph_rows[10'd586]=16'h0160;
        glyph_rows[10'd587]=16'h0118;
        glyph_rows[10'd588]=16'h0100;
        glyph_rows[10'd589]=16'h0100;
        glyph_rows[10'd590]=16'h0100;
        // Glyph 37: 通
        glyph_rows[10'd592]=16'h27f8;
        glyph_rows[10'd593]=16'h3018;
        glyph_rows[10'd594]=16'h10e0;
        glyph_rows[10'd595]=16'h0060;
        glyph_rows[10'd596]=16'h03fc;
        glyph_rows[10'd597]=16'h7244;
        glyph_rows[10'd598]=16'h13fc;
        glyph_rows[10'd599]=16'h1244;
        glyph_rows[10'd600]=16'h13fc;
        glyph_rows[10'd601]=16'h1244;
        glyph_rows[10'd602]=16'h1244;
        glyph_rows[10'd603]=16'h1048;
        glyph_rows[10'd604]=16'h3c00;
        glyph_rows[10'd605]=16'h43fe;
        // Glyph 38: 自
        glyph_rows[10'd609]=16'h0300;
        glyph_rows[10'd610]=16'h0200;
        glyph_rows[10'd611]=16'h1ff8;
        glyph_rows[10'd612]=16'h1008;
        glyph_rows[10'd613]=16'h1008;
        glyph_rows[10'd614]=16'h1ff8;
        glyph_rows[10'd615]=16'h1008;
        glyph_rows[10'd616]=16'h1008;
        glyph_rows[10'd617]=16'h1ff8;
        glyph_rows[10'd618]=16'h1008;
        glyph_rows[10'd619]=16'h1008;
        glyph_rows[10'd620]=16'h1ff8;
        glyph_rows[10'd621]=16'h1008;
        glyph_rows[10'd622]=16'h1008;
        // Glyph 39: 动
        glyph_rows[10'd625]=16'h0020;
        glyph_rows[10'd626]=16'h3f20;
        glyph_rows[10'd627]=16'h0020;
        glyph_rows[10'd628]=16'h00fe;
        glyph_rows[10'd629]=16'h0026;
        glyph_rows[10'd630]=16'h7f24;
        glyph_rows[10'd631]=16'h0824;
        glyph_rows[10'd632]=16'h1024;
        glyph_rows[10'd633]=16'h1424;
        glyph_rows[10'd634]=16'h2244;
        glyph_rows[10'd635]=16'h2244;
        glyph_rows[10'd636]=16'h7bc4;
        glyph_rows[10'd637]=16'h0184;
        glyph_rows[10'd638]=16'h0118;
        // Glyph 40: 曝
        glyph_rows[10'd641]=16'h03fc;
        glyph_rows[10'd642]=16'h7a04;
        glyph_rows[10'd643]=16'h4bfc;
        glyph_rows[10'd644]=16'h4a04;
        glyph_rows[10'd645]=16'h4bfc;
        glyph_rows[10'd646]=16'h7890;
        glyph_rows[10'd647]=16'h4bfc;
        glyph_rows[10'd648]=16'h4890;
        glyph_rows[10'd649]=16'h4ffe;
        glyph_rows[10'd650]=16'h4948;
        glyph_rows[10'd651]=16'h7a5e;
        glyph_rows[10'd652]=16'h48f0;
        glyph_rows[10'd653]=16'h424c;
        glyph_rows[10'd654]=16'h00c0;
        // Glyph 41: 光
        glyph_rows[10'd656]=16'h0080;
        glyph_rows[10'd657]=16'h008c;
        glyph_rows[10'd658]=16'h1898;
        glyph_rows[10'd659]=16'h04b0;
        glyph_rows[10'd660]=16'h0080;
        glyph_rows[10'd661]=16'h7ffe;
        glyph_rows[10'd662]=16'h0240;
        glyph_rows[10'd663]=16'h0240;
        glyph_rows[10'd664]=16'h0240;
        glyph_rows[10'd665]=16'h0640;
        glyph_rows[10'd666]=16'h0440;
        glyph_rows[10'd667]=16'h0842;
        glyph_rows[10'd668]=16'h3842;
        glyph_rows[10'd669]=16'h607c;
        // Glyph 42: 颜
        glyph_rows[10'd672]=16'h0800;
        glyph_rows[10'd673]=16'h08fe;
        glyph_rows[10'd674]=16'h3e10;
        glyph_rows[10'd675]=16'h1210;
        glyph_rows[10'd676]=16'h127c;
        glyph_rows[10'd677]=16'h3f44;
        glyph_rows[10'd678]=16'h2254;
        glyph_rows[10'd679]=16'h2c54;
        glyph_rows[10'd680]=16'h3254;
        glyph_rows[10'd681]=16'h2654;
        glyph_rows[10'd682]=16'h2854;
        glyph_rows[10'd683]=16'h2320;
        glyph_rows[10'd684]=16'h662c;
        glyph_rows[10'd685]=16'h58c6;
        glyph_rows[10'd686]=16'h4080;
        // Glyph 43: 形
        glyph_rows[10'd689]=16'h0004;
        glyph_rows[10'd690]=16'h7f88;
        glyph_rows[10'd691]=16'h1210;
        glyph_rows[10'd692]=16'h1230;
        glyph_rows[10'd693]=16'h1260;
        glyph_rows[10'd694]=16'h1204;
        glyph_rows[10'd695]=16'h7fcc;
        glyph_rows[10'd696]=16'h1210;
        glyph_rows[10'd697]=16'h1260;
        glyph_rows[10'd698]=16'h1202;
        glyph_rows[10'd699]=16'h1204;
        glyph_rows[10'd700]=16'h2218;
        glyph_rows[10'd701]=16'h2230;
        glyph_rows[10'd702]=16'h42c0;
        // Glyph 44: 状
        glyph_rows[10'd705]=16'h0c20;
        glyph_rows[10'd706]=16'h0828;
        glyph_rows[10'd707]=16'h0824;
        glyph_rows[10'd708]=16'h6820;
        glyph_rows[10'd709]=16'h3bfe;
        glyph_rows[10'd710]=16'h0820;
        glyph_rows[10'd711]=16'h0870;
        glyph_rows[10'd712]=16'h1850;
        glyph_rows[10'd713]=16'h3850;
        glyph_rows[10'd714]=16'h28c8;
        glyph_rows[10'd715]=16'h4888;
        glyph_rows[10'd716]=16'h0904;
        glyph_rows[10'd717]=16'h0f06;
        glyph_rows[10'd718]=16'h0e00;
        // Glyph 45: 识
        glyph_rows[10'd721]=16'h21fc;
        glyph_rows[10'd722]=16'h1904;
        glyph_rows[10'd723]=16'h0904;
        glyph_rows[10'd724]=16'h0104;
        glyph_rows[10'd725]=16'h7104;
        glyph_rows[10'd726]=16'h1104;
        glyph_rows[10'd727]=16'h11fc;
        glyph_rows[10'd728]=16'h1000;
        glyph_rows[10'd729]=16'h1000;
        glyph_rows[10'd730]=16'h14c8;
        glyph_rows[10'd731]=16'h1c8c;
        glyph_rows[10'd732]=16'h1906;
        glyph_rows[10'd733]=16'h1202;
        glyph_rows[10'd734]=16'h0600;
        // Glyph 46: 别
        glyph_rows[10'd737]=16'h0002;
        glyph_rows[10'd738]=16'h3f02;
        glyph_rows[10'd739]=16'h2082;
        glyph_rows[10'd740]=16'h2092;
        glyph_rows[10'd741]=16'h3f92;
        glyph_rows[10'd742]=16'h0012;
        glyph_rows[10'd743]=16'h0412;
        glyph_rows[10'd744]=16'h3f92;
        glyph_rows[10'd745]=16'h0892;
        glyph_rows[10'd746]=16'h0882;
        glyph_rows[10'd747]=16'h0882;
        glyph_rows[10'd748]=16'h1982;
        glyph_rows[10'd749]=16'h3306;
        glyph_rows[10'd750]=16'h600c;
        // Glyph 47: 运
        glyph_rows[10'd752]=16'h23fc;
        glyph_rows[10'd753]=16'h1000;
        glyph_rows[10'd754]=16'h0800;
        glyph_rows[10'd756]=16'h07fe;
        glyph_rows[10'd757]=16'h70c0;
        glyph_rows[10'd758]=16'h1080;
        glyph_rows[10'd759]=16'h1110;
        glyph_rows[10'd760]=16'h1108;
        glyph_rows[10'd761]=16'h13f8;
        glyph_rows[10'd762]=16'h1704;
        glyph_rows[10'd763]=16'h1000;
        glyph_rows[10'd764]=16'h7c00;
        glyph_rows[10'd765]=16'h43fe;
        // Glyph 48: 警
        glyph_rows[10'd768]=16'h0a20;
        glyph_rows[10'd769]=16'h7fbe;
        glyph_rows[10'd770]=16'h0248;
        glyph_rows[10'd771]=16'h3f28;
        glyph_rows[10'd772]=16'h6510;
        glyph_rows[10'd773]=16'h1d3c;
        glyph_rows[10'd774]=16'h0300;
        glyph_rows[10'd775]=16'h3ffe;
        glyph_rows[10'd777]=16'h1ff8;
        glyph_rows[10'd779]=16'h1ff8;
        glyph_rows[10'd780]=16'h1008;
        glyph_rows[10'd781]=16'h1ff8;
        glyph_rows[10'd782]=16'h1008;
        // Glyph 49: 戒
        glyph_rows[10'd785]=16'h0040;
        glyph_rows[10'd786]=16'h0058;
        glyph_rows[10'd787]=16'h0048;
        glyph_rows[10'd788]=16'h7ffe;
        glyph_rows[10'd789]=16'h1040;
        glyph_rows[10'd790]=16'h1240;
        glyph_rows[10'd791]=16'h1248;
        glyph_rows[10'd792]=16'h7fa8;
        glyph_rows[10'd793]=16'h1230;
        glyph_rows[10'd794]=16'h1230;
        glyph_rows[10'd795]=16'h1230;
        glyph_rows[10'd796]=16'h3252;
        glyph_rows[10'd797]=16'h228e;
        glyph_rows[10'd798]=16'h4104;
        // Glyph 50: 照
        glyph_rows[10'd801]=16'h3dfc;
        glyph_rows[10'd802]=16'h2464;
        glyph_rows[10'd803]=16'h2444;
        glyph_rows[10'd804]=16'h24c4;
        glyph_rows[10'd805]=16'h3f88;
        glyph_rows[10'd806]=16'h24fc;
        glyph_rows[10'd807]=16'h2484;
        glyph_rows[10'd808]=16'h2484;
        glyph_rows[10'd809]=16'h3efc;
        glyph_rows[10'd811]=16'h1248;
        glyph_rows[10'd812]=16'h1244;
        glyph_rows[10'd813]=16'h2226;
        glyph_rows[10'd814]=16'h6000;
        // Glyph 51: 片
        glyph_rows[10'd817]=16'h0040;
        glyph_rows[10'd818]=16'h0840;
        glyph_rows[10'd819]=16'h0840;
        glyph_rows[10'd820]=16'h0840;
        glyph_rows[10'd821]=16'h0ffc;
        glyph_rows[10'd822]=16'h0800;
        glyph_rows[10'd823]=16'h0800;
        glyph_rows[10'd824]=16'h0fe0;
        glyph_rows[10'd825]=16'h0820;
        glyph_rows[10'd826]=16'h0820;
        glyph_rows[10'd827]=16'h1020;
        glyph_rows[10'd828]=16'h1020;
        glyph_rows[10'd829]=16'h2020;
        glyph_rows[10'd830]=16'h2020;
        // Glyph 52: 档
        glyph_rows[10'd832]=16'h1820;
        glyph_rows[10'd833]=16'h1a24;
        glyph_rows[10'd834]=16'h1b24;
        glyph_rows[10'd835]=16'h1928;
        glyph_rows[10'd836]=16'h7ca8;
        glyph_rows[10'd837]=16'h1820;
        glyph_rows[10'd838]=16'h1bfe;
        glyph_rows[10'd839]=16'h3c02;
        glyph_rows[10'd840]=16'h3c02;
        glyph_rows[10'd841]=16'h7802;
        glyph_rows[10'd842]=16'h59fe;
        glyph_rows[10'd843]=16'h1802;
        glyph_rows[10'd844]=16'h1802;
        glyph_rows[10'd845]=16'h1802;
        glyph_rows[10'd846]=16'h1bfe;
        glyph_rows[10'd847]=16'h1802;
        // Glyph 53: 案
        glyph_rows[10'd849]=16'h0100;
        glyph_rows[10'd850]=16'h3ffc;
        glyph_rows[10'd851]=16'h2004;
        glyph_rows[10'd852]=16'h0300;
        glyph_rows[10'd853]=16'h7ffe;
        glyph_rows[10'd854]=16'h0460;
        glyph_rows[10'd855]=16'h07c0;
        glyph_rows[10'd856]=16'h03f0;
        glyph_rows[10'd857]=16'h3c8c;
        glyph_rows[10'd858]=16'h3ffe;
        glyph_rows[10'd859]=16'h03c0;
        glyph_rows[10'd860]=16'h04b0;
        glyph_rows[10'd861]=16'h389c;
        glyph_rows[10'd862]=16'h2080;
        // Glyph 54: 数
        glyph_rows[10'd864]=16'h0430;
        glyph_rows[10'd865]=16'h2520;
        glyph_rows[10'd866]=16'h0620;
        glyph_rows[10'd867]=16'h7fa0;
        glyph_rows[10'd868]=16'h0c7e;
        glyph_rows[10'd869]=16'h1f44;
        glyph_rows[10'd870]=16'h6508;
        glyph_rows[10'd871]=16'h0068;
        glyph_rows[10'd872]=16'h0828;
        glyph_rows[10'd873]=16'h7f38;
        glyph_rows[10'd874]=16'h1110;
        glyph_rows[10'd875]=16'h3238;
        glyph_rows[10'd876]=16'h0e2c;
        glyph_rows[10'd877]=16'h19c6;
        glyph_rows[10'd878]=16'h2082;
        // Glyph 55: 字
        glyph_rows[10'd881]=16'h0100;
        glyph_rows[10'd882]=16'h0180;
        glyph_rows[10'd883]=16'h3ffe;
        glyph_rows[10'd884]=16'h2006;
        glyph_rows[10'd885]=16'h2006;
        glyph_rows[10'd886]=16'h1ff0;
        glyph_rows[10'd887]=16'h0040;
        glyph_rows[10'd888]=16'h0080;
        glyph_rows[10'd889]=16'h7ffe;
        glyph_rows[10'd890]=16'h0080;
        glyph_rows[10'd891]=16'h0080;
        glyph_rows[10'd892]=16'h0080;
        glyph_rows[10'd893]=16'h0180;
        glyph_rows[10'd894]=16'h0700;
        // Glyph 56: 增
        glyph_rows[10'd896]=16'h1008;
        glyph_rows[10'd897]=16'h1098;
        glyph_rows[10'd898]=16'h13fe;
        glyph_rows[10'd899]=16'h1222;
        glyph_rows[10'd900]=16'h7aaa;
        glyph_rows[10'd901]=16'h12a2;
        glyph_rows[10'd902]=16'h13fe;
        glyph_rows[10'd903]=16'h1000;
        glyph_rows[10'd904]=16'h11fc;
        glyph_rows[10'd905]=16'h1104;
        glyph_rows[10'd906]=16'h1dfc;
        glyph_rows[10'd907]=16'h7104;
        glyph_rows[10'd908]=16'h0104;
        glyph_rows[10'd909]=16'h01fc;
        glyph_rows[10'd910]=16'h0104;
        // Glyph 57: 益
        glyph_rows[10'd912]=16'h0020;
        glyph_rows[10'd913]=16'h0820;
        glyph_rows[10'd914]=16'h0460;
        glyph_rows[10'd915]=16'h0040;
        glyph_rows[10'd916]=16'h3ffc;
        glyph_rows[10'd918]=16'h0460;
        glyph_rows[10'd919]=16'h0818;
        glyph_rows[10'd920]=16'h300c;
        glyph_rows[10'd921]=16'h3ff8;
        glyph_rows[10'd922]=16'h1248;
        glyph_rows[10'd923]=16'h1248;
        glyph_rows[10'd924]=16'h1248;
        glyph_rows[10'd925]=16'h1248;
        glyph_rows[10'd926]=16'h7ffe;
        // Glyph 58: 相
        glyph_rows[10'd929]=16'h0800;
        glyph_rows[10'd930]=16'h08fc;
        glyph_rows[10'd931]=16'h0884;
        glyph_rows[10'd932]=16'h7e84;
        glyph_rows[10'd933]=16'h18fc;
        glyph_rows[10'd934]=16'h1884;
        glyph_rows[10'd935]=16'h3c84;
        glyph_rows[10'd936]=16'h2a84;
        glyph_rows[10'd937]=16'h68fc;
        glyph_rows[10'd938]=16'h4884;
        glyph_rows[10'd939]=16'h0884;
        glyph_rows[10'd940]=16'h0884;
        glyph_rows[10'd941]=16'h08fc;
        glyph_rows[10'd942]=16'h0880;
        // Glyph 59: 机
        glyph_rows[10'd944]=16'h1800;
        glyph_rows[10'd945]=16'h18f8;
        glyph_rows[10'd946]=16'h1888;
        glyph_rows[10'd947]=16'h7e88;
        glyph_rows[10'd948]=16'h1888;
        glyph_rows[10'd949]=16'h1888;
        glyph_rows[10'd950]=16'h3c88;
        glyph_rows[10'd951]=16'h3888;
        glyph_rows[10'd952]=16'h5888;
        glyph_rows[10'd953]=16'h5988;
        glyph_rows[10'd954]=16'h1908;
        glyph_rows[10'd955]=16'h1908;
        glyph_rows[10'd956]=16'h1a0a;
        glyph_rows[10'd957]=16'h1c0e;
        // Glyph 60: 饱
        glyph_rows[10'd960]=16'h0080;
        glyph_rows[10'd961]=16'h1080;
        glyph_rows[10'd962]=16'h30fc;
        glyph_rows[10'd963]=16'h3d04;
        glyph_rows[10'd964]=16'h2704;
        glyph_rows[10'd965]=16'h46f4;
        glyph_rows[10'd966]=16'h5094;
        glyph_rows[10'd967]=16'h1094;
        glyph_rows[10'd968]=16'h1094;
        glyph_rows[10'd969]=16'h10fc;
        glyph_rows[10'd970]=16'h1088;
        glyph_rows[10'd971]=16'h1480;
        glyph_rows[10'd972]=16'h1c82;
        glyph_rows[10'd973]=16'h1882;
        glyph_rows[10'd974]=16'h10fc;
        // Glyph 61: 和
        glyph_rows[10'd977]=16'h0300;
        glyph_rows[10'd978]=16'h3c00;
        glyph_rows[10'd979]=16'h047e;
        glyph_rows[10'd980]=16'h0442;
        glyph_rows[10'd981]=16'h7fc2;
        glyph_rows[10'd982]=16'h0c42;
        glyph_rows[10'd983]=16'h0e42;
        glyph_rows[10'd984]=16'h1742;
        glyph_rows[10'd985]=16'h3442;
        glyph_rows[10'd986]=16'h2442;
        glyph_rows[10'd987]=16'h047e;
        glyph_rows[10'd988]=16'h0446;
        glyph_rows[10'd989]=16'h0400;
        glyph_rows[10'd990]=16'h0400;
        // 62: 主; previously blank slot, same ERAM.
        glyph_rows[10'd993]=16'h0200;
        glyph_rows[10'd994]=16'h0100;
        glyph_rows[10'd996]=16'h7ffc;
        glyph_rows[10'd997]=16'h0100;
        glyph_rows[10'd998]=16'h0100;
        glyph_rows[10'd999]=16'h0100;
        glyph_rows[10'd1000]=16'h0100;
        glyph_rows[10'd1001]=16'h3ff8;
        glyph_rows[10'd1002]=16'h0100;
        glyph_rows[10'd1003]=16'h0100;
        glyph_rows[10'd1004]=16'h0100;
        glyph_rows[10'd1005]=16'h0100;
        glyph_rows[10'd1006]=16'h0100;
        glyph_rows[10'd1007]=16'hfffe;
    end
    always @(posedge clk)bits<=glyph_rows[{glyph,row}];
endmodule


// Shared 16x16 UI font: tracking at 0..511, range at 512..767.
// Assist title uses rows 768..831; rows 832..1023 remain blank. One 1024x16 ERAM read
// replaces the two LUT-ROM reads without adding a video pipeline stage.
module hud_track_range_font_sync(input clk,input [9:0] address,output reg [15:0] bits);
    (* rom_style="bram", ram_style="bram" *) reg [15:0] rows[0:1023];
    integer i;
    initial begin
        for(i=0;i<1024;i=i+1)rows[i]=0;
        // Tracking glyph 0: 静
        rows[10'd1]=16'h0840;
        rows[10'd2]=16'h7e78;
        rows[10'd3]=16'h0888;
        rows[10'd4]=16'h3e90;
        rows[10'd5]=16'h09fc;
        rows[10'd6]=16'h7e24;
        rows[10'd7]=16'h3e24;
        rows[10'd8]=16'h23fe;
        rows[10'd9]=16'h3e24;
        rows[10'd10]=16'h22fc;
        rows[10'd11]=16'h3e24;
        rows[10'd12]=16'h2220;
        rows[10'd13]=16'h2220;
        rows[10'd14]=16'h2460;
        // Tracking glyph 1: 态
        rows[10'd17]=16'h0100;
        rows[10'd18]=16'h0100;
        rows[10'd19]=16'h7ffe;
        rows[10'd20]=16'h0240;
        rows[10'd21]=16'h0260;
        rows[10'd22]=16'h0430;
        rows[10'd23]=16'h1998;
        rows[10'd24]=16'h7006;
        rows[10'd26]=16'h0180;
        rows[10'd27]=16'h340c;
        rows[10'd28]=16'h2406;
        rows[10'd29]=16'h4430;
        rows[10'd30]=16'h07e0;
        // Tracking glyph 2: 跟
        rows[10'd33]=16'h3efc;
        rows[10'd34]=16'h2284;
        rows[10'd35]=16'h2284;
        rows[10'd36]=16'h22fc;
        rows[10'd37]=16'h3e84;
        rows[10'd38]=16'h0884;
        rows[10'd39]=16'h28fc;
        rows[10'd40]=16'h2ea0;
        rows[10'd41]=16'h28b4;
        rows[10'd42]=16'h2898;
        rows[10'd43]=16'h2898;
        rows[10'd44]=16'h2ea8;
        rows[10'd45]=16'h70c6;
        rows[10'd46]=16'h0082;
        // Tracking glyph 3: 踪
        rows[10'd48]=16'h0020;
        rows[10'd49]=16'h3c30;
        rows[10'd50]=16'h2400;
        rows[10'd51]=16'h25fe;
        rows[10'd52]=16'h2502;
        rows[10'd53]=16'h3dfe;
        rows[10'd54]=16'h0800;
        rows[10'd55]=16'h2800;
        rows[10'd56]=16'h2ffe;
        rows[10'd57]=16'h2810;
        rows[10'd58]=16'h2810;
        rows[10'd59]=16'h2c9c;
        rows[10'd60]=16'h3d94;
        rows[10'd61]=16'h7112;
        rows[10'd62]=16'h0232;
        rows[10'd63]=16'h0060;
        // Tracking glyph 4: 警
        rows[10'd64]=16'h0a20;
        rows[10'd65]=16'h7fbe;
        rows[10'd66]=16'h0248;
        rows[10'd67]=16'h3f28;
        rows[10'd68]=16'h6510;
        rows[10'd69]=16'h1d3c;
        rows[10'd70]=16'h0300;
        rows[10'd71]=16'h3ffe;
        rows[10'd73]=16'h1ff8;
        rows[10'd75]=16'h1ff8;
        rows[10'd76]=16'h1008;
        rows[10'd77]=16'h1ff8;
        rows[10'd78]=16'h1008;
        // Tracking glyph 5: 戒
        rows[10'd81]=16'h0040;
        rows[10'd82]=16'h0058;
        rows[10'd83]=16'h0048;
        rows[10'd84]=16'h7ffe;
        rows[10'd85]=16'h1040;
        rows[10'd86]=16'h1240;
        rows[10'd87]=16'h1248;
        rows[10'd88]=16'h7fa8;
        rows[10'd89]=16'h1230;
        rows[10'd90]=16'h1230;
        rows[10'd91]=16'h1230;
        rows[10'd92]=16'h3252;
        rows[10'd93]=16'h228e;
        rows[10'd94]=16'h4104;
        // Tracking glyph 6: 目
        rows[10'd97]=16'h1ff8;
        rows[10'd98]=16'h1008;
        rows[10'd99]=16'h1008;
        rows[10'd100]=16'h1008;
        rows[10'd101]=16'h1ff8;
        rows[10'd102]=16'h1008;
        rows[10'd103]=16'h1008;
        rows[10'd104]=16'h1008;
        rows[10'd105]=16'h1ff8;
        rows[10'd106]=16'h1008;
        rows[10'd107]=16'h1008;
        rows[10'd108]=16'h1ff8;
        rows[10'd109]=16'h1008;
        rows[10'd110]=16'h1000;
        // Tracking glyph 7: 标
        rows[10'd113]=16'h1800;
        rows[10'd114]=16'h19fc;
        rows[10'd115]=16'h1800;
        rows[10'd116]=16'h7e00;
        rows[10'd117]=16'h1800;
        rows[10'd118]=16'h1bfe;
        rows[10'd119]=16'h3c20;
        rows[10'd120]=16'h3820;
        rows[10'd121]=16'h78a8;
        rows[10'd122]=16'h5924;
        rows[10'd123]=16'h1b22;
        rows[10'd124]=16'h1a22;
        rows[10'd125]=16'h1820;
        rows[10'd126]=16'h18e0;
        // Tracking glyph 8: 红
        rows[10'd128]=16'h0800;
        rows[10'd129]=16'h11fc;
        rows[10'd130]=16'h1020;
        rows[10'd131]=16'h2620;
        rows[10'd132]=16'h2420;
        rows[10'd133]=16'h7c20;
        rows[10'd134]=16'h0820;
        rows[10'd135]=16'h1020;
        rows[10'd136]=16'h3220;
        rows[10'd137]=16'h7c20;
        rows[10'd138]=16'h0020;
        rows[10'd139]=16'h0220;
        rows[10'd140]=16'h7c20;
        rows[10'd141]=16'h63fe;
        // Tracking glyph 9: 圆
        rows[10'd145]=16'h3ffc;
        rows[10'd146]=16'h2004;
        rows[10'd147]=16'h27e4;
        rows[10'd148]=16'h2424;
        rows[10'd149]=16'h27e4;
        rows[10'd150]=16'h2004;
        rows[10'd151]=16'h27e4;
        rows[10'd152]=16'h2424;
        rows[10'd153]=16'h2524;
        rows[10'd154]=16'h2524;
        rows[10'd155]=16'h2664;
        rows[10'd156]=16'h2c14;
        rows[10'd157]=16'h3ffc;
        rows[10'd158]=16'h2004;
        // Tracking glyph 10: 蓝
        rows[10'd160]=16'h0820;
        rows[10'd161]=16'h0820;
        rows[10'd162]=16'hfffe;
        rows[10'd163]=16'h0820;
        rows[10'd164]=16'h0480;
        rows[10'd165]=16'h2480;
        rows[10'd166]=16'h24fc;
        rows[10'd167]=16'h24a0;
        rows[10'd168]=16'h2510;
        rows[10'd170]=16'h3ff8;
        rows[10'd171]=16'h2448;
        rows[10'd172]=16'h2448;
        rows[10'd173]=16'h2448;
        rows[10'd174]=16'hfffe;
        // Tracking glyph 11: 矩
        rows[10'd176]=16'h2000;
        rows[10'd177]=16'h21fe;
        rows[10'd178]=16'h3d00;
        rows[10'd179]=16'h5100;
        rows[10'd180]=16'h9100;
        rows[10'd181]=16'h11fc;
        rows[10'd182]=16'h1104;
        rows[10'd183]=16'hff04;
        rows[10'd184]=16'h1104;
        rows[10'd185]=16'h1104;
        rows[10'd186]=16'h11fc;
        rows[10'd187]=16'h2900;
        rows[10'd188]=16'h2500;
        rows[10'd189]=16'h4500;
        rows[10'd190]=16'h41fe;
        rows[10'd191]=16'h8000;
        // Tracking glyph 12: 形
        rows[10'd193]=16'h7f84;
        rows[10'd194]=16'h1204;
        rows[10'd195]=16'h1208;
        rows[10'd196]=16'h1210;
        rows[10'd197]=16'h1222;
        rows[10'd198]=16'h1202;
        rows[10'd199]=16'hffc4;
        rows[10'd200]=16'h1208;
        rows[10'd201]=16'h1210;
        rows[10'd202]=16'h1222;
        rows[10'd203]=16'h1202;
        rows[10'd204]=16'h2204;
        rows[10'd205]=16'h2208;
        rows[10'd206]=16'h4210;
        rows[10'd207]=16'h8260;
        // Tracking glyph 13: 速
        rows[10'd208]=16'h0040;
        rows[10'd209]=16'h6040;
        rows[10'd210]=16'h37fc;
        rows[10'd211]=16'h1040;
        rows[10'd212]=16'h03fc;
        rows[10'd213]=16'h7244;
        rows[10'd214]=16'h1244;
        rows[10'd215]=16'h13fc;
        rows[10'd216]=16'h10e0;
        rows[10'd217]=16'h11f0;
        rows[10'd218]=16'h1348;
        rows[10'd219]=16'h1444;
        rows[10'd220]=16'h6c40;
        rows[10'd221]=16'h03fe;
        // Tracking glyph 14: 度
        rows[10'd224]=16'h0080;
        rows[10'd225]=16'h0040;
        rows[10'd226]=16'h1ffe;
        rows[10'd227]=16'h1110;
        rows[10'd228]=16'h1ffe;
        rows[10'd229]=16'h1110;
        rows[10'd230]=16'h1110;
        rows[10'd231]=16'h11f0;
        rows[10'd232]=16'h17f8;
        rows[10'd233]=16'h1110;
        rows[10'd234]=16'h11a0;
        rows[10'd235]=16'h20e0;
        rows[10'd236]=16'h20e0;
        rows[10'd237]=16'h673e;
        rows[10'd238]=16'h4c06;
        // Tracking glyph 15: 稳
        rows[10'd241]=16'h1c80;
        rows[10'd242]=16'h78f8;
        rows[10'd243]=16'h1118;
        rows[10'd244]=16'h1210;
        rows[10'd245]=16'h7dfc;
        rows[10'd246]=16'h1004;
        rows[10'd247]=16'h19fc;
        rows[10'd248]=16'h3c04;
        rows[10'd249]=16'h31fc;
        rows[10'd250]=16'h5020;
        rows[10'd251]=16'h12b4;
        rows[10'd252]=16'h1282;
        rows[10'd253]=16'h128a;
        rows[10'd254]=16'h10f0;
        // Tracking glyph 16: 定
        rows[10'd256]=16'h0100;
        rows[10'd257]=16'h0080;
        rows[10'd258]=16'h3ffc;
        rows[10'd259]=16'h2004;
        rows[10'd260]=16'h2004;
        rows[10'd262]=16'h1ff8;
        rows[10'd263]=16'h0080;
        rows[10'd264]=16'h0880;
        rows[10'd265]=16'h08f8;
        rows[10'd266]=16'h0880;
        rows[10'd267]=16'h1880;
        rows[10'd268]=16'h1c80;
        rows[10'd269]=16'h2780;
        rows[10'd270]=16'h41fe;
        // Tracking glyph 17: 正
        rows[10'd273]=16'h3ffc;
        rows[10'd274]=16'h0080;
        rows[10'd275]=16'h0080;
        rows[10'd276]=16'h0880;
        rows[10'd277]=16'h0880;
        rows[10'd278]=16'h08f8;
        rows[10'd279]=16'h0880;
        rows[10'd280]=16'h0880;
        rows[10'd281]=16'h0880;
        rows[10'd282]=16'h0880;
        rows[10'd283]=16'h0880;
        rows[10'd284]=16'h7ffe;
        // Tracking glyph 18: 常
        rows[10'd289]=16'h0190;
        rows[10'd290]=16'h0990;
        rows[10'd291]=16'h05a0;
        rows[10'd292]=16'h3ffc;
        rows[10'd293]=16'h2004;
        rows[10'd294]=16'h2ff4;
        rows[10'd295]=16'h0810;
        rows[10'd296]=16'h0ff0;
        rows[10'd297]=16'h0080;
        rows[10'd298]=16'h1ff8;
        rows[10'd299]=16'h1088;
        rows[10'd300]=16'h1088;
        rows[10'd301]=16'h1088;
        rows[10'd302]=16'h1098;
        // Tracking glyph 19: 快
        rows[10'd304]=16'h1060;
        rows[10'd305]=16'h1040;
        rows[10'd306]=16'h1040;
        rows[10'd307]=16'h15fc;
        rows[10'd308]=16'h7444;
        rows[10'd309]=16'h5444;
        rows[10'd310]=16'h5044;
        rows[10'd311]=16'h5044;
        rows[10'd312]=16'h13fe;
        rows[10'd313]=16'h1060;
        rows[10'd314]=16'h10f0;
        rows[10'd315]=16'h1090;
        rows[10'd316]=16'h1108;
        rows[10'd317]=16'h1606;
        rows[10'd318]=16'h1402;
        // Tracking glyph 20: 区
        rows[10'd321]=16'h3ffc;
        rows[10'd322]=16'h2000;
        rows[10'd323]=16'h2010;
        rows[10'd324]=16'h2420;
        rows[10'd325]=16'h2220;
        rows[10'd326]=16'h21c0;
        rows[10'd327]=16'h20c0;
        rows[10'd328]=16'h21c0;
        rows[10'd329]=16'h2320;
        rows[10'd330]=16'h2610;
        rows[10'd331]=16'h2c08;
        rows[10'd332]=16'h2000;
        rows[10'd333]=16'h3ffe;
        // Tracking glyph 21: 域
        rows[10'd337]=16'h1028;
        rows[10'd338]=16'h102c;
        rows[10'd339]=16'h1024;
        rows[10'd340]=16'h17fe;
        rows[10'd341]=16'h7c20;
        rows[10'd342]=16'h13a4;
        rows[10'd343]=16'h1264;
        rows[10'd344]=16'h126c;
        rows[10'd345]=16'h13d8;
        rows[10'd346]=16'h1018;
        rows[10'd347]=16'h3850;
        rows[10'd348]=16'h4fb8;
        rows[10'd349]=16'h006e;
        rows[10'd350]=16'h00c6;
        // Tracking glyph 22: 内
        rows[10'd353]=16'h0180;
        rows[10'd354]=16'h0180;
        rows[10'd355]=16'h0180;
        rows[10'd356]=16'h3ffc;
        rows[10'd357]=16'h2104;
        rows[10'd358]=16'h2104;
        rows[10'd359]=16'h2184;
        rows[10'd360]=16'h21c4;
        rows[10'd361]=16'h2264;
        rows[10'd362]=16'h2624;
        rows[10'd363]=16'h2c34;
        rows[10'd364]=16'h2004;
        rows[10'd365]=16'h200c;
        rows[10'd366]=16'h2038;
        // Tracking glyph 23: 移
        rows[10'd369]=16'h0e20;
        rows[10'd370]=16'h787c;
        rows[10'd371]=16'h0988;
        rows[10'd372]=16'h0958;
        rows[10'd373]=16'h7e30;
        rows[10'd374]=16'h1860;
        rows[10'd375]=16'h1990;
        rows[10'd376]=16'h3c3e;
        rows[10'd377]=16'h2842;
        rows[10'd378]=16'h4884;
        rows[10'd379]=16'h4938;
        rows[10'd380]=16'h0830;
        rows[10'd381]=16'h08e0;
        rows[10'd382]=16'h0b00;
        // Tracking glyph 24: 出
        rows[10'd385]=16'h0100;
        rows[10'd386]=16'h0108;
        rows[10'd387]=16'h1108;
        rows[10'd388]=16'h1108;
        rows[10'd389]=16'h1108;
        rows[10'd390]=16'h1108;
        rows[10'd391]=16'h1ff8;
        rows[10'd392]=16'h0100;
        rows[10'd393]=16'h2104;
        rows[10'd394]=16'h2104;
        rows[10'd395]=16'h2104;
        rows[10'd396]=16'h2104;
        rows[10'd397]=16'h3ffc;
        rows[10'd398]=16'h0004;
        // Tracking glyph 25: 等
        rows[10'd400]=16'h1860;
        rows[10'd401]=16'h1f7e;
        rows[10'd402]=16'h2490;
        rows[10'd403]=16'h6418;
        rows[10'd404]=16'h0180;
        rows[10'd405]=16'h1ff8;
        rows[10'd406]=16'h0100;
        rows[10'd407]=16'h7ffe;
        rows[10'd408]=16'h0030;
        rows[10'd409]=16'h3ffc;
        rows[10'd410]=16'h0420;
        rows[10'd411]=16'h0420;
        rows[10'd412]=16'h0220;
        rows[10'd413]=16'h0020;
        rows[10'd414]=16'h0060;
        // Tracking glyph 26: 待
        rows[10'd416]=16'h0820;
        rows[10'd417]=16'h1820;
        rows[10'd418]=16'h31fc;
        rows[10'd419]=16'h6020;
        rows[10'd420]=16'h0820;
        rows[10'd421]=16'h0bfe;
        rows[10'd422]=16'h1000;
        rows[10'd423]=16'h3008;
        rows[10'd424]=16'h73fe;
        rows[10'd425]=16'h1008;
        rows[10'd426]=16'h1088;
        rows[10'd427]=16'h10c8;
        rows[10'd428]=16'h1008;
        rows[10'd429]=16'h1008;
        rows[10'd430]=16'h1038;
        // Tracking glyph 27: 回
        rows[10'd433]=16'h3ffc;
        rows[10'd434]=16'h2004;
        rows[10'd435]=16'h2004;
        rows[10'd436]=16'h27e4;
        rows[10'd437]=16'h2424;
        rows[10'd438]=16'h2424;
        rows[10'd439]=16'h2424;
        rows[10'd440]=16'h27e4;
        rows[10'd441]=16'h2004;
        rows[10'd442]=16'h2004;
        rows[10'd443]=16'h2004;
        rows[10'd444]=16'h3ffc;
        rows[10'd445]=16'h2004;
        // Tracking glyph 28: 协
        rows[10'd449]=16'h20c0;
        rows[10'd450]=16'h20c0;
        rows[10'd451]=16'h2040;
        rows[10'd452]=16'h23c8;
        rows[10'd453]=16'h7848;
        rows[10'd454]=16'h2088;
        rows[10'd455]=16'h2288;
        rows[10'd456]=16'h268e;
        rows[10'd457]=16'h248a;
        rows[10'd458]=16'h218a;
        rows[10'd459]=16'h2118;
        rows[10'd460]=16'h2210;
        rows[10'd461]=16'h2630;
        rows[10'd462]=16'h2420;
        // Tracking glyph 29: 同
        rows[10'd465]=16'h3ffc;
        rows[10'd466]=16'h2004;
        rows[10'd467]=16'h2004;
        rows[10'd468]=16'h2ff4;
        rows[10'd469]=16'h2004;
        rows[10'd470]=16'h2004;
        rows[10'd471]=16'h27e4;
        rows[10'd472]=16'h2424;
        rows[10'd473]=16'h2424;
        rows[10'd474]=16'h27e4;
        rows[10'd475]=16'h2004;
        rows[10'd476]=16'h2004;
        rows[10'd477]=16'h2004;
        rows[10'd478]=16'h201c;
        // Range glyph 0: 视
        rows[10'd512]=16'h21fc;
        rows[10'd513]=16'h1904;
        rows[10'd514]=16'h0904;
        rows[10'd515]=16'h7d24;
        rows[10'd516]=16'h0524;
        rows[10'd517]=16'h0924;
        rows[10'd518]=16'h1924;
        rows[10'd519]=16'h3d24;
        rows[10'd520]=16'h5770;
        rows[10'd521]=16'h1070;
        rows[10'd522]=16'h10d0;
        rows[10'd523]=16'h1090;
        rows[10'd524]=16'h1312;
        rows[10'd525]=16'h161e;
        // Range glyph 1: 距
        rows[10'd529]=16'h3efe;
        rows[10'd530]=16'h2280;
        rows[10'd531]=16'h2280;
        rows[10'd532]=16'h2280;
        rows[10'd533]=16'h7efc;
        rows[10'd534]=16'h0884;
        rows[10'd535]=16'h0884;
        rows[10'd536]=16'h6e84;
        rows[10'd537]=16'h4884;
        rows[10'd538]=16'h48fc;
        rows[10'd539]=16'h4880;
        rows[10'd540]=16'h4e80;
        rows[10'd541]=16'h7880;
        rows[10'd542]=16'h40fe;
        // Range glyph 2: 保
        rows[10'd545]=16'h0800;
        rows[10'd546]=16'h09fc;
        rows[10'd547]=16'h1904;
        rows[10'd548]=16'h1104;
        rows[10'd549]=16'h31fc;
        rows[10'd550]=16'h7040;
        rows[10'd551]=16'h5040;
        rows[10'd552]=16'h17fe;
        rows[10'd553]=16'h10e0;
        rows[10'd554]=16'h10f0;
        rows[10'd555]=16'h1148;
        rows[10'd556]=16'h1246;
        rows[10'd557]=16'h1442;
        rows[10'd558]=16'h1060;
        // Range glyph 3: 持
        rows[10'd560]=16'h1020;
        rows[10'd561]=16'h1020;
        rows[10'd562]=16'h11fc;
        rows[10'd563]=16'h1020;
        rows[10'd564]=16'h7c20;
        rows[10'd565]=16'h13fe;
        rows[10'd566]=16'h1008;
        rows[10'd567]=16'h1c08;
        rows[10'd568]=16'h39fe;
        rows[10'd569]=16'h7008;
        rows[10'd570]=16'h1088;
        rows[10'd571]=16'h10c8;
        rows[10'd572]=16'h1008;
        rows[10'd573]=16'h1008;
        rows[10'd574]=16'h3018;
        // Range glyph 4: 设
        rows[10'd577]=16'h21f0;
        rows[10'd578]=16'h1110;
        rows[10'd579]=16'h0910;
        rows[10'd580]=16'h0110;
        rows[10'd581]=16'h020e;
        rows[10'd582]=16'h7600;
        rows[10'd583]=16'h13f8;
        rows[10'd584]=16'h1118;
        rows[10'd585]=16'h1090;
        rows[10'd586]=16'h10f0;
        rows[10'd587]=16'h1060;
        rows[10'd588]=16'h1cf0;
        rows[10'd589]=16'h1b8e;
        rows[10'd590]=16'h0602;
        // Range glyph 5: 定
        rows[10'd592]=16'h0100;
        rows[10'd593]=16'h0080;
        rows[10'd594]=16'h3ffc;
        rows[10'd595]=16'h2004;
        rows[10'd596]=16'h2004;
        rows[10'd598]=16'h1ff8;
        rows[10'd599]=16'h0080;
        rows[10'd600]=16'h0880;
        rows[10'd601]=16'h08f8;
        rows[10'd602]=16'h0880;
        rows[10'd603]=16'h1880;
        rows[10'd604]=16'h1c80;
        rows[10'd605]=16'h2780;
        rows[10'd606]=16'h41fe;
        // Range glyph 6: 离
        rows[10'd608]=16'h0100;
        rows[10'd609]=16'h0080;
        rows[10'd610]=16'h7ffe;
        rows[10'd611]=16'h0020;
        rows[10'd612]=16'h13c8;
        rows[10'd613]=16'h11c8;
        rows[10'd614]=16'h1628;
        rows[10'd615]=16'h1ff8;
        rows[10'd616]=16'h0100;
        rows[10'd617]=16'h1ffc;
        rows[10'd618]=16'h1244;
        rows[10'd619]=16'h1664;
        rows[10'd620]=16'h17e4;
        rows[10'd621]=16'h1004;
        rows[10'd622]=16'h3018;
        // Range glyph 7: 等
        rows[10'd624]=16'h1860;
        rows[10'd625]=16'h1f7e;
        rows[10'd626]=16'h2490;
        rows[10'd627]=16'h6418;
        rows[10'd628]=16'h0180;
        rows[10'd629]=16'h1ff8;
        rows[10'd630]=16'h0100;
        rows[10'd631]=16'h7ffe;
        rows[10'd632]=16'h0030;
        rows[10'd633]=16'h3ffc;
        rows[10'd634]=16'h0420;
        rows[10'd635]=16'h0420;
        rows[10'd636]=16'h0220;
        rows[10'd637]=16'h0020;
        rows[10'd638]=16'h0060;
        // Range glyph 8: 待
        rows[10'd640]=16'h0820;
        rows[10'd641]=16'h1820;
        rows[10'd642]=16'h31fc;
        rows[10'd643]=16'h6020;
        rows[10'd644]=16'h0820;
        rows[10'd645]=16'h0bfe;
        rows[10'd646]=16'h1000;
        rows[10'd647]=16'h3008;
        rows[10'd648]=16'h73fe;
        rows[10'd649]=16'h1008;
        rows[10'd650]=16'h1088;
        rows[10'd651]=16'h10c8;
        rows[10'd652]=16'h1008;
        rows[10'd653]=16'h1008;
        rows[10'd654]=16'h1038;
        // Range glyph 9: 数
        rows[10'd656]=16'h0430;
        rows[10'd657]=16'h2520;
        rows[10'd658]=16'h0620;
        rows[10'd659]=16'h7fa0;
        rows[10'd660]=16'h0c7e;
        rows[10'd661]=16'h1f44;
        rows[10'd662]=16'h6508;
        rows[10'd663]=16'h0068;
        rows[10'd664]=16'h0828;
        rows[10'd665]=16'h7f38;
        rows[10'd666]=16'h1110;
        rows[10'd667]=16'h3238;
        rows[10'd668]=16'h0e2c;
        rows[10'd669]=16'h19c6;
        rows[10'd670]=16'h2082;
        // Range glyph 10: 据
        rows[10'd672]=16'h1800;
        rows[10'd673]=16'h11fc;
        rows[10'd674]=16'h1104;
        rows[10'd675]=16'h7d04;
        rows[10'd676]=16'h11fc;
        rows[10'd677]=16'h1110;
        rows[10'd678]=16'h1510;
        rows[10'd679]=16'h1dfe;
        rows[10'd680]=16'h3110;
        rows[10'd681]=16'h51fc;
        rows[10'd682]=16'h1184;
        rows[10'd683]=16'h1284;
        rows[10'd684]=16'h1284;
        rows[10'd685]=16'h14fc;
        rows[10'd686]=16'h3084;
        // Range glyph 11: 应
        rows[10'd689]=16'h0100;
        rows[10'd690]=16'h0080;
        rows[10'd691]=16'h1ffe;
        rows[10'd692]=16'h3000;
        rows[10'd693]=16'h3000;
        rows[10'd694]=16'h308c;
        rows[10'd695]=16'h3088;
        rows[10'd696]=16'h3458;
        rows[10'd697]=16'h2650;
        rows[10'd698]=16'h2210;
        rows[10'd699]=16'h2120;
        rows[10'd700]=16'h2020;
        rows[10'd701]=16'h7ffe;
        rows[10'd702]=16'h4000;
        // Range glyph 12: 用
        rows[10'd705]=16'h1ffc;
        rows[10'd706]=16'h1084;
        rows[10'd707]=16'h1084;
        rows[10'd708]=16'h1084;
        rows[10'd709]=16'h1ffc;
        rows[10'd710]=16'h1084;
        rows[10'd711]=16'h1084;
        rows[10'd712]=16'h1ffc;
        rows[10'd713]=16'h1084;
        rows[10'd714]=16'h1084;
        rows[10'd715]=16'h1084;
        rows[10'd716]=16'h2084;
        rows[10'd717]=16'h2004;
        rows[10'd718]=16'h601c;
        // Range glyph 13: 已
        rows[10'd721]=16'h3ff8;
        rows[10'd722]=16'h0008;
        rows[10'd723]=16'h0008;
        rows[10'd724]=16'h2008;
        rows[10'd725]=16'h2008;
        rows[10'd726]=16'h3ff8;
        rows[10'd727]=16'h2000;
        rows[10'd728]=16'h2000;
        rows[10'd729]=16'h2000;
        rows[10'd730]=16'h2000;
        rows[10'd731]=16'h2004;
        rows[10'd732]=16'h200c;
        rows[10'd733]=16'h1ff8;
        // 30: 选; previously blank slot, same ERAM.
        rows[10'd481]=16'h0040;
        rows[10'd482]=16'h2240;
        rows[10'd483]=16'h1240;
        rows[10'd484]=16'h13f8;
        rows[10'd485]=16'h0440;
        rows[10'd486]=16'h0040;
        rows[10'd487]=16'hf7fc;
        rows[10'd488]=16'h1120;
        rows[10'd489]=16'h1120;
        rows[10'd490]=16'h1120;
        rows[10'd491]=16'h1224;
        rows[10'd492]=16'h1224;
        rows[10'd493]=16'h141c;
        rows[10'd494]=16'h2800;
        rows[10'd495]=16'h47fe;

        // Assist title: 辅助瞄准, formerly unused rows 768..831.
        rows[10'd769]=16'h1828;
        rows[10'd770]=16'h1024;
        rows[10'd771]=16'h7ffe;
        rows[10'd772]=16'h3020;
        rows[10'd773]=16'h21fc;
        rows[10'd774]=16'h2924;
        rows[10'd775]=16'h6924;
        rows[10'd776]=16'h7ffc;
        rows[10'd777]=16'h0924;
        rows[10'd778]=16'h09fc;
        rows[10'd779]=16'h1f24;
        rows[10'd780]=16'h7924;
        rows[10'd781]=16'h0924;
        rows[10'd782]=16'h090c;
        rows[10'd785]=16'h0020;
        rows[10'd786]=16'h3e20;
        rows[10'd787]=16'h2220;
        rows[10'd788]=16'h23fe;
        rows[10'd789]=16'h3e22;
        rows[10'd790]=16'h2222;
        rows[10'd791]=16'h2222;
        rows[10'd792]=16'h3e26;
        rows[10'd793]=16'h2266;
        rows[10'd794]=16'h2244;
        rows[10'd795]=16'h27c4;
        rows[10'd796]=16'h3f84;
        rows[10'd797]=16'h6104;
        rows[10'd798]=16'h021c;
        rows[10'd801]=16'h0098;
        rows[10'd802]=16'h3c90;
        rows[10'd803]=16'h67fe;
        rows[10'd804]=16'h6490;
        rows[10'd805]=16'h7c90;
        rows[10'd806]=16'h6400;
        rows[10'd807]=16'h65fc;
        rows[10'd808]=16'h7d24;
        rows[10'd809]=16'h65fc;
        rows[10'd810]=16'h6524;
        rows[10'd811]=16'h6524;
        rows[10'd812]=16'h7d24;
        rows[10'd813]=16'h65fc;
        rows[10'd814]=16'h0104;
        rows[10'd817]=16'h0120;
        rows[10'd818]=16'h0130;
        rows[10'd819]=16'h6210;
        rows[10'd820]=16'h33fe;
        rows[10'd821]=16'h0620;
        rows[10'd822]=16'h0e20;
        rows[10'd823]=16'h1bfc;
        rows[10'd824]=16'h0220;
        rows[10'd825]=16'h0a20;
        rows[10'd826]=16'h13fc;
        rows[10'd827]=16'h2220;
        rows[10'd828]=16'h6220;
        rows[10'd829]=16'h03fe;
        rows[10'd830]=16'h0200;
        rows[10'd831]=16'h0200;
    end
    always @(posedge clk)bits<=rows[address];
endmodule


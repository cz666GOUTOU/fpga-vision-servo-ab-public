// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module uart_region_store(
    input wire clk,rst_n,command_valid,
    input wire [7:0] command_code,command_data,
    output reg [15:0] point1_x,point1_y,point2_x,point2_y,
        point3_x,point3_y,point4_x,point4_y,
    output reg [2:0] selected_point,
    output reg confirmed
);
    wire [15:0] selected_x=selected_point==1 ? point1_x :
        (selected_point==2 ? point2_x : (selected_point==3 ? point3_x : point4_x));
    wire [15:0] selected_y=selected_point==1 ? point1_y :
        (selected_point==2 ? point2_y : (selected_point==3 ? point3_y : point4_y));
    function [15:0] move_pixel;
        input [15:0] coordinate,maximum;
        input signed [7:0] delta;
        reg signed [17:0] sum;
        begin
            sum=$signed({2'b00,coordinate})+$signed({{10{delta[7]}},delta});
            if(sum<0) move_pixel=0;
            else if(sum>$signed({2'b00,maximum})) move_pixel=maximum;
            else move_pixel=sum[15:0];
        end
    endfunction
    wire [15:0] next_x=move_pixel(selected_x,16'd1279,$signed(command_data));
    wire [15:0] next_y=move_pixel(selected_y,16'd719,$signed(command_data));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            point1_x<=400;point1_y<=200;point2_x<=879;point2_y<=200;
            point3_x<=879;point3_y<=519;point4_x<=400;point4_y<=519;
            selected_point<=0;confirmed<=0;
        end else if(command_valid) begin
            case(command_code)
                8'h24:if(command_data<=4) selected_point<=command_data[2:0];
                8'h21:if(command_data==2) begin
                    point1_x<=400;point1_y<=200;point2_x<=879;point2_y<=200;
                    point3_x<=879;point3_y<=519;point4_x<=400;point4_y<=519;
                    selected_point<=0;confirmed<=0;
                end else if(command_data==1) confirmed<=1;
                8'h22:if(selected_point!=0 && next_x!=selected_x) begin
                    case(selected_point)
                        1:point1_x<=next_x;
                        2:point2_x<=next_x;
                        3:point3_x<=next_x;
                        4:point4_x<=next_x;
                        default:begin end
                    endcase
                    confirmed<=0;
                end
                8'h23:if(selected_point!=0 && next_y!=selected_y) begin
                    case(selected_point)
                        1:point1_y<=next_y;
                        2:point2_y<=next_y;
                        3:point3_y<=next_y;
                        4:point4_y<=next_y;
                        default:begin end
                    endcase
                    confirmed<=0;
                end
                default:begin end
            endcase
        end
    end
endmodule

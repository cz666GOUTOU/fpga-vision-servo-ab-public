`include "fpga_b_example_config.vh"

// One exact two-phase 32x32 multiplier using two shared 17x17 lanes.
// Boundary tangents extend the measured field without clipping angle targets.
module vision_geometry_map(
    input wire clk, rst_n, start,
    input wire signed [31:0] x_q16, y_q16,
    output reg busy, done,
    output reg signed [31:0] q1, q2, j11, j12, j21, j22
);
    localparam IDLE=0, WAIT_MUL=1, NX=2, NY=3, POWERS=4,
        POWER_STORE=5, TERM=6, TERM_STORE=7, EXT_U=8,
        EXT_U_STORE=9, EXT_V=10, EXT_V_STORE=11,
        JX=12, JX_STORE=13, JY=14, JY_STORE=15, FINISH=16;
    reg [4:0] state, next_state;
    reg [3:0] power_index, term_index;
    reg [1:0] group;
    reg axis;
    reg signed [31:0] mx, my, raw_y, u, v, extra_u, extra_v;
    reg signed [31:0] powers[0:8];
    reg signed [31:0] mapped[0:1], du[0:1], dv[0:1];
    reg signed [63:0] product, sum;
    function signed [31:0] coeff;
        input integer ax, n;
        begin
            case((ax<<<3)+(ax<<<1)+n)
                0:coeff=32'sd0;
                1:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_1;
                2:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_1;
                3:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_2;
                4:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_3;
                5:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_2;
                6:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_4;
                7:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_5;
                8:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_6;
                9:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_3;
                10:coeff=32'sd0;
                11:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_7;
                12:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_4;
                13:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_5;
                14:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_8;
                15:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_6;
                16:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_9;
                17:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_7;
                18:coeff=-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_10;
                19:coeff=`FPGA_B_VISION_GEOMETRY_MAP_COEFF_8;
                default: coeff=0;
            endcase
        end
    endfunction
    function signed [31:0] times3;
        input signed [31:0] value;
        begin times3=(value<<<1)+value;end
    endfunction
    function signed [31:0] term_coeff;
        input integer ax, g, n;
        begin
            if(g==0) term_coeff=coeff(ax,n+1);
            else if(g==1) case(n)
                0:term_coeff=coeff(ax,3)<<<1; 1:term_coeff=coeff(ax,4);
                2:term_coeff=times3(coeff(ax,6)); 3:term_coeff=coeff(ax,7)<<<1;
                default:term_coeff=coeff(ax,8);
            endcase
            else case(n)
                0:term_coeff=coeff(ax,4); 1:term_coeff=coeff(ax,5)<<<1;
                2:term_coeff=coeff(ax,7); 3:term_coeff=coeff(ax,8)<<<1;
                default:term_coeff=times3(coeff(ax,9));
            endcase
        end
    endfunction
    reg multiply_phase;
    reg [31:0] partial_low;
    reg signed [31:0] partial_lh;
    wire multiplication_wait=state==WAIT_MUL;
    wire signed [16:0] multiply_a=multiply_phase?{mx[31],mx[31:16]}:{1'b0,mx[15:0]};
    wire signed [16:0] multiply_bl={1'b0,my[15:0]};
    wire signed [16:0] multiply_bh={my[31],my[31:16]};
    wire signed [33:0] multiply_low=multiply_a*multiply_bl;
    wire signed [33:0] multiply_high=multiply_a*multiply_bh;
    wire signed [32:0] cross_sum={partial_lh[31],partial_lh}+{multiply_low[31],multiply_low[31:0]};
    wire signed [32:0] middle_sum=cross_sum+$signed({17'd0,partial_low[31:16]});
    wire [31:0] high_sum=multiply_high[31:0]+{{15{middle_sum[32]}},middle_sum[32:16]};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin multiply_phase<=0;partial_low<=0;partial_lh<=0;product<=0;end
        else if(multiplication_wait)begin
            multiply_phase<=!multiply_phase;
            if(!multiply_phase)begin partial_low<=multiply_low[31:0];partial_lh<=multiply_high[31:0];end
            else product<={high_sum,middle_sum[15:0],partial_low[15:0]};
        end else multiply_phase<=0;
    end
    always @(posedge clk or negedge rst_n) begin: geometry
        reg signed [31:0] n;
        reg signed [63:0] accum;
        if(!rst_n) begin
            state<=IDLE;next_state<=IDLE;busy<=0;done<=0;
            q1<=0;q2<=0;j11<=0;j12<=0;j21<=0;j22<=0;
            mx<=0;my<=0;raw_y<=0;u<=0;v<=0;extra_u<=0;extra_v<=0;
            axis<=0;group<=0;power_index<=0;term_index<=0;sum<=0;
        end else begin
            done<=0;
            case(state)
                IDLE:if(start) begin
                    busy<=1;raw_y<=y_q16;
                    mx<=x_q16-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_11;my<=`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_12;
                    state<=WAIT_MUL;next_state<=NX;
                end
                WAIT_MUL:if(multiply_phase)state<=next_state;
                NX:begin
                    n=product>>>24;
                    u<=n<-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_13 ? -`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_14:(n>`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_15 ? `FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_16:n);
                    extra_u<=n-(n<-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_17 ? -`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_18:(n>`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_19 ? `FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_20:n));
                    mx<=raw_y-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_21;my<=`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_22;
                    state<=WAIT_MUL;next_state<=NY;
                end
                NY:begin
                    n=product>>>24;
                    v<=n<-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_23 ? -`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_24:(n>`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_25 ? `FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_26:n);
                    extra_v<=n-(n<-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_27 ? -`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_28:(n>`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_29 ? `FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_30:n));
                    powers[0]<=u;powers[1]<=n<-`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_31 ? -`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_32:(n>`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_33 ? `FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_34:n);
                    power_index<=2;state<=POWERS;
                end
                POWERS:begin
                    case(power_index)
                        2:begin mx<=u;my<=u;end
                        3:begin mx<=u;my<=v;end
                        4:begin mx<=v;my<=v;end
                        5:begin mx<=powers[2];my<=u;end
                        6:begin mx<=powers[2];my<=v;end
                        7:begin mx<=u;my<=powers[4];end
                        default:begin mx<=powers[4];my<=v;end
                    endcase
                    state<=WAIT_MUL;next_state<=POWER_STORE;
                end
                POWER_STORE:begin
                    powers[power_index]<=product>>>16;
                    if(power_index==8) begin axis<=0;group<=0;term_index<=0;sum<=0;state<=TERM;end
                    else begin power_index<=power_index+1'b1;state<=POWERS;end
                end
                TERM:begin
                    mx<=term_coeff(axis,group,term_index);my<=powers[term_index];
                    state<=WAIT_MUL;next_state<=TERM_STORE;
                end
                TERM_STORE:begin
                    accum=sum+(product>>>16);
                    if(term_index==(group==0 ? 8:4)) begin
                        if(group==0) mapped[axis]<=accum;
                        else if(group==1) du[axis]<=accum;
                        else dv[axis]<=accum;
                        term_index<=0;
                        if(group==2) begin
                            if(axis) begin axis<=0;state<=EXT_U;end
                            else begin axis<=1;group<=0;sum<=0;state<=TERM;end
                        end else begin
                            group<=group+1'b1;
                            sum<=coeff(axis,group==0 ? 1:2);state<=TERM;
                        end
                    end else begin sum<=accum;term_index<=term_index+1'b1;state<=TERM;end
                end
                EXT_U:begin mx<=du[axis];my<=extra_u;state<=WAIT_MUL;next_state<=EXT_U_STORE;end
                EXT_U_STORE:begin mapped[axis]<=mapped[axis]+(product>>>16);state<=EXT_V;end
                EXT_V:begin mx<=dv[axis];my<=extra_v;state<=WAIT_MUL;next_state<=EXT_V_STORE;end
                EXT_V_STORE:begin
                    mapped[axis]<=mapped[axis]+(product>>>16);
                    if(axis) begin axis<=0;state<=JX;end
                    else begin axis<=1;state<=EXT_U;end
                end
                JX:begin mx<=du[axis];my<=`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_35;state<=WAIT_MUL;next_state<=JX_STORE;end
                JX_STORE:begin
                    if(axis) j21<=product>>>24;else j11<=product>>>24;
                    state<=JY;
                end
                JY:begin mx<=dv[axis];my<=`FPGA_B_VISION_GEOMETRY_MAP_CALIBRATION_36;state<=WAIT_MUL;next_state<=JY_STORE;end
                JY_STORE:begin
                    if(axis) begin j22<=product>>>24;state<=FINISH;end
                    else begin j12<=product>>>24;axis<=1;state<=JX;end
                end
                FINISH:begin q1<=mapped[0];q2<=mapped[1];done<=1;busy<=0;state<=IDLE;end
                default:begin busy<=0;state<=IDLE;end
            endcase
        end
    end
endmodule

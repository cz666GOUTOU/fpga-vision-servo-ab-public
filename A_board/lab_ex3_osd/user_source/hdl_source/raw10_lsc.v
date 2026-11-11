// RAW10 spatial colour correction. P0 is I_tdata[9:0].
// Four pixels/cycle, six registered cycles for DATA/VALID/USER/LAST.
// Static Q2.10 node gains: 1024 = 1.0; 0..4095 are representable.
// Full bilinear interpolation is evaluated by exact additive recurrences:
// vertical knots carry GRID_BITS fractional bits; horizontal accumulators
// carry 2*GRID_BITS. No divider or interpolation multiplier is required.
module raw10_lsc #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer GRID_BITS = 8,
    parameter integer GRID_COLS = ((IMG_WIDTH-1) >> GRID_BITS) + 2,
    parameter integer GRID_ROWS = ((IMG_HEIGHT-1) >> GRID_BITS) + 2,
    parameter BAYER_MODE = "BGGR",
    parameter integer ENABLE = 1,
    // Least significant plane: R, then Gr, Gb, B. Within each plane,
    // the least significant node is (x=0,y=0), then increasing x, then y.
    parameter [4*GRID_COLS*GRID_ROWS*12-1:0] GAIN_TABLE =
        {4*GRID_COLS*GRID_ROWS{12'd1024}}
) (
    input wire I_clk, I_rst_n,
    input wire [39:0] I_tdata,
    input wire I_tvalid, I_tuser, I_tlast,
    output reg [39:0] O_tdata,
    output wire O_tvalid, O_tuser, O_tlast
);
    localparam integer X_BITS = (IMG_WIDTH > 1) ? $clog2(IMG_WIDTH) : 1;
    localparam integer Y_BITS = (IMG_HEIGHT > 1) ? $clog2(IMG_HEIGHT) : 1;
    localparam integer ROW_W = 12 + GRID_BITS;
    localparam integer STEP_W = ROW_W + 1;
    localparam integer ACC_W = 12 + 2*GRID_BITS;
    localparam [ACC_W:0] INTERP_HALF = 1 << (2*GRID_BITS-1);

    // This function is used ONLY by localparams with genvar/constant arguments.
    // A runtime integer index into the entire packed map makes TD infer wide
    // address multipliers. Row-band deltas below are precomputed constants.
    function [11:0] node_gain;
        input integer plane, gx, gy;
        begin
            node_gain = GAIN_TABLE[
                12*(plane*GRID_COLS*GRID_ROWS + gy*GRID_COLS + gx) +: 12];
        end
    endfunction

    function [1:0] colour_plane;
        input odd_y, odd_x;
        begin
            case (BAYER_MODE)
                "RGGB": case ({odd_y,odd_x})
                    2'b00: colour_plane=0; 2'b01: colour_plane=1;
                    2'b10: colour_plane=2; 2'b11: colour_plane=3;
                endcase
                "GRBG": case ({odd_y,odd_x})
                    2'b00: colour_plane=1; 2'b01: colour_plane=0;
                    2'b10: colour_plane=3; 2'b11: colour_plane=2;
                endcase
                "GBRG": case ({odd_y,odd_x})
                    2'b00: colour_plane=2; 2'b01: colour_plane=3;
                    2'b10: colour_plane=0; 2'b11: colour_plane=1;
                endcase
                default: case ({odd_y,odd_x}) // BGGR
                    2'b00: colour_plane=3; 2'b01: colour_plane=2;
                    2'b10: colour_plane=1; 2'b11: colour_plane=0;
                endcase
            endcase
        end
    endfunction

    generate if ((ENABLE == 0) ||
        (GAIN_TABLE == {4*GRID_COLS*GRID_ROWS{12'd1024}})) begin : g_unity
        // Compile-time identity: exactly the same six clocks, including DATA
        // during blanking and reset flush, without coordinate/coefficient logic.
        reg [39:0] raw_d [0:4];
        reg [5:0] valid_d, user_d, last_d;
        integer n;
        assign O_tvalid = valid_d[5];
        assign O_tuser = user_d[5];
        assign O_tlast = last_d[5];
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                for (n=0;n<5;n=n+1) raw_d[n] <= 0;
                O_tdata <= 0;
                valid_d <= 0; user_d <= 0; last_d <= 0;
            end else begin
                raw_d[0] <= I_tdata;
                for (n=1;n<5;n=n+1) raw_d[n] <= raw_d[n-1];
                O_tdata <= raw_d[4];
                valid_d <= {valid_d[4:0],I_tvalid};
                user_d <= {user_d[4:0],I_tuser};
                last_d <= {last_d[4:0],I_tlast};
            end
        end
    end else begin : g_correct
    reg [X_BITS-1:0] x_count;
    reg [Y_BITS-1:0] y_count;
    wire [X_BITS-1:0] x_use = I_tuser ? {X_BITS{1'b0}} : x_count;
    wire [Y_BITS-1:0] y_use = I_tuser ? {Y_BITS{1'b0}} : y_count;
    wire line_end = I_tvalid && (I_tlast || x_use == IMG_WIDTH-4);
    wire frame_end = line_end && y_use == IMG_HEIGHT-1;
    wire cell_start = (x_use & ((1 << GRID_BITS)-1)) == 0;
    wire [X_BITS-1:0] cell_x = x_use >> GRID_BITS;
    wire [Y_BITS:0] next_y = frame_end ? 0 : {1'b0,y_use} + 1'b1;
    wire [Y_BITS:0] next_band = next_y >> GRID_BITS;

    // Node value at the CURRENT row, and its change per one logical row.
    reg [ROW_W-1:0] row_knot [0:4*GRID_COLS-1];
    reg signed [12:0] row_dy [0:4*GRID_COLS-1];
    wire [ROW_W-1:0] next_knot [0:4*GRID_COLS-1];
    reg [ACC_W-1:0] h_acc [0:3];
    reg signed [STEP_W-1:0] h_step [0:3];
    wire [ACC_W-1:0] acc_use [0:3];
    wire signed [STEP_W-1:0] step_use [0:3];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_count <= 0; y_count <= 0;
        end else begin
            if (I_tuser) begin x_count <= 0; y_count <= 0; end
            if (I_tvalid) begin
                if (line_end) begin
                    x_count <= 0;
                    y_count <= frame_end ? 0 : y_use + 1'b1;
                end else begin
                    x_count <= x_use + 4;
                    y_count <= y_use;
                end
            end
        end
    end

    genvar c, k, b;
    for (c=0;c<4;c=c+1) begin : g_plane
        for (k=0;k<GRID_COLS;k=k+1) begin : g_knot
            localparam integer IDX = c*GRID_COLS+k;
            localparam [11:0] TOP = node_gain(c,k,0);
            localparam signed [12:0] FIRST_DY =
                $signed({1'b0,node_gain(c,k,1)}) - $signed({1'b0,TOP});
            // One-hot row-band selection of already evaluated 13-bit deltas.
            // No runtime call to node_gain, table shift, address multiply, or
            // subtraction of selected node values is left in this path.
            wire signed [12:0] dy_select [0:GRID_ROWS-1];
            assign dy_select[0] = 13'sd0;
            for (b=0;b<GRID_ROWS-1;b=b+1) begin : g_band_dy
                localparam [Y_BITS:0] BAND = b;
                localparam signed [12:0] BAND_DY =
                    $signed({1'b0,node_gain(c,k,b+1)}) -
                    $signed({1'b0,node_gain(c,k,b)});
                assign dy_select[b+1] = dy_select[b] |
                    ((next_band == BAND) ? BAND_DY : 13'sd0);
            end
            wire [ROW_W-1:0] row_base = I_tuser ?
                {TOP,{GRID_BITS{1'b0}}} : row_knot[IDX];
            wire signed [12:0] dy_use = I_tuser ? FIRST_DY : row_dy[IDX];
            wire signed [ROW_W:0] row_sum = $signed({1'b0,row_base}) +
                $signed({{(ROW_W-12){dy_use[12]}},dy_use});
            assign next_knot[IDX] = frame_end ?
                {TOP,{GRID_BITS{1'b0}}} : row_sum[ROW_W-1:0];
            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) begin
                    row_knot[IDX] <= {TOP,{GRID_BITS{1'b0}}};
                    row_dy[IDX] <= FIRST_DY;
                end else if (I_tuser || line_end) begin
                    if (frame_end || !line_end) begin
                        row_knot[IDX] <= {TOP,{GRID_BITS{1'b0}}};
                        row_dy[IDX] <= FIRST_DY;
                    end else begin
                        row_knot[IDX] <= next_knot[IDX];
                        row_dy[IDX] <= dy_select[GRID_ROWS-1];
                    end
                end
            end
        end
        localparam [11:0] TOP_LEFT = node_gain(c,0,0);
        localparam signed [12:0] TOP_DX =
            $signed({1'b0,node_gain(c,1,0)}) - $signed({1'b0,TOP_LEFT});
        wire [ROW_W-1:0] left_knot = row_knot[c*GRID_COLS+cell_x];
        wire [ROW_W-1:0] right_knot = row_knot[c*GRID_COLS+cell_x+1'b1];
        wire signed [STEP_W-1:0] knot_dx =
            $signed({1'b0,right_knot}) - $signed({1'b0,left_knot});
        wire signed [STEP_W-1:0] first_dx =
            $signed({{GRID_BITS{TOP_DX[12]}},TOP_DX}) <<< GRID_BITS;
        assign acc_use[c] = I_tuser ? {TOP_LEFT,{2*GRID_BITS{1'b0}}} :
            cell_start ? {left_knot,{GRID_BITS{1'b0}}} : h_acc[c];
        assign step_use[c] = I_tuser ? first_dx :
            cell_start ? knot_dx : h_step[c];
        wire signed [ACC_W:0] dx_extended =
            {{(ACC_W+1-STEP_W){step_use[c][STEP_W-1]}},step_use[c]};
        wire signed [ACC_W:0] acc_next =
            $signed({1'b0,acc_use[c]}) + (dx_extended <<< 2);
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                h_acc[c] <= {TOP_LEFT,{2*GRID_BITS{1'b0}}};
                h_step[c] <= first_dx;
            end else if (line_end) begin
                h_acc[c] <= {next_knot[c*GRID_COLS],{GRID_BITS{1'b0}}};
                h_step[c] <=
                    $signed({1'b0,next_knot[c*GRID_COLS+1]}) -
                    $signed({1'b0,next_knot[c*GRID_COLS]});
            end else if (I_tvalid) begin
                h_acc[c] <= acc_next[ACC_W-1:0];
                h_step[c] <= step_use[c];
            end else if (I_tuser) begin
                h_acc[c] <= {TOP_LEFT,{2*GRID_BITS{1'b0}}};
                h_step[c] <= first_dx;
            end
        end
    end

    reg [5:0] valid_d, user_d, last_d;
    reg [39:0] raw_s1, raw_s2, raw_s3, scaled_s5;
    reg [ACC_W-1:0] base_s1 [0:3];
    reg signed [STEP_W-1:0] delta_s1 [0:3];
    reg signed [ACC_W:0] acc_s2 [0:3];
    reg [11:0] gain_s3 [0:3];
    // One pixel multiplier per lane. Interpolation uses only add/shift.
    (* use_dsp = "yes" *) reg [21:0] product_s4 [0:3];
    assign O_tvalid=valid_d[5];
    assign O_tuser=user_d[5];
    assign O_tlast=last_d[5];
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d<=0; user_d<=0; last_d<=0;
            raw_s1<=0; raw_s2<=0; raw_s3<=0; O_tdata<=0;
        end else begin
            valid_d<={valid_d[4:0],I_tvalid};
            user_d<={user_d[4:0],I_tuser};
            last_d<={last_d[4:0],I_tlast};
            raw_s1<=I_tdata; raw_s2<=raw_s1; raw_s3<=raw_s2;
            O_tdata<=scaled_s5;
        end
    end
    genvar p;
    for (p=0;p<4;p=p+1) begin : g_pixel
        wire [1:0] plane=colour_plane(y_use[0],(p%2)!=0);
        wire signed [ACC_W:0] dx_s1 =
            {{(ACC_W+1-STEP_W){delta_s1[p][STEP_W-1]}},delta_s1[p]};
        wire signed [ACC_W:0] offset_s1;
        if (p==0) assign offset_s1=0;
        else if (p==1) assign offset_s1=dx_s1;
        else if (p==2) assign offset_s1=dx_s1 <<< 1;
        else assign offset_s1=(dx_s1 <<< 1)+dx_s1;
        wire [ACC_W:0] rounded_gain=$unsigned(acc_s2[p])+INTERP_HALF;
        wire [22:0] rounded_product={1'b0,product_s4[p]}+23'd512;
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                base_s1[p]<=0; delta_s1[p]<=0; acc_s2[p]<=0;
                gain_s3[p]<=12'd1024; product_s4[p]<=0;
                scaled_s5[p*10+:10]<=0;
            end else begin
                // S1 select plane/base/slope; S2 offset for x+lane;
                // S3 round Q2.10 gain; S4 multiply; S5 round/clamp; S6 output.
                base_s1[p]<=acc_use[plane];
                delta_s1[p]<=step_use[plane];
                acc_s2[p]<=$signed({1'b0,base_s1[p]})+offset_s1;
                gain_s3[p]<=ENABLE ? rounded_gain[2*GRID_BITS+:12] : 12'd1024;
                product_s4[p]<=raw_s3[p*10+:10]*gain_s3[p];
                scaled_s5[p*10+:10]<= (|rounded_product[22:20]) ?
                    10'd1023 : rounded_product[19:10];
            end
        end
    end
    end endgenerate

    // synthesis translate_off
    initial begin
        if (IMG_WIDTH<4 || IMG_WIDTH%4!=0 || IMG_HEIGHT<1 ||
            GRID_BITS<2 || GRID_BITS>8 ||
            GRID_COLS!=((IMG_WIDTH-1)>>GRID_BITS)+2 ||
            GRID_ROWS!=((IMG_HEIGHT-1)>>GRID_BITS)+2 ||
            (BAYER_MODE!="BGGR" && BAYER_MODE!="GBRG" &&
             BAYER_MODE!="RGGB" && BAYER_MODE!="GRBG")) begin
            $display("ERROR: unsupported raw10_lsc geometry/CFA");
            $finish;
        end
    end
    // synthesis translate_on
endmodule

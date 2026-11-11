// Active modes (button order): 0 RGB, 1 gray, 2 binary, 3 histogram stretch,
// 4 Sobel, 5 Gaussian, 7 invert, 9 gamma, 10 false color, 11 cartoon, 12 auto.
// Retired modes 6/8 select RGB; existing command numbers are unchanged.
// Removed: half scaling and grayscale brightness/contrast demo.
// ============================================================================
// Processing Mode Selection (proc_sel)
// ----------------------------------------------------------------------------
// ���ź�����ѡ����Ƶ����ģʽ����4λ��4'b0000 ~ 4'b1111������ǰӳ�����£�
//
//
// ����ȡֵ��������չʱ��ͬ������ case ��֧��ģ��ӳ�䡣
// ============================================================================

// ʾ���÷����ڶ���ģ���ж��壩��

`timescale 1ns / 1ps


module vision #(
    parameter integer VIDEO_WIDTH  = 1280, // ��ǰʹ�� 1280x720 �ֱ���
    parameter integer VIDEO_HEIGHT = 720   // �и߲��������ں�����Ҫ�ĸ߶�����
)(
    input        clk,
    input        rst_n,
    input        pre_frame_vsync,
    input        pre_frame_href,
    input        pre_frame_de,
    input  [23:0]pre_rgb,
    input  [3:0] proc_sel,
    output       post_frame_vsync,
    output       post_frame_href,
    output       post_frame_de,
    output [23:0]post_rgb
);
    wire cartoon_vsync, cartoon_href, cartoon_de;
    wire [23:0] cartoon_rgb;
    video_proc_cartoon #(.VIDEO_WIDTH(VIDEO_WIDTH)) u_proc_cartoon(
        .clk(clk),.rst_n(rst_n),.vs(pre_frame_vsync),.hs(pre_frame_href),
        .de(pre_frame_de),.rgb(pre_rgb),.ov(cartoon_vsync),.oh(cartoon_href),
        .od(cartoon_de),.pixel(cartoon_rgb));
    wire [7:0] img_y;
    wire post_vsync_int;
    wire post_href_int;
    wire post_de_int;


    localparam [3:0] PROC_BYPASS    = 4'd0;
    localparam [3:0] PROC_GRAY      = 4'd1;
    localparam [3:0] PROC_GRAY_BIN  = 4'd2;
    localparam [3:0] PROC_HIST      = 4'd3; // ֱ��ͼ���죨���У�
    localparam [3:0] PROC_SOBEL     = 4'd4;
    localparam [3:0] PROC_GAUSS     = 4'd5;
    // ԭ PROC_HIST_EQ(4'd9) ɾ�����滻Ϊ�򵥻Ҷȷ��๦�ܣ�����������ʾ
    localparam [3:0] PROC_INVERT    = 4'd7; // �Ҷȷ��� 255-Y
    localparam [3:0] PROC_GAMMA     = 4'd9; // ٤��У�� (Gamma ~2.2 Ĭ��)
    localparam [3:0] PROC_FALSE     = 4'd10; // �Ҷ�α��ӳ��
    localparam [3:0] PROC_AUTO      = 4'd12; // mode 12: camera auto exposure, original pixels

    wire        bypass_vsync;
    wire        bypass_href;
    wire        bypass_de;
    wire [23:0] bypass_rgb;

    wire        gray_vsync;
    wire        gray_href;
    wire        gray_de;
    wire [23:0] gray_rgb;

    wire        binary_vsync;
    wire        binary_href;
    wire        binary_de;
    wire [23:0] binary_rgb;

    wire        hist_vsync;
    wire        hist_href;
    wire        hist_de;
    wire [23:0] hist_rgb;

    wire        sobel_vsync;
    wire        sobel_href;
    wire        sobel_de;
    wire [23:0] sobel_rgb;


    wire        gauss_vsync;
    wire        gauss_href;
    wire        gauss_de;
    wire [23:0] gauss_rgb;



    wire        invert_vsync;
    wire        invert_href;
    wire        invert_de;
    wire [23:0] invert_rgb;


    wire        gamma_vsync;
    wire        gamma_href;
    wire        gamma_de;
    wire [23:0] gamma_rgb;
    wire        false_vsync;
    wire        false_href;
    wire        false_de;
    wire [23:0] false_rgb;


    reg        post_vsync_sel;
    reg        post_href_sel;
    reg        post_de_sel;
    reg [23:0] post_rgb_sel;

    //��ƵRGB888ת�Ҷ�
    rgb2ycbcr_888 u_rgb2ycbcr(
        .clk             (clk),
        .rst_n           (rst_n),
        .pre_frame_vsync (pre_frame_vsync),
        .pre_frame_href  (pre_frame_href),
        .pre_frame_de    (pre_frame_de),
        .img_red         (pre_rgb[23:16]),
        .img_green       (pre_rgb[15:8]),
        .img_blue        (pre_rgb[7:0]),
        .post_frame_vsync(post_vsync_int),
        .post_frame_href (post_href_int),
        .post_frame_de   (post_de_int),
        .img_y           (img_y),
        .img_cb          (),
        .img_cr          ()
    );

    video_proc_passthrough u_proc_bypass(
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (pre_frame_vsync),
        .in_frame_href    (pre_frame_href),
        .in_frame_de      (pre_frame_de),
        .in_rgb           (pre_rgb),
        .out_frame_vsync  (bypass_vsync),
        .out_frame_href   (bypass_href),
        .out_frame_de     (bypass_de),
        .out_rgb          (bypass_rgb)
    );

    video_proc_gray u_proc_gray(
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (gray_vsync),
        .out_frame_href   (gray_href),
        .out_frame_de     (gray_de),
        .out_rgb          (gray_rgb)
    );

    video_proc_gray_binary #(
        .THRESHOLD        (8'd128)
    ) u_proc_binary (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (binary_vsync),
        .out_frame_href   (binary_href),
        .out_frame_de     (binary_de),
        .out_rgb          (binary_rgb)
    );

    video_proc_histogram u_proc_hist(
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (hist_vsync),
        .out_frame_href   (hist_href),
        .out_frame_de     (hist_de),
        .out_rgb          (hist_rgb)
    );

    localparam integer SHARE_FILTER_ROWS=(VIDEO_WIDTH==1280 && VIDEO_HEIGHT==720);
    wire [7:0] filter_row1,filter_row2;
    reg shared_first_de=1'b0,shared_rows_enabled=1'b0;
    // The VTC can extend its first DE burst while its reset counter releases.
    // Discard that window only, without modifying any public control stream.
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin shared_first_de<=0;shared_rows_enabled<=0;end
        else if(!shared_rows_enabled) begin
            if(post_de_int) shared_first_de<=1;
            else if(shared_first_de) shared_rows_enabled<=1;
        end
    wire shared_window_de=post_de_int && shared_rows_enabled;
    generate if(SHARE_FILTER_ROWS) begin : shared_filter_rows
        video_filter_row_store #(.VIDEO_WIDTH(VIDEO_WIDTH)) u_rows (
            .clk(clk),.rst_n(rst_n),.de(shared_window_de),.gray(img_y),
            .row1(filter_row1),.row2(filter_row2));
    end else begin : independent_filter_rows
        assign filter_row1=8'd0;
        assign filter_row2=8'd0;
    end endgenerate

    video_proc_sobel_rows #(
        .EXTERNAL_ROWS    (SHARE_FILTER_ROWS),
        .VIDEO_WIDTH      (VIDEO_WIDTH),
        .VIDEO_HEIGHT     (VIDEO_HEIGHT)
    ) u_proc_sobel (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (sobel_vsync),
        .out_frame_href   (sobel_href),
        .out_frame_de     (sobel_de),
        .shared_row1      (filter_row1),
        .shared_row2      (filter_row2),
        .shared_enable    (shared_rows_enabled),
        .out_rgb          (sobel_rgb)
    );


    video_proc_gaussian_rows #(
        .EXTERNAL_ROWS    (SHARE_FILTER_ROWS),
        .VIDEO_WIDTH      (VIDEO_WIDTH),
        .VIDEO_HEIGHT     (VIDEO_HEIGHT)
    ) u_proc_gauss (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (gauss_vsync),
        .out_frame_href   (gauss_href),
        .out_frame_de     (gauss_de),
        .shared_row1      (filter_row1),
        .shared_row2      (filter_row2),
        .shared_enable    (shared_rows_enabled),
        .out_rgb          (gauss_rgb)
    );



    // �򵥻Ҷȷ���ģ�飨�滻ԭֱ��ͼ������ʾģ�飩
    video_proc_invert u_proc_invert (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (invert_vsync),
        .out_frame_href   (invert_href),
        .out_frame_de     (invert_de),
        .out_rgb          (invert_rgb)
    );




    // ٤��У��ģ�� (Gamma=2.2) ʹ�� 64 �� LUT + ���Բ�ֵ
    video_proc_gamma #(
        .GAMMA_SCALE      (220),          // ���� 2.20 (���� *100)
        .LUT_POINTS       (64),
        .VIDEO_WIDTH      (VIDEO_WIDTH),
        .VIDEO_HEIGHT     (VIDEO_HEIGHT)
    ) u_proc_gamma (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (gamma_vsync),
        .out_frame_href   (gamma_href),
        .out_frame_de     (gamma_de),
        .out_rgb          (gamma_rgb)
    );

    // �Ҷ�α��ӳ��ģ��
    video_proc_false_color u_proc_false (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_frame_vsync   (post_vsync_int),
        .in_frame_href    (post_href_int),
        .in_frame_de      (post_de_int),
        .in_gray          (img_y),
        .out_frame_vsync  (false_vsync),
        .out_frame_href   (false_href),
        .out_frame_de     (false_de),
        .out_rgb          (false_rgb)
    );

    always @(*) begin
        post_vsync_sel = bypass_vsync;
        post_href_sel  = bypass_href;
        post_de_sel    = bypass_de;
        post_rgb_sel   = bypass_rgb;

        case (proc_sel)
            4'd11: begin
                post_vsync_sel=cartoon_vsync;
                post_href_sel=cartoon_href;
                post_de_sel=cartoon_de;
                post_rgb_sel=cartoon_rgb;
            end
            PROC_GRAY: begin
                post_vsync_sel = gray_vsync;
                post_href_sel  = gray_href;
                post_de_sel    = gray_de;
                post_rgb_sel   = gray_rgb;
            end
            PROC_GRAY_BIN: begin
                post_vsync_sel = binary_vsync;
                post_href_sel  = binary_href;
                post_de_sel    = binary_de;
                post_rgb_sel   = binary_rgb;
            end
            PROC_HIST: begin
                post_vsync_sel = hist_vsync;
                post_href_sel  = hist_href;
                post_de_sel    = hist_de;
                post_rgb_sel   = hist_rgb;
            end
            PROC_SOBEL: begin
                post_vsync_sel = sobel_vsync;
                post_href_sel  = sobel_href;
                post_de_sel    = sobel_de;
                post_rgb_sel   = sobel_rgb;
            end
            PROC_GAUSS: begin
                post_vsync_sel = gauss_vsync;
                post_href_sel  = gauss_href;
                post_de_sel    = gauss_de;
                post_rgb_sel   = gauss_rgb;
            end
            PROC_INVERT: begin
                post_vsync_sel = invert_vsync;
                post_href_sel  = invert_href;
                post_de_sel    = invert_de;
                post_rgb_sel   = invert_rgb;
            end
            PROC_GAMMA: begin
                post_vsync_sel = gamma_vsync;
                post_href_sel  = gamma_href;
                post_de_sel    = gamma_de;
                post_rgb_sel   = gamma_rgb;
            end
            PROC_FALSE: begin
                post_vsync_sel = false_vsync;
                post_href_sel  = false_href;
                post_de_sel    = false_de;
                post_rgb_sel   = false_rgb;
            end
            PROC_AUTO: begin
                post_vsync_sel = bypass_vsync;
                post_href_sel  = bypass_href;
                post_de_sel    = bypass_de;
                post_rgb_sel   = bypass_rgb;
            end
            default: begin
                /* default uses bypass assignments above */
            end
        endcase
    end

    assign post_frame_vsync = post_vsync_sel;
    assign post_frame_href  = post_href_sel;
    assign post_frame_de    = post_de_sel;
    assign post_rgb         = post_rgb_sel;
endmodule

//RGB888תYCbCr����ʹ��Y�������лҶ����
// Original six-sample luma edge with top/left border replication.
// Raw RGB uses the original six color levels without smoothing/chroma boost.
// Six clocks, one pixel/clock, two 8-bit row banks; no DSP or frame RAM.
module video_proc_cartoon #(
    parameter integer VIDEO_WIDTH=1280,
    parameter integer EDGE_THRESHOLD=120
)(
    input wire clk,rst_n,vs,hs,de,
    input wire [23:0] rgb,
    output wire ov,oh,od,
    output reg [23:0] pixel
);
    // Six registered clocks, one pixel/clock. Four levels per channel.
    // Quantize before delaying: only six color bits traverse the pipeline.
    // No outline, line buffer, arithmetic or frame-dependent state.
    reg [5:0] colors[0:5];
    reg [5:0] vp,hp,dp;
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vp<=0;hp<=0;dp<=0;
            for(i=0;i<6;i=i+1) colors[i]<=0;
        end else begin
            vp<={vp[4:0],vs};hp<={hp[4:0],hs};dp<={dp[4:0],de};
            colors[0]<={rgb[23:22],rgb[15:14],rgb[7:6]};
            for(i=1;i<6;i=i+1) colors[i]<=colors[i-1];
        end
    end
    assign ov=vp[5];assign oh=hp[5];assign od=dp[5];
    always @* begin
        if(dp[5]) pixel={{4{colors[5][5:4]}},{4{colors[5][3:2]}},{4{colors[5][1:0]}}};
        else pixel=24'd0;
    end
endmodule

module rgb2ycbcr_888(
    input        clk,
    input        rst_n,
    input        pre_frame_vsync,
    input        pre_frame_href,
    input        pre_frame_de,
    input  [7:0] img_red,
    input  [7:0] img_green,
    input  [7:0] img_blue,
    output reg   post_frame_vsync,
    output reg   post_frame_href,
    output reg   post_frame_de,
    output reg [7:0] img_y,
    output reg [7:0] img_cb,
    output reg [7:0] img_cr
);
    reg        pre_frame_vsync_d;
    reg        pre_frame_href_d;
    reg        pre_frame_de_d;
    reg [7:0]  img_red_d;
    reg [7:0]  img_green_d;
    reg [7:0]  img_blue_d;

    wire [15:0] y_calc;

    assign y_calc = (img_red_d * 8'd77) + (img_green_d * 8'd150) + (img_blue_d * 8'd29);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pre_frame_vsync_d <= 1'b0;
            pre_frame_href_d  <= 1'b0;
            pre_frame_de_d    <= 1'b0;
            img_red_d         <= 8'd0;
            img_green_d       <= 8'd0;
            img_blue_d        <= 8'd0;
            post_frame_vsync  <= 1'b0;
            post_frame_href   <= 1'b0;
            post_frame_de     <= 1'b0;
            img_y             <= 8'd0;
            img_cb            <= 8'd128;
            img_cr            <= 8'd128;
        end else begin
            pre_frame_vsync_d <= pre_frame_vsync;
            pre_frame_href_d  <= pre_frame_href;
            pre_frame_de_d    <= pre_frame_de;
            img_red_d         <= img_red;
            img_green_d       <= img_green;
            img_blue_d        <= img_blue;

            post_frame_vsync  <= pre_frame_vsync_d;
            post_frame_href   <= pre_frame_href_d;
            post_frame_de     <= pre_frame_de_d;
            img_y             <= (y_calc + 16'd128) >> 8;
            img_cb            <= 8'd128;
            img_cr            <= 8'd128;
        end
    end
endmodule

//RGBֱͨ����
module video_proc_passthrough(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [23:0]in_rgb,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
        end else begin
            out_frame_vsync <= in_frame_vsync;
            out_frame_href  <= in_frame_href;
            out_frame_de    <= in_frame_de;
            out_rgb         <= in_rgb;
        end
    end
endmodule

//�Ҷ�ͼ���
module video_proc_gray(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
        end else begin
            out_frame_vsync <= in_frame_vsync;
            out_frame_href  <= in_frame_href;
            out_frame_de    <= in_frame_de;
            out_rgb         <= {in_gray, in_gray, in_gray};
        end
    end
endmodule

//�Ҷȶ�ֵ�����
module video_proc_gray_binary #(
    parameter [7:0] THRESHOLD = 8'd128
)(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    wire [7:0] gray_bin = (in_gray >= THRESHOLD) ? 8'hFF : 8'h00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
        end else begin
            out_frame_vsync <= in_frame_vsync;
            out_frame_href  <= in_frame_href;
            out_frame_de    <= in_frame_de;
            out_rgb         <= {gray_bin, gray_bin, gray_bin};
        end
    end
endmodule

//�Ҷ�ֱ��ͼ�������
module video_proc_histogram(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    // The stretch coefficient is constant for a complete frame.  Compute it
    // once in vertical blanking instead of placing a divider in every pixel
    // path. gain_q8 represents 255/range in unsigned Q8 format.
    reg        in_frame_vsync_d;
    reg [7:0]  frame_min;
    reg [7:0]  frame_max;
    reg [7:0]  latched_min;
    reg [7:0]  latched_max;
    reg [15:0] gain_q8;

    // Keep the old 17-clock coefficient commit, including restart priority.
    reg div_busy;
    reg [4:0] div_count;
    reg [7:0] lookup_range;
    (* ram_style="bram" *) reg [15:0] gain_table[0:255];
    reg [15:0] gain_lookup;
    initial begin
        gain_table[0]=16'd0;
        gain_table[1]=16'd65280;
        gain_table[2]=16'd32640;
        gain_table[3]=16'd21760;
        gain_table[4]=16'd16320;
        gain_table[5]=16'd13056;
        gain_table[6]=16'd10880;
        gain_table[7]=16'd9326;
        gain_table[8]=16'd8160;
        gain_table[9]=16'd7253;
        gain_table[10]=16'd6528;
        gain_table[11]=16'd5935;
        gain_table[12]=16'd5440;
        gain_table[13]=16'd5022;
        gain_table[14]=16'd4663;
        gain_table[15]=16'd4352;
        gain_table[16]=16'd4080;
        gain_table[17]=16'd3840;
        gain_table[18]=16'd3627;
        gain_table[19]=16'd3436;
        gain_table[20]=16'd3264;
        gain_table[21]=16'd3109;
        gain_table[22]=16'd2967;
        gain_table[23]=16'd2838;
        gain_table[24]=16'd2720;
        gain_table[25]=16'd2611;
        gain_table[26]=16'd2511;
        gain_table[27]=16'd2418;
        gain_table[28]=16'd2331;
        gain_table[29]=16'd2251;
        gain_table[30]=16'd2176;
        gain_table[31]=16'd2106;
        gain_table[32]=16'd2040;
        gain_table[33]=16'd1978;
        gain_table[34]=16'd1920;
        gain_table[35]=16'd1865;
        gain_table[36]=16'd1813;
        gain_table[37]=16'd1764;
        gain_table[38]=16'd1718;
        gain_table[39]=16'd1674;
        gain_table[40]=16'd1632;
        gain_table[41]=16'd1592;
        gain_table[42]=16'd1554;
        gain_table[43]=16'd1518;
        gain_table[44]=16'd1484;
        gain_table[45]=16'd1451;
        gain_table[46]=16'd1419;
        gain_table[47]=16'd1389;
        gain_table[48]=16'd1360;
        gain_table[49]=16'd1332;
        gain_table[50]=16'd1306;
        gain_table[51]=16'd1280;
        gain_table[52]=16'd1255;
        gain_table[53]=16'd1232;
        gain_table[54]=16'd1209;
        gain_table[55]=16'd1187;
        gain_table[56]=16'd1166;
        gain_table[57]=16'd1145;
        gain_table[58]=16'd1126;
        gain_table[59]=16'd1106;
        gain_table[60]=16'd1088;
        gain_table[61]=16'd1070;
        gain_table[62]=16'd1053;
        gain_table[63]=16'd1036;
        gain_table[64]=16'd1020;
        gain_table[65]=16'd1004;
        gain_table[66]=16'd989;
        gain_table[67]=16'd974;
        gain_table[68]=16'd960;
        gain_table[69]=16'd946;
        gain_table[70]=16'd933;
        gain_table[71]=16'd919;
        gain_table[72]=16'd907;
        gain_table[73]=16'd894;
        gain_table[74]=16'd882;
        gain_table[75]=16'd870;
        gain_table[76]=16'd859;
        gain_table[77]=16'd848;
        gain_table[78]=16'd837;
        gain_table[79]=16'd826;
        gain_table[80]=16'd816;
        gain_table[81]=16'd806;
        gain_table[82]=16'd796;
        gain_table[83]=16'd787;
        gain_table[84]=16'd777;
        gain_table[85]=16'd768;
        gain_table[86]=16'd759;
        gain_table[87]=16'd750;
        gain_table[88]=16'd742;
        gain_table[89]=16'd733;
        gain_table[90]=16'd725;
        gain_table[91]=16'd717;
        gain_table[92]=16'd710;
        gain_table[93]=16'd702;
        gain_table[94]=16'd694;
        gain_table[95]=16'd687;
        gain_table[96]=16'd680;
        gain_table[97]=16'd673;
        gain_table[98]=16'd666;
        gain_table[99]=16'd659;
        gain_table[100]=16'd653;
        gain_table[101]=16'd646;
        gain_table[102]=16'd640;
        gain_table[103]=16'd634;
        gain_table[104]=16'd628;
        gain_table[105]=16'd622;
        gain_table[106]=16'd616;
        gain_table[107]=16'd610;
        gain_table[108]=16'd604;
        gain_table[109]=16'd599;
        gain_table[110]=16'd593;
        gain_table[111]=16'd588;
        gain_table[112]=16'd583;
        gain_table[113]=16'd578;
        gain_table[114]=16'd573;
        gain_table[115]=16'd568;
        gain_table[116]=16'd563;
        gain_table[117]=16'd558;
        gain_table[118]=16'd553;
        gain_table[119]=16'd549;
        gain_table[120]=16'd544;
        gain_table[121]=16'd540;
        gain_table[122]=16'd535;
        gain_table[123]=16'd531;
        gain_table[124]=16'd526;
        gain_table[125]=16'd522;
        gain_table[126]=16'd518;
        gain_table[127]=16'd514;
        gain_table[128]=16'd510;
        gain_table[129]=16'd506;
        gain_table[130]=16'd502;
        gain_table[131]=16'd498;
        gain_table[132]=16'd495;
        gain_table[133]=16'd491;
        gain_table[134]=16'd487;
        gain_table[135]=16'd484;
        gain_table[136]=16'd480;
        gain_table[137]=16'd476;
        gain_table[138]=16'd473;
        gain_table[139]=16'd470;
        gain_table[140]=16'd466;
        gain_table[141]=16'd463;
        gain_table[142]=16'd460;
        gain_table[143]=16'd457;
        gain_table[144]=16'd453;
        gain_table[145]=16'd450;
        gain_table[146]=16'd447;
        gain_table[147]=16'd444;
        gain_table[148]=16'd441;
        gain_table[149]=16'd438;
        gain_table[150]=16'd435;
        gain_table[151]=16'd432;
        gain_table[152]=16'd429;
        gain_table[153]=16'd427;
        gain_table[154]=16'd424;
        gain_table[155]=16'd421;
        gain_table[156]=16'd418;
        gain_table[157]=16'd416;
        gain_table[158]=16'd413;
        gain_table[159]=16'd411;
        gain_table[160]=16'd408;
        gain_table[161]=16'd405;
        gain_table[162]=16'd403;
        gain_table[163]=16'd400;
        gain_table[164]=16'd398;
        gain_table[165]=16'd396;
        gain_table[166]=16'd393;
        gain_table[167]=16'd391;
        gain_table[168]=16'd389;
        gain_table[169]=16'd386;
        gain_table[170]=16'd384;
        gain_table[171]=16'd382;
        gain_table[172]=16'd380;
        gain_table[173]=16'd377;
        gain_table[174]=16'd375;
        gain_table[175]=16'd373;
        gain_table[176]=16'd371;
        gain_table[177]=16'd369;
        gain_table[178]=16'd367;
        gain_table[179]=16'd365;
        gain_table[180]=16'd363;
        gain_table[181]=16'd361;
        gain_table[182]=16'd359;
        gain_table[183]=16'd357;
        gain_table[184]=16'd355;
        gain_table[185]=16'd353;
        gain_table[186]=16'd351;
        gain_table[187]=16'd349;
        gain_table[188]=16'd347;
        gain_table[189]=16'd345;
        gain_table[190]=16'd344;
        gain_table[191]=16'd342;
        gain_table[192]=16'd340;
        gain_table[193]=16'd338;
        gain_table[194]=16'd336;
        gain_table[195]=16'd335;
        gain_table[196]=16'd333;
        gain_table[197]=16'd331;
        gain_table[198]=16'd330;
        gain_table[199]=16'd328;
        gain_table[200]=16'd326;
        gain_table[201]=16'd325;
        gain_table[202]=16'd323;
        gain_table[203]=16'd322;
        gain_table[204]=16'd320;
        gain_table[205]=16'd318;
        gain_table[206]=16'd317;
        gain_table[207]=16'd315;
        gain_table[208]=16'd314;
        gain_table[209]=16'd312;
        gain_table[210]=16'd311;
        gain_table[211]=16'd309;
        gain_table[212]=16'd308;
        gain_table[213]=16'd306;
        gain_table[214]=16'd305;
        gain_table[215]=16'd304;
        gain_table[216]=16'd302;
        gain_table[217]=16'd301;
        gain_table[218]=16'd299;
        gain_table[219]=16'd298;
        gain_table[220]=16'd297;
        gain_table[221]=16'd295;
        gain_table[222]=16'd294;
        gain_table[223]=16'd293;
        gain_table[224]=16'd291;
        gain_table[225]=16'd290;
        gain_table[226]=16'd289;
        gain_table[227]=16'd288;
        gain_table[228]=16'd286;
        gain_table[229]=16'd285;
        gain_table[230]=16'd284;
        gain_table[231]=16'd283;
        gain_table[232]=16'd281;
        gain_table[233]=16'd280;
        gain_table[234]=16'd279;
        gain_table[235]=16'd278;
        gain_table[236]=16'd277;
        gain_table[237]=16'd275;
        gain_table[238]=16'd274;
        gain_table[239]=16'd273;
        gain_table[240]=16'd272;
        gain_table[241]=16'd271;
        gain_table[242]=16'd270;
        gain_table[243]=16'd269;
        gain_table[244]=16'd268;
        gain_table[245]=16'd266;
        gain_table[246]=16'd265;
        gain_table[247]=16'd264;
        gain_table[248]=16'd263;
        gain_table[249]=16'd262;
        gain_table[250]=16'd261;
        gain_table[251]=16'd260;
        gain_table[252]=16'd259;
        gain_table[253]=16'd258;
        gain_table[254]=16'd257;
        gain_table[255]=16'd256;
    end
    always @(posedge clk) gain_lookup<=gain_table[lookup_range];
    wire frame_end=in_frame_vsync_d && !in_frame_vsync;
    wire [7:0] frame_range=frame_max-frame_min;

    // Three-stage pixel pipeline: subtract, multiply, round/saturate.
    reg [7:0]  diff_s1;
    reg [23:0] product_s2;
    reg        vsync_s1, vsync_s2;
    reg        href_s1,  href_s2;
    reg        de_s1,    de_s2;

    wire [23:0] product_full    = diff_s1 * gain_q8;
    wire [23:0] rounded_product = product_s2 + 24'd128;
    wire [15:0] scaled_gray_q8  = rounded_product[23:8];
    wire [7:0]  gray_eq_s3 = (|scaled_gray_q8[15:8]) ?
                                      8'hff : scaled_gray_q8[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
            vsync_s1        <= 1'b0;
            vsync_s2        <= 1'b0;
            href_s1         <= 1'b0;
            href_s2         <= 1'b0;
            de_s1           <= 1'b0;
            de_s2           <= 1'b0;
            diff_s1         <= 8'd0;
            product_s2      <= 24'd0;
            in_frame_vsync_d <= 1'b0;
            frame_min       <= 8'hFF;
            frame_max       <= 8'h00;
            latched_min     <= 8'd0;
            latched_max     <= 8'hFF;
        end else begin
            in_frame_vsync_d <= in_frame_vsync;

            vsync_s1   <= in_frame_vsync;
            href_s1    <= in_frame_href;
            de_s1      <= in_frame_de;
            diff_s1    <= (in_gray > latched_min) ?
                                      (in_gray - latched_min) : 8'd0;

            vsync_s2   <= vsync_s1;
            href_s2    <= href_s1;
            de_s2      <= de_s1;
            product_s2 <= product_full;

            out_frame_vsync <= vsync_s2;
            out_frame_href  <= href_s2;
            out_frame_de    <= de_s2;
            out_rgb         <= {gray_eq_s3, gray_eq_s3, gray_eq_s3};

            if (frame_end) begin
                if (frame_min <= frame_max) begin
                    latched_min <= frame_min;
                    latched_max <= frame_max;
                end
                frame_min <= 8'hFF;
                frame_max <= 8'h00;
            end else if (in_frame_de) begin
                if (in_gray < frame_min) frame_min <= in_gray;
                if (in_gray > frame_max) frame_max <= in_gray;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            div_busy<=0;div_count<=0;lookup_range<=8'd1;gain_q8<=16'd256;
        end else begin
            if(frame_end && (frame_min<=frame_max)) begin
                if(frame_range==0) begin gain_q8<=0;div_busy<=0;end
                else begin div_busy<=1;div_count<=0;lookup_range<=frame_range;end
            end else if(div_busy) begin
                if(div_count==5'd16) begin gain_q8<=gain_lookup;div_busy<=0;end
                else div_count<=div_count+1'b1;
            end
        end
    end
endmodule

//Sobel��Ե��⣨3��3 �����ˣ�
// Compatibility entry: private row stores retain the standalone contract.
module video_proc_sobel #(
    parameter integer VIDEO_WIDTH=1280,VIDEO_HEIGHT=720,
    parameter USE_HREF=0
)(
    input clk,rst_n,in_frame_vsync,in_frame_href,in_frame_de,
    input [7:0] in_gray,
    output out_frame_vsync,out_frame_href,out_frame_de,
    output [23:0] out_rgb
);
    video_proc_sobel_rows #(.VIDEO_WIDTH(VIDEO_WIDTH),.VIDEO_HEIGHT(VIDEO_HEIGHT),
        .USE_HREF(USE_HREF),.EXTERNAL_ROWS(0)) u_rows (
        .clk(clk),.rst_n(rst_n),.in_frame_vsync(in_frame_vsync),
        .in_frame_href(in_frame_href),.in_frame_de(in_frame_de),.in_gray(in_gray),
        .out_frame_vsync(out_frame_vsync),.out_frame_href(out_frame_href),
        .out_frame_de(out_frame_de),.out_rgb(out_rgb),
        .shared_row1(8'd0),.shared_row2(8'd0),.shared_enable(1'b1));
endmodule

module video_proc_sobel_rows #(
    parameter integer VIDEO_WIDTH  = 1280,
    parameter integer VIDEO_HEIGHT = 720,
    parameter integer EXTERNAL_ROWS = 0,
    parameter USE_HREF = 0 // 0: ʹ�� DE+�м����ж��н�����1: ʹ�� href �½����ж��н���
)(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb,
    input [7:0] shared_row1,shared_row2,
    input shared_enable
);
    wire window_de=EXTERNAL_ROWS?(in_frame_de && shared_enable):in_frame_de;
    // Verilog-2001 ���ݣ�����ʹ�� $clog2��1280 ������Ҫ 11 bits��
    // ������ VIDEO_WIDTH�����ֶ����� COL_WIDTH ���Ϊ����������
    localparam integer COL_WIDTH = 11;

    reg [COL_WIDTH-1:0] col_cnt = {COL_WIDTH{1'b0}};
    // Exact warm-up state for ordinary heights: only row==0 vs row>=1
    // is observable. Unusual integer parameters retain the legacy counter.
    localparam integer ROW_STATE_WIDTH=(VIDEO_HEIGHT>=2 && VIDEO_HEIGHT<=65536)?1:16;
    reg [ROW_STATE_WIDTH-1:0] row_cnt = 0;
    // ȡ���� href ��Ӳ������ʹ�� de ��Ϊ�л��־������������ href ���´�����Զ��Ч
    reg                 in_href_d = 1'b0; // ��������͸�����������߼����� window_de
    reg                 in_de_d    = 1'b0; // ǰһ���� de�����ڼ���н���
    reg                 in_vsync_d = 1'b0;

    reg frame_vsync_d0 = 1'b0;
    reg frame_vsync_d1 = 1'b0;
    reg frame_href_d0  = 1'b0;
    reg frame_href_d1  = 1'b0;
    reg frame_de_d0    = 1'b0;
    reg frame_de_d1    = 1'b0;

    reg window_h_ready = 1'b0;
    reg window_h_ready_d = 1'b0;
    reg window_v_ready = 1'b0;
    reg window_v_ready_d = 1'b0;



    reg [7:0] win00 = 8'd0, win01 = 8'd0, win02 = 8'd0;
    reg [7:0] win10 = 8'd0, win11 = 8'd0, win12 = 8'd0;
    reg [7:0] win20 = 8'd0, win21 = 8'd0, win22 = 8'd0;

    wire [7:0] prev_row1_pixel,prev_row2_pixel;
    generate if(EXTERNAL_ROWS) begin : external_rows
        assign prev_row1_pixel=shared_row1;
        assign prev_row2_pixel=shared_row2;
    end else begin : private_rows
    (* ram_style = "bram" *) reg [7:0] line_buffer0 [0:VIDEO_WIDTH-1];
    (* ram_style = "bram" *) reg [7:0] line_buffer1 [0:VIDEO_WIDTH-1];
    // Prefetch the address that col_cnt will have AFTER this edge.
    // The synchronous RAM output supplies the existing window on the next
    // edge: no extra window, RGB, or control latency.
    wire [COL_WIDTH-1:0] prefetch_addr = (!rst_n || !window_de || col_cnt == VIDEO_WIDTH-1)
                                      ? {COL_WIDTH{1'b0}} : col_cnt + 1'b1;
    reg [7:0] row1_read, row2_read;
    reg prefetch_collision;
    reg [7:0] row1_forward, row2_forward;
    wire [7:0] local_prev_row1_pixel = prefetch_collision ? row1_forward : row1_read;
    wire [7:0] local_prev_row2_pixel = prefetch_collision ? row2_forward : row2_read;
    // Write forwarding removes dependence on RAM read-during-write mode.
    // It is needed for a held last column, DE bubbles, and width=1.
    // No reset on RAM data/read registers, allowing synchronous ERAM.
    always @(posedge clk) begin
        row1_read <= line_buffer0[prefetch_addr];
        row2_read <= line_buffer1[prefetch_addr];
        prefetch_collision <= rst_n && window_de && (prefetch_addr == col_cnt);
        row1_forward <= in_gray;
        row2_forward <= local_prev_row1_pixel;
        if (rst_n && window_de) begin
            line_buffer0[col_cnt] <= in_gray;
            line_buffer1[col_cnt] <= local_prev_row1_pixel;
        end
    end
        assign prev_row1_pixel=local_prev_row1_pixel;
        assign prev_row2_pixel=local_prev_row2_pixel;
    end endgenerate

    // �н�����
    // USE_HREF=1 ʱ�� href �½��أ�����ʹ���м����� VIDEO_WIDTH-1 ������һ���ڸ�λ
    wire line_end_href = in_href_d && !in_frame_href; // ���� USE_HREF=1 ��Ч
    wire line_end_cnt  = (window_de && (col_cnt == VIDEO_WIDTH-1));
    wire line_end      = USE_HREF ? line_end_href : line_end_cnt;
    wire frame_start = !in_vsync_d && in_frame_vsync;

    // Sobel kernel (Gx / Gy)
    // | -1  0  1 |       | -1 -2 -1 |
    // | -2  0  2 |   &   |  0  0  0 |
    // | -1  0  1 |       |  1  2  1 |

        wire signed [10:0] gx =
                    ($signed({1'b0, win02}) - $signed({1'b0, win00}))
                + (($signed({1'b0, win12}) - $signed({1'b0, win10})) << 1)
                + ($signed({1'b0, win22}) - $signed({1'b0, win20}));

        wire signed [10:0] gy =
                    ($signed({1'b0, win20}) - $signed({1'b0, win00}))
                + (($signed({1'b0, win21}) - $signed({1'b0, win01})) << 1)
                + ($signed({1'b0, win22}) - $signed({1'b0, win02}));

    wire [10:0] abs_gx = gx[10] ? (~gx + 11'd1) : gx;
    wire [10:0] abs_gy = gy[10] ? (~gy + 11'd1) : gy;
    wire [10:0] mag_sum = abs_gx + abs_gy;
    wire [7:0] edge_val = (mag_sum > 11'd255) ? 8'hFF : mag_sum[7:0];
    // pixel_ready ��ʾ��ǰ���� 3x3 �����Ѿ����ã�������Եǰ������ǰ���У�
    wire pixel_ready = window_h_ready_d && window_v_ready_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
            col_cnt         <= {COL_WIDTH{1'b0}};
            row_cnt         <= 16'd0;
            in_href_d       <= 1'b0;
            in_vsync_d      <= 1'b0;
            frame_vsync_d0  <= 1'b0;
            frame_vsync_d1  <= 1'b0;
            frame_href_d0   <= 1'b0;
            frame_href_d1   <= 1'b0;
            frame_de_d0     <= 1'b0;
            frame_de_d1     <= 1'b0;
            window_h_ready  <= 1'b0;
            window_h_ready_d <= 1'b0;
            window_v_ready  <= 1'b0;
            window_v_ready_d <= 1'b0;
            win00 <= 8'd0; win01 <= 8'd0; win02 <= 8'd0;
            win10 <= 8'd0; win11 <= 8'd0; win12 <= 8'd0;
            win20 <= 8'd0; win21 <= 8'd0; win22 <= 8'd0;
        end else begin
            in_href_d  <= in_frame_href;
            in_de_d    <= in_frame_de;
            in_vsync_d <= in_frame_vsync;

            frame_vsync_d0 <= in_frame_vsync;
            frame_vsync_d1 <= frame_vsync_d0;
            frame_href_d0  <= in_frame_href;
            frame_href_d1  <= frame_href_d0;
            frame_de_d0    <= in_frame_de;
            frame_de_d1    <= frame_de_d0;

            window_h_ready_d <= window_h_ready;
            window_v_ready_d <= window_v_ready;

            // �����ͬ���źű����������ӳٶ��룬����ʹ�ܲ��ٰ� pixel_valid ���ˣ������ϲ㱣����/֡ʱ������
            out_frame_vsync <= frame_vsync_d1;
            out_frame_href  <= frame_href_d1;
            out_frame_de    <= frame_de_d1;

            // �м�����ʹ�� DE ��Ч���ڼ�һ���н������е�ĩβ����λ
            if (!window_de) begin
                // �հ׻��м��������
                col_cnt        <= {COL_WIDTH{1'b0}};
                window_h_ready <= 1'b0;
            end else begin
                if (col_cnt == VIDEO_WIDTH-1) begin
                    col_cnt        <= {COL_WIDTH{1'b0}};
                    window_h_ready <= 1'b0; // ���������ۻ�
                end else begin
                    col_cnt <= col_cnt + {{(COL_WIDTH-1){1'b0}},1'b1};
                    if (col_cnt >= 2) window_h_ready <= 1'b1;
                end
            end

            if (frame_start) begin
                row_cnt        <= 16'd0;
                window_v_ready <= 1'b0;
            end else if (line_end) begin
                if (ROW_STATE_WIDTH==1) begin
                    row_cnt <= 1'b1;
                end else if (row_cnt < VIDEO_HEIGHT-1) begin
                    row_cnt <= row_cnt + 16'd1;
                end else begin
                    row_cnt <= row_cnt; // ���ͱ���
                end
                if (row_cnt >= 16'd1) window_v_ready <= 1'b1;
            end

            if (!window_de) begin
                // ���ִ�������ֱ�������׸���Ч����
                win00 <= 8'd0; win01 <= 8'd0; win02 <= 8'd0;
                win10 <= 8'd0; win11 <= 8'd0; win12 <= 8'd0;
                win20 <= 8'd0; win21 <= 8'd0; win22 <= 8'd0;
            end else begin
                win00 <= win01;
                win01 <= win02;
                win02 <= prev_row2_pixel;

                win10 <= win11;
                win11 <= win12;
                win12 <= prev_row1_pixel;

                win20 <= win21;
                win21 <= win22;
                win22 <= in_gray;

                // Line RAM writes are in the synchronous prefetch block.
            end

            // ���ڴ���׼����ʱ�����Եֵ���������0������ DE = 1 ����ʾ���ܿ�����ɫ�߿���Ƕ�ʧ����
            if (frame_de_d1) begin
                if (pixel_ready) begin
                    out_rgb <= {edge_val, edge_val, edge_val};
                end else begin
                    out_rgb <= 24'd0; // ��Ե��0
                end
            end else begin
                out_rgb <= 24'd0;
            end
        end
    end
endmodule

//��Ƶ���ţ��򵥶����²���+���ƣ�VIDEO_WIDTH����Ϊż����

// ֱ��ͼ���⻯ + ���½�ͼ�� (������) ��ͼ��ռ���� 256���߶� 128����֡���½Ǹ���
// �Ҷȷ��ࣨ����ʾ���ܣ��滻ԭֱ��ͼ����ģ�飩
module video_proc_invert(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    wire [7:0] inv_gray = 8'd255 - in_gray;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
        end else begin
            out_frame_vsync <= in_frame_vsync;
            out_frame_href  <= in_frame_href;
            out_frame_de    <= in_frame_de;
            out_rgb         <= {inv_gray, inv_gray, inv_gray};
        end
    end
endmodule

// ���� / �Աȶ� ����: ��� = clip( ( (in_gray-128)*CONTRAST_NUM/CONTRAST_DEN ) + 128 + BRIGHTNESS )

// �ü���ֻ��ʾ���� 1/4 �������������
// Standalone menu effect removed; old command selects original pixels.

//��˹�˲���3��3 �����ˣ�
// Compatibility entry: private row stores retain the standalone contract.
module video_proc_gaussian #(
    parameter integer VIDEO_WIDTH=1280,VIDEO_HEIGHT=720,
    parameter USE_HREF=0
)(
    input clk,rst_n,in_frame_vsync,in_frame_href,in_frame_de,
    input [7:0] in_gray,
    output out_frame_vsync,out_frame_href,out_frame_de,
    output [23:0] out_rgb
);
    video_proc_gaussian_rows #(.VIDEO_WIDTH(VIDEO_WIDTH),.VIDEO_HEIGHT(VIDEO_HEIGHT),
        .USE_HREF(USE_HREF),.EXTERNAL_ROWS(0)) u_rows (
        .clk(clk),.rst_n(rst_n),.in_frame_vsync(in_frame_vsync),
        .in_frame_href(in_frame_href),.in_frame_de(in_frame_de),.in_gray(in_gray),
        .out_frame_vsync(out_frame_vsync),.out_frame_href(out_frame_href),
        .out_frame_de(out_frame_de),.out_rgb(out_rgb),
        .shared_row1(8'd0),.shared_row2(8'd0),.shared_enable(1'b1));
endmodule

module video_proc_gaussian_rows #(
    parameter integer VIDEO_WIDTH  = 1280,
    parameter integer VIDEO_HEIGHT = 720,
    parameter integer EXTERNAL_ROWS = 0,
    parameter USE_HREF = 0
)(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb,
    input [7:0] shared_row1,shared_row2,
    input shared_enable
);
    wire window_de=EXTERNAL_ROWS?(in_frame_de && shared_enable):in_frame_de;
    localparam integer COL_WIDTH = 11; // 1280 ������Ҫ 11 bits

    reg [COL_WIDTH-1:0] col_cnt = {COL_WIDTH{1'b0}};
    // Exact warm-up state for ordinary heights: only row==0 vs row>=1
    // is observable. Unusual integer parameters retain the legacy counter.
    localparam integer ROW_STATE_WIDTH=(VIDEO_HEIGHT>=2 && VIDEO_HEIGHT<=65536)?1:16;
    reg [ROW_STATE_WIDTH-1:0] row_cnt = 0;
    reg                 line_end_pending = 1'b0; // ������ĩ�е����ȴ� DE �����ٸ�λ
    reg                 in_href_d = 1'b0;
    reg                 in_de_d    = 1'b0; // ǰһ���� de
    reg                 in_vsync_d = 1'b0;

    reg frame_vsync_d0 = 1'b0;
    reg frame_vsync_d1 = 1'b0;
    reg frame_href_d0  = 1'b0;
    reg frame_href_d1  = 1'b0;
    reg frame_de_d0    = 1'b0;
    reg frame_de_d1    = 1'b0;

    reg window_h_ready = 1'b0;
    reg window_h_ready_d = 1'b0;
    reg window_v_ready = 1'b0;
    reg window_v_ready_d = 1'b0;



    reg [7:0] win00 = 8'd0, win01 = 8'd0, win02 = 8'd0;
    reg [7:0] win10 = 8'd0, win11 = 8'd0, win12 = 8'd0;
    reg [7:0] win20 = 8'd0, win21 = 8'd0, win22 = 8'd0;

    wire [7:0] prev_row1_pixel,prev_row2_pixel;
    generate if(EXTERNAL_ROWS) begin : external_rows
        assign prev_row1_pixel=shared_row1;
        assign prev_row2_pixel=shared_row2;
    end else begin : private_rows
    (* ram_style = "bram" *) reg [7:0] line_buffer0 [0:VIDEO_WIDTH-1];
    (* ram_style = "bram" *) reg [7:0] line_buffer1 [0:VIDEO_WIDTH-1];
    // Same prefetch/forwarding structure as the existing Sobel/erosion RAMs.
    // Read the column that col_cnt will have after this edge. The old window
    // sees the correct row on the next edge, without another video stage.
    wire [COL_WIDTH-1:0] prefetch_addr = (!rst_n || !window_de) ? {COL_WIDTH{1'b0}} :
        ((line_end_pending || col_cnt == VIDEO_WIDTH-1) ? col_cnt : col_cnt + 1'b1);
    reg [7:0] row1_read, row2_read;
    reg prefetch_collision;
    reg [7:0] row1_forward, row2_forward;
    wire [7:0] local_prev_row1_pixel = prefetch_collision ? row1_forward : row1_read;
    wire [7:0] local_prev_row2_pixel = prefetch_collision ? row2_forward : row2_read;
    always @(posedge clk) begin
        row1_read <= line_buffer0[prefetch_addr];
        row2_read <= line_buffer1[prefetch_addr];
        prefetch_collision <= rst_n && window_de && (prefetch_addr == col_cnt);
        row1_forward <= in_gray;
        row2_forward <= local_prev_row1_pixel;
        if (rst_n && window_de) begin
            line_buffer0[col_cnt] <= in_gray;
            line_buffer1[col_cnt] <= local_prev_row1_pixel;
        end
    end
        assign prev_row1_pixel=local_prev_row1_pixel;
        assign prev_row2_pixel=local_prev_row2_pixel;
    end endgenerate

    wire line_end_href = in_href_d && !in_frame_href;
    wire last_col_hit  = (window_de && (col_cnt == VIDEO_WIDTH-1));
    wire line_end      = USE_HREF ? line_end_href : last_col_hit; // �н����ж�����ĩ����������
    wire frame_start   = !in_vsync_d && in_frame_vsync;

    // Gaussian kernel
    // | 1  2  1 |
    // | 2  4  2 |  >> 4
    // | 1  2  1 |

    wire [11:0] blur_sum =
          win00 + (win01 << 1) + win02
        + (win10 << 1) + (win11 << 2) + (win12 << 1)
        + win20 + (win21 << 1) + win22;

    wire [7:0] blur_val = blur_sum >> 4;
    // �� Sobel �޸�һ�£�pixel_ready ��ָ������Ч����� DE ��������������ӳٰ汾
    wire pixel_ready = window_h_ready_d && window_v_ready_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame_vsync <= 1'b0;
            out_frame_href  <= 1'b0;
            out_frame_de    <= 1'b0;
            out_rgb         <= 24'd0;
            col_cnt         <= {COL_WIDTH{1'b0}};
            row_cnt         <= 16'd0;
            in_href_d       <= 1'b0;
            in_vsync_d      <= 1'b0;
            frame_vsync_d0  <= 1'b0;
            frame_vsync_d1  <= 1'b0;
            frame_href_d0   <= 1'b0;
            frame_href_d1   <= 1'b0;
            frame_de_d0     <= 1'b0;
            frame_de_d1     <= 1'b0;
            window_h_ready  <= 1'b0;
            window_h_ready_d <= 1'b0;
            window_v_ready  <= 1'b0;
            window_v_ready_d <= 1'b0;
            win00 <= 8'd0; win01 <= 8'd0; win02 <= 8'd0;
            win10 <= 8'd0; win11 <= 8'd0; win12 <= 8'd0;
            win20 <= 8'd0; win21 <= 8'd0; win22 <= 8'd0;
        end else begin
            in_href_d  <= in_frame_href;
            in_de_d    <= in_frame_de;
            in_vsync_d <= in_frame_vsync;

            frame_vsync_d0 <= in_frame_vsync;
            frame_vsync_d1 <= frame_vsync_d0;
            frame_href_d0  <= in_frame_href;
            frame_href_d1  <= frame_href_d0;
            frame_de_d0    <= in_frame_de;
            frame_de_d1    <= frame_de_d0;

            window_h_ready_d <= window_h_ready;
            window_v_ready_d <= window_v_ready;

            out_frame_vsync <= frame_vsync_d1;
            out_frame_href  <= frame_href_d1;
            out_frame_de    <= frame_de_d1;

            // ���м������ԣ�ĩ�����е������Ա��� col_cnt=VIDEO_WIDTH-1���� line_end_pending��
            // �����Ŀհ����� (window_de==0) �Ÿ�λ col_cnt �� window_h_ready��
            if (!window_de) begin
                if (line_end_pending) begin
                    col_cnt        <= {COL_WIDTH{1'b0}};
                    window_h_ready <= 1'b0;
                    line_end_pending <= 1'b0;
                end else begin
                    col_cnt        <= {COL_WIDTH{1'b0}};
                    window_h_ready <= 1'b0;
                end
            end else begin
                if (!line_end_pending) begin
                    if (col_cnt == VIDEO_WIDTH-1) begin
                        // ����ĩ�У����ּ���ֵ����ǵȴ�
                        line_end_pending <= 1'b1;
                        // �������� window_h_ready������ĩ����������ʹ�ô���
                        if (col_cnt >= 2) window_h_ready <= 1'b1;
                    end else begin
                        col_cnt <= col_cnt + {{(COL_WIDTH-1){1'b0}},1'b1};
                        if (col_cnt >= 2) window_h_ready <= 1'b1;
                    end
                end
            end

            if (frame_start) begin
                row_cnt        <= 16'd0;
                window_v_ready <= 1'b0;
            end else if (line_end && last_col_hit) begin
                // �н�������ĩ���������ڼ��� +1������հ����ظ��ӣ�
                if (ROW_STATE_WIDTH==1) row_cnt <= 1'b1;
                else if (row_cnt < VIDEO_HEIGHT-1) row_cnt <= row_cnt + 16'd1; else row_cnt <= row_cnt;
                if (row_cnt >= 16'd1) window_v_ready <= 1'b1;
            end

            if (!window_de) begin
                win00 <= 8'd0; win01 <= 8'd0; win02 <= 8'd0;
                win10 <= 8'd0; win11 <= 8'd0; win12 <= 8'd0;
                win20 <= 8'd0; win21 <= 8'd0; win22 <= 8'd0;
            end else begin
                win00 <= win01;
                win01 <= win02;
                win02 <= prev_row2_pixel;

                win10 <= win11;
                win11 <= win12;
                win12 <= prev_row1_pixel;

                win20 <= win21;
                win21 <= win22;
                win22 <= in_gray;

                // Line RAM writes are in the synchronous prefetch block.
            end

            if (frame_de_d1) begin
                if (pixel_ready) begin
                    out_rgb <= {blur_val, blur_val, blur_val};
                end else begin
                    out_rgb <= 24'd0; // ��Ե��0
                end
            end else begin
                out_rgb <= 24'd0;
            end
        end
    end
endmodule

//��ʴ��3��3 �ṹԪ�أ�
// Standalone menu effect removed; old command selects original pixels.

// ٤��У��ģ�飺ʹ�ô� LUT (LUT_POINTS) + ���Բ�ֵ��Ĭ�� gamma=2.20
module video_proc_gamma #(
    parameter integer GAMMA_SCALE = 220,      // 2.20 => ����Ҷ�^(1/��)�������ü��ݽ��� LUT
    parameter integer LUT_POINTS  = 64,
    parameter integer VIDEO_WIDTH = 1280,
    parameter integer VIDEO_HEIGHT= 720
)(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    // Sixteen coarse bands from the previous curve. Dark/highlight bands
    // deliberately map to black/white; no interpolation, DSP or block RAM.
    reg [7:0] coarse_value;
    reg initialized;
    always @(posedge clk) begin
        case(in_gray[7:4])
            4'd0: coarse_value<=8'd0;
            4'd1: coarse_value<=8'd76;
            4'd2: coarse_value<=8'd94;
            4'd3: coarse_value<=8'd108;
            4'd4: coarse_value<=8'd120;
            4'd5: coarse_value<=8'd130;
            4'd6: coarse_value<=8'd140;
            4'd7: coarse_value<=8'd150;
            4'd8: coarse_value<=8'd159;
            4'd9: coarse_value<=8'd168;
            4'd10: coarse_value<=8'd176;
            4'd11: coarse_value<=8'd184;
            4'd12: coarse_value<=8'd192;
            4'd13: coarse_value<=8'd200;
            4'd14: coarse_value<=8'd207;
            4'd15: coarse_value<=8'd255;
            default: coarse_value<=8'd0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            initialized<=0;out_frame_vsync<=0;out_frame_href<=0;out_frame_de<=0;
        end else begin
            initialized<=1;out_frame_vsync<=in_frame_vsync;
            out_frame_href<=in_frame_href;out_frame_de<=in_frame_de;
        end
    end
    always @* out_rgb=(initialized && out_frame_de) ? {coarse_value,coarse_value,coarse_value} : 24'd0;
endmodule

// �Ҷ�α�ʣ��ֶ��ݶ� (Blue->Cyan->Green->Yellow->Red)
module video_proc_false_color(
    input        clk,
    input        rst_n,
    input        in_frame_vsync,
    input        in_frame_href,
    input        in_frame_de,
    input  [7:0] in_gray,
    output reg   out_frame_vsync,
    output reg   out_frame_href,
    output reg   out_frame_de,
    output reg [23:0] out_rgb
);
    // Exact current curve/segment endpoints; initialization has no runtime math.
    (* ram_style="bram" *) reg [23:0] values[0:255];
    reg [23:0] rom_value;
    reg initialized;
    initial begin
        values[0]=24'h0000ff;
        values[1]=24'h0005ff;
        values[2]=24'h000aff;
        values[3]=24'h000fff;
        values[4]=24'h0014ff;
        values[5]=24'h0019ff;
        values[6]=24'h001eff;
        values[7]=24'h0023ff;
        values[8]=24'h0028ff;
        values[9]=24'h002dff;
        values[10]=24'h0032ff;
        values[11]=24'h0037ff;
        values[12]=24'h003cff;
        values[13]=24'h0041ff;
        values[14]=24'h0046ff;
        values[15]=24'h004bff;
        values[16]=24'h0050ff;
        values[17]=24'h0055ff;
        values[18]=24'h005aff;
        values[19]=24'h005fff;
        values[20]=24'h0064ff;
        values[21]=24'h0069ff;
        values[22]=24'h006eff;
        values[23]=24'h0073ff;
        values[24]=24'h0078ff;
        values[25]=24'h007dff;
        values[26]=24'h0082ff;
        values[27]=24'h0087ff;
        values[28]=24'h008cff;
        values[29]=24'h0091ff;
        values[30]=24'h0096ff;
        values[31]=24'h009bff;
        values[32]=24'h00a0ff;
        values[33]=24'h00a5ff;
        values[34]=24'h00aaff;
        values[35]=24'h00afff;
        values[36]=24'h00b4ff;
        values[37]=24'h00b9ff;
        values[38]=24'h00beff;
        values[39]=24'h00c3ff;
        values[40]=24'h00c8ff;
        values[41]=24'h00cdff;
        values[42]=24'h00d2ff;
        values[43]=24'h00d7ff;
        values[44]=24'h00dcff;
        values[45]=24'h00e1ff;
        values[46]=24'h00e6ff;
        values[47]=24'h00ebff;
        values[48]=24'h00f0ff;
        values[49]=24'h00f5ff;
        values[50]=24'h00faff;
        values[51]=24'h00ffff;
        values[52]=24'h00ffff;
        values[53]=24'h00fffa;
        values[54]=24'h00fff5;
        values[55]=24'h00fff0;
        values[56]=24'h00ffeb;
        values[57]=24'h00ffe6;
        values[58]=24'h00ffe1;
        values[59]=24'h00ffdc;
        values[60]=24'h00ffd7;
        values[61]=24'h00ffd2;
        values[62]=24'h00ffcd;
        values[63]=24'h00ffc8;
        values[64]=24'h00ffc3;
        values[65]=24'h00ffbe;
        values[66]=24'h00ffb9;
        values[67]=24'h00ffb4;
        values[68]=24'h00ffaf;
        values[69]=24'h00ffaa;
        values[70]=24'h00ffa5;
        values[71]=24'h00ffa0;
        values[72]=24'h00ff9b;
        values[73]=24'h00ff96;
        values[74]=24'h00ff91;
        values[75]=24'h00ff8c;
        values[76]=24'h00ff87;
        values[77]=24'h00ff82;
        values[78]=24'h00ff7d;
        values[79]=24'h00ff78;
        values[80]=24'h00ff73;
        values[81]=24'h00ff6e;
        values[82]=24'h00ff69;
        values[83]=24'h00ff64;
        values[84]=24'h00ff5f;
        values[85]=24'h00ff5a;
        values[86]=24'h00ff55;
        values[87]=24'h00ff50;
        values[88]=24'h00ff4b;
        values[89]=24'h00ff46;
        values[90]=24'h00ff41;
        values[91]=24'h00ff3c;
        values[92]=24'h00ff37;
        values[93]=24'h00ff32;
        values[94]=24'h00ff2d;
        values[95]=24'h00ff28;
        values[96]=24'h00ff23;
        values[97]=24'h00ff1e;
        values[98]=24'h00ff19;
        values[99]=24'h00ff14;
        values[100]=24'h00ff0f;
        values[101]=24'h00ff0a;
        values[102]=24'h00ff05;
        values[103]=24'h00ff00;
        values[104]=24'h05ff00;
        values[105]=24'h0aff00;
        values[106]=24'h0fff00;
        values[107]=24'h14ff00;
        values[108]=24'h19ff00;
        values[109]=24'h1eff00;
        values[110]=24'h23ff00;
        values[111]=24'h28ff00;
        values[112]=24'h2dff00;
        values[113]=24'h32ff00;
        values[114]=24'h37ff00;
        values[115]=24'h3cff00;
        values[116]=24'h41ff00;
        values[117]=24'h46ff00;
        values[118]=24'h4bff00;
        values[119]=24'h50ff00;
        values[120]=24'h55ff00;
        values[121]=24'h5aff00;
        values[122]=24'h5fff00;
        values[123]=24'h64ff00;
        values[124]=24'h69ff00;
        values[125]=24'h6eff00;
        values[126]=24'h73ff00;
        values[127]=24'h78ff00;
        values[128]=24'h7dff00;
        values[129]=24'h82ff00;
        values[130]=24'h87ff00;
        values[131]=24'h8cff00;
        values[132]=24'h91ff00;
        values[133]=24'h96ff00;
        values[134]=24'h9bff00;
        values[135]=24'ha0ff00;
        values[136]=24'ha5ff00;
        values[137]=24'haaff00;
        values[138]=24'hafff00;
        values[139]=24'hb4ff00;
        values[140]=24'hb9ff00;
        values[141]=24'hbeff00;
        values[142]=24'hc3ff00;
        values[143]=24'hc8ff00;
        values[144]=24'hcdff00;
        values[145]=24'hd2ff00;
        values[146]=24'hd7ff00;
        values[147]=24'hdcff00;
        values[148]=24'he1ff00;
        values[149]=24'he6ff00;
        values[150]=24'hebff00;
        values[151]=24'hf0ff00;
        values[152]=24'hf5ff00;
        values[153]=24'hfaff00;
        values[154]=24'hffff00;
        values[155]=24'hfffa00;
        values[156]=24'hfff500;
        values[157]=24'hfff000;
        values[158]=24'hffeb00;
        values[159]=24'hffe600;
        values[160]=24'hffe100;
        values[161]=24'hffdc00;
        values[162]=24'hffd700;
        values[163]=24'hffd200;
        values[164]=24'hffcd00;
        values[165]=24'hffc800;
        values[166]=24'hffc300;
        values[167]=24'hffbe00;
        values[168]=24'hffb900;
        values[169]=24'hffb400;
        values[170]=24'hffaf00;
        values[171]=24'hffaa00;
        values[172]=24'hffa500;
        values[173]=24'hffa000;
        values[174]=24'hff9b00;
        values[175]=24'hff9600;
        values[176]=24'hff9100;
        values[177]=24'hff8c00;
        values[178]=24'hff8700;
        values[179]=24'hff8200;
        values[180]=24'hff7d00;
        values[181]=24'hff7800;
        values[182]=24'hff7300;
        values[183]=24'hff6e00;
        values[184]=24'hff6900;
        values[185]=24'hff6400;
        values[186]=24'hff5f00;
        values[187]=24'hff5a00;
        values[188]=24'hff5500;
        values[189]=24'hff5000;
        values[190]=24'hff4b00;
        values[191]=24'hff4600;
        values[192]=24'hff4100;
        values[193]=24'hff3c00;
        values[194]=24'hff3700;
        values[195]=24'hff3200;
        values[196]=24'hff2d00;
        values[197]=24'hff2800;
        values[198]=24'hff2300;
        values[199]=24'hff1e00;
        values[200]=24'hff1900;
        values[201]=24'hff1400;
        values[202]=24'hff0f00;
        values[203]=24'hff0a00;
        values[204]=24'hff0500;
        values[205]=24'hff0000;
        values[206]=24'hff0000;
        values[207]=24'hff0000;
        values[208]=24'hff0000;
        values[209]=24'hff0000;
        values[210]=24'hff0000;
        values[211]=24'hff0000;
        values[212]=24'hff0000;
        values[213]=24'hff0000;
        values[214]=24'hff0000;
        values[215]=24'hff0000;
        values[216]=24'hff0000;
        values[217]=24'hff0000;
        values[218]=24'hff0000;
        values[219]=24'hff0000;
        values[220]=24'hff0000;
        values[221]=24'hff0000;
        values[222]=24'hff0000;
        values[223]=24'hff0000;
        values[224]=24'hff0000;
        values[225]=24'hff0000;
        values[226]=24'hff0000;
        values[227]=24'hff0000;
        values[228]=24'hff0000;
        values[229]=24'hff0000;
        values[230]=24'hff0000;
        values[231]=24'hff0000;
        values[232]=24'hff0000;
        values[233]=24'hff0000;
        values[234]=24'hff0000;
        values[235]=24'hff0000;
        values[236]=24'hff0000;
        values[237]=24'hff0000;
        values[238]=24'hff0000;
        values[239]=24'hff0000;
        values[240]=24'hff0000;
        values[241]=24'hff0000;
        values[242]=24'hff0000;
        values[243]=24'hff0000;
        values[244]=24'hff0000;
        values[245]=24'hff0000;
        values[246]=24'hff0000;
        values[247]=24'hff0000;
        values[248]=24'hff0000;
        values[249]=24'hff0000;
        values[250]=24'hff0000;
        values[251]=24'hff0000;
        values[252]=24'hff0000;
        values[253]=24'hff0000;
        values[254]=24'hff0000;
        values[255]=24'hff0000;
    end
    always @(posedge clk) rom_value<=values[in_gray];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            initialized<=0;out_frame_vsync<=0;out_frame_href<=0;out_frame_de<=0;
        end else begin
            initialized<=1;out_frame_vsync<=in_frame_vsync;
            out_frame_href<=in_frame_href;out_frame_de<=in_frame_de;
        end
    end
    always @* out_rgb=(initialized && out_frame_de) ? rom_value : 24'd0;
endmodule

// One pixel/clock, two previous rows for the fixed VTC raster. Both kernels
// keep their own readiness and last-column masks. No additional pixel stage.
// Contract: each DE burst is at most VIDEO_WIDTH clocks; there is a blank
// clock between rows. The compatibility modules below retain private RAMs.
module video_filter_row_store #(parameter integer VIDEO_WIDTH=1280)(
    input clk,rst_n,de,input [7:0] gray,
    output [7:0] row1,row2
);
    reg [10:0] col=0;
    wire [10:0] prefetch_addr=(!rst_n || !de || col==VIDEO_WIDTH-1)?11'd0:col+1'b1;
    (* ram_style="bram" *) reg [7:0] line0[0:VIDEO_WIDTH-1];
    (* ram_style="bram" *) reg [7:0] line1[0:VIDEO_WIDTH-1];
    reg [7:0] read0,read1,forward0,forward1;
    reg collision;
    assign row1=collision?forward0:read0;
    assign row2=collision?forward1:read1;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) col<=0;
        else if(!de || col==VIDEO_WIDTH-1) col<=0;
        else col<=col+1'b1;
    // Same synchronous read/write forwarding as the frozen Sobel buffer.
    always @(posedge clk) begin
        read0<=line0[prefetch_addr]; read1<=line1[prefetch_addr];
        collision<=rst_n && de && (prefetch_addr==col);
        forward0<=gray; forward1<=row1;
        if(rst_n && de) begin line0[col]<=gray; line1[col]<=row1; end
    end
endmodule

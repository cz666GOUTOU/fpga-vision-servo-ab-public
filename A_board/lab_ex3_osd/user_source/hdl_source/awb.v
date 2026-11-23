/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
                 让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
                 得它的适用行更加广泛了。
*****************************************************************/
module awb  #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) 
(
    input                   I_clk  ,
    input                   I_rst_n,


    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

/*****************************************************************
                          RGB565תRGB888                                        
*****************************************************************/

    // //RGB565??????888
    // wire [4:0]  rgb565_r   = I_st_data[11+:5];
    // wire [5:0]  rgb565_g   = I_st_data[5+:6];
    // wire [4:0]  rgb565_b   = I_st_data[0+:5];
    
    // wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};
    
    // wire [7:0]  rgb888_r   = rgb888[16+:8];
    // wire [7:0]  rgb888_g   = rgb888[8+:8] ;
    // wire [7:0]  rgb888_b   = rgb888[0+:8] ;
    
  /*****************************************************************
                          中间信号                                        
*****************************************************************/


  reg         I_tvalid_r0,I_tvalid_r1;
  reg  [95:0] I_tdata_d0,I_tdata_d1;


  //累加RGB通道的�??
  // Only specialize the proven 720p four-pixel input contract. One lane is
  // sampled per word: 320*720 samples/frame; even two extra pipeline words
  // give 1+(230400+2)*255=58752511 < 2^26. No gain precision is removed.
  // Other image configurations keep the original complete 32-bit domain.
  localparam integer CHANNEL_SUM_WIDTH =
      (IMG_WIDTH == 1280 && IMG_HEIGHT == 720) ? 26 : 32;
  reg  [CHANNEL_SUM_WIDTH-1:0] sum_r[0:3];
  reg  [CHANNEL_SUM_WIDTH-1:0] sum_g[0:3];
  reg  [CHANNEL_SUM_WIDTH-1:0] sum_b[0:3];

  
  wire  [95:0]        data_d0 ;
  wire                valid_d0;
  wire                I_tuser_r0;    

  reg                 I_tuser_r1;

  reg   [95:0]        data_d1 ;
  reg                 valid_d1;
  reg   [9:0]         rgb_sum[0:3];//每个像素点RGB的和
  /*****************************************************************
                            平均值计�??                                      
*****************************************************************/

// 对输入数据和有效信号进行寄存，形成流水线
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
end

// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d[0:3];
wire [7:0] rgb888_g_d[0:3];
wire [7:0] rgb888_b_d[0:3];

assign  rgb888_r_d[0] = I_tdata[16+:8];
assign  rgb888_g_d[0] = I_tdata[8+:8];
assign  rgb888_b_d[0] = I_tdata[0+:8];


// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d0[0:3];
wire [7:0] rgb888_g_d0[0:3];
wire [7:0] rgb888_b_d0[0:3];

assign  rgb888_r_d0[0] = I_tdata_d0[16+:8];
assign  rgb888_g_d0[0] = I_tdata_d0[8+:8];
assign  rgb888_b_d0[0] = I_tdata_d0[0+:8];


        ///削弱白色
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                rgb_sum[0] <= 0;
            end
            else if(I_tvalid)begin
                rgb_sum[0] <= rgb888_r_d[0] + rgb888_g_d[0] + rgb888_b_d[0];
            end
        end

        // 对每个通道的值进行累加，用于计算平均值
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) begin
                // 复位或行开始信号有效时，清零累加器
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
            end else if (I_tvalid_r0 && (rgb_sum[0] < 720)) begin
                // 当输入有效时，累加RGB分量的值
                sum_r[0] <= sum_r[0] + rgb888_r_d0[0];
                sum_g[0] <= sum_g[0] + rgb888_g_d0[0];
                sum_b[0] <= sum_b[0] + rgb888_b_d0[0];
            end
        end

  /*****************************************************************
                           计算增益                                       
*****************************************************************/

  // One shared ratio pipeline. Snapshot final RGB sums of a complete
  // input frame, calculate R then B during vertical blanking, and commit
  // the pair at the next TUSER. Pixel buffering/sidebands stay unchanged.
  localparam integer FRAME_WORDS=(IMG_WIDTH/4)*IMG_HEIGHT;
  localparam integer FRAME_COUNT_BITS=(FRAME_WORDS<2)?1:$clog2(FRAME_WORDS+1);
  reg [FRAME_COUNT_BITS-1:0] statistics_words;
  reg [CHANNEL_SUM_WIDTH-1:0] saved_r,saved_g,saved_b;
  reg div_start,div_select,div_busy;
  reg [19:0] pending_r,pending_b,in_r_r1,in_b_r1;
  reg pending_r_valid,pending_b_valid;
  wire [47:0] div_quotient;
  wire div_done;
  wire [31:0] div_den=div_select ?
      {{(32-CHANNEL_SUM_WIDTH){1'b0}},saved_b} :
      {{(32-CHANNEL_SUM_WIDTH){1'b0}},saved_r};
  wire [47:0] div_num={{(32-CHANNEL_SUM_WIDTH){1'b0}},saved_g,16'd0};
  wire [19:0] div_gain=(|div_quotient[47:20])?20'hfffff:div_quotient[19:0];
  wire include_statistics=rgb_sum[0]<720;
  wire [CHANNEL_SUM_WIDTH-1:0] final_r=sum_r[0]+(include_statistics?rgb888_r_d0[0]:8'd0);
  wire [CHANNEL_SUM_WIDTH-1:0] final_g=sum_g[0]+(include_statistics?rgb888_g_d0[0]:8'd0);
  wire [CHANNEL_SUM_WIDTH-1:0] final_b=sum_b[0]+(include_statistics?rgb888_b_d0[0]:8'd0);
  awb_frame_gain_divider #(.SUM_WIDTH(CHANNEL_SUM_WIDTH),
      .SERIAL_ENABLE(IMG_WIDTH==1280 && IMG_HEIGHT==720)) div_shared (
      .clk(I_clk),.rst(!I_rst_n),.start(div_start),
      .denominator(div_den),.numerator(div_num),
      .quotient(div_quotient),.done(div_done));

  always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n)begin
      statistics_words<=0;saved_r<=1;saved_g<=1;saved_b<=1;
      div_start<=0;div_select<=0;div_busy<=0;
      pending_r<=20'h10000;pending_b<=20'h10000;
      pending_r_valid<=0;pending_b_valid<=0;
      in_r_r1<=20'h10000;in_b_r1<=20'h10000;
    end else begin
      div_start<=0;
      if(I_tuser)begin
        statistics_words<=0;div_select<=0;div_busy<=0;
        // Incomplete/too-short frames retain the previous complete gain pair.
        if(pending_r_valid && pending_b_valid)begin
          in_r_r1<=pending_r;in_b_r1<=pending_b;
        end
        pending_r_valid<=0;pending_b_valid<=0;
      end else begin
        if(I_tvalid_r0 && statistics_words<FRAME_WORDS)begin
          statistics_words<=statistics_words+1'b1;
          if(statistics_words==FRAME_WORDS-1)begin
            saved_r<=final_r;saved_g<=final_g;saved_b<=final_b;
            pending_r_valid<=0;pending_b_valid<=0;
            div_select<=0;div_start<=1;div_busy<=1;
          end
        end
        if(div_done && div_busy)begin
          if(!div_select)begin
            pending_r<=div_gain;pending_r_valid<=1;
            div_select<=1;div_start<=1;
          end else begin
            pending_b<=div_gain;pending_b_valid<=1;div_busy<=0;
          end
        end
      end
    end
  end

    signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
    )signal_delay_d (
        /*input                       */ .I_clk  (I_clk  ),
        /*input                       */ .I_rst_n(I_rst_n),
        /*input                       */ .I_tuser(I_tuser),  //synthesis keep 
        /*input  wire                 */ .I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/ .I_data (I_tdata_d1 ),   //synthesis keep 
        /*output wire                 */ .O_valid(valid_d0   ),  //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/ .O_data (data_d0    ),   //synthesis keep 
        /*output wire                 */ .O_tuser(I_tuser_r0 )
    );

    

/*****************************************************************
                            ��������                                      
*****************************************************************/

    ////信号同步
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           ��������                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n)begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end
        else if(valid_d1) begin
            R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
            G_new_r1 <=           rgb888_g_d1[0];
            B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

            R_new_r2 <= in_r_r1 * rgb888_r_d1[1];
            G_new_r2 <=           rgb888_g_d1[1];
            B_new_r2 <= in_b_r1 * rgb888_b_d1[1];

            R_new_r3 <= in_r_r1 * rgb888_r_d1[2];
            G_new_r3 <=           rgb888_g_d1[2];
            B_new_r3 <= in_b_r1 * rgb888_b_d1[2];

            R_new_r4 <= in_r_r1 * rgb888_r_d1[3];
            G_new_r4 <=           rgb888_g_d1[3];
            B_new_r4 <= in_b_r1 * rgb888_b_d1[3];
        end
    end

/*****************************************************************
                            �������???                                      
*****************************************************************/

    // Post-AWB red/blue compensation is unity; automatic AWB gains stay active.
    // Combinational only; pixel registers and sideband latency are unchanged.
    function [7:0] boost_rb;
        input [7:0] channel;
        begin
            boost_rb = channel;
        end
    endfunction

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    assign R_new_x1 = (|R_new_r1[27:24]) ? 8'hff : boost_rb(R_new_r1[23:16]);
    assign G_new_x1 =  G_new_r1;
    assign B_new_x1 = (|B_new_r1[27:24]) ? 8'hff : boost_rb(B_new_r1[23:16]);

    assign R_new_x2 = (|R_new_r2[27:24]) ? 8'hff : boost_rb(R_new_r2[23:16]);
    assign G_new_x2 =  G_new_r2;
    assign B_new_x2 = (|B_new_r2[27:24]) ? 8'hff : boost_rb(B_new_r2[23:16]);

    assign R_new_x3 = (|R_new_r3[27:24]) ? 8'hff : boost_rb(R_new_r3[23:16]);
    assign G_new_x3 =  G_new_r3;
    assign B_new_x3 = (|B_new_r3[27:24]) ? 8'hff : boost_rb(B_new_r3[23:16]);

    assign R_new_x4 = (|R_new_r4[27:24]) ? 8'hff : boost_rb(R_new_r4[23:16]);
    assign G_new_x4 =  G_new_r4;
    assign B_new_x4 = (|B_new_r4[27:24]) ? 8'hff : boost_rb(B_new_r4[23:16]);
/*****************************************************************
                           ͬ���ź�                                       
*****************************************************************/

    reg valid_d2,I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end


    assign  O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);   
    assign  O_tuser  = I_tuser ;   
    assign  O_tvalid = valid_d2;

    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign  I_tready = O_tready;
 
endmodule




// AWB-only unsigned ratio: rounded Q8 precision in the existing Q16 interface.
// numerator is always {32-bit channel sum,16'b0}. SUM_WIDTH (2..32) selects
// a proven input range, not fractional precision; default 32 is unchanged.
// The caller must zero-extend a smaller sum into the existing port widths.
// Accept one input per clock;
// return its capped quotient and start tag after exactly 50 register stages.
// Arithmetic and result memory keep running through reset. Clear transaction
// tags on reset so an old request cannot be accepted by the frame scheduler;
// this does not change the normal quotient or its 50-stage result timing.
module awb_gain_divider #(
    parameter integer SUM_WIDTH = 32
)(
    input wire clk,rst,start,
    input wire [31:0] denominator,
    input wire [47:0] numerator,
    output wire [47:0] quotient,
    output reg done
);
    reg [SUM_WIDTH-1:0] denominator_pipe[0:13];
    reg [SUM_WIDTH-1:0] remainder_pipe[0:13];
    // Four integer bits, eight fraction bits and one round-half-up guard bit.
    reg [12:0] quotient_pipe[0:13];
    reg saturated_pipe[0:13];
    // Single-tap 35-clock history: saturation flag + twelve rounded Q8 bits.
    // Like the arithmetic stages, this memory/pointer runs through reset.
    // The address is configuration-initialized, never restarted by rst: doing
    // so would reorder valid computations already in flight during a reset.
    (* ram_style="bram" *) reg [12:0] result_memory[0:34];
    reg [5:0] result_pointer=6'd0;
    reg [12:0] result_read;
    reg result_reset;
    wire [12:0] result_output=result_reset ? 13'd0 : result_read;
    reg [48:0] start_delay=49'd0;
    wire [12:0] rounded_gain={1'b0,quotient_pipe[13][12:1]}+
                             {12'd0,quotient_pipe[13][0]};
    wire rounded_saturated=saturated_pipe[13] | rounded_gain[12];

    // One input stage. Four additional comparison bits preserve denominator
    // scaling, including the original full 36-bit domain when SUM_WIDTH=32.
    // Exact ratios >=16 are already saturated by AWB.
    always @(posedge clk) begin
        denominator_pipe[0]<=denominator[SUM_WIDTH-1:0];
        remainder_pipe[0]<=numerator[SUM_WIDTH+15:16];
        quotient_pipe[0]<=13'd0;
        saturated_pipe[0]<=({4'd0,numerator[SUM_WIDTH+15:16]}>=
                            {denominator[SUM_WIDTH-1:0],4'd0});
        if(rst)start_delay<=49'd0;
        else start_delay<={start_delay[47:0],start};
    end
    always @(posedge clk or posedge rst) begin
        if(rst) done<=1'b0;
        else done<=start_delay[48];
    end

    genvar step;
    generate for(step=0;step<13;step=step+1) begin : g_divide
        if(step<4) begin : g_integer
            localparam SHIFT=3-step;
            localparam WIDTH=SUM_WIDTH+1+SHIFT;
            wire [WIDTH-1:0] difference=
                {{(WIDTH-SUM_WIDTH){1'b0}},remainder_pipe[step]}-
                ({{(WIDTH-SUM_WIDTH){1'b0}},denominator_pipe[step]}<<SHIFT);
            wire take_bit=~difference[WIDTH-1];
            always @(posedge clk) begin
                denominator_pipe[step+1]<=denominator_pipe[step];
                remainder_pipe[step+1]<=take_bit?difference[SUM_WIDTH-1:0]:remainder_pipe[step];
                quotient_pipe[step+1]<={quotient_pipe[step][11:0],take_bit};
                saturated_pipe[step+1]<=saturated_pipe[step];
            end
        end else begin : g_fraction
            // Remainder is <denominator on the nonsaturated path.
            // For R<D, 2R-D fits SUM_WIDTH+1 signed bits without removing
            // any quotient/rounding bit. Saturated transactions keep their cap.
            wire [SUM_WIDTH:0] difference={remainder_pipe[step],1'b0}-
                                          {1'b0,denominator_pipe[step]};
            wire take_bit=~difference[SUM_WIDTH];
            always @(posedge clk) begin
                denominator_pipe[step+1]<=denominator_pipe[step];
                remainder_pipe[step+1]<=take_bit?difference[SUM_WIDTH-1:0]:
                    {remainder_pipe[step][SUM_WIDTH-2:0],1'b0};
                quotient_pipe[step+1]<={quotient_pipe[step][11:0],take_bit};
                saturated_pipe[step+1]<=saturated_pipe[step];
            end
        end
    end endgenerate

    // 1 input + 13 divide + 36 result-only stages = original 50 stages.
    // Carry rounding overflow separately to preserve the original 20'hfffff
    // cap, including division by zero. Unsaturated outputs have eight zero LSBs.
    always @(posedge clk) begin
        result_memory[result_pointer]<={rounded_saturated,rounded_gain[11:0]};
        result_pointer<=result_pointer==6'd34 ? 6'd0 : result_pointer+6'd1;
    end
    // Synchronous read-before-write shares the original output edge.
    // RAM and the ring pointer keep running through reset. A one-bit reset
    // mask preserves the former output bank's asynchronous clear exactly.
    always @(posedge clk) result_read<=result_memory[result_pointer];
    always @(posedge clk or posedge rst) begin
        if(rst) result_reset<=1'b1;
        else result_reset<=1'b0;
    end
    assign quotient={28'd0,(result_output[12] ? 20'hfffff :
                           {result_output[11:0],8'd0})};
endmodule

// Private AWB frame-statistics engine. The 720p caller starts R, waits for
// done, then starts B; its next complete frame is at least 230400 words away.
// SERIAL_ENABLE is deliberately opt-in: retain the original fully pipelined
// divider for other parameterizations and for any unrelated streaming caller.
module awb_frame_gain_divider #(
    parameter integer SUM_WIDTH = 32,
    parameter integer SERIAL_ENABLE = 0
)(
    input wire clk,rst,start,
    input wire [31:0] denominator,
    input wire [47:0] numerator,
    output wire [47:0] quotient,
    output wire done
);
    generate if(SERIAL_ENABLE) begin : g_serial
        // A fixed divisor 8*D avoids a variable shift or thirteen subtractors.
        // Each iteration emits one quotient bit and doubles the remainder.
        // For a nonsaturated N<16*D, the working remainder is <16*D, so
        // SUM_WIDTH+4 bits preserve every integer/fraction/rounding bit.
        localparam integer WIDTH=SUM_WIDTH+4;
        reg [WIDTH-1:0] remainder;
        reg [WIDTH-2:0] divisor;
        reg [12:0] bits;
        reg saturated;
        reg [3:0] iteration;
        reg [5:0] clocks_left;
        reg done_q;
        reg [12:0] result;
        wire [WIDTH:0] difference={1'b0,remainder}-{2'b0,divisor};
        wire take_bit=~difference[WIDTH];
        wire [12:0] rounded={1'b0,bits[12:1]}+{12'd0,bits[0]};
        // Numeric state needs no reset: no result can be published without
        // a new start having initialized every operand. Only tags/output reset.
        always @(posedge clk) begin
            if(start) begin
                remainder<={{4{1'b0}},numerator[SUM_WIDTH+15:16]};
                divisor<={denominator[SUM_WIDTH-1:0],3'b000};
                bits<=13'd0;
                saturated<=({4'd0,numerator[SUM_WIDTH+15:16]}>=
                            {denominator[SUM_WIDTH-1:0],4'b0000});
                iteration<=4'd0;
            end else if(clocks_left!=0 && iteration<4'd13) begin
                remainder<=take_bit ? {difference[WIDTH-2:0],1'b0} :
                                      {remainder[WIDTH-2:0],1'b0};
                bits<={bits[11:0],take_bit};
                iteration<=iteration+1'b1;
            end
        end
        // Request sampled on edge 0, result and done appear on edge 49,
        // exactly matching the original fifty-register-stage convention.
        always @(posedge clk or posedge rst) begin
            if(rst) begin
                clocks_left<=6'd0;
                done_q<=1'b0;
                result<=13'd0;
            end else begin
                done_q<=1'b0;
                if(start) clocks_left<=6'd49;
                else if(clocks_left!=0) begin
                    clocks_left<=clocks_left-1'b1;
                    if(clocks_left==6'd1) begin
                        result<={saturated|rounded[12],rounded[11:0]};
                        done_q<=1'b1;
                    end
                end
            end
        end
        assign done=done_q;
        assign quotient={28'd0,(result[12] ? 20'hfffff :
                               {result[11:0],8'd0})};
    end else begin : g_pipeline
        awb_gain_divider #(.SUM_WIDTH(SUM_WIDTH)) legacy(
            .clk(clk),.rst(rst),.start(start),.denominator(denominator),
            .numerator(numerator),.quotient(quotient),.done(done));
    end endgenerate
endmodule

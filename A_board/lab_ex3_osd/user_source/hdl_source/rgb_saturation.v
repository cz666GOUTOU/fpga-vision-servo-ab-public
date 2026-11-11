// Four RGB888 pixels per beat, serial levels 0..16 = 0.5..2x, startup 1x.
// DATA/VALID/USER/LAST all retain two registered clocks of latency.
module rgb_saturation (
    input wire I_clk,I_rst_n,I_config_valid, input wire [4:0] I_level,
    input wire [95:0] I_tdata, input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata, output reg O_tvalid,O_tuser,O_tlast
);
    // The same twelve PH1P DSPs now perform pre-subtract, multiply and post-add.
    // Decode signed K once per configuration; no added pixel pipeline stage.
    function signed [5:0] decode_dsp_level;
        input [4:0] level;
        begin
            case(level)
                 0: decode_dsp_level=-6'sd8;
                 1: decode_dsp_level=-6'sd7;
                 2: decode_dsp_level=-6'sd6;
                 3: decode_dsp_level=-6'sd5;
                 4: decode_dsp_level=-6'sd4;
                 5: decode_dsp_level=-6'sd3;
                 6: decode_dsp_level=-6'sd2;
                 7: decode_dsp_level=-6'sd1;
                 8: decode_dsp_level= 6'sd0;
                 9: decode_dsp_level= 6'sd2;
                10: decode_dsp_level= 6'sd4;
                11: decode_dsp_level= 6'sd6;
                12: decode_dsp_level= 6'sd8;
                13: decode_dsp_level= 6'sd10;
                14: decode_dsp_level= 6'sd12;
                15: decode_dsp_level= 6'sd14;
                16: decode_dsp_level= 6'sd16;
                default: decode_dsp_level=6'sd0;
            endcase
        end
    endfunction
    reg signed [5:0] requested_dsp_coefficient,active_dsp_coefficient;
    wire signed [5:0] pixel_dsp_coefficient=I_tuser?requested_dsp_coefficient:active_dsp_coefficient;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin requested_dsp_coefficient<=6'sd0;active_dsp_coefficient<=6'sd0;end
        else begin
            if(I_config_valid && I_level<=16) requested_dsp_coefficient<=decode_dsp_level(I_level);
            if(I_tuser) active_dsp_coefficient<=requested_dsp_coefficient;
        end
    end
    // sum = 16*C + (C-Y)*K. Range -4080..8160 fits signed14;
    // floor(sum/16) exactly equals C + floor((C-Y)*K/16).
    function [7:0] clamp_sum;
        input [53:0] sum;
        begin
            if(sum[13]) clamp_sum=8'd0;
            else if(sum[12]) clamp_sum=8'd255;
            else clamp_sum=sum[11:4];
        end
    endfunction
    wire [647:0] channel_sums;
    genvar pixel,channel;
    generate for(pixel=0;pixel<4;pixel=pixel+1) begin: g_pixel
        wire [7:0] blue=I_tdata[pixel*24+:8];
        wire [7:0] green=I_tdata[pixel*24+8+:8];
        wire [7:0] red=I_tdata[pixel*24+16+:8];
        wire [9:0] luma_sum={2'b00,red}+{1'b0,green,1'b0}+{2'b00,blue};
        wire [7:0] luma=luma_sum[9:2];
        for(channel=0;channel<3;channel=channel+1) begin: g_channel
            rgb_saturation_dsp_channel arithmetic(
                .clk(I_clk),.rst_n(I_rst_n),
                .value(I_tdata[pixel*24+channel*8+:8]),.luma(luma),
                .coefficient(pixel_dsp_coefficient),
                .sum(channel_sums[(pixel*3+channel)*54+:54])
            );
        end
    end endgenerate
    reg stage1_valid,stage1_user,stage1_last;
    integer index;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            stage1_valid<=0;stage1_user<=0;stage1_last<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end else begin
            stage1_valid<=I_tvalid;stage1_user<=I_tuser;stage1_last<=I_tlast;
            O_tvalid<=stage1_valid;O_tuser<=stage1_user;O_tlast<=stage1_last;
            for(index=0;index<12;index=index+1)
                O_tdata[index*8+:8]<=clamp_sum(channel_sums[index*54+:54]);
        end
    end
endmodule

// One physical DSP: AU=C-Y, MU=AU*K, TU=MU+16*C.
// The first pixel stage is XABREG/YREG/ZREG; the caller is stage two.
// Control encodings: UG1310_1.2 tables on printed pages144..148.
module rgb_saturation_dsp_channel(
    input wire clk,rst_n,
    input wire [7:0] value,luma,
    input wire signed [5:0] coefficient,
    output wire [53:0] sum
);
    wire [26:0] aa,ab,asum,mx;
    wire [1:0] aop;
    wire [17:0] my;
    wire [44:0] mp;
    wire mop,mul9_mode,mul9_signed;
    wire [53:0] ta,tb,tc,ts;
    wire ti,to,ov,un;
    wire [6:0] top;
    wire [5:0] tos;
    PH1P_PHY_DSPSIOU_V2 #(
        .CLKMUX("SIG"),.CE0("SIG"),.CE1("SIG"),.CE2("SIG"),.CE3("SIG"),
        .RST0("SIG"),.RST1("SIG"),.RST2("SIG"),.RST3("SIG"),
        .MULT_MODE("NORMAL"),.MULT9_SIGNED("SIGNED"),
        .XAREG("0"),.XBREG("0"),.XABREG("1"),.YREG("1"),.ZREG("1"),
        .INCTRLREG("0"),.MUXCTRLREG("0"),.OPCTRLREG("0"),.CINCTRLREG("0"),
        .CXAREG("0"),.CXBREG("0"),.CYREG("0"),
        .MREG("0"),.POUWREG("0"),.CCOREG("0"),
        .SR0MODE("ASYNC"),.SR1MODE("ASYNC"),.SR2MODE("ASYNC"),.SR3MODE("ASYNC"),
        .USER_GSRN("DISABLE")
    ) sio(
        .xa({19'd0,value}),.xb({19'd0,luma}),
        .y({{12{coefficient[5]}},coefficient}),.z({42'd0,value,4'd0}),
        .clk(clk),.ce(4'b1111),.rst({4{!rst_n}}),
        .muxctrl(7'b0001110),.inctrl(7'b1110111),.cinctrl(3'b000),
        .opctrl(11'b10000001111),
        .cxai(),.cxbi(),.cxabi(),.cyi(),.cpi(),.cci(),
        .add_a(aa),.add_b(ab),.add_opctrl(aop),.add_sum(asum),
        .mult_x(mx),.mult_y(my),.mult_opctrl(mop),.mult_p(mp),
        .mul9_mode(mul9_mode),.mul9_signed(mul9_signed),
        .tadd_a(ta),.tadd_b(tb),.tadd_c(tc),.tadd_ci(ti),
        .tadd_opctrl(top),.tadd_oversel(tos),.tadd_sum(ts),
        .tadd_co(to),.tadd_overflow(ov),.tadd_underflow(un),
        .logic_p(),.logic_wxor(),.p(sum)
    );
    PH1P_PHY_DSPADD au(.a(aa),.b(ab),.opctrl(aop),.sum(asum));
    PH1P_PHY_DSPMULT_V2 mu(.x(mx),.y(my),.opctrl(mop),
        .mul9_mode(mul9_mode),.mul9_signed(mul9_signed),.p(mp));
    PH1P_PHY_DSPTADD tu(.a(ta),.b(tb),.c(tc),.ci(ti),.opctrl(top),
        .oversel(tos),.sum(ts),.co(to),.overflow(ov),.underflow(un));
endmodule

// Explicit PH1P hard arithmetic. A38_SIM_DSP is a restricted test model only.
module a38_dsp_addsub54(
    input wire [53:0] a,b,
    input wire subtract,
    output wire [53:0] sum
);
`ifdef A38_SIM_DSP
    assign sum=subtract ? a-b : a+b;
`else
    wire [53:0] ta,tb,tc,ts;
    wire ti,to,ov,un;
    wire [6:0] top;
    wire [5:0] tos;
    // TU: a={xa,xb}, b=z, c=0; add or a-b. All pipeline bypasses.
    PH1P_PHY_DSPSIOU_V2 #(
        .CLKMUX("0"), .CE0("0"),.CE1("0"),.CE2("0"),.CE3("0"),
        .RST0("0"),.RST1("0"),.RST2("0"),.RST3("0"),
        .XAREG("0"),.XBREG("0"),.YREG("0"),.ZREG("0"),
        .INCTRLREG("0"),.MUXCTRLREG("0"),.OPCTRLREG("0"),.CINCTRLREG("0"),
        .CXAREG("0"),.CXBREG("0"),.CYREG("0"),.XABREG("0"),
        .MREG("0"),.POUWREG("0"),.CCOREG("0"),.USER_GSRN("DISABLE")
    ) sio(
        .xa(a[53:27]),.xb(a[26:0]),.y(18'b0),.z(b),
        .clk(1'b0),.ce(4'b0),.rst(4'b0),
        .muxctrl(7'b0001101),.inctrl(7'b0010111),.cinctrl(3'b000),
        .opctrl({3'b100,1'b0,subtract,2'b00,4'b1000}),
        .cxai(),.cxbi(),.cxabi(),.cyi(),.cpi(),.cci(),
        .add_sum(),.mult_p(),.logic_p(),.logic_wxor(),
        .tadd_sum(ts),.tadd_co(to),.tadd_overflow(ov),.tadd_underflow(un),
        .tadd_a(ta),.tadd_b(tb),.tadd_c(tc),.tadd_ci(ti),
        .tadd_opctrl(top),.tadd_oversel(tos),.p(sum)
    );
    PH1P_PHY_DSPTADD tu(
        .a(ta),.b(tb),.c(tc),.ci(ti),.opctrl(top),.oversel(tos),
        .sum(ts),.co(to),.overflow(ov),.underflow(un)
    );
`endif
endmodule

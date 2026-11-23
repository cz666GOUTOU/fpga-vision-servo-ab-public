// 50 MHz board clock to the 125 MHz RGMII clock used by the sender.
// The sender's generated PLL uses C0=100 MHz for feedback and C2=125 MHz
// for Ethernet. Keep the same vendor PLL parameters on the receiver.
// The exact generated frequency and lock behavior require TD verification.
module qzw_clk125 (
    input  wire refclk_50m,
    output wire clk_125m,
    output wire locked
);
    wire pll_clk0;
    wire pll_clk0_buf;
    wire pll_clk2;
    PH1P_LOGIC_BUFG u_bufg0 (.i(pll_clk0), .o(pll_clk0_buf));
    PH1P_LOGIC_BUFG u_bufg2 (.i(pll_clk2), .o(clk_125m));

    ph1p_phy_pll_wrapper_25a56e5ce2f9 #(
        .FBKCLK("CLKC0_EXT"),
        .FBKCLK_INT("CLKC0_EXT"),
        .FIN("50.000000000"),
        .REFCLK_DIV(1),
        .FBCLK_DIV(2),
        .CLKC0_ENABLE("ENABLE"),
        .CLKC0_DIV(15),
        .CLKC0_CPHASE(14),
        .CLKC0_FPHASE(0),
        .CLKC0_DUTY50("ENABLE"),
        .CLKC0_DUTY_INT(8),
        .CLKC2_ENABLE("ENABLE"),
        .CLKC2_DIV(12),
        .CLKC2_CPHASE(11),
        .CLKC2_FPHASE(0),
        .CLKC2_DUTY50("ENABLE"),
        .CLKC2_DUTY_INT(6),
        .PLL_USR_RST("ENABLE"),
        .PLL_FEED_TYPE("EXTERNAL"),
        .PLL_FASTLOOP("ENABLE"),
        .LPF_RES(0),
        .LPF_CAP(13),
        .ICP_CUR(29),
        .PHASE_PATH_SEL(0),
        .DYN_PHASE_PATH_SEL("DISABLE"),
        .DYN_FPHASE_EN("DISABLE"),
        .PI_OUT_SEL("NORMAL"),
        .PI_FRAC_EN("DISABLE"),
        .CLKC0_PI_SHIFT_EN("DISABLE"),
        .FEEDBK_MODE("NORMAL"),
        .DYN_CPHASE_EN("DISABLE")
    ) u_pll (
        .refclk(refclk_50m),
        .fbclk(pll_clk0_buf),
        .clk0_en(1'b1), .clk0_out(pll_clk0), .clkb0_out(),
        .clk1_en(1'b0), .clk1_out(), .clkb1_out(),
        .clk2_en(1'b1), .clk2_out(pll_clk2), .clkb2_out(),
        .clk3_en(1'b0), .clk3_out(), .clkb3_out(),
        .clk4_en(1'b0), .clk4_out(), .clkb4_out(),
        .clk5_en(1'b0), .clk5_out(), .clkb5_out(),
        .clk6_en(1'b0), .clk6_out(), .clkb6_out(),
        .lock(locked),
        .reset(1'b0),
        .clkc_rst(2'b00),
        .refclk_rst(1'b0),
        .wakeup(1'b1),
        .cps_step(1'b0),
        .pllpd(1'b0),
        .psclk(1'b0), .psclksel(3'b000), .psstep(1'b0),
        .psdown(1'b0), .psdone(),
        .drp_clk(1'b0), .drp_rstn(1'b1), .drp_sel(1'b0),
        .drp_rd(1'b0), .drp_wr(1'b0), .drp_addr(8'b0),
        .drp_wdata(8'b0), .drp_err(), .drp_rdy(), .drp_rdata(),
        .ssc_reset(1'b0)
    );
endmodule

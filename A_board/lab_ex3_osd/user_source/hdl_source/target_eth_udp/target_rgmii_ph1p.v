// Device-specific physical adapter. TX clock is in phase at FPGA pins;
// YT8511 controller enables PHY-internal TX and RX skew. Do not add 90deg too.
// Primitive port polarity verified against D:/TD/sim_release/ph1p/ph1p_logic_hrio.v.
module target_rgmii_tx_ph1p(
    input tx_clk, input reset_n, input [7:0] gmii_txd, input gmii_tx_en,
    input gmii_tx_er, output [3:0] rgmii_txd, output rgmii_tx_ctl, output rgmii_tx_clk
);
    // Hold a complete byte across both DDR edges, independent of whether the
    // primitive internally captures d1 on the rising or falling clock edge.
    // Assert asynchronously; release the six TX ODDR resets at the falling
    // edge, half a tx_clk period away from their rising-edge hold check.
    // Keep the byte-holding registers on the original reset and clock edges.
    // Retain separate reset leaves near each HDIO. Same assertion/release edge.
    (* syn_preserve="true", syn_keep="true" *) reg [5:0] oddr_reset;
    always @(negedge tx_clk or negedge reset_n)
        if (!reset_n) oddr_reset <= 6'b111111;
        else oddr_reset <= 6'b000000;
    reg [7:0] tx_hold;
    reg en_hold, er_hold;
    always @(negedge tx_clk or negedge reset_n)
        if(!reset_n) begin tx_hold<=0; en_hold<=0; er_hold<=0; end
        else begin tx_hold<=gmii_txd; en_hold<=gmii_tx_en; er_hold<=gmii_tx_er; end
    genvar k;
    generate for(k=0;k<4;k=k+1) begin: g_tx
        if (k >= 0) begin: g_hd
            // HX1P35A R11/P11/T10/R12 (TXD0..TXD3) are HDIO sites.
            PH1P_LOGIC_HD_ODDR od(.clk(tx_clk),.rst(oddr_reset[k]),
                .d0(tx_hold[k]),.d1(tx_hold[k+4]),.q(rgmii_txd[k]));
        end else begin: g_hr
            PH1P_LOGIC_ODDR od(.clk(tx_clk),.rst(oddr_reset[k]),
                .d0(tx_hold[k]),.d1(tx_hold[k+4]),.q(rgmii_txd[k]));
        end
    end endgenerate
    // Board HX1P35A maps TXEN/TX_CTL (R10) to HDIO as well.
    PH1P_LOGIC_HD_ODDR oc(.clk(tx_clk),.rst(oddr_reset[4]),.d0(en_hold),
        .d1(en_hold ^ er_hold),.q(rgmii_tx_ctl));
    // Board HX1P35A maps TXCLK (U9) to an HDIO site. TXD2/TXD3, TX_CTL,
    // and TXCLK all use HDIO DDR primitives on this board's Ethernet pins.
    PH1P_LOGIC_HD_ODDR ck(.clk(tx_clk),.rst(oddr_reset[5]),.d0(1'b1),.d1(1'b0),.q(rgmii_tx_clk));
endmodule

module target_rgmii_rx_ph1p(
    input rgmii_rx_clk, input reset_n, input [3:0] rgmii_rxd, input rgmii_rx_ctl,
    output [7:0] gmii_rxd, output gmii_rx_dv, output gmii_rx_er
);
    wire [3:0] rise_data, fall_data;
    wire rise_ctl, fall_ctl;
    genvar k;
    // NONE exposes samples on their individual edges. Register the previous
    // rising sample at the falling edge to pair it with that same byte's high nibble.
    generate for(k=0;k<4;k=k+1) begin: g_rx
        PH1P_LOGIC_HD_IDDR id(.clk(rgmii_rx_clk),.rst(!reset_n),
            .d(rgmii_rxd[k]),.q0(rise_data[k]),.q1(fall_data[k]));
    end endgenerate
        PH1P_LOGIC_HD_IDDR ic(.clk(rgmii_rx_clk),.rst(!reset_n),
        .d(rgmii_rx_ctl),.q0(rise_ctl),.q1(fall_ctl));
    reg [3:0] low_hold;
    reg ctl_hold;
    always @(negedge rgmii_rx_clk or negedge reset_n)
        if(!reset_n) begin low_hold<=0; ctl_hold<=0; end
        else begin low_hold<=rise_data; ctl_hold<=rise_ctl; end
    // Consumed by core at the following rising edge; both halves are stable.
    assign gmii_rxd={fall_data,low_hold};
    assign gmii_rx_dv=ctl_hold;
    assign gmii_rx_er=ctl_hold ^ fall_ctl;
endmodule


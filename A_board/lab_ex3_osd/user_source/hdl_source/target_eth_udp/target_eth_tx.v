// Board A top. Clocks supplied by caller: tx_clk=125MHz, mgmt_clk per parameter.
// result_update is a pulse, not a ready/valid handshake: when !result_ready it
// is dropped and counted. tx_done is in tx_clk, link_ready/phy_error in mgmt_clk.
module target_eth_tx #(
    parameter [47:0] SRC_MAC=48'h020000000001, DST_MAC=48'h020000000002,
    parameter [31:0] SRC_IP=32'hc0a80a01, DST_IP=32'hc0a80a02,
    parameter [15:0] SRC_PORT=16'd5000, DST_PORT=16'd5000,
    parameter integer MGMT_CLK_HZ=50000000,
    parameter [4:0] PHY_ADDR=5'd4,
    parameter integer PHY_MDIO_ENABLE=1
)(
    input rst_n, input mgmt_clk, input tx_clk, input result_clk,
    input result_update, input target_valid, input distance_valid, input region_valid,
    input [15:0] target_id, center_x, center_y, input [31:0] distance,
    output result_ready, result_link_ready, overflow, tx_done, link_ready, phy_error,
    output [31:0] dropped_results, phy_id,
    output [3:0] rgmii_txd, output rgmii_tx_ctl, rgmii_tx_clk,
    output phy_reset_n, output mdc, inout mdio
);
    wire [7:0] txd;
    wire en, er, tx_reset_n;
    target_reset_sync r0(tx_clk,rst_n,tx_reset_n);
    generate
        if (PHY_MDIO_ENABLE) begin : g_phy_mdio
            target_yt8511_ctrl #(.MGMT_CLK_HZ(MGMT_CLK_HZ),.PHY_ADDR(PHY_ADDR)) phy(
                .clk(mgmt_clk),.rst_n(rst_n),.phy_reset_n(phy_reset_n),.mdc(mdc),.mdio(mdio),
                .link_ready(link_ready),.phy_error(phy_error),.phy_id(phy_id));
        end else begin : g_phy_reset_only
            target_yt8511_ctrl_reset_only #(.MGMT_CLK_HZ(MGMT_CLK_HZ),.PHY_ADDR(PHY_ADDR)) phy(
                .clk(mgmt_clk),.rst_n(rst_n),.phy_reset_n(phy_reset_n),.mdc(mdc),.mdio(mdio),
                .link_ready(link_ready),.phy_error(phy_error),.phy_id(phy_id));
        end
    endgenerate
    target_udp_tx_core #(.SRC_MAC(SRC_MAC),.DST_MAC(DST_MAC),.SRC_IP(SRC_IP),
        .DST_IP(DST_IP),.SRC_PORT(SRC_PORT),.DST_PORT(DST_PORT)) core(
        .rst_n(rst_n),.result_clk(result_clk),.tx_clk(tx_clk),.link_ready(link_ready),
        .result_update(result_update),.target_valid(target_valid),.distance_valid(distance_valid),.region_valid(region_valid),
        .target_id(target_id),.center_x(center_x),.center_y(center_y),.distance(distance),
        .result_ready(result_ready),.result_link_ready(result_link_ready),.overflow(overflow),.dropped_results(dropped_results),
        .gmii_txd(txd),.gmii_tx_en(en),.gmii_tx_er(er),.tx_done(tx_done));
    target_rgmii_tx_ph1p io(.tx_clk(tx_clk),.reset_n(tx_reset_n),.gmii_txd(txd),
        .gmii_tx_en(en),.gmii_tx_er(er),.rgmii_txd(rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_tx_clk(rgmii_tx_clk));
endmodule

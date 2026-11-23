// Board B top. All result outputs in app_clk, bad_frames/rx_overflow in RX clock.
// Idle TX clock/data are provided to the PHY; no ARP/ACK transmitter in this v1.
module target_eth_rx #(
    parameter [47:0] SRC_MAC=48'h020000000001, DST_MAC=48'h020000000002,
    parameter [31:0] SRC_IP=32'hc0a80a01, DST_IP=32'hc0a80a02,
    parameter [15:0] SRC_PORT=16'd5000, DST_PORT=16'd5000,
    parameter integer MGMT_CLK_HZ=50000000,
    parameter integer TIMEOUT_CYCLES=7500000,
    parameter [4:0] PHY_ADDR=5'd4,
    parameter integer PHY_MDIO_ENABLE=1
)(
    input rst_n, input mgmt_clk, input tx_clk, input app_clk,
    input rgmii_rx_clk, input [3:0] rgmii_rxd, input rgmii_rx_ctl,
    output [3:0] rgmii_txd, output rgmii_tx_ctl, rgmii_tx_clk,
    output result_update, target_valid, distance_valid, guard_inside,
    output [15:0] target_id, center_x, center_y,
    output [31:0] distance, result_sequence,
    output comm_timeout, link_ready, phy_error,
    output [31:0] received_results, stale_results, missing_results,
    output [31:0] bad_frames, phy_id, output rx_overflow,
    output phy_reset_n, output mdc, inout mdio,
    output debug_data_seen, debug_frame_seen
);
    wire [7:0] rxd;
    wire dv, er, rx_reset_n, tx_reset_n;
    target_reset_sync r0(rgmii_rx_clk,rst_n,rx_reset_n);
    target_reset_sync r1(tx_clk,rst_n,tx_reset_n);
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
    target_rgmii_tx_ph1p idle_io(.tx_clk(tx_clk),.reset_n(tx_reset_n),.gmii_txd(8'b0),
        .gmii_tx_en(1'b0),.gmii_tx_er(1'b0),.rgmii_txd(rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_tx_clk(rgmii_tx_clk));
    target_rgmii_rx_ph1p io(.rgmii_rx_clk(rgmii_rx_clk),.reset_n(rx_reset_n),
        .rgmii_rxd(rgmii_rxd),.rgmii_rx_ctl(rgmii_rx_ctl),.gmii_rxd(rxd),
        .gmii_rx_dv(dv),.gmii_rx_er(er));
    target_udp_rx_core #(.SRC_MAC(SRC_MAC),.DST_MAC(DST_MAC),.SRC_IP(SRC_IP),
        .DST_IP(DST_IP),.SRC_PORT(SRC_PORT),.DST_PORT(DST_PORT),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) core(
        .rst_n(rst_n),.rx_clk(rgmii_rx_clk),.app_clk(app_clk),.link_ready(link_ready),
        .gmii_rxd(rxd),.gmii_rx_dv(dv),.gmii_rx_er(er),.result_update(result_update),
        .target_valid(target_valid),.distance_valid(distance_valid),.guard_inside(guard_inside),.target_id(target_id),
        .center_x(center_x),.center_y(center_y),.distance(distance),.result_sequence(result_sequence),
        .comm_timeout(comm_timeout),.received_results(received_results),.stale_results(stale_results),
        .missing_results(missing_results),.bad_frames(bad_frames),.rx_overflow(rx_overflow),
        .debug_data_seen(debug_data_seen),.debug_frame_seen(debug_frame_seen));
endmodule

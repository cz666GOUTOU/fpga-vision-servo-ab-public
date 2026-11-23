// Standalone PH1P35 receiver for the target-coordinate UDP records.
// Four diagnostic LEDs: RX clock active, data seen, CRC frame seen, record seen.
// LEDs 2..4 remain set until reset; LED1 clears when RX clock stops.
module ethernet_rx (
    input  wire       I_sys_clk,
    input  wire       rst_n,
    input  wire       I_eth_rx_clk,
    input  wire [3:0] I_eth_rxd,
    input  wire       I_eth_rx_ctl,
    output wire [3:0] O_eth_txd,
    output wire       O_eth_tx_ctl,
    output wire       O_eth_tx_clk,
    output wire       O_phy_reset_n,
    output wire       O_eth_mdc,
    inout  wire       IO_eth_mdio,
    output wire       O_led1,
    output wire       O_led2,
    output wire       O_led3,
    output wire       O_led4,
    output wire result_update, target_valid, distance_valid, guard_inside,
    output wire [15:0] target_id, center_x, center_y,
    output wire [31:0] distance, result_sequence,
    output wire comm_timeout, link_ready, phy_error,
    output wire [31:0] received_results, stale_results, missing_results,
    output wire [31:0] bad_frames, phy_id,
    output wire rx_overflow
);
    wire clk_125m;
    wire pll_locked;
    wire receiver_reset_n = rst_n && pll_locked;
    wire debug_data_seen, debug_frame_seen;
    wire rx_diag_reset_n, app_diag_reset_n;
    target_reset_sync diag_rx_reset(I_eth_rx_clk,receiver_reset_n,rx_diag_reset_n);
    target_reset_sync diag_app_reset(I_sys_clk,receiver_reset_n,app_diag_reset_n);
    reg [9:0] rx_div;
    (* ASYNC_REG = "TRUE" *) reg [1:0] heartbeat_sync, data_sync, frame_sync;
    reg heartbeat_last, clock_active, result_seen;
    reg [15:0] clock_idle;
    always @(posedge I_eth_rx_clk or negedge rx_diag_reset_n)
        if(!rx_diag_reset_n) rx_div<=0;
        else rx_div<=rx_div+1'b1;

    qzw_clk125 u_clk (
        .refclk_50m(I_sys_clk),
        .clk_125m(clk_125m),
        .locked(pll_locked)
    );

    target_eth_rx #(
        .MGMT_CLK_HZ(50_000_000),
        .TIMEOUT_CYCLES(7_500_000),
        .PHY_ADDR(5'd4),
        .PHY_MDIO_ENABLE(0)
    ) u_eth (
        .rst_n(receiver_reset_n),
        .mgmt_clk(I_sys_clk),
        .tx_clk(clk_125m),
        .app_clk(I_sys_clk),
        .rgmii_rx_clk(I_eth_rx_clk),
        .rgmii_rxd(I_eth_rxd),
        .rgmii_rx_ctl(I_eth_rx_ctl),
        .rgmii_txd(O_eth_txd),
        .rgmii_tx_ctl(O_eth_tx_ctl),
        .rgmii_tx_clk(O_eth_tx_clk),
        .result_update(result_update),
        .target_valid(target_valid),
        .distance_valid(distance_valid),
        .guard_inside(guard_inside),
        .target_id(target_id),
        .center_x(center_x),
        .center_y(center_y),
        .distance(distance),
        .result_sequence(result_sequence),
        .comm_timeout(comm_timeout),
        .link_ready(link_ready),
        .phy_error(phy_error),
        .received_results(received_results),
        .stale_results(stale_results),
        .missing_results(missing_results),
        .bad_frames(bad_frames),
        .phy_id(phy_id),
        .rx_overflow(rx_overflow),
        .phy_reset_n(O_phy_reset_n),
        .mdc(O_eth_mdc),
        .mdio(IO_eth_mdio),
        .debug_data_seen(debug_data_seen),
        .debug_frame_seen(debug_frame_seen)
    );

    // LED1: recent RX clock activity (not negotiated speed or PHY Link).
    // LED2/3: sticky RX-domain levels synchronized to 50 MHz.
    // LED4: sticky application record accepted, including no-target records.
    always @(posedge I_sys_clk or negedge app_diag_reset_n) begin
        if(!app_diag_reset_n) begin
            heartbeat_sync<=0; data_sync<=0; frame_sync<=0;
            heartbeat_last<=0; clock_active<=0; clock_idle<=0; result_seen<=0;
        end else begin
            heartbeat_sync<={heartbeat_sync[0],rx_div[9]};
            data_sync<={data_sync[0],debug_data_seen};
            frame_sync<={frame_sync[0],debug_frame_seen};
            heartbeat_last<=heartbeat_sync[1];
            if(heartbeat_sync[1]!=heartbeat_last) begin
                clock_active<=1; clock_idle<=0;
            end else if(clock_idle==16'd49999) clock_active<=0;
            else clock_idle<=clock_idle+1'b1;
            if(result_update) result_seen<=1;
        end
    end
    assign O_led1 = clock_active;
    assign O_led2 = data_sync[1];
    assign O_led3 = frame_sync[1];
    assign O_led4 = result_seen;
endmodule

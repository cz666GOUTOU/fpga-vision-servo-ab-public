`timescale 1ns / 1ps

// GM6020 driver for user_source/ip_source/CAN/CAN.ipc (FILTER_CNT=0).
// Application ports use sys_clk. Defaults require a real 24 MHz can_clk.
// MOTOR_ID/MOTOR_ID_2 are DIP-switch IDs, not 11-bit CAN arbitration IDs.
// One CAN peripheral packs their command slots into the same group frame.
module GM6020 #(
    parameter integer MOTOR_ID = 1,                 // 1..7
    parameter integer MOTOR_ID_2 = 0,               // 0: disabled, otherwise 1..7
    parameter integer SYS_CLK_HZ = 50000000,
    parameter integer CAN_CLK_HZ = 24000000,
    parameter integer CAN_BRP = 1,                  // prescaler minus one
    parameter integer CAN_TSEG1 = 9,               // actual quanta: 1..16
    parameter integer CAN_TSEG2 = 2,                // actual quanta: 1..8
    parameter integer CAN_SJW = 1,                  // actual quanta: 1..4
    parameter integer TX_HZ = 1000,
    parameter integer AUTO_SEND = 1,                // 0: use tx_request
    parameter integer CURRENT_MODE = 0,            // 0: voltage mode, 1: current mode
    parameter integer VOLTAGE_LIMIT = 25000,        // v1.4 manual; old v1.2: 30000
    parameter integer FEEDBACK_TIMEOUT_MS = 100,
    parameter integer BUS_TIMEOUT_CYCLES = 4096
)(
    input  wire              sys_clk,
    input  wire              can_clk,
    input  wire              rst_n,
    input  wire              can_rx,                // transceiver RXD
    output wire              can_tx,                // transceiver TXD
    input  wire              motor_enable,          // 0: send zero command
    input  wire signed [15:0] command,              // signed voltage/current raw value
    input  wire              motor_enable_2,        // second command slot enable
    input  wire signed [15:0] command_2,            // second raw command
    input  wire              tx_request,            // manual valid, held until tx_ready
    output wire              tx_ready,
    output wire              tx_busy,
    output reg               tx_queued,             // pulse: written into CAN FIFO
    output reg               tx_done,               // pulse: transmitted successfully
    output reg               init_done,
    output reg               feedback_valid,        // one sys_clk pulse
    output reg [12:0]         angle,                 // 0..8191, angle*360/8192 degrees
    output reg signed [15:0]  speed_rpm,
    output reg signed [15:0]  torque_current,        // raw signed feedback value
    output reg [7:0]          temperature,
    output reg               online,
    output reg               rx_overflow,           // sticky until reset
    output reg               fault,                 // IPIC timeout / bus-off; reset to retry
    output reg [31:0]         can_status,
    output reg [31:0]         can_irq_status,
    output reg               feedback_valid_2,      // second motor feedback pulse
    output reg [12:0]         angle_2,
    output reg signed [15:0]  speed_rpm_2,
    output reg signed [15:0]  torque_current_2,
    output reg [7:0]          temperature_2,
    output reg               online_2
);
    // Native Anlogic IPIC register indices, verified against CAN_gate.v.
    // These are NOT the Xilinx AXI CAN register offsets. Bits use [31:0].
    localparam [5:0] R_SRR=1, R_MSR=0, R_BRPR=2, R_BTR=3,
        R_SR=7, R_ISR=5, R_IER=4, R_ICR=6,
        R_TX_ID=23, R_TX_DLC=24, R_TX_DW1=25, R_TX_DW2=26,
        R_RX_ID=19, R_RX_DLC=20, R_RX_DW1=21, R_RX_DW2=22;
    localparam [10:0] RX_CAN_ID = 11'h204 + MOTOR_ID;
    localparam [10:0] RX_CAN_ID_2 = 11'h204 + MOTOR_ID_2;
    localparam [10:0] TX_CAN_ID = CURRENT_MODE ?
        ((MOTOR_ID <= 4) ? 11'h1fe : 11'h2fe) :
        ((MOTOR_ID <= 4) ? 11'h1ff : 11'h2ff);
    localparam integer SLOT = (MOTOR_ID-1) % 4;
    localparam integer SLOT_2 = (MOTOR_ID_2 > 0) ? (MOTOR_ID_2-1) % 4 : 0;
    localparam integer COMMAND_LIMIT = CURRENT_MODE ? 16384 : VOLTAGE_LIMIT;
    localparam integer TX_CYCLES = SYS_CLK_HZ / TX_HZ;
    localparam integer FEEDBACK_CYCLES = (SYS_CLK_HZ / 1000) * FEEDBACK_TIMEOUT_MS;
    localparam [31:0] BIT_TIMING = ((CAN_SJW-1)<<7) |
        ((CAN_TSEG2-1)<<4) | (CAN_TSEG1-1);

    localparam [5:0] RESET=0, CONFIG=1, CONFIG_CHECK=2, MODE=3,
        BRP=4, BTR=5, IER=6, CLEAR=7, ENABLE=8, START=9, START_CHECK=10,
        STATUS=11, STATUS_CHECK=12, IRQ_CHECK=13, DISPATCH=14,
        RX_ID=15, RX_DLC=16, RX_DW1=17, RX_DW2=18, RX_PARSE=19,
        TX_ID=20, TX_DLC=21, TX_DW1=22, TX_DW2=23, TX_FINISH=24,
        BUS_WAIT=25, BUS_GAP=26, FAULT=27;
    reg [5:0] state, return_state;
    reg [6:0] reset_count;
    reg [31:0] bus_count, tx_count, feedback_age, feedback_age_2;
    reg [5:0] bus_addr;
    reg bus_cs, bus_rnw;
    reg [31:0] bus_wdata, bus_rdata;
    wire [31:0] ip_data;
    wire ip_ack, ip_irq;
    wire ip_reset = !rst_n || (state == RESET) || fault;
    // The CAN core samples RX in can_clk domain.  Register the asynchronous
    // transceiver RXD first, with a recessive reset value, as required by the
    // CAN IP integration guide.
    reg can_rx_sync;
    reg pending, in_flight, auto_due;
    reg [63:0] tx_data;
    reg rx_pending, tx_full, prefer_rx;
    reg [31:0] rx_id_word, rx_dlc_word, rx_dw1;
    wire rx_frame_acceptable =
        !rx_id_word[20] && !rx_id_word[19] && !rx_id_word[0] &&
        (rx_dlc_word[31:28] == 4'd8) && (rx_dw1[31:29] == 0);
    wire rx_acceptable = rx_frame_acceptable &&
        (rx_id_word[31:21] == RX_CAN_ID);
    wire rx_acceptable_2 = rx_frame_acceptable && (MOTOR_ID_2 != 0) &&
        (rx_id_word[31:21] == RX_CAN_ID_2);

    assign tx_ready = init_done && !fault && !pending && !in_flight;
    assign tx_busy = pending || in_flight;

    always @(posedge can_clk or negedge rst_n) begin
        if (!rst_n) can_rx_sync <= 1'b1;
        else        can_rx_sync <= can_rx;
    end

    CAN u_can (
        .bus2ip_addr(bus_addr), .bus2ip_cs(bus_cs), .bus2ip_data(bus_wdata),
        .bus2ip_reset(ip_reset), .bus2ip_rnw(bus_rnw), .can_clk(can_clk),
        .can_phy_rx(can_rx_sync), .sys_clk(sys_clk), .can_phy_tx(can_tx),
        .ip2bus_ack(ip_ack), .ip2bus_data(ip_data), .ip2bus_intrevent(ip_irq)
    );

    function [15:0] limit_command;
        input signed [15:0] value;
        begin
            if (value > COMMAND_LIMIT) limit_command = COMMAND_LIMIT;
            else if (value < -COMMAND_LIMIT) limit_command = -COMMAND_LIMIT;
            else limit_command = value;
        end
    endfunction

    wire [15:0] limited_command = motor_enable ? limit_command(command) : 16'b0;
    wire [15:0] limited_command_2 = motor_enable_2 ?
        limit_command(command_2) : 16'b0;
    wire [63:0] command_frame =
        ({limited_command, 48'b0} >> (16*SLOT)) |
        ((MOTOR_ID_2 != 0) ?
         ({limited_command_2, 48'b0} >> (16*SLOT_2)) : 64'b0);

    // Hold request until ACK, then insert a low-CS gap for every transaction.
    task transact;
        input read_not_write;
        input [5:0] address;
        input [31:0] data;
        input [5:0] next_state;
        begin
            bus_addr <= address;
            bus_wdata <= data;
            bus_rnw <= read_not_write;
            bus_cs <= 1;
            bus_count <= 0;
            return_state <= next_state;
            state <= BUS_WAIT;
        end
    endtask

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET;
            return_state <= RESET;
            reset_count <= 0;
            bus_count <= 0;
            bus_addr <= 0;
            bus_cs <= 0;
            bus_rnw <= 1;
            bus_wdata <= 0;
            bus_rdata <= 0;
            tx_count <= 0;
            feedback_age <= 0;
            feedback_age_2 <= 0;
            init_done <= 0;
            fault <= 0;
            rx_overflow <= 0;
            can_status <= 0;
            can_irq_status <= 0;
            pending <= 0;
            in_flight <= 0;
            auto_due <= 0;
            tx_data <= 0;
            tx_queued <= 0;
            tx_done <= 0;
            rx_pending <= 0;
            tx_full <= 0;
            prefer_rx <= 1;
            rx_id_word <= 0;
            rx_dlc_word <= 0;
            rx_dw1 <= 0;
            feedback_valid <= 0;
            angle <= 0;
            speed_rpm <= 0;
            torque_current <= 0;
            temperature <= 0;
            online <= 0;
            feedback_valid_2 <= 0;
            angle_2 <= 0;
            speed_rpm_2 <= 0;
            torque_current_2 <= 0;
            temperature_2 <= 0;
            online_2 <= 0;
        end else begin
            tx_queued <= 0;
            tx_done <= 0;
            feedback_valid <= 0;
            feedback_valid_2 <= 0;
            if (online) begin
                if (feedback_age >= FEEDBACK_CYCLES-1) online <= 0;
                else feedback_age <= feedback_age + 1'b1;
            end
            if (online_2) begin
                if (feedback_age_2 >= FEEDBACK_CYCLES-1) online_2 <= 0;
                else feedback_age_2 <= feedback_age_2 + 1'b1;
            end

            // Coalesce missed ticks: no growing queue of stale motor commands.
            if (init_done && AUTO_SEND) begin
                if (tx_count >= TX_CYCLES-1) begin
                    tx_count <= 0;
                    auto_due <= 1;
                end else tx_count <= tx_count + 1'b1;
            end
            if (tx_ready && (AUTO_SEND ? auto_due : tx_request)) begin
                pending <= 1;
                auto_due <= 0;
                tx_data <= command_frame;
            end

            case (state)
                RESET: begin
                    if (reset_count == 63) state <= CONFIG;
                    else reset_count <= reset_count + 1'b1;
                end
                CONFIG: transact(1, R_SR, 0, CONFIG_CHECK);
                CONFIG_CHECK: begin
                    if (bus_rdata[0]) state <= MODE;
                    else state <= CONFIG;
                end
                // MSR at index 0 selects normal mode; SRR at index 1 keeps
                // CEN low until all timing/configuration writes are complete.
                MODE:   transact(0, R_MSR, 32'h00000000, BRP);
                BRP:    transact(0, R_BRPR, CAN_BRP, BTR);
                BTR:    transact(0, R_BTR, BIT_TIMING, IER);
                IER:    transact(0, R_IER, 0, CLEAR);
                CLEAR:  transact(0, R_ICR, 32'h00000fff, ENABLE);
                ENABLE: transact(0, R_SRR, 32'h00000002, START);
                START:  transact(1, R_SR, 0, START_CHECK);
                START_CHECK: begin
                    can_status <= bus_rdata;
                    if (bus_rdata[3]) begin
                        init_done <= 1;
                        state <= STATUS;
                    end else state <= START;
                end
                STATUS: transact(1, R_SR, 0, STATUS_CHECK);
                STATUS_CHECK: begin
                    can_status <= bus_rdata;
                    tx_full <= bus_rdata[10];
                    if (bus_rdata[8:7] == 2'b10) begin
                        fault <= 1;
                        state <= FAULT;
                    end else transact(1, R_ISR, 0, IRQ_CHECK);
                end
                IRQ_CHECK: begin
                    can_irq_status <= bus_rdata;
                    rx_pending <= bus_rdata[7];
                    if (bus_rdata[6]) rx_overflow <= 1;
                    if (bus_rdata[1] && in_flight) begin
                        tx_done <= 1;
                        in_flight <= 0;
                    end
                    if (bus_rdata[9]) begin
                        fault <= 1;
                        state <= FAULT;
                    end 
                    else
                        transact(0, R_ICR, bus_rdata & 32'h00000fff, DISPATCH);
                end
                DISPATCH: begin
                    if (rx_pending && (prefer_rx || !pending || in_flight || tx_full))
                        state <= RX_ID;
                    else if (pending && !in_flight && !tx_full) state <= TX_ID;
                    else state <= STATUS;
                end
                RX_ID: transact(1, R_RX_ID, 0, RX_DLC);
                RX_DLC: begin
                    rx_id_word <= bus_rdata;
                    transact(1, R_RX_DLC, 0, RX_DW1);
                end
                RX_DW1: begin
                    rx_dlc_word <= bus_rdata;
                    transact(1, R_RX_DW1, 0, RX_DW2);
                end
                RX_DW2: begin
                    rx_dw1 <= bus_rdata;
                    transact(1, R_RX_DW2, 0, RX_PARSE);
                end
                RX_PARSE: begin
                    // Read all four words even for frames that must be discarded.
                    if (rx_acceptable) begin
                        feedback_valid <= 1;
                        angle <= rx_dw1[28:16];
                        speed_rpm <= rx_dw1[15:0];
                        torque_current <= bus_rdata[31:16];
                        temperature <= bus_rdata[15:8];
                        online <= 1;
                        feedback_age <= 0;
                    end else if (rx_acceptable_2) begin
                        feedback_valid_2 <= 1;
                        angle_2 <= rx_dw1[28:16];
                        speed_rpm_2 <= rx_dw1[15:0];
                        torque_current_2 <= bus_rdata[31:16];
                        temperature_2 <= bus_rdata[15:8];
                        online_2 <= 1;
                        feedback_age_2 <= 0;
                    end
                    prefer_rx <= 0;
                    state <= STATUS;
                end
                TX_ID: transact(0, R_TX_ID, {TX_CAN_ID, 21'b0}, TX_DLC);
                TX_DLC: transact(0, R_TX_DLC, 32'h80000000, TX_DW1);
                TX_DW1: transact(0, R_TX_DW1, tx_data[63:32], TX_DW2);
                TX_DW2: transact(0, R_TX_DW2, tx_data[31:0], TX_FINISH);
                TX_FINISH: begin
                    pending <= 0;
                    in_flight <= 1;
                    tx_queued <= 1;
                    prefer_rx <= 1;
                    state <= STATUS;
                end
                BUS_WAIT: begin
                    if (ip_ack) begin
                        bus_rdata <= ip_data;
                        bus_cs <= 0;
                        bus_count <= 0;
                        state <= BUS_GAP;
                    end else if (bus_count >= BUS_TIMEOUT_CYCLES-1) begin
                        bus_cs <= 0;
                        fault <= 1;
                        state <= FAULT;
                    end else bus_count <= bus_count + 1'b1;
                end
                BUS_GAP: begin
                    if (!ip_ack) state <= return_state;
                    else if (bus_count >= BUS_TIMEOUT_CYCLES-1) begin
                        fault <= 1;
                        state <= FAULT;
                    end else bus_count <= bus_count + 1'b1;
                end
                FAULT: begin
                    bus_cs <= 0;
                    init_done <= 0;
                    pending <= 0;
                    in_flight <= 0;
                    online <= 0;
                    online_2 <= 0;
                end
                default: begin
                    fault <= 1;
                    state <= FAULT;
                end
            endcase
        end
    end

    // synthesis translate_off
    initial begin
        if (MOTOR_ID < 1 || MOTOR_ID > 7 || MOTOR_ID_2 < 0 || MOTOR_ID_2 > 7 ||
            (MOTOR_ID_2 != 0 && MOTOR_ID_2 == MOTOR_ID) ||
            (MOTOR_ID_2 != 0 && ((MOTOR_ID_2 <= 4) != (MOTOR_ID <= 4))) ||
            SYS_CLK_HZ < 1000 ||
            TX_HZ < 1 || TX_CYCLES < 1 || FEEDBACK_TIMEOUT_MS < 1 ||
            FEEDBACK_CYCLES < 1 || BUS_TIMEOUT_CYCLES < 1 ||
            CAN_BRP < 0 || CAN_BRP > 255 || CAN_TSEG1 < 1 || CAN_TSEG1 > 16 ||
            CAN_TSEG2 < 1 || CAN_TSEG2 > 8 || CAN_SJW < 1 || CAN_SJW > 4 ||
            CAN_SJW > CAN_TSEG2 || VOLTAGE_LIMIT < 1 || VOLTAGE_LIMIT > 30000 ||
            CAN_CLK_HZ != 1000000*(CAN_BRP+1)*(1+CAN_TSEG1+CAN_TSEG2))
            $fatal(1, "GM6020: invalid parameters / CAN bitrate is not 1 Mbit/s");
    end
    // synthesis translate_on
endmodule

create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
# SPI fast-mode minimum period is 80 ns; clock can stop between bytes and
# slows to 200 kHz during initialization. IO budgets require real-card/PCB
# validation and TD generated-clock matching; no first-stage blanket cuts.
create_generated_clock -name SD_SPI_CLK -source [get_ports {I_sys_clk}] -divide_by 4 [get_ports {O_sd_clk}]
set_output_delay -clock SD_SPI_CLK -max 10.000 [get_ports {O_sd_mosi O_sd_cs}]
set_output_delay -clock SD_SPI_CLK -min 0.000 [get_ports {O_sd_mosi O_sd_cs}]
set_input_delay -clock SD_SPI_CLK -clock_fall -max 15.000 [get_ports {I_sd_miso}]
set_input_delay -clock SD_SPI_CLK -clock_fall -min 0.000 [get_ports {I_sd_miso}]
# SD CE phase contract (photo_spi_byte FAST_HALF=2, LOW_HALF=125):
# MISO is sampled only on an SCLK rising CE, two sys clocks after the
# preceding falling CE. Byte gaps/initialization only lengthen that time.
# Move setup to that real capture edge; paired hold keeps input hold intact.
set_multicycle_path 2 -setup -end -from [get_ports {I_sd_miso}] -to [get_clocks {sys_clk_50m}]
set_multicycle_path 1 -hold -end -from [get_ports {I_sd_miso}] -to [get_clocks {sys_clk_50m}]
# MOSI changes on falling CE (or idle byte start), never on rising CE.
# CS releases after byte completion, INCLUDING timeout/FAILED exits.
# Both outputs change >=40 ns after the last rise. Advance hold launch by
# two sys periods, NOT two 80-ns SD periods. Output setup remains unchanged.
# This relies on the sd_photo_spi FAILED byte_busy guard; do not revert it
# independently or lower FAST_HALF below 2 without revisiting constraints.
# No feedback, unrelated IO, reset, or synchronizer path is exempted here.
set_multicycle_path 2 -hold -start -from [get_clocks {sys_clk_50m}] -to [get_ports {O_sd_mosi O_sd_cs}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {ETH_TX_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[2]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

# These are true two-stage, stable-enable/toggle synchronizers.
# Use TD's documented register collections (TD template set_false_path,
# example 2), rather than pin -regexp/-of/property combinations whose
# intended first-stage exceptions were absent in the current timing report.
# Register endpoint collections select the receiver register, independent of
# packed LUT input names. Explicit index 0 excludes the second stage.
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] \
    -to [get_regs {auto_mode_meta_24m auto_mode_meta_24m_reg*}]
set_false_path -from [get_clocks {pll_clk_24m}] \
    -to [get_regs {u_motion_gain_change_cdc/request_sync[0] u_motion_gain_change_cdc/request_sync_reg[0]*}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] \
    -to [get_regs {u_motion_gain_change_cdc/ack_sync[0] u_motion_gain_change_cdc/ack_sync_reg[0]*}]

# Command UART: external RX reaches only the first synchronizer input.
# TD can attach the input to an I_uart_rx_dup_N net after port duplication.
# Direct connectivity selects the first DATA input even if FFs are packed.
set_false_path -from [get_ports {I_uart_rx}] \
    -to [get_pins -of [get_nets -regexp {^I_uart_rx(_dup_[0-9]+)?$}] -regexp {^u_command_uart/commands/receiver/rx_(meta|sync).*\.(D|d|i[a-z]+)$}]

# Command mailbox toggles: direct net connectivity excludes the second stage.
# GUARD uses the same held-payload request/ack protocol. Only direct first
# synchronizer inputs are excepted; destination feedback/hold remain timed.
set_false_path -from [get_clocks {sys_clk_50m}] \
    -to [get_pins -of [get_nets -regexp {^(S_guard_req|u_command_uart/guard_source/request)$}] -regexp {^u_command_guard/request_sync.*\.(D|d|i[a-z]+)$}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] \
    -to [get_pins -of [get_nets -regexp {^(S_guard_ack|u_command_guard/ack)$}] -regexp {^u_command_uart/guard_source/ack_sync.*\.(D|d|i[a-z]+)$}]
set_max_delay -from [get_clocks {sys_clk_50m}] \
    -to [get_pins -of [get_nets {S_guard_source* u_command_uart/guard_source/payload*}] \
        -regexp {^u_command_guard/.*\.(D|d|e|i[a-z]+)$}] 20.000
# Payload is held through ACK; payload and destination logic remain timed.
set_false_path -from [get_clocks {sys_clk_50m}] \
    -to [get_pins -of [get_nets -regexp {^(S_uart_hdmi_req|u_command_uart/hdmi_source/request)$}] -regexp {^u_command_hdmi/request_sync.*\.(D|d|i[a-z]+)$}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] \
    -to [get_pins -of [get_nets -regexp {^(S_uart_hdmi_ack|u_command_hdmi/ack)$}] -regexp {^u_command_uart/hdmi_source/ack_sync.*\.(D|d|i[a-z]+)$}]
set_false_path -from [get_clocks {sys_clk_50m}] \
    -to [get_pins -of [get_nets -regexp {^(S_uart_csi_req|u_command_uart/csi_source/request)$}] -regexp {^u_command_csi/request_sync.*\.(D|d|i[a-z]+)$}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] \
    -to [get_pins -of [get_nets -regexp {^(S_uart_csi_ack|u_command_csi/ack)$}] -regexp {^u_command_uart/csi_source/ack_sync.*\.(D|d|i[a-z]+)$}]
set_false_path -from [get_clocks {sys_clk_50m}] \
    -to [get_pins -of [get_nets -regexp {^(S_uart_cam_req|u_command_uart/cam_source/request)$}] -regexp {^u_command_cam/request_sync.*\.(D|d|i[a-z]+)$}]
set_false_path -from [get_clocks {pll_clk_24m}] \
    -to [get_pins -of [get_nets -regexp {^(S_uart_cam_ack|u_command_cam/ack)$}] -regexp {^u_command_uart/cam_source/ack_sync.*\.(D|d|i[a-z]+)$}]

# UART CAM mailbox data is held until ACK and captured only after
# the two-stage request synchronizer. Bound this bundled data path
# to one sys50 period; keep hold and all destination feedback timed.
# A captured FF can share a packed cell named under u_ui_cam_cdc.
# Match only direct payload DATA inputs; never the whole packed cell.
set_max_delay -from [get_clocks {sys_clk_50m}] \
    -to [get_pins -of [get_nets {S_uart_cam_source* u_command_uart/cam_source/payload*}] \
        -regexp {^(u_command_cam|u_ui_cam_cdc)/.*\.(D|d|e|i[a-z]+)$}] 20.000

# Source-synchronous RGMII: clock and data use the same HDIO ODDR type.
# Keep the forwarded clock definition for clock visibility, but do not claim
# board-level TX data delay inside the FPGA core timing report. The PHY delay,
# package delay and PCB skew must be validated with the board Link/packet test.
create_generated_clock -name RGMII_TX_FWD -source [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[2]}] -master_clock ETH_TX_CLK -divide_by 1 [get_ports {O_eth_tx_clk}]
# No set_output_delay here: this is an external source-synchronous interface.
# The FPGA core timing result must be read together with board-level RGMII
# Link/packet validation, as done by the official/qzwtest flow.
# sync_ff is declared ONLY by target_reset_sync in the current source set.
# Its two ASYNC_REG flops intentionally accept asynchronous reset assertion.
# TD gate reports name these async pins .sr; packed reports use .asr.
# Do not cut D/enable/clock pins, downstream resets, ODDR.rst or DDR PHY.
# In particular, the second-stage DATA path is still timed.
# 2026-11-05: explicit target_reset_sync instances and async pins only.
# Include elaborated sync_ff[] and synthesized sync_ff_reg[] aliases.
# Match literal bit indices; never select a whole packed register/cell.
# Stage-1 DATA, downstream reset loads, ODDR and DDR IP remain timed.
# Static Tcl/name-fixture checks are not a TD live-collection/STA proof.
set_false_path -to [get_pins -regexp {^(u_(hdmi|cam|csi|ddr|lp|send)_reset|u_target_tx/(r0|core/r[01])|u_video_latency_monitor/(pixel|camera|ddr)_reset|u_hdmi_tx/u_hdmi2phy_wrapper/u[0-3]_lane_lvds_8_1/serial_reset)/sync_ff(_reg)?\[[01]\](_syn_[0-9]+)*\.(sr|asr)$}]
set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m SD_SPI_CLK pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK ETH_TX_CLK RGMII_TX_FWD}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
# Photo CDCs are held-data request/ack mailboxes inside the existing async
# domain groups, not arbitrary independently synchronized pixel buses.
# IMPORTANT: these clock-group exceptions also suppress setup for their held
# data and the expanded result FIFO. They are NOT proof of physical bus skew.
# After routing, inspect source-held->destination-data delay for u_photo_*_mail
# and u_photo_sector/{commands,responses}, the CSI frame ID->slot ID bundle,
# and result FIFO Gray pointer skew against their receiver clock periods.
# Do not add a blanket first/second-stage cut or treat a false-pathed bus as
# physically verified. No automatic TD implementation was performed here.

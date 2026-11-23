# Local Ethernet RTL

These RTL files are copied into this project so the project can be archived and shared without the sibling `target_eth_udp` directory.

- TX build dependencies: `target_eth_tx.v`, `target_udp_tx_core.v`, `target_yt8511_ctrl.v`, `target_mdio_master.v`, `target_async_fifo.v`, `target_reset_sync.v`, `target_rgmii_ph1p.v`
- Receiver RTL kept locally for reuse: `target_eth_rx.v`, `target_udp_rx_core.v`

The current `camera_to_dsi_display.al` registers the seven TX dependencies from this directory. The receiver files are kept available but are not added to this sender synthesis file list.

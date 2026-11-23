# Ethernet target receiver: three-flag24-byte protocol

Current packet specification is the sender's2026-10-31 update. The source path
provided for the other FPGA was unavailable on this host; this receiver follows
the exact byte/flag table supplied by the user.

| UDP payload offset | Bytes | Meaning |
| --- | --- | --- |
| 0..1 | 2 | A5 5A |
| 2 | 1 | Version01 |
| 3 | 1 | flags below |
| 4..7 | 4 | Monotonic32-bit sequence |
| 8..9 | 2 | Selected target ID |
| 10..11 | 2 | Selected center X |
| 12..13 | 2 | Selected center Y |
| 14..15 | 2 | Reserved zero |
| 16..19 | 4 | Distance, currently zero |
| 20..23 | 4 | Reserved zero |

All multibyte application fields use network byte order(high byte first).

| Flag | Mask | Meaning | Receiver output/use |
| --- | --- | --- | --- |
| bit0 | 01 | This packet's selected XY is valid | target_valid; visual tracking |
| bit1 | 02 | Selected valid center is within X560..720,Y315..405 inclusive | distance_valid legacy port; center-window status |
| bit2 | 04 | Scene has an effective target inside guard region | guard_inside; guard entry speech |
| bits7..3 | F8 | Reserved zero | Reject nonzero reserved bits |

Bit2 is scene-wide and need not describe the packet's selected target ID.
It is not a substitute for bit0.04 can announce entry before selected XY is
available;05 must track valid off-center coordinates even with bit1 clear.
03 does not announce guard entry, and07 keeps an existing entry active without
repeating speech.00..03 legacy packets remain accepted.

The old receiver incorrectly required flags[7:2]==0, rejecting04/05/07.
The new validator checks flags[7:3]==0. The CDC FIFO is115bits, with the new
guard bit appended above the original114-bit sequence/flags/ID/XY/distance
layout. All fields cross atomically with result_update.

Production chain:
ethernet_rx -> target_eth_rx -> target_udp_rx_core -> target_async_fifo.
guard_inside is wired through both wrappers to top.v. All application outputs
and counters except RX bad_frames/rx_overflow are synchronous to50MHz app_clk.

Visual tracking requires bit0, coordinates in0..1279/0..719 excluding(0,0),
the existing selected-ID policy and normal motor/communication readiness.
Neither bit1 nor bit2 nor a zero UDP distance suppresses coordinate tracking.
The shared stable/normal/fast control algorithms and current tuning are used.

Guard speech uses bit2 only, in the enabled confirmed feature/whole guard.
Entry speaks once, continued presence does not repeat, leaving/reentering
speaks again. It does not require bit0, usable XY, matching selected ID, local
TOF or settled motor feedback.25 supplies the feature voice code; no local
countdown is added.

Legacy distance_valid remains the bit1 center-window status. Only the chassis
distance-keeping permission uses it to qualify aligned local TOF readings.
Actual ranging remains the independent TOF UART; the zero network distance is
not used as a distance measurement. It never gates the visual tracking path.

Transport policy is preserved: fixed MACs02:00:00:00:00:01 -> :02,
IPv4192.168.10.1 ->192.168.10.2, UDP5000 ->5000, exact24-byte payload,
Ethernet FCS/IP checksum/nonzero UDP checksum validation, no ARP responder.
Sequence checks reject duplicate/stale results and count gaps. Link loss,
reset and the150ms app timeout clear all three flags. No PHY timing, pin,
clock, speed negotiation or LED behavior is changed.

RTL verification:

~~~powershell
& tests/protocol_flags3/run_core.ps1
& tests/protocol_flags3/run_core.ps1 -OldProtocol -SourceDir tmp/protocol_flags3_20261031/before/user_source/ethernet -WorkDir tmp/protocol_flags3_20261031/old_repro
& tests/protocol_flags3/run_top.ps1
~~~

The core suite feeds checksummed Ethernet frames across125/50MHz domains and
checks all00..07 flags, field ordering, zero distance,04 before XY, sequence
handling, invalid08/80, checksum faults, link loss and timeout.
The full-top suite uses both actual receiver wrappers, validator/FIFO, stable
visual control, UART and CAN driver. Only physical PHY/PLL/DDR and external
motor feedback are modeled. It checks05 static tracking and04/03/01/05/07
guard speech/tracking behavior. No synthesis, TD elaboration, placement,
routing or bit generation is run. Results:tmp/protocol_flags3_20261031/.

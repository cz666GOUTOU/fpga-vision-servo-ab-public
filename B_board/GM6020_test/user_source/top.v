`include "fpga_b_example_config.vh"

module top #(
	// ID2 follows the existing key/vision target; mode 1 enables the 180deg test.
	parameter integer GM6020_2_CONTINUOUS_TEST = 0,
	parameter integer GM6020_2_TEST_AUTOSTART = 0,

	// Reset value of the GM6020 target-angle register.  The controller uses
	// this register instead of the former 0/90/180/270-degree key selection.
	parameter [12:0] GM6020_INITIAL_ANGLE   = 13'd0,

	parameter [12:0] GM6020_2_INITIAL_ANGLE = 13'd0,

	parameter [12:0] GM6020_2_ZERO_OFFSET_COUNTS = 13'd4096,
	// Power-on/reset moves to the fixed logical zero before releasing modes.

	parameter integer STARTUP_HOME_ENABLE = 1,
	parameter integer STARTUP_HOME_SETTLE_MS = 100,
	parameter integer STARTUP_HOME_TOLERANCE_COUNTS = 23,

	// The measured motor/encoder convention is positive command -> increasing
	// encoder count, so the default must not reverse the closed-loop command.
	parameter integer GM6020_COMMAND_REVERSE = 0,
	parameter integer GM6020_2_COMMAND_REVERSE = 0,
	// Define the mechanical clockwise direction in encoder coordinates.  This
	// resolves the otherwise ambiguous 180-degree half-turn deterministically.
	parameter integer GM6020_CLOCKWISE_COUNT_INCREASE = 1,
	parameter integer GM6020_2_CLOCKWISE_COUNT_INCREASE = 1,

	// changes the single-turn target by this nearest integer number of counts.
	parameter [12:0] GM6020_STEP_20_DEG = 13'd455,
	// Camera target coordinates are independent of the motor target angles.
	parameter [15:0] X_TARGET_INITIAL = 16'd640,
	parameter [15:0] Y_TARGET_INITIAL = 16'd360,
	parameter integer VISION_ENABLE = 1,
	// 2C 02 only: final ID1/ID2 output LPF uses FAST_TRACKING_OUTPUT_FILTER_SHIFT.
	parameter integer FAST_TRACKING_OUTPUT_FILTER_SHIFT = `FPGA_B_TOP_FAST_TRACKING_OUTPUT_FILTER_SHIFT_1,
	// Nonlinear visual tracking; the UART feature mode adds region angle limits.
	parameter integer VISION_DELAY_MS = 23,
	parameter integer VISION_UPDATE_MS = 10,
	parameter integer VISION_ACQUIRE_MS = 80,

	// Invalid coordinates reuse the last good target for 300ms; packet silence
	// keeps this independent receive timeout.
	parameter integer VISION_RX_TIMEOUT_MS = 100,

	// of invalid records. Feature guard declares loss only after this grace.
	parameter integer VISION_INVALID_GRACE_MS = 300,
	parameter integer VISION_DEADBAND_PIXELS = 2,
	// Ordinary static tracking only: two fixed-zero sine sweeps on target loss.
	parameter integer PATROL_LOSS_MS = 2000,
	parameter integer PATROL_X_PERIOD_MS = 6000,
	parameter integer PATROL_Y_PERIOD_MS = 4000,
	// Minimum silence after a completed five-byte speech UART frame.
	parameter integer VOICE_COOLDOWN_MS = 3000,
	parameter integer FEATURE_OUTSIDE_TIMEOUT_MS = 5000,
	parameter integer FEATURE_HOME_SETTLE_MS = 100,
	// Both home-arrival checks use +/-23 counts, approximately +/-1 degree.
	parameter integer FEATURE_HOME_TOLERANCE_COUNTS = 23,

	parameter integer FEATURE_BOUNDARY_TOLERANCE_COUNTS = 23,
	// Physical forward polarity: A/RR=0, B/FR=1, C/FL=1, D/RL=0.
	// B/FR and D/RL drive and feedback signs are paired after calibration.
	parameter integer MOTOR_FL_FORWARD_LEVEL = 1,
	parameter integer MOTOR_FR_FORWARD_LEVEL = 1,
	parameter integer MOTOR_RL_FORWARD_LEVEL = 0,
	parameter integer MOTOR_RR_FORWARD_LEVEL = 0,
	// Independent TOFSense UART active-output stream, 50 MHz system clock.
	parameter integer TOF_BAUD_RATE = 921600,

	// The wheel circumference remains the existing provisional 204 mm.
	parameter integer CHASSIS_SPEED_CLOSED_LOOP = 1,
	parameter integer CHASSIS_WHEEL_CIRCUMFERENCE_MM = 204,
	parameter integer CHASSIS_ENCODER_CPR_A = 16384,
	parameter integer CHASSIS_ENCODER_CPR_B = 16384,
	parameter integer CHASSIS_ENCODER_CPR_C = 16384,
	parameter integer CHASSIS_ENCODER_CPR_D = 16384,
	// 1: 31 00/01/02/03 selects FL/RL/FR/RR individually, positive speed.
	// 0 (default): ordinary four-wheel forward/back/left/right movement.
	parameter integer CHASSIS_MANUAL_SINGLE_WHEEL = 0,
	parameter integer CHASSIS_MANUAL_COUNTS_10MS = 600,
	// 600 / 10 ms at 16384 counts/rev and 204 mm/rev ~= 747 mm/s.
	parameter integer CHASSIS_MANUAL_SPEED_MM_S =
		(64'd100*CHASSIS_MANUAL_COUNTS_10MS*CHASSIS_WHEEL_CIRCUMFERENCE_MM+CHASSIS_ENCODER_CPR_A/2)/CHASSIS_ENCODER_CPR_A,
	// Sight radial speed ceiling; retain the existing distance P/I/D gains,
	// wheel PI/ramp/PWM, distance deadband and validity stop behavior.
	parameter integer SIGHT_MAX_SPEED_MM_S = 3000,
	// Mecanum mixing can request sqrt(2) times the radial sight speed.
	// Round upward and reserve 1 mm/s for integer vector rounding.
	parameter integer CHASSIS_WHEEL_MAX_SPEED_MM_S =
		(CHASSIS_MANUAL_SPEED_MM_S>250?CHASSIS_MANUAL_SPEED_MM_S:250) > ((64'd46341*SIGHT_MAX_SPEED_MM_S+32767)/32768+1) ?
		(CHASSIS_MANUAL_SPEED_MM_S>250?CHASSIS_MANUAL_SPEED_MM_S:250) : ((64'd46341*SIGHT_MAX_SPEED_MM_S+32767)/32768+1),
	// Positive wheel travel: raw counts A/B decrease, C/D increase.
	// Correct C/FL feedback without changing its forward bridge level.
	parameter integer CHASSIS_ENCODER_REVERSE_A = 1,
	parameter integer CHASSIS_ENCODER_REVERSE_B = 1,
	parameter integer CHASSIS_ENCODER_REVERSE_C = 0,
	parameter integer CHASSIS_ENCODER_REVERSE_D = 0,
	parameter integer CHASSIS_SPEED_SAMPLE_MS = 10,


	parameter integer CHASSIS_MODEL_KP_Q24 = `FPGA_B_TOP_CHASSIS_MODEL_KP_Q24_1,
	parameter integer CHASSIS_MODEL_KI_STEP_Q24 = (`FPGA_B_CHASSIS_MODEL_KI_BASE_Q24*CHASSIS_SPEED_SAMPLE_MS+5)/10,
	parameter integer CHASSIS_MODEL_FF_Q24 = `FPGA_B_TOP_CHASSIS_MODEL_FF_Q24_1,
	parameter integer CHASSIS_REFERENCE_RATE = `FPGA_B_TOP_CHASSIS_REFERENCE_RATE_1,

	parameter integer CHASSIS_CLOSED_MAX_DUTY = 300,
	parameter integer CHASSIS_CLOSED_PWM_HZ = 1000,
	// HAL TIM3 filter 6: six samples at 18MHz (~333ns). At 50MHz,
	// require 17 consecutive equal samples (~340ns) on each AB input.
	parameter integer CHASSIS_ENCODER_FILTER_CYCLES = 17,
	parameter integer SIGHT_INITIAL_DISTANCE_MM = 1000,
	parameter integer SIGHT_FORWARD_ENCODER = 0,
	// ID1 count increase points left; only the chassis bearing mapping reverses.
	parameter integer SIGHT_ENCODER_INCREASE_RIGHT = 0,

	parameter integer SIGHT_PID_KP_Q16 = `FPGA_B_TOP_SIGHT_PID_KP_Q16_1,
	parameter integer SIGHT_PID_KI_STEP_Q16 = `FPGA_B_TOP_SIGHT_PID_KI_STEP_Q16_1,
	parameter integer SIGHT_PID_KD_STEP_Q8 = `FPGA_B_TOP_SIGHT_PID_KD_STEP_Q8_1,
	parameter integer SIGHT_PID_I_LIMIT_MM_S = `FPGA_B_TOP_SIGHT_PID_I_LIMIT_MM_S_1,
	parameter integer SIGHT_DEADBAND_MM = 20,
	parameter integer SIGHT_RESUME_MM = 30,
	parameter integer SIGHT_DISTANCE_TIMEOUT_MS = 250,
	// Legacy open-loop option retained for reference regression only.
	parameter integer CHASSIS_PWM_DUTY = 300,
	parameter integer CHASSIS_REVERSE_ROLLERS = 1
) (
	input  wire I_sys_clk,
	input  wire I_rst_n,
	input  wire can_rxd,
	input  wire I_uart_rx,
	input  wire I_tof_uart_rx,
	// E1=A/right rear, E2=B/right front, E3=C/left front, E4=D/left rear.
	input  wire E1A,E1B,E2A,E2B,E3A,E3B,E4A,E4B,
	output wire O_uart_tx,
	// Independent 115200 8N1 speech-module UART, FPGA TX -> module RX.
	output wire O_voice_tx,
	// U1, active-high laser enable; reset and all ineligible states drive low.
	output wire laser_en,
	input  wire I_eth_rx_clk,
	input  wire [3:0] I_eth_rxd,
	input  wire I_eth_rx_ctl,
	output wire [3:0] O_eth_txd,
	output wire O_eth_tx_ctl,
	output wire O_eth_tx_clk,
	output wire O_phy_reset_n,
	output wire O_eth_mdc,
	inout  wire IO_eth_mdio,
	output wire O_led1, O_led2, O_led3, O_led4,
	// Active-low keys: K1/K2 control ID 1, K3/K4 control ID 2.
	input  wire key1,
	input  wire key2,
	input  wire key3,
	input  wire key4,
	output wire can_txd,
	output wire M_POS_fl,
	output wire M_NEG_fl,
	output wire PWM_OUT_fl,
	output wire M_POS_fr,
	output wire M_NEG_fr,
	output wire PWM_OUT_fr,
	output wire M_POS_rl,
	output wire M_NEG_rl,
	output wire PWM_OUT_rl,
	output wire M_POS_rr,
	output wire M_NEG_rr,
	output wire PWM_OUT_rr,
	// Active-high standby release shared by both TB6612 drivers, pin B14.
	output wire O_chassis_stby,

	// Board LED13 green, pin A14.  The board LED is active low.
	output wire LED13_GREEN_N
);
	wire PLL_lock;
	// Independent local distance receiver. Values are millimetres; valid/error
	// are one-system-clock events, while distance_mm holds the last good frame.
	// Keep the local TOF interface available for later distance consumers.
	(* async_reg = "true" *) reg [1:0] tof_reset_release;
	always @(posedge I_sys_clk or negedge I_rst_n)
		if (!I_rst_n) tof_reset_release<=2'b00;
		else tof_reset_release<={tof_reset_release[0],1'b1};
	wire tof_distance_valid, tof_frame_error;
	wire [23:0] tof_distance_mm;
	tof_uart_rx #(.CLK_FREQ_HZ(50000000),.BAUD_RATE(TOF_BAUD_RATE)) u_tof_uart_rx (
		.clk(I_sys_clk), .rst(!tof_reset_release[1]), .sensor_tx(I_tof_uart_rx),
		.distance_valid(tof_distance_valid), .frame_error(tof_frame_error), .distance_mm(tof_distance_mm)
	);
	// Accepted UDP records are synchronous to I_sys_clk (50 MHz).
	// Camera coordinates feed the two outer visual tracking loops.
	wire eth_result_update, eth_target_valid, eth_distance_valid, eth_guard_inside;
	wire [15:0] eth_target_id, eth_center_x, eth_center_y;
	wire [31:0] eth_distance, eth_result_sequence;
	wire eth_comm_timeout, eth_link_ready, eth_phy_error;
	wire [31:0] eth_received_results, eth_stale_results, eth_missing_results;
	wire [31:0] eth_bad_frames, eth_phy_id;
	wire eth_rx_overflow;
	ethernet_rx u_ethernet_rx (
		.I_sys_clk(I_sys_clk), .rst_n(I_rst_n),
		.I_eth_rx_clk(I_eth_rx_clk), .I_eth_rxd(I_eth_rxd),
		.I_eth_rx_ctl(I_eth_rx_ctl), .O_eth_txd(O_eth_txd),
		.O_eth_tx_ctl(O_eth_tx_ctl), .O_eth_tx_clk(O_eth_tx_clk),
		.O_phy_reset_n(O_phy_reset_n), .O_eth_mdc(O_eth_mdc),
		.IO_eth_mdio(IO_eth_mdio),
		.O_led1(), .O_led2(), .O_led3(), .O_led4(),
		.result_update(eth_result_update), .target_valid(eth_target_valid),
		.distance_valid(eth_distance_valid), .guard_inside(eth_guard_inside), .target_id(eth_target_id),
		.center_x(eth_center_x), .center_y(eth_center_y),
		.distance(eth_distance), .result_sequence(eth_result_sequence),
		.comm_timeout(eth_comm_timeout), .link_ready(eth_link_ready),
		.phy_error(eth_phy_error), .received_results(eth_received_results),
		.stale_results(eth_stale_results), .missing_results(eth_missing_results),
		.bad_frames(eth_bad_frames), .phy_id(eth_phy_id), .rx_overflow(eth_rx_overflow)
	);
	// PLL C0 is 25 MHz. These CAN settings keep the bus at 1 Mbit/s.
	wire S_25m_clk;
	wire gm_init_done;
	wire gm_fault;
	wire gm_feedback_valid;
	wire [12:0] gm_angle;
	wire signed [15:0] gm_speed_rpm;
	wire gm_online;
	wire gm_motor_enable;
	wire signed [15:0] gm6020_command, gm6020_manual_command, gm6020_tracking_command;
	wire gm_feedback_valid_2;
	wire [12:0] gm_angle_2;
	wire signed [15:0] gm_speed_rpm_2;
	wire gm_online_2, gm_motor_enable_2;
	wire signed [15:0] gm6020_command_2;
	wire [7:0] gm_temperature_2;
	wire gm_model_fault_2;
	reg [12:0] gm6020_2_target_angle_reg;
	// Keep the target register in logical coordinates. Truncating the sum
	// to 13 bits implements modulo 8192, including the 360-degree wrap.
	wire [12:0] gm6020_2_encoder_target =
		gm6020_2_target_angle_reg + GM6020_2_ZERO_OFFSET_COUNTS;
	reg key3_meta, key3_sync, key3_stable, key3_stable_d;
	reg key4_meta, key4_sync, key4_stable, key4_stable_d;
	reg [18:0] key3_debounce_count, key4_debounce_count;
	wire key3_pressed, key4_pressed;
	// Runtime target register written by keys, UART manual mode, or vision.

	reg [12:0] gm6020_target_angle_reg;
	reg key1_meta, key1_sync, key1_stable, key1_stable_d;
	reg key2_meta, key2_sync, key2_stable, key2_stable_d;
	reg [18:0] key1_debounce_count, key2_debounce_count;
	wire key1_pressed, key2_pressed;
	// Reserved user-adjustable coordinate targets. Add a future register writer
	// to this same always block; do not drive these regs from a second block.
	reg [15:0] x_target, y_target;
	reg [15:0] vision_last_x_target, vision_last_y_target, vision_last_target_id;
	wire feature_guard_mode, feature_region_selected, all_target_guard_mode;
	wire feature_limits_ready;
	reg feature_guard_mode_d,all_target_guard_mode_d,feature_limits_ready_d;
	reg recognition_motors_disabled,recognition_motors_disabled_d;
	reg all_target_guard_applied;
	wire feature_return_override, feature_vision_suspend, manual_override;
	reg feature_vision_suspend_d;
	wire selected_tracking_mode,self_select_mode;
	reg selected_tracking_mode_d;
	wire patrol_active,patrol_bounds_ready;
	reg patrol_active_d;
	wire vision_target_changed;
	wire vision_clear_history = (feature_guard_mode != feature_guard_mode_d) ||
		(feature_limits_ready != feature_limits_ready_d) ||
		(all_target_guard_mode != all_target_guard_mode_d) ||
		(recognition_motors_disabled != recognition_motors_disabled_d) ||
		(feature_vision_suspend != feature_vision_suspend_d) ||
		(selected_tracking_mode != selected_tracking_mode_d) ||
		(patrol_active != patrol_active_d) ||
		(x_target != vision_last_x_target) ||
		(y_target != vision_last_y_target) ||
		vision_target_changed;
	// Both target angles and speed offsets come from the same visual update.
	wire vision_command_valid, vision_hold, vision_tracking_valid, vision_busy;
	wire signed [31:0] vision_target1, vision_target2, vision_velocity1, vision_velocity2;
	wire signed [31:0] gm_position1, gm_position2;
	wire gm_feedback_ready1, gm_feedback_ready2, gm_tracking_fault1;
	wire gm_at_target1, gm_at_target2;
	wire signed [31:0] gm_reference1, gm_reference2;
	reg vision_stream_active;
	reg [12:0] gm_origin1, gm_origin2;
	reg gm_origin_valid1, gm_origin_valid2;
	wire startup_home_pending,startup_home_ready,startup_home_done;
	wire signed [31:0] startup_home_target1,startup_home_target2;
	wire [12:0] startup_zero2=GM6020_2_INITIAL_ANGLE+GM6020_2_ZERO_OFFSET_COUNTS;
	// Keep the controllers' multi-turn coordinates continuous. The home
	// target is expressed relative to each first-feedback origin; the fixed
	// physical zero does not become a new discontinuous encoder origin.
	gimbal_startup_home #(
		.ENABLED(STARTUP_HOME_ENABLE),.SETTLE_MS(STARTUP_HOME_SETTLE_MS),
		.TOLERANCE_COUNTS(STARTUP_HOME_TOLERANCE_COUNTS),
		.CLOCKWISE_COUNT_INCREASE1(GM6020_CLOCKWISE_COUNT_INCREASE),
		.CLOCKWISE_COUNT_INCREASE2(GM6020_2_CLOCKWISE_COUNT_INCREASE)
	) u_startup_home (
		.clk(I_sys_clk),.rst_n(I_rst_n && PLL_lock),
		.feedback_ready(gm_feedback_ready1 && gm_feedback_ready2 && gm_origin_valid1 && gm_origin_valid2),
		.origin1(gm_origin1),.origin2(gm_origin2),.zero1(GM6020_INITIAL_ANGLE),.zero2(startup_zero2),
		.angle1(gm_angle),.angle2(gm_angle_2),.speed1(gm_speed_rpm),.speed2(gm_speed_rpm_2),
		.reference1(gm_reference1),.reference2(gm_reference2),.at_target1(gm_at_target1),.at_target2(gm_at_target2),
		.target1(startup_home_target1),.target2(startup_home_target2),
		.pending(startup_home_pending),.ready(startup_home_ready),.done(startup_home_done)
	);
	wire uart_manual_mode, uart_enter_manual, uart_dx_valid, uart_dy_valid;
	wire [1:0] tracking_mode;
	wire static_tracking_mode, static_tracking_hold;
	// Whole-region guard announces entries while holding the entry pose.
	// Reuse the existing fixed-pose registers instead of following live XY.
	wire visual_position_hold=static_tracking_hold || all_target_guard_mode;
	wire region_confirmed;
	wire uart_command_valid;
	wire [7:0] uart_command, uart_command_data;
	// Independent recognition interlock: only0A00/reset releases0A01.
	// Do not clear the selected tracking/guard owner or its target-ID lock.
	always @(posedge I_sys_clk or negedge I_rst_n)begin
		if(!I_rst_n)recognition_motors_disabled<=0;
		else if(uart_command_valid && uart_command==8'h0a && uart_command_data<=1)
			recognition_motors_disabled<=uart_command_data[0];
	end
	// Keep explicit ownership: distance mode's reused static flag and legacy
	// 38 03 must never acquire ordinary-static loss search.
	reg [1:0] patrol_owner;
	wire sight_selected,sight_active,sight_drive;
	// Selection is a child of an applied feature region or an explicit static
	// parent. Distance mode's reused static flag does not create that parent.
	wire self_select_parent_context=(feature_guard_mode && region_confirmed) ||
		(patrol_owner==1 && static_tracking_mode && !static_tracking_hold && !selected_tracking_mode);
	wire self_select_enter=uart_command_valid && uart_command==8'h38 &&
		(uart_command_data==1 || uart_command_data==3) && self_select_parent_context;
	wire self_select_leave=uart_command_valid && uart_command==8'h38 &&
		uart_command_data==0 && self_select_mode;
	wire patrol_restart=uart_command_valid &&
		uart_command==8'h2c && uart_command_data==3;
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if(!I_rst_n)patrol_owner<=0;
		else if(uart_command_valid)begin
			if(uart_command==8'h2c && uart_command_data==3)patrol_owner<=1;
			else if(uart_command==8'h2d && uart_command_data==1)patrol_owner<=2;
			else if((uart_command==8'h2c && uart_command_data==4 && static_tracking_mode) ||
				(uart_command==8'h2d && uart_command_data==0 && patrol_owner==2) ||
				(uart_command==8'h26 && uart_command_data<=1) ||
				(uart_command==8'h0e && uart_command_data==1) ||
				(uart_command==8'h28 && uart_command_data==1) ||
				(uart_command==8'h38 && uart_command_data==3 && !self_select_parent_context))patrol_owner<=0;
		end
	end
	// Retain acquisition-hold context when a running scan is stopped by
	// selection or distance entry; the separate enable below forbids motion.
	wire patrol_parent_enabled=static_tracking_mode &&
		(patrol_owner==1 || (patrol_owner==2 && sight_selected)) &&
		!selected_tracking_mode && !uart_manual_mode && !static_tracking_hold &&
		!feature_region_selected && !feature_guard_mode && !all_target_guard_mode;
	// Selection remains active across apply/cancel; only leaving selection
	// permits ordinary-static search. All distance states prohibit search.
	wire patrol_mode_enabled=patrol_parent_enabled && patrol_owner==1 && !sight_selected && !self_select_mode;
	wire signed [31:0] patrol_target1,patrol_target2,patrol_velocity1,patrol_velocity2;
	wire signed [31:0] patrol_min1,patrol_max1,patrol_min2,patrol_max2;
	reg patrol_handoff_hold;
	reg signed [31:0] patrol_hold_position1,patrol_hold_position2;
	reg static_target_locked;
	reg [15:0] static_target_id;
	wire eth_coordinate_valid=eth_target_valid && !eth_comm_timeout &&
		eth_center_x<1280 && eth_center_y<720 && (eth_center_x!=0 || eth_center_y!=0);

	// the upstream FPGA: never reject its coordinates because of a saved ID.
	wire static_target_matches=self_select_mode || selected_tracking_mode || !static_tracking_mode ||
		!static_target_locked || eth_target_id==static_target_id;
	// A no-target record (often ID=0) is a miss, not a source switch.
	// Only a usable target may replace the saved ID and reset its observer.
	assign vision_target_changed=eth_result_update && eth_coordinate_valid &&
		static_target_matches && eth_target_id!=vision_last_target_id;
	// 2C 03 selects the current valid target (or the first subsequent target).
	// Entering distance mode keeps that selection instead of taking a new ID.
	always @(posedge I_sys_clk or negedge I_rst_n)begin
		if(!I_rst_n)begin static_target_locked<=0;static_target_id<=0;end
		else if(self_select_enter || (uart_command_valid && uart_command==8'h38 && uart_command_data==3))begin
			static_target_locked<=0;static_target_id<=0;
		end else if(uart_command_valid && uart_command==8'h2c && uart_command_data==3)begin
			static_target_locked<=eth_coordinate_valid;static_target_id<=eth_target_id;
		end else if(uart_command_valid && uart_command==8'h2d && uart_command_data==1 &&
			(self_select_mode || selected_tracking_mode || (!static_tracking_mode && !static_tracking_hold)))begin
			static_target_locked<=eth_coordinate_valid;static_target_id<=eth_target_id;
		end else if(self_select_leave && static_tracking_mode)begin
			// Closing the child keeps static tracking and locks its current
			// upstream-selected target (or the first subsequent valid one).
			static_target_locked<=eth_coordinate_valid;static_target_id<=eth_target_id;
		end else if(self_select_mode || selected_tracking_mode || (!static_tracking_mode && !static_tracking_hold))static_target_locked<=0;
		else if(!static_target_locked && eth_result_update && eth_coordinate_valid)begin
			static_target_locked<=1;static_target_id<=eth_target_id;
		end
	end
	// All visual owners use the same saved stable/normal/fast profile.
	wire [1:0] vision_tracking_mode=tracking_mode;
	reg signed [31:0] static_hold_position1, static_hold_position2;
	wire signed [7:0] uart_dx, uart_dy;
	wire uart_step1_done, uart_step2_done;
	wire signed [9:0] uart_step1_counts, uart_step2_counts;
	// Retain region storage in hardware before the later motor-limiting stage
	// consumes it. Pixel coordinates: x=0..1279 and y=0..719, points 1..4.
	wire [15:0] region_point1_x, region_point1_y;
	wire [15:0] region_point2_x, region_point2_y;
	wire [15:0] region_point3_x, region_point3_y;
	wire [15:0] region_point4_x, region_point4_y;
	wire [2:0] region_selected_point;
	uart_gimbal_manual u_uart_manual (
		.clk(I_sys_clk), .rst_n(I_rst_n), .rx(I_uart_rx),
		.self_select_parent(self_select_parent_context),.self_select_mode(self_select_mode),
		.manual_mode(uart_manual_mode), .enter_manual(uart_enter_manual),
		.dx_valid(uart_dx_valid), .dy_valid(uart_dy_valid), .dx(uart_dx), .dy(uart_dy),
		.command_valid(uart_command_valid), .command_code(uart_command), .command_data(uart_command_data),
		.feature_guard_mode(feature_guard_mode), .feature_region_selected(feature_region_selected), .tracking_mode(tracking_mode),
		.static_tracking_mode(static_tracking_mode), .static_tracking_hold(static_tracking_hold),
		.all_target_guard_mode(all_target_guard_mode),.selected_tracking_mode(selected_tracking_mode)
	);
	// Whole-region application is independent of the editable feature points.
	wire region_store_command_valid=uart_command_valid && !(all_target_guard_mode &&
		uart_command==8'h21 && uart_command_data<=1);
	uart_region_store u_region_store (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock),
		.command_valid(region_store_command_valid), .command_code(uart_command), .command_data(uart_command_data),
		.point1_x(region_point1_x), .point1_y(region_point1_y),
		.point2_x(region_point2_x), .point2_y(region_point2_y),
		.point3_x(region_point3_x), .point3_y(region_point3_y),
		.point4_x(region_point4_x), .point4_y(region_point4_y),
		.selected_point(region_selected_point), .confirmed(region_confirmed)
	);
	wire signed [31:0] limited_vision_target1, limited_vision_target2;
	wire signed [31:0] limited_vision_velocity1, limited_vision_velocity2;
	wire signed [31:0] feature_angle_min1, feature_angle_max1;
	wire signed [31:0] feature_angle_min2, feature_angle_max2;
	wire signed [31:0] feature_initial_position1, feature_initial_position2;
	feature_region_limit #(
		// The calibrated visual goal is map(setpoint)-map(target). Both
		// pixel axes therefore map to DECREASING target encoder counts.
		// Manual clockwise preference is independent of this image mapping.
		.X_COUNT_INCREASE(0),
		.Y_COUNT_INCREASE(0)
	) u_feature_limits (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock), .armed(feature_guard_mode && !startup_home_pending),
		.confirmed(region_confirmed), .feedback_ready(gm_feedback_ready1 && gm_feedback_ready2),
		.point1_x(region_point1_x), .point1_y(region_point1_y),
		.point2_x(region_point2_x), .point2_y(region_point2_y),
		.point3_x(region_point3_x), .point3_y(region_point3_y),
		.point4_x(region_point4_x), .point4_y(region_point4_y),
		.setpoint_x(x_target), .setpoint_y(y_target), .position1(gm_position1), .position2(gm_position2),
		.target1(vision_target1), .target2(vision_target2),
		.velocity1(vision_velocity1), .velocity2(vision_velocity2),
		.limited_target1(limited_vision_target1), .limited_target2(limited_vision_target2),
		.limited_velocity1(limited_vision_velocity1), .limited_velocity2(limited_vision_velocity2),
		.ready(feature_limits_ready), .min1(feature_angle_min1), .max1(feature_angle_max1),
		.min2(feature_angle_min2), .max2(feature_angle_max2),
		.initial_position1(feature_initial_position1), .initial_position2(feature_initial_position2)
	);
	wire feature_home_done;
	feature_guard_return #(
		.CLK_HZ(50000000), .OUTSIDE_TIMEOUT_MS(FEATURE_OUTSIDE_TIMEOUT_MS),
		.TARGET_LOSS_MS(VISION_INVALID_GRACE_MS),
		.HOME_SETTLE_MS(FEATURE_HOME_SETTLE_MS),
		.BOUNDARY_TOLERANCE_COUNTS(FEATURE_BOUNDARY_TOLERANCE_COUNTS)
	) u_feature_return (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock), .armed(feature_guard_mode && !startup_home_pending),
		.limits_ready(feature_limits_ready), .feedback_ready(gm_feedback_ready1 && gm_feedback_ready2),
		.manual_override(manual_override || recognition_motors_disabled), .tracking_active(vision_stream_active && vision_tracking_valid && !vision_hold),
		.target_update(eth_result_update), .target_valid(eth_target_valid && !eth_comm_timeout),
		.center_x(eth_center_x), .center_y(eth_center_y),
		.point1_x(region_point1_x), .point1_y(region_point1_y),
		.point2_x(region_point2_x), .point2_y(region_point2_y),
		.point3_x(region_point3_x), .point3_y(region_point3_y),
		.point4_x(region_point4_x), .point4_y(region_point4_y),
		.target1(vision_target1), .target2(vision_target2),
		.min1(feature_angle_min1), .max1(feature_angle_max1),
		.min2(feature_angle_min2), .max2(feature_angle_max2),
		.initial_position1(feature_initial_position1), .initial_position2(feature_initial_position2),
		.position1(gm_position1), .position2(gm_position2),
		.reference1(gm_reference1), .reference2(gm_reference2),
		.at_target1(gm_at_target1), .at_target2(gm_at_target2),
		.vision_command_valid(vision_command_valid), .vision_hold(vision_hold), .vision_tracking(vision_tracking_valid),
		.return_override(feature_return_override), .vision_suspend(feature_vision_suspend), .home_done(feature_home_done)
	);
	wire feature_status_valid, feature_status_ready;
	wire [7:0] feature_status_data;
	feature_region_status u_feature_status (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock),
		.enabled(feature_guard_mode && region_confirmed && !uart_manual_mode && !recognition_motors_disabled),
		.limits_ready(feature_limits_ready),
		.target_update(vision_command_valid), .target_valid(eth_target_valid && vision_tracking_valid),
		.comm_timeout(eth_comm_timeout), .center_x(eth_center_x), .center_y(eth_center_y),
		.target1(vision_target1), .target2(vision_target2),
		.min1(feature_angle_min1), .max1(feature_angle_max1),
		.min2(feature_angle_min2), .max2(feature_angle_max2),
		.ready(feature_status_ready), .status_valid(feature_status_valid), .status_data(feature_status_data)
	);
	uart_guard_report u_uart_guard_report (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock), .home_request(feature_home_done),
		.status_enable(feature_status_ready), .status_valid(feature_status_valid), .status_data(feature_status_data),
		.tx(O_uart_tx), .busy()
	);
	// New packet flags[2] is scene-wide guard presence. It is independent of
	// flags[0] selected-target XY and flags[1] center-window status (legacy name
	// distance_valid). It may precede coordinates (the other FPGA owns the
	// requested delay). Before actual tracking, speech does not require selected
	// XY, local TOF or motor feedback. Tracking closes speech until a completed
	// automatic return opens the next entry-warning cycle.
	reg feature_voice_muted;
	wire feature_tracking_begin=feature_guard_mode && region_confirmed && feature_limits_ready &&
		!startup_home_pending && !manual_override && !recognition_motors_disabled && !feature_return_override && !feature_vision_suspend &&
		vision_stream_active && vision_tracking_valid;
	always @(posedge I_sys_clk or negedge I_rst_n)begin
		if(!I_rst_n)feature_voice_muted<=0;
		else if(!feature_guard_mode || !region_confirmed || feature_home_done ||
			(uart_command_valid && uart_command==8'h21 && uart_command_data==1))feature_voice_muted<=0;
		else if(feature_tracking_begin)feature_voice_muted<=1;
	end
	// 28 selects the whole-region workflow; 21 01/00 applies/cancels it.
	// Exits clear application, while repeated28 01 and profile changes retain
	// it. A stray21 01 outside the selected workflow cannot pre-arm a later entry.
	always @(posedge I_sys_clk or negedge I_rst_n)begin
		if(!I_rst_n)all_target_guard_applied<=0;
		else if(!all_target_guard_mode)all_target_guard_applied<=0;
		else if(uart_command_valid && uart_command==8'h21 && uart_command_data<=1)
			all_target_guard_applied<=uart_command_data[0];
	end
	// Revoke a pending request on the cancel event itself, including a cancel
	// coincident with cooldown expiry. An already-started frame still finishes.
	wire all_guard_cancel=uart_command_valid && uart_command==8'h21 && uart_command_data==0;
	guard_voice_control #(.COOLDOWN_MS(VOICE_COOLDOWN_MS)) u_guard_voice (
		.clk(I_sys_clk),.rst_n(I_rst_n),
		.feature_enabled(feature_guard_mode && region_confirmed && !uart_manual_mode),
		.feature_suppress(feature_voice_muted || feature_tracking_begin),
		.feature_rearm(feature_home_done),
		.all_enabled(all_target_guard_mode && all_target_guard_applied && !all_guard_cancel && !uart_manual_mode),
		.command_valid(uart_command_valid),.command_code(uart_command),.command_data(uart_command_data),
		.result_update(eth_result_update),.inside_flag(eth_guard_inside),.comm_timeout(eth_comm_timeout),
		.tx(O_voice_tx),.busy()
	);
	// Region selection is preparation, not guard activation. Until a fresh
	// confirmation, hold the streamed path unless explicit manual control owns it.
	wire feature_prepare_hold=feature_region_selected && !feature_guard_mode && !manual_override;
	// A region wholly to one side of the screen center can exclude the entry
	// pose. Do not clamp that idle pose into the region on application: bounds
	// govern actual visual tracking commands, not the wait for the first target.
	// Keep the visual observer running here so it can acquire/publish that goal.
	reg feature_tracking_command_ready;
	always @(posedge I_sys_clk or negedge I_rst_n)begin
		if(!I_rst_n)feature_tracking_command_ready<=0;
		else if(!feature_guard_mode || !feature_limits_ready ||
			manual_override || recognition_motors_disabled || startup_home_pending || feature_vision_suspend)
			feature_tracking_command_ready<=0;
		else if(vision_command_valid && vision_tracking_valid)feature_tracking_command_ready<=1;
	end
	// Once tracking has begun, retain its original hard bounds during the
	// invalid-coordinate/loss wait. Automatic return still bypasses them.
	wire feature_wait_hold=feature_guard_mode && !feature_return_override &&
		!feature_tracking_command_ready;
	gimbal_sine_search #(.LOSS_MS(PATROL_LOSS_MS),.RX_TIMEOUT_MS(VISION_RX_TIMEOUT_MS),
		.X_PERIOD_MS(PATROL_X_PERIOD_MS),.Y_PERIOD_MS(PATROL_Y_PERIOD_MS),
		.CLOCKWISE_COUNT_INCREASE1(GM6020_CLOCKWISE_COUNT_INCREASE),
		.CLOCKWISE_COUNT_INCREASE2(GM6020_2_CLOCKWISE_COUNT_INCREASE)) u_sine_search (
		.clk(I_sys_clk),.rst_n(I_rst_n && PLL_lock),
		.enable(VISION_ENABLE && !GM6020_2_CONTINUOUS_TEST && patrol_mode_enabled &&
			!startup_home_pending && !manual_override && !recognition_motors_disabled),.restart(patrol_restart),
		.feedback_ready(gm_feedback_ready1 && gm_feedback_ready2 && gm_origin_valid1 && gm_origin_valid2),
		.result_update(eth_result_update),.target_valid(eth_coordinate_valid && static_target_matches),
		.comm_timeout(eth_comm_timeout),.zero1(GM6020_INITIAL_ANGLE),.zero2(startup_zero2),
		.angle1(gm_angle),.angle2(gm_angle_2),.position1(gm_position1),.position2(gm_position2),
		.reference1(gm_reference1),.reference2(gm_reference2),.at_target1(gm_at_target1),.at_target2(gm_at_target2),
		.active(patrol_active),.bounds_ready(patrol_bounds_ready),
		.target1(patrol_target1),.target2(patrol_target2),
		.velocity1_q16(patrol_velocity1),.velocity2_q16(patrol_velocity2),
		.min1(patrol_min1),.max1(patrol_max1),.min2(patrol_min2),.max2(patrol_max2)
	);
	// Never expose the old scan or cached visual goal while the original
	// visual controller acquires the rediscovered target. Hold the exit pose
	// until it publishes the first fresh, complete two-axis tracking command.
	always @(posedge I_sys_clk or negedge I_rst_n)begin
		if(!I_rst_n)begin
			patrol_handoff_hold<=0;patrol_hold_position1<=0;patrol_hold_position2<=0;
		end else if(!patrol_parent_enabled || startup_home_pending || manual_override || recognition_motors_disabled ||
			!gm_feedback_ready1 || !gm_feedback_ready2)patrol_handoff_hold<=0;
		else if(patrol_active)begin
			patrol_handoff_hold<=1;patrol_hold_position1<=gm_position1;patrol_hold_position2<=gm_position2;
		end else if(vision_command_valid && vision_tracking_valid)patrol_handoff_hold<=0;
	end

	// The center-window bit belongs to the current selected coordinate record;
	// scene-wide flags[2] cannot authorize the laser. Invalid current records

	reg laser_strike_enabled;
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) laser_strike_enabled <= 1'b0;
		else if (uart_command_valid && uart_command==8'h66 &&
			(uart_command_data==8'h00 || uart_command_data==8'h01))
			laser_strike_enabled <= uart_command_data[0];
	end
	// A live centered target may legitimately assert vision_hold while still
	// tracking. Do not confuse that centered hold with loss/return suspension.
	assign laser_en = I_rst_n && PLL_lock && laser_strike_enabled &&
		!recognition_motors_disabled &&
		feature_guard_mode && region_confirmed && feature_limits_ready &&
		!startup_home_pending && !manual_override && !static_tracking_hold &&
		!feature_prepare_hold && !feature_return_override && !feature_vision_suspend &&
		vision_stream_active && vision_tracking_valid &&
		gm_motor_enable && gm_motor_enable_2 && gm_feedback_ready1 && gm_feedback_ready2 &&
		!gm_tracking_fault1 && !gm_model_fault_2 &&
		eth_coordinate_valid && static_target_matches && eth_distance_valid;
	// Selected tuning applies to visual following; preparation/home use stable.

	// envelope, then restore the user's unchanged tracking profile.
	wire [1:0] motor_tracking_mode=patrol_active?2'd2:
		((vision_tracking_valid && !patrol_handoff_hold && !startup_home_pending && !feature_return_override && !feature_prepare_hold && !feature_wait_hold && !visual_position_hold) ? vision_tracking_mode : 2'd0);
	wire signed [31:0] motor_target1=recognition_motors_disabled ? gm_position1 : startup_home_pending ? (startup_home_ready?startup_home_target1:gm_position1) :
		visual_position_hold ? static_hold_position1 : feature_return_override ? feature_initial_position1 :
		(feature_prepare_hold || feature_wait_hold) ? gm_position1 : patrol_active ? patrol_target1 :
		(patrol_handoff_hold ? patrol_hold_position1 : limited_vision_target1);
	wire signed [31:0] motor_target2=recognition_motors_disabled ? gm_position2 : startup_home_pending ? (startup_home_ready?startup_home_target2:gm_position2) :
		visual_position_hold ? static_hold_position2 : feature_return_override ? feature_initial_position2 :
		(feature_prepare_hold || feature_wait_hold) ? gm_position2 : patrol_active ? patrol_target2 :
		(patrol_handoff_hold ? patrol_hold_position2 : limited_vision_target2);
	wire signed [31:0] motor_velocity1=(recognition_motors_disabled || startup_home_pending || visual_position_hold || feature_return_override || feature_prepare_hold || feature_wait_hold) ? 32'sd0 :
		patrol_active ? patrol_velocity1 : patrol_handoff_hold ? 32'sd0 : limited_vision_velocity1;
	wire signed [31:0] motor_velocity2=(recognition_motors_disabled || startup_home_pending || visual_position_hold || feature_return_override || feature_prepare_hold || feature_wait_hold) ? 32'sd0 :
		patrol_active ? patrol_velocity2 : patrol_handoff_hold ? 32'sd0 : limited_vision_velocity2;
	wire motor_limits_enabled=patrol_bounds_ready || (feature_guard_mode && feature_limits_ready && !feature_return_override && !feature_wait_hold);
	wire signed [31:0] motor_min1=patrol_bounds_ready?patrol_min1:feature_angle_min1;
	wire signed [31:0] motor_max1=patrol_bounds_ready?patrol_max1:feature_angle_max1;
	wire signed [31:0] motor_min2=patrol_bounds_ready?patrol_min2:feature_angle_min2;
	wire signed [31:0] motor_max2=patrol_bounds_ready?patrol_max2:feature_angle_max2;

	// and subsequent feedback/XY changes cannot move the latched hold target.
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin static_hold_position1<=0;static_hold_position2<=0;end
		else if (startup_home_pending)begin
			static_hold_position1<=startup_home_target1;static_hold_position2<=startup_home_target2;
		end else if (!visual_position_hold ||
			(uart_command_valid && uart_command==8'h28 && uart_command_data==1 && !all_target_guard_mode)) begin
			static_hold_position1<=gm_position1;static_hold_position2<=gm_position2;
		end
	end
	gimbal_manual_step u_uart_step1 (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock),
		.clear(startup_home_pending || !uart_manual_mode || uart_enter_manual || key1_pressed || key2_pressed ||
			(gm_feedback_valid && !gm_origin_valid1)),
		.valid(uart_dx_valid), .units(uart_dx), .done(uart_step1_done), .counts(uart_step1_counts)
	);
	gimbal_manual_step u_uart_step2 (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock),
		.clear(startup_home_pending || !uart_manual_mode || uart_enter_manual || key3_pressed || key4_pressed ||
			(gm_feedback_valid_2 && !gm_origin_valid2)),
		.valid(uart_dy_valid), .units(uart_dy), .done(uart_step2_done), .counts(uart_step2_counts)
	);
	// Guard owns the bounded tracking path. Physical keys cannot select the
	// unbounded manual controller until an explicit UART manual-mode command.
	assign manual_override = uart_manual_mode || (!feature_guard_mode && !all_target_guard_mode &&
		(key1_pressed || key2_pressed || key3_pressed || key4_pressed));
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			gm_origin1 <= 0; gm_origin2 <= 0;
			gm_origin_valid1 <= 0; gm_origin_valid2 <= 0;
            vision_stream_active <= STARTUP_HOME_ENABLE || (VISION_ENABLE && !GM6020_2_CONTINUOUS_TEST);
		end else begin
			if (!gm_motor_enable) gm_origin_valid1 <= 0;
			else if (gm_feedback_valid && !gm_origin_valid1) begin gm_origin1 <= gm_angle; gm_origin_valid1 <= 1; end
			if (!gm_motor_enable_2) gm_origin_valid2 <= 0;
			else if (gm_feedback_valid_2 && !gm_origin_valid2) begin gm_origin2 <= gm_angle_2; gm_origin_valid2 <= 1; end
            if (recognition_motors_disabled || startup_home_pending)vision_stream_active<=1;
            else if (!VISION_ENABLE || GM6020_2_CONTINUOUS_TEST || manual_override)
				vision_stream_active <= 0;
            // Invalid guard bounds need streamed position hold. Ready bounds
            // retain the existing key/manual priority until vision reacquires.
            else if (patrol_active || patrol_handoff_hold || visual_position_hold || feature_return_override || feature_prepare_hold || feature_wait_hold || (feature_guard_mode && !feature_limits_ready)) vision_stream_active <= 1;
            else if (!gm_origin_valid1 || !gm_origin_valid2)
                vision_stream_active <= 1;
			else if (vision_command_valid) vision_stream_active <= 1;
		end
	end
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			x_target <= X_TARGET_INITIAL;
			y_target <= Y_TARGET_INITIAL;
		end
	end
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			feature_guard_mode_d <= 0;
			all_target_guard_mode_d <= 0;
			feature_limits_ready_d <= 0;
			recognition_motors_disabled_d <= 0;
			feature_vision_suspend_d <= 0;
			selected_tracking_mode_d <= 0;
			patrol_active_d <= 0;
			vision_last_x_target <= X_TARGET_INITIAL;
			vision_last_y_target <= Y_TARGET_INITIAL;
			vision_last_target_id <= 16'd0;
		end else begin
			feature_guard_mode_d <= feature_guard_mode;
			all_target_guard_mode_d <= all_target_guard_mode;
			feature_limits_ready_d <= feature_limits_ready;
			recognition_motors_disabled_d <= recognition_motors_disabled;
			feature_vision_suspend_d <= feature_vision_suspend;
			selected_tracking_mode_d <= selected_tracking_mode;
			patrol_active_d <= patrol_active;
			vision_last_x_target <= x_target;
			vision_last_y_target <= y_target;
			if (eth_result_update && eth_coordinate_valid && static_target_matches)
				vision_last_target_id <= eth_target_id;
		end
	end
	vision_nonlinear_ctrl #(
		.CLK_HZ(50000000), .DELAY_MS(VISION_DELAY_MS), .UPDATE_MS(VISION_UPDATE_MS),
		.ACQUIRE_MS(VISION_ACQUIRE_MS), .RX_TIMEOUT_MS(VISION_RX_TIMEOUT_MS),
		.INVALID_GRACE_MS(VISION_INVALID_GRACE_MS),
		.DEADBAND_PIXELS(VISION_DEADBAND_PIXELS)
	) u_vision_nonlinear (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock), .tracking_mode(vision_tracking_mode),
		.enable(VISION_ENABLE && !GM6020_2_CONTINUOUS_TEST && gm_motor_enable && gm_motor_enable_2),
		.manual_override(recognition_motors_disabled || startup_home_pending || manual_override || patrol_active || visual_position_hold || feature_prepare_hold || feature_vision_suspend || (feature_guard_mode && !feature_limits_ready)),
		.result_update(eth_result_update), .target_valid(eth_target_valid && static_target_matches),
        .comm_timeout(eth_comm_timeout), .clear_history(vision_clear_history),
        .source_change((feature_guard_mode != feature_guard_mode_d) ||
			(feature_limits_ready != feature_limits_ready_d) ||
			(all_target_guard_mode != all_target_guard_mode_d) ||
			(recognition_motors_disabled != recognition_motors_disabled_d) ||
            (feature_vision_suspend != feature_vision_suspend_d) ||
			(selected_tracking_mode != selected_tracking_mode_d) ||
			(patrol_active != patrol_active_d) ||
			vision_target_changed),
		.center_x(eth_center_x), .center_y(eth_center_y),
		.setpoint_x(x_target), .setpoint_y(y_target),
		.feedback_ready1(gm_feedback_ready1), .feedback_ready2(gm_feedback_ready2),
		.position1(gm_position1), .position2(gm_position2),
		.command_valid(vision_command_valid), .hold(vision_hold),
		.tracking(vision_tracking_valid), .busy(vision_busy),
		.target1(vision_target1), .target2(vision_target2),
		.velocity1_q16(vision_velocity1), .velocity2_q16(vision_velocity2),
		.predicted_x_q16(), .predicted_y_q16(), .error_x_q16(), .error_y_q16(), .hold_reason()
	);
	// Indicator functions are disabled. Drive each board LED to its off level.
	assign {O_led4,O_led3,O_led2,O_led1}=4'b0000;
	assign LED13_GREEN_N=1'b1;
	wire signed [31:0] speed_fl, speed_fr, speed_rl, speed_rr;
	wire signed [31:0] mixed_speed_fl,mixed_speed_fr,mixed_speed_rl,mixed_speed_rr;
	wire signed [15:0] forward_mm_s,lateral_mm_s,manual_forward,manual_lateral;
	wire signed [15:0] yaw_deg_s=16'sd0;
	wire [2:0] chassis_mode;
	wire chassis_drive_enable;

	// Keep explicit reset/startup initialization; PLL loss does not stop wheels.
	// Reset release takes two clocks, independently of the CAN/vision PLL.
	wire chassis_async_reset_n=I_rst_n;
	(* async_reg="true" *) reg [1:0] chassis_reset_sync=2'b00;
	always @(posedge I_sys_clk or negedge chassis_async_reset_n)begin
		if(!chassis_async_reset_n)chassis_reset_sync<=2'b00;
		else chassis_reset_sync<={chassis_reset_sync[0],1'b1};
	end
	wire chassis_reset_n=chassis_async_reset_n && chassis_reset_sync[1];
	wire heading_selected,heading_drive,heading_commit;
	wire signed [15:0] heading_forward,heading_lateral;
	localparam signed [15:0] MANUAL_SPEED=CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_MANUAL_SPEED_MM_S:1;
	// 39 high / 3A low: body-relative CCW translation in 26 01 mode.
	// The distance controller retains priority through prepare/cancel/apply.
	chassis_heading_control #(.SPEED_MM_S(MANUAL_SPEED)) u_chassis_heading (
		.clk(I_sys_clk),.rst_n(chassis_reset_n),.enabled(uart_manual_mode && !sight_selected),
		.command_valid(uart_command_valid),.command_code(uart_command),.command_data(uart_command_data),
		.selected(heading_selected),.drive_enable(heading_drive),.command_commit(heading_commit),
		.forward_mm_s(heading_forward),.lateral_mm_s(heading_lateral)
	);
	// The selected range controller owns motion through preparation/apply.
	// Ignore manual 31 packets while owned; keep 2D exits visible so the
	// manual latch stays stopped and cannot replay a queued direction.
	wire chassis_manual_command_valid=uart_command_valid &&
		(uart_command!=8'h31 || !sight_selected);
	wire heading_clear_manual=heading_commit && !(chassis_manual_command_valid &&
		uart_command==8'h31 && uart_command_data<=4);
	chassis_uart_control u_chassis_control (
		.clk(I_sys_clk),.rst_n(chassis_reset_n),
		// Clear the old 31 latch when a complete heading takes control. This
		// prevents a previous direction from replaying after 26 00 or FFFF.
		.command_valid(chassis_manual_command_valid || heading_commit),
		.command_code(heading_clear_manual?8'h31:uart_command),
		.command_data(heading_clear_manual?8'h04:uart_command_data),
		.mode(chassis_mode),.forward_unit(manual_forward),.lateral_unit(manual_lateral),.drive_enable(chassis_drive_enable)
	);
	// Legacy distance_valid is now flags[1] center-window status. It only
	// qualifies aligned local TOF samples for chassis distance holding; neither
	// this status nor flags[2] gates visual following. UDP distance is not used.
	wire sight_measurement_allowed=static_tracking_mode && static_target_locked &&
		static_target_matches && eth_coordinate_valid && eth_distance_valid &&
		vision_tracking_valid && !patrol_active && !patrol_handoff_hold && !manual_override && !static_tracking_hold && !recognition_motors_disabled;
	wire signed [15:0] sight_forward,sight_lateral;
	wire [15:0] sight_target_distance,sight_staged_distance;
	sight_distance_control #(
		.INITIAL_DISTANCE_MM(SIGHT_INITIAL_DISTANCE_MM),.FORWARD_ENCODER(SIGHT_FORWARD_ENCODER),
		.ENCODER_INCREASE_RIGHT(SIGHT_ENCODER_INCREASE_RIGHT),.MAX_SPEED_MM_S(SIGHT_MAX_SPEED_MM_S),
		.DEADBAND_MM(SIGHT_DEADBAND_MM),.RESUME_MM(SIGHT_RESUME_MM),
		.DISTANCE_TIMEOUT_MS(SIGHT_DISTANCE_TIMEOUT_MS),
		.PID_KP_Q16(SIGHT_PID_KP_Q16),.PID_KI_STEP_Q16(SIGHT_PID_KI_STEP_Q16),
		.PID_KD_STEP_Q8(SIGHT_PID_KD_STEP_Q8),.PID_I_LIMIT_MM_S(SIGHT_PID_I_LIMIT_MM_S)
	) u_sight_distance (
		.clk(I_sys_clk),.rst_n(chassis_reset_n),.command_valid(uart_command_valid),
		.command_code(uart_command),.command_data(uart_command_data),
		.distance_valid(tof_distance_valid),.distance_mm(tof_distance_mm),
		.measurement_allowed(sight_measurement_allowed),
		.bearing_ready(gm_motor_enable),.bearing_encoder(gm_angle),
		.selected(sight_selected),.active(sight_active),.drive_enable(sight_drive),
		.forward_mm_s(sight_forward),.lateral_mm_s(sight_lateral),
		.target_distance_mm(sight_target_distance),.staged_distance_mm(sight_staged_distance)
	);
	assign forward_mm_s=sight_selected?sight_forward:heading_selected?heading_forward:
		(manual_forward==0?16'sd0:(manual_forward>0?MANUAL_SPEED:-MANUAL_SPEED));
	assign lateral_mm_s=sight_selected?sight_lateral:heading_selected?heading_lateral:
		(manual_lateral==0?16'sd0:(manual_lateral>0?MANUAL_SPEED:-MANUAL_SPEED));
	car #(.REVERSE_ROLLERS(CHASSIS_REVERSE_ROLLERS)) m_car (
		.clk(I_sys_clk),
		.rst_n(chassis_reset_n),
		.in_valid(1'b1),
		.forward_mm_s(forward_mm_s),
		.lateral_mm_s(lateral_mm_s),
		.yaw_deg_s(yaw_deg_s),
		.out_valid(),
		// Wheel peripheral LINEAR speeds, mm/s; not encoder counts or RPM.
		// Wide outputs preserve mixed-command sums without wrap or clipping.
		.speed_fl(mixed_speed_fl),
		.speed_fr(mixed_speed_fr),
		.speed_rl(mixed_speed_rl),
		.speed_rr(mixed_speed_rr)
	);
	// Diagnostic manual selection; lane order is A/RR,B/FR,C/FL,D/RL.
	// Distance holding keeps its original mecanum vector and all four outputs.
	wire [3:0] manual_wheel_select={chassis_mode==3'd1,chassis_mode==3'd0,
		chassis_mode==3'd2,chassis_mode==3'd3};
	wire single_wheel_manual=CHASSIS_MANUAL_SINGLE_WHEEL && !sight_selected && !heading_selected;
	wire [3:0] wheel_output_select=single_wheel_manual?manual_wheel_select:4'b1111;
	assign speed_rr=single_wheel_manual?(manual_wheel_select[0]?$signed(MANUAL_SPEED):32'sd0):mixed_speed_rr;
	assign speed_fr=single_wheel_manual?(manual_wheel_select[1]?$signed(MANUAL_SPEED):32'sd0):mixed_speed_fr;
	assign speed_fl=single_wheel_manual?(manual_wheel_select[2]?$signed(MANUAL_SPEED):32'sd0):mixed_speed_fl;
	assign speed_rl=single_wheel_manual?(manual_wheel_select[3]?$signed(MANUAL_SPEED):32'sd0):mixed_speed_rl;
	localparam [9:0] CHASSIS_DUTY=CHASSIS_PWM_DUTY<0 ? 0 :
		(CHASSIS_PWM_DUTY>1000 ? 1000 : CHASSIS_PWM_DUTY);
	localparam integer WHEEL_DUTY_W=CHASSIS_SPEED_CLOSED_LOOP?14:10;
	wire [WHEEL_DUTY_W-1:0] mot_speed_fl,mot_speed_fr,mot_speed_rl,mot_speed_rr;
	wire mot_fl_direction,mot_fr_direction,mot_rl_direction,mot_rr_direction;
	wire [3:0] wheel_drive,wheel_fault;
	wire signed [31:0] encoder_count_rr,encoder_count_fr,encoder_count_fl,encoder_count_rl;
	wire chassis_request=sight_selected?sight_drive:heading_selected?heading_drive:chassis_drive_enable;
	wire chassis_fault=|wheel_fault;
	wire chassis_enable=chassis_reset_n && chassis_request &&
		(CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_CLOSED_MAX_DUTY!=0:CHASSIS_DUTY!=0);
	// No automatic wheel fault latch or group-stop interlock. Compatibility
	// fault outputs are tied low by the HAL wheel modules.
	wire wheel_fault_clear=1'b0;
	// The shared inner loop expresses all targets as counts per nominal 10 ms.

	localparam integer CHASSIS_ENCODER_CPR_AB_MAX=CHASSIS_ENCODER_CPR_A>CHASSIS_ENCODER_CPR_B?CHASSIS_ENCODER_CPR_A:CHASSIS_ENCODER_CPR_B;
	localparam integer CHASSIS_ENCODER_CPR_CD_MAX=CHASSIS_ENCODER_CPR_C>CHASSIS_ENCODER_CPR_D?CHASSIS_ENCODER_CPR_C:CHASSIS_ENCODER_CPR_D;
	localparam integer CHASSIS_ENCODER_CPR_MAX=CHASSIS_ENCODER_CPR_AB_MAX>CHASSIS_ENCODER_CPR_CD_MAX?CHASSIS_ENCODER_CPR_AB_MAX:CHASSIS_ENCODER_CPR_CD_MAX;
	localparam integer CHASSIS_WHEEL_TARGET_COUNTS_FROM_SPEED=(64'd1*CHASSIS_WHEEL_MAX_SPEED_MM_S*CHASSIS_ENCODER_CPR_MAX*10+CHASSIS_WHEEL_CIRCUMFERENCE_MM*1000-1)/(CHASSIS_WHEEL_CIRCUMFERENCE_MM*1000);
	localparam integer CHASSIS_WHEEL_TARGET_LIMIT_COUNTS=CHASSIS_WHEEL_TARGET_COUNTS_FROM_SPEED>1000?CHASSIS_WHEEL_TARGET_COUNTS_FROM_SPEED:1000;
	generate if(CHASSIS_SPEED_CLOSED_LOOP)begin:closed_wheels
		chassis_four_wheel_shared #(
			.ENCODER_CPR_A(CHASSIS_ENCODER_CPR_A),.ENCODER_CPR_B(CHASSIS_ENCODER_CPR_B),
			.ENCODER_CPR_C(CHASSIS_ENCODER_CPR_C),.ENCODER_CPR_D(CHASSIS_ENCODER_CPR_D),
			.ENCODER_REVERSE_MASK({CHASSIS_ENCODER_REVERSE_D!=0,CHASSIS_ENCODER_REVERSE_C!=0,
				CHASSIS_ENCODER_REVERSE_B!=0,CHASSIS_ENCODER_REVERSE_A!=0}),
			.FORWARD_LEVEL_MASK({MOTOR_RL_FORWARD_LEVEL!=0,MOTOR_FL_FORWARD_LEVEL!=0,
				MOTOR_FR_FORWARD_LEVEL!=0,MOTOR_RR_FORWARD_LEVEL!=0}),
			.CIRCUMFERENCE_MM(CHASSIS_WHEEL_CIRCUMFERENCE_MM),
			.SAMPLE_MS(CHASSIS_SPEED_SAMPLE_MS),.MAX_SPEED_MM_S(CHASSIS_WHEEL_MAX_SPEED_MM_S),
			.TARGET_LIMIT_COUNTS(CHASSIS_WHEEL_TARGET_LIMIT_COUNTS),
			.KP_Q24(CHASSIS_MODEL_KP_Q24),.KI_STEP_Q24(CHASSIS_MODEL_KI_STEP_Q24),
			.FEEDFORWARD_Q24(CHASSIS_MODEL_FF_Q24),.REFERENCE_RATE(CHASSIS_REFERENCE_RATE),
			.MAX_DUTY(CHASSIS_CLOSED_MAX_DUTY)) shared(
			.clk(I_sys_clk),.rst_n(chassis_reset_n),.enable(chassis_request),
			// Distance PID already supplies the speed reference; do not add
			// the manual-motion acceleration/deceleration ramp in this owner.
			.bypass_speed_ramp(sight_selected),
			.target_mm_s_bus({speed_rl,speed_fl,speed_fr,speed_rr}),
			.encoder_count_bus({encoder_count_rl,encoder_count_fl,encoder_count_fr,encoder_count_rr}),
			.duty_bus({mot_speed_rl,mot_speed_fl,mot_speed_fr,mot_speed_rr}),
			.direction({mot_rl_direction,mot_fl_direction,mot_fr_direction,mot_rr_direction}),
			.drive_enable(wheel_drive),.fault(wheel_fault));
	end else begin:legacy_wheels
		assign mot_speed_fl=speed_fl==0?10'd0:CHASSIS_DUTY;
		assign mot_speed_fr=speed_fr==0?10'd0:CHASSIS_DUTY;
		assign mot_speed_rl=speed_rl==0?10'd0:CHASSIS_DUTY;
		assign mot_speed_rr=speed_rr==0?10'd0:CHASSIS_DUTY;
		assign mot_fl_direction=speed_fl>=0?MOTOR_FL_FORWARD_LEVEL:!MOTOR_FL_FORWARD_LEVEL;
		assign mot_fr_direction=speed_fr>=0?MOTOR_FR_FORWARD_LEVEL:!MOTOR_FR_FORWARD_LEVEL;
		assign mot_rl_direction=speed_rl>=0?MOTOR_RL_FORWARD_LEVEL:!MOTOR_RL_FORWARD_LEVEL;
		assign mot_rr_direction=speed_rr>=0?MOTOR_RR_FORWARD_LEVEL:!MOTOR_RR_FORWARD_LEVEL;
		assign wheel_drive=4'b1111;assign wheel_fault=4'b0000;
	end endgenerate
	// Raise STBY as soon as a movement command latches, before the existing
	// 20 us blank interval ends and PWM starts. Keep STBY high on direction
	// changes; explicit stop/reset and a zero configured limit enter standby.
	// External STBY pull-down is needed before FPGA configuration completes.
	assign O_chassis_stby=chassis_reset_n &&
		(sight_selected?sight_drive:heading_selected?heading_drive:chassis_mode<3'd4) &&
		(CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_CLOSED_MAX_DUTY!=0:CHASSIS_DUTY!=0);

	chassis_encoder_ab #(.FILTER_CYCLES(CHASSIS_ENCODER_FILTER_CYCLES)) u_encoder_a(.clk(I_sys_clk),.rst_n(chassis_reset_n),.a(E1A),.b(E1B),.count(encoder_count_rr),.step_valid(),.step_positive(),.invalid_transition());
	chassis_encoder_ab #(.FILTER_CYCLES(CHASSIS_ENCODER_FILTER_CYCLES)) u_encoder_b(.clk(I_sys_clk),.rst_n(chassis_reset_n),.a(E2A),.b(E2B),.count(encoder_count_fr),.step_valid(),.step_positive(),.invalid_transition());
	chassis_encoder_ab #(.FILTER_CYCLES(CHASSIS_ENCODER_FILTER_CYCLES)) u_encoder_c(.clk(I_sys_clk),.rst_n(chassis_reset_n),.a(E3A),.b(E3B),.count(encoder_count_fl),.step_valid(),.step_positive(),.invalid_transition());
	chassis_encoder_ab #(.FILTER_CYCLES(CHASSIS_ENCODER_FILTER_CYCLES)) u_encoder_d(.clk(I_sys_clk),.rst_n(chassis_reset_n),.a(E4A),.b(E4B),.count(encoder_count_rl),.step_valid(),.step_positive(),.invalid_transition());

	// Debounce the active-low board keys for 10 ms before producing one press
	// event.  This prevents a mechanical bounce from issuing several 20-degree
	// target steps.
	assign key1_pressed = key1_stable_d && !key1_stable;
	assign key2_pressed = key2_stable_d && !key2_stable;
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			key1_meta <= 1'b1;
			key1_sync <= 1'b1;
			key1_stable <= 1'b1;
			key1_stable_d <= 1'b1;
			key1_debounce_count <= 19'd0;
			key2_meta <= 1'b1;
			key2_sync <= 1'b1;
			key2_stable <= 1'b1;
			key2_stable_d <= 1'b1;
			key2_debounce_count <= 19'd0;
		end else begin
			key1_meta <= key1;
			key1_sync <= key1_meta;
			key1_stable_d <= key1_stable;
			if (key1_sync != key1_stable) begin
				if (key1_debounce_count >= 19'd499999) begin
					key1_stable <= key1_sync;
					key1_debounce_count <= 19'd0;
				end else
					key1_debounce_count <= key1_debounce_count + 1'b1;
			end else
				key1_debounce_count <= 19'd0;

			key2_meta <= key2;
			key2_sync <= key2_meta;
			key2_stable_d <= key2_stable;
			if (key2_sync != key2_stable) begin
				if (key2_debounce_count >= 19'd499999) begin
					key2_stable <= key2_sync;
					key2_debounce_count <= 19'd0;
				end else
					key2_debounce_count <= key2_debounce_count + 1'b1;
			end else
				key2_debounce_count <= 19'd0;
		end
	end

	assign key3_pressed = key3_stable_d && !key3_stable;
	assign key4_pressed = key4_stable_d && !key4_stable;
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			key3_meta <= 1'b1;
			key3_sync <= 1'b1;
			key3_stable <= 1'b1;
			key3_stable_d <= 1'b1;
			key3_debounce_count <= 19'd0;
			key4_meta <= 1'b1;
			key4_sync <= 1'b1;
			key4_stable <= 1'b1;
			key4_stable_d <= 1'b1;
			key4_debounce_count <= 19'd0;
		end else begin
			key3_meta <= key3;
			key3_sync <= key3_meta;
			key3_stable_d <= key3_stable;
			if (key3_sync != key3_stable) begin
				if (key3_debounce_count >= 19'd499999) begin
					key3_stable <= key3_sync;
					key3_debounce_count <= 19'd0;
				end else
					key3_debounce_count <= key3_debounce_count + 1'b1;
			end else
				key3_debounce_count <= 19'd0;

			key4_meta <= key4;
			key4_sync <= key4_meta;
			key4_stable_d <= key4_stable;
			if (key4_sync != key4_stable) begin
				if (key4_debounce_count >= 19'd499999) begin
					key4_stable <= key4_sync;
					key4_debounce_count <= 19'd0;
				end else
					key4_debounce_count <= key4_debounce_count + 1'b1;
			end else
				key4_debounce_count <= 19'd0;
		end
	end

	// GM6020_pos_ctrl reads this target register. K1 steps clockwise by 20

	// naturally wraps the target within 0..8191.
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n)
			gm6020_target_angle_reg <= GM6020_INITIAL_ANGLE;
        else if (startup_home_pending)
            gm6020_target_angle_reg <= GM6020_INITIAL_ANGLE;
        else if (uart_enter_manual && gm_motor_enable)
            gm6020_target_angle_reg <= gm_angle;
        else if (VISION_ENABLE && !GM6020_2_CONTINUOUS_TEST && gm_feedback_valid && !gm_origin_valid1)
            gm6020_target_angle_reg <= gm_angle;
        else if (!feature_guard_mode && !all_target_guard_mode && key1_pressed && !key2_pressed)
			gm6020_target_angle_reg <= GM6020_CLOCKWISE_COUNT_INCREASE ?
				gm6020_target_angle_reg + GM6020_STEP_20_DEG :
				gm6020_target_angle_reg - GM6020_STEP_20_DEG;
		else if (!feature_guard_mode && !all_target_guard_mode && key2_pressed && !key1_pressed)
			gm6020_target_angle_reg <= GM6020_CLOCKWISE_COUNT_INCREASE ?
				gm6020_target_angle_reg - GM6020_STEP_20_DEG :
				gm6020_target_angle_reg + GM6020_STEP_20_DEG;
		else if (uart_manual_mode && uart_step1_done)
			gm6020_target_angle_reg <= GM6020_CLOCKWISE_COUNT_INCREASE ?
				gm6020_target_angle_reg + {{3{uart_step1_counts[9]}}, uart_step1_counts} :
				gm6020_target_angle_reg - {{3{uart_step1_counts[9]}}, uart_step1_counts};
		else if ((vision_command_valid || patrol_active || patrol_handoff_hold || visual_position_hold || feature_return_override || feature_prepare_hold || feature_wait_hold) && !manual_override)
			gm6020_target_angle_reg <= gm_origin1 + motor_target1[12:0];
	end
	assign gm_motor_enable = gm_init_done && gm_online && !gm_fault;
	GM6020_pos_ctrl #(
		.CLK_HZ(50000000),
		.COMMAND_REVERSE(GM6020_COMMAND_REVERSE),
		.CLOCKWISE_COUNT_INCREASE(GM6020_CLOCKWISE_COUNT_INCREASE),
		.FEEDBACK_TIMEOUT_MS(10)
	) u_gm6020_pos_ctrl (
		.clk(I_sys_clk),
		.rst_n(I_rst_n && PLL_lock),
		.enable(gm_motor_enable),
		.feedback_valid(gm_feedback_valid),
		.angle(gm_angle),
		.speed_rpm(gm_speed_rpm),
		.target_angle_register(gm6020_target_angle_reg),
		.command(gm6020_manual_command),
		.active(),
		.position_counts(),
		.target_counts(),
		.acceleration_rpm_s(),
		.position_error_counts()
	);

	// Original ID1 cascade remains the manual/key controller. Visual mode uses

	GM6020_dual_model_ctrl #(
		.CLK_HZ(50000000),
		.COMMAND_REVERSE_A(GM6020_COMMAND_REVERSE),
		.CLOCKWISE_COUNT_INCREASE_A(GM6020_CLOCKWISE_COUNT_INCREASE),
		.MODEL_INV_K_Q16_A(`FPGA_B_TOP_MODEL_INV_K_Q16_A_1),
		.MODEL_KP_Q16_A(`FPGA_B_TOP_MODEL_KP_Q16_A_1),
		.MODEL_KI_DT_Q16_A(`FPGA_B_TOP_MODEL_KI_DT_Q16_A_1),
		.MODEL_TAU_Q24_A(`FPGA_B_TOP_MODEL_TAU_Q24_A_1),
		.NORMAL_KP_Q16_A(`FPGA_B_TOP_NORMAL_KP_Q16_A_1),
		.NORMAL_KI_DT_Q16_A(`FPGA_B_TOP_NORMAL_KI_DT_Q16_A_1),
		.FAST_KP_Q16_A(`FPGA_B_TOP_FAST_KP_Q16_A_1),
		.FAST_KI_DT_Q16_A(`FPGA_B_TOP_FAST_KI_DT_Q16_A_1),
		.FAST_OUTPUT_FILTER_SHIFT_A(FAST_TRACKING_OUTPUT_FILTER_SHIFT),
		.MAX_SPEED_Q16_A(`FPGA_B_TOP_MAX_SPEED_Q16_A_1),
		.FAST_MAX_SPEED_Q16_A(`FPGA_B_TOP_FAST_MAX_SPEED_Q16_A_1),
        .FAST_COMMAND_LIMIT_Q16_A(`FPGA_B_TOP_FAST_COMMAND_LIMIT_Q16_A_1),.FAST_OVERSPEED_RPM_A(`FPGA_B_TOP_FAST_OVERSPEED_RPM_A_1),
		.HOLD_LEAK_ENABLE_A(`FPGA_B_TOP_HOLD_LEAK_ENABLE_A_1),
		.TEST_MODE_A(0),
		.AUTO_START_A(0),
		.ENABLE_TEST_TRAJECTORY_A(0),
		.ENABLE_POSITION_LIMITS_A(1),
		.ARRIVAL_TOLERANCE_COUNTS_A(FEATURE_HOME_TOLERANCE_COUNTS),
		.COMMAND_REVERSE_B(GM6020_2_COMMAND_REVERSE),
		.CLOCKWISE_COUNT_INCREASE_B(GM6020_2_CLOCKWISE_COUNT_INCREASE),
		.FEEDBACK_TIMEOUT_MS_B(10),
		.TRACKING_STABLE_KP_Q16_B(`FPGA_B_TOP_TRACKING_STABLE_KP_Q16_B_1),
		.TRACKING_STABLE_KI_DT_Q16_B(`FPGA_B_TOP_TRACKING_STABLE_KI_DT_Q16_B_1),
		.NORMAL_KP_Q16_B(`FPGA_B_TOP_NORMAL_KP_Q16_B_1),
		.NORMAL_KI_DT_Q16_B(`FPGA_B_TOP_NORMAL_KI_DT_Q16_B_1),
		.FAST_KP_Q16_B(`FPGA_B_TOP_FAST_KP_Q16_B_1),
		.FAST_KI_DT_Q16_B(`FPGA_B_TOP_FAST_KI_DT_Q16_B_1),
		.FAST_MAX_SPEED_Q16_B(`FPGA_B_TOP_FAST_MAX_SPEED_Q16_B_1),
        .FAST_COMMAND_LIMIT_Q16_B(`FPGA_B_TOP_FAST_COMMAND_LIMIT_Q16_B_1),.FAST_OVERSPEED_RPM_B(`FPGA_B_TOP_FAST_OVERSPEED_RPM_B_1),
		.FAST_OUTPUT_FILTER_SHIFT_B(FAST_TRACKING_OUTPUT_FILTER_SHIFT),
		.TRACKING_ENCODER_ALPHA_Q16_B(`FPGA_B_TOP_TRACKING_ENCODER_ALPHA_Q16_B_1),
		.TRACKING_SPEED_FILTER_SHIFT_B(`FPGA_B_TOP_TRACKING_SPEED_FILTER_SHIFT_B_1),
		.TEST_MODE_B(GM6020_2_CONTINUOUS_TEST),
		.ENABLE_TEST_TRAJECTORY_B(GM6020_2_CONTINUOUS_TEST),
		.AUTO_START_B(GM6020_2_TEST_AUTOSTART),
		.ENABLE_POSITION_LIMITS_B(1),
		.ARRIVAL_TOLERANCE_COUNTS_B(FEATURE_HOME_TOLERANCE_COUNTS)
	) u_gm6020_tracking (
		.clk(I_sys_clk), .rst_n(I_rst_n && PLL_lock),
		.enable_bus({gm_motor_enable_2, gm_motor_enable}),
		.feedback_valid_bus({gm_feedback_valid_2, gm_feedback_valid}),
		.angle_bus({gm_angle_2, gm_angle}),
		.speed_rpm_bus({gm_speed_rpm_2, gm_speed_rpm}),
		.temperature_bus({gm_temperature_2, 8'd0}),
		.target_angle_register_bus({gm6020_2_encoder_target, gm6020_target_angle_reg}),
		.test_start_bus({GM6020_2_CONTINUOUS_TEST ? key3_pressed : 1'b0, 1'b0}),
		.test_stop_bus({GM6020_2_CONTINUOUS_TEST ? key4_pressed : 1'b0, 1'b0}),
		.tracking_mode_bus({motor_tracking_mode, motor_tracking_mode}),
		.tracking_enable_bus({startup_home_pending || (vision_stream_active && !GM6020_2_CONTINUOUS_TEST), startup_home_pending || vision_stream_active}),
		.tracking_target_counts_bus({motor_target2, motor_target1}),
		.tracking_velocity_q16_bus({motor_velocity2, motor_velocity1}),
		.position_limit_enable_bus({motor_limits_enabled,motor_limits_enabled}),
		.position_min_counts_bus({motor_min2,motor_min1}),
		.position_max_counts_bus({motor_max2,motor_max1}),
		.command_bus({gm6020_command_2, gm6020_tracking_command}),
		.command_valid_bus(),
		.active_bus(),
		.fault_bus({gm_model_fault_2, gm_tracking_fault1}),
		.test_running_bus(),
		.position_counts_bus({gm_position2, gm_position1}),
		.target_counts_bus(),
		.reference_counts_bus({gm_reference2, gm_reference1}),
		.speed_setpoint_q16_bus(),
		.completed_segments_bus(),
		.feedback_ready_bus({gm_feedback_ready2, gm_feedback_ready1}),
		.at_target_bus({gm_at_target2, gm_at_target1})
	);
	assign gm6020_command = (startup_home_pending || vision_stream_active) ? gm6020_tracking_command : gm6020_manual_command;

	// Independent target and controller for CAN ID 2.
	always @(posedge I_sys_clk or negedge I_rst_n) begin
		if (!I_rst_n)
			gm6020_2_target_angle_reg <= GM6020_2_INITIAL_ANGLE;
        else if (startup_home_pending)
            gm6020_2_target_angle_reg <= GM6020_2_INITIAL_ANGLE;
        else if (uart_enter_manual && gm_motor_enable_2)
            gm6020_2_target_angle_reg <= gm_angle_2 - GM6020_2_ZERO_OFFSET_COUNTS;
        else if (VISION_ENABLE && !GM6020_2_CONTINUOUS_TEST && gm_feedback_valid_2 && !gm_origin_valid2)
            gm6020_2_target_angle_reg <= gm_angle_2 - GM6020_2_ZERO_OFFSET_COUNTS;
        else if (!feature_guard_mode && !all_target_guard_mode && key3_pressed && !key4_pressed)
			gm6020_2_target_angle_reg <= GM6020_2_CLOCKWISE_COUNT_INCREASE ?
				gm6020_2_target_angle_reg + GM6020_STEP_20_DEG :
				gm6020_2_target_angle_reg - GM6020_STEP_20_DEG;
		else if (!feature_guard_mode && !all_target_guard_mode && key4_pressed && !key3_pressed)
			gm6020_2_target_angle_reg <= GM6020_2_CLOCKWISE_COUNT_INCREASE ?
				gm6020_2_target_angle_reg - GM6020_STEP_20_DEG :
				gm6020_2_target_angle_reg + GM6020_STEP_20_DEG;
		else if (uart_manual_mode && uart_step2_done)
			gm6020_2_target_angle_reg <= GM6020_2_CLOCKWISE_COUNT_INCREASE ?
				gm6020_2_target_angle_reg + {{3{uart_step2_counts[9]}}, uart_step2_counts} :
				gm6020_2_target_angle_reg - {{3{uart_step2_counts[9]}}, uart_step2_counts};
		else if ((vision_command_valid || patrol_active || patrol_handoff_hold || visual_position_hold || feature_return_override || feature_prepare_hold || feature_wait_hold) && !manual_override)
			gm6020_2_target_angle_reg <= gm_origin2 + motor_target2[12:0] - GM6020_2_ZERO_OFFSET_COUNTS;
	end
	assign gm_motor_enable_2 = gm_init_done && gm_online_2 && !gm_fault;


	GM6020 #(
		.MOTOR_ID    (1),
		.MOTOR_ID_2  (2),
		.SYS_CLK_HZ  (50000000),
		.CAN_CLK_HZ  (25000000),
		.CAN_BRP     (0),         // 25 MHz / 1 / 25 TQ = 1 Mbit/s
		.CAN_TSEG1   (16),
		.CAN_TSEG2   (8),
		.CAN_SJW     (1),
		.AUTO_SEND   (1),
		// GM6020 feedback and the cascade controller run at 1 kHz.

		// only saturate a 1 Mbit/s CAN bus.
		.TX_HZ       (1000),
		.CURRENT_MODE(0)
	) u_gm6020_1 (
		.sys_clk(I_sys_clk),
		.can_clk(S_25m_clk),
		.rst_n  (I_rst_n && PLL_lock),

		.can_rx(can_rxd),
		.can_tx(can_txd),

		.motor_enable(gm_motor_enable && !recognition_motors_disabled && (!startup_home_pending || startup_home_ready)),
		.command     (gm6020_command),
		.motor_enable_2(gm_motor_enable_2 && !recognition_motors_disabled && !gm_model_fault_2 && (!startup_home_pending || startup_home_ready)),
		.command_2(gm6020_command_2),
		.tx_request  (1'b0),

		.tx_ready (),
		.tx_busy  (),
		.tx_queued(),
		.tx_done  (),
		.init_done(gm_init_done),

		.feedback_valid(gm_feedback_valid),
		.angle         (gm_angle),
		.speed_rpm     (gm_speed_rpm),
		.torque_current(),
		.temperature   (),
		.online        (gm_online),
		.feedback_valid_2(gm_feedback_valid_2),
		.angle_2(gm_angle_2),
		.speed_rpm_2(gm_speed_rpm_2),
		.torque_current_2(),
		.temperature_2(gm_temperature_2),
		.online_2(gm_online_2),

		.rx_overflow   (),
		.fault         (gm_fault),
		.can_status    (),
		.can_irq_status()
	);
	motor #(.PWM_HZ(CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_CLOSED_PWM_HZ:50000),
		.BRAKE_AT_ZERO(CHASSIS_SPEED_CLOSED_LOOP),.DUTY_STEPS(CHASSIS_SPEED_CLOSED_LOOP?10000:1000)) motor_FL (
		.clk       (I_sys_clk),
		.enable    (chassis_enable && wheel_drive[2] && wheel_output_select[2]),
		.duty_cycle(mot_speed_fl),      // Closed loop: 0.01% units, 1500=15%; legacy: 0.1%.
		.direction (mot_fl_direction),  // 1: forward, 0: reverse.
		.M_POS     (M_POS_fl),
		.M_NEG     (M_NEG_fl),
		.PWM_OUT   (PWM_OUT_fl)
	);
	motor #(.PWM_HZ(CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_CLOSED_PWM_HZ:50000),
		.BRAKE_AT_ZERO(CHASSIS_SPEED_CLOSED_LOOP),.DUTY_STEPS(CHASSIS_SPEED_CLOSED_LOOP?10000:1000)) motor_FR (
		.clk       (I_sys_clk),
		.enable    (chassis_enable && wheel_drive[1] && wheel_output_select[1]),
		.duty_cycle(mot_speed_fr),      // Closed loop: 0.01% units, 1500=15%; legacy: 0.1%.
		.direction (mot_fr_direction),  // 1: forward, 0: reverse.
		.M_POS     (M_POS_fr),

		.M_NEG  (M_NEG_fr),
		.PWM_OUT(PWM_OUT_fr)
	);
	motor #(.PWM_HZ(CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_CLOSED_PWM_HZ:50000),
		.BRAKE_AT_ZERO(CHASSIS_SPEED_CLOSED_LOOP),.DUTY_STEPS(CHASSIS_SPEED_CLOSED_LOOP?10000:1000)) motor_RL (
		.clk       (I_sys_clk),
		.enable    (chassis_enable && wheel_drive[3] && wheel_output_select[3]),
		.duty_cycle(mot_speed_rl),      // Closed loop: 0.01% units, 1500=15%; legacy: 0.1%.
		.direction (mot_rl_direction),  // 1: forward, 0: reverse.
		.M_POS     (M_POS_rl),
		.M_NEG     (M_NEG_rl),
		.PWM_OUT   (PWM_OUT_rl)
	);
	motor #(.PWM_HZ(CHASSIS_SPEED_CLOSED_LOOP?CHASSIS_CLOSED_PWM_HZ:50000),
		.BRAKE_AT_ZERO(CHASSIS_SPEED_CLOSED_LOOP),.DUTY_STEPS(CHASSIS_SPEED_CLOSED_LOOP?10000:1000)) motor_RR (
		.clk       (I_sys_clk),
		.enable    (chassis_enable && wheel_drive[0] && wheel_output_select[0]),
		.duty_cycle(mot_speed_rr),      // Closed loop: 0.01% units, 1500=15%; legacy: 0.1%.
		.direction (mot_rr_direction),  // 1: forward, 0: reverse.
		.M_POS     (M_POS_rr),

		.M_NEG  (M_NEG_rr),
		.PWM_OUT(PWM_OUT_rr)
	);
	
	PLL u_pll (
		.refclk(I_sys_clk),
		.clk0_out(S_25m_clk),
		.lock(PLL_lock),
		.reset(!I_rst_n)
	);

endmodule


// One power-on/reset homing transaction. Reference coordinates stay relative
// to each controller's first feedback; fixed encoder zero is not redefined
// from the physical startup pose. Completing homing is latched until reset,
// so later mode changes/feedback recovery never unexpectedly request home.
module gimbal_startup_home #(
    parameter integer CLK_HZ=50000000,
    parameter integer ENABLED=1,
    parameter integer SETTLE_MS=100,
    parameter integer TOLERANCE_COUNTS=23,
    parameter integer CLOCKWISE_COUNT_INCREASE1=1,
    parameter integer CLOCKWISE_COUNT_INCREASE2=1
)(
    input wire clk,rst_n,feedback_ready,
    input wire [12:0] origin1,origin2,zero1,zero2,angle1,angle2,
    input wire signed [15:0] speed1,speed2,
    input wire signed [31:0] reference1,reference2,
    input wire at_target1,at_target2,
    output wire signed [31:0] target1,target2,
    output wire pending,ready,
    output reg done
);
    localparam integer SETTLE_TICKS=(CLK_HZ/1000)*SETTLE_MS;
    localparam integer CW=SETTLE_TICKS>1?$clog2(SETTLE_TICKS+1):1;
    reg [CW-1:0] settled;
    function signed [31:0] encoder_delta;
        input [12:0] target,actual;
        input positive_half_turn;
        reg signed [31:0] d;
        begin
            d=$signed({1'b0,target})-$signed({1'b0,actual});
            if(d==4096 || d== -4096)d=positive_half_turn?32'sd4096:-32'sd4096;
            else if(d>4096)d=d-8192;
            else if(d< -4096)d=d+8192;
            encoder_delta=d;
        end
    endfunction
    assign target1=encoder_delta(zero1,origin1,CLOCKWISE_COUNT_INCREASE1!=0);
    assign target2=encoder_delta(zero2,origin2,CLOCKWISE_COUNT_INCREASE2!=0);
    wire signed [31:0] error1=encoder_delta(zero1,angle1,CLOCKWISE_COUNT_INCREASE1!=0);
    wire signed [31:0] error2=encoder_delta(zero2,angle2,CLOCKWISE_COUNT_INCREASE2!=0);
    assign pending=ENABLED && !done;
    assign ready=feedback_ready;
    wire arrived=feedback_ready && at_target1 && at_target2 &&
        reference1==target1 && reference2==target2 &&
        error1>=-TOLERANCE_COUNTS && error1<=TOLERANCE_COUNTS &&
        error2>=-TOLERANCE_COUNTS && error2<=TOLERANCE_COUNTS &&
        speed1>=-1 && speed1<=1 && speed2>=-1 && speed2<=1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin done<=!ENABLED;settled<=0;end
        else if(!done)begin
            if(!arrived)settled<=0;
            else if(settled>=SETTLE_TICKS-1)begin done<=1;settled<=0;end
            else settled<=settled+1'b1;
        end
    end
`ifndef SYNTHESIS
    initial if(CLK_HZ<1000 || CLK_HZ%1000!=0 || SETTLE_TICKS<1 ||
        TOLERANCE_COUNTS<0 || TOLERANCE_COUNTS>4095)$fatal(1,"Invalid startup home parameters");
`endif
endmodule


// Target-loss sine search for explicit static/distance owners only.
// Fixed physical zero is mapped to the nearest equivalent multi-turn zero;
// neither encoder origin nor the motor controller's position is ever reset.
module gimbal_sine_search #(
    parameter integer CLK_HZ=50000000, LOSS_MS=2000, RX_TIMEOUT_MS=100,
    parameter integer X_PERIOD_MS=6000, Y_PERIOD_MS=4000,
    parameter integer CLOCKWISE_COUNT_INCREASE1=1, CLOCKWISE_COUNT_INCREASE2=1,
    parameter integer ENTRY_X_DEG_S=120, ENTRY_Y_DEG_S=100
)(
    input wire clk,rst_n,enable,restart,feedback_ready,
    input wire result_update,target_valid,comm_timeout,
    input wire [12:0] zero1,zero2,angle1,angle2,
    input wire signed [31:0] position1,position2,reference1,reference2,
    input wire at_target1,at_target2,
    output wire active,bounds_ready,
    output reg signed [31:0] target1,target2,velocity1_q16,velocity2_q16,
    output wire signed [31:0] min1,max1,min2,max2
);
    localparam integer MS_TICKS=CLK_HZ/1000;
    localparam integer LOSS_TICKS=MS_TICKS*LOSS_MS, AGE_TICKS=MS_TICKS*RX_TIMEOUT_MS;
    localparam integer TW=MS_TICKS>1?$clog2(MS_TICKS):1;
    localparam integer LW=$clog2(LOSS_TICKS+1), AW=$clog2(AGE_TICKS+1);
    localparam integer X_AMPLITUDE=2048, Y_AMPLITUDE=1138;
    localparam [31:0] X_INC=((64'd1<<32)+X_PERIOD_MS/2)/X_PERIOD_MS;
    localparam [31:0] Y_INC=((64'd1<<32)+Y_PERIOD_MS/2)/Y_PERIOD_MS;
    // 2*pi in Q24; constant divisions disappear before RTL implementation.
    localparam signed [31:0] X_VMAX_Q16=(64'd2048*105414357*1000+X_PERIOD_MS*128)/(X_PERIOD_MS*256);
    localparam signed [31:0] Y_VMAX_Q16=(64'd1138*105414357*1000+Y_PERIOD_MS*128)/(Y_PERIOD_MS*256);
    localparam signed [31:0] ENTRY_X_STEP=(64'd8192*65536*ENTRY_X_DEG_S)/(360*1000);
    localparam signed [31:0] ENTRY_Y_STEP=(64'd8192*65536*ENTRY_Y_DEG_S)/(360*1000);
    localparam WAIT_TARGET=0, ENTER_CENTER=1, SINE_RUN=2;
    reg [1:0] state;
    reg [TW-1:0] tick;
    reg [LW-1:0] loss_ticks;
    reg [AW-1:0] record_age;
    reg record_good;
    reg signed [31:0] center1,center2,entry1_q16,entry2_q16;
    reg [31:0] phase_x,phase_y;
    wire ms_tick=tick==MS_TICKS-1;
    wire fresh_target=result_update && target_valid && !comm_timeout;
    wire target_present=!comm_timeout &&
        (fresh_target || (record_good && record_age<AGE_TICKS)) &&
        !(result_update && !target_valid);
    assign active=enable && feedback_ready && !restart && state!=WAIT_TARGET && !fresh_target;
    assign bounds_ready=active && state==SINE_RUN;
    assign min1=center1-X_AMPLITUDE;assign max1=center1+X_AMPLITUDE;
    assign min2=center2-Y_AMPLITUDE;assign max2=center2+Y_AMPLITUDE;
    function signed [31:0] encoder_delta;
        input [12:0] wanted,actual;
        input positive_half_turn;
        reg signed [31:0] d;
        begin
            d=$signed({1'b0,wanted})-$signed({1'b0,actual});
            if(d==4096 || d== -4096)d=positive_half_turn?4096:-4096;
            else if(d>4096)d=d-8192;
            else if(d< -4096)d=d+8192;
            encoder_delta=d;
        end
    endfunction
    function signed [15:0] quarter_sine;
        input [6:0] index;
        begin
            case(index)
                7'd0:quarter_sine=16'sd0;
                7'd1:quarter_sine=16'sd402;
                7'd2:quarter_sine=16'sd804;
                7'd3:quarter_sine=16'sd1205;
                7'd4:quarter_sine=16'sd1606;
                7'd5:quarter_sine=16'sd2006;
                7'd6:quarter_sine=16'sd2404;
                7'd7:quarter_sine=16'sd2801;
                7'd8:quarter_sine=16'sd3196;
                7'd9:quarter_sine=16'sd3590;
                7'd10:quarter_sine=16'sd3981;
                7'd11:quarter_sine=16'sd4370;
                7'd12:quarter_sine=16'sd4756;
                7'd13:quarter_sine=16'sd5139;
                7'd14:quarter_sine=16'sd5520;
                7'd15:quarter_sine=16'sd5897;
                7'd16:quarter_sine=16'sd6270;
                7'd17:quarter_sine=16'sd6639;
                7'd18:quarter_sine=16'sd7005;
                7'd19:quarter_sine=16'sd7366;
                7'd20:quarter_sine=16'sd7723;
                7'd21:quarter_sine=16'sd8076;
                7'd22:quarter_sine=16'sd8423;
                7'd23:quarter_sine=16'sd8765;
                7'd24:quarter_sine=16'sd9102;
                7'd25:quarter_sine=16'sd9434;
                7'd26:quarter_sine=16'sd9760;
                7'd27:quarter_sine=16'sd10080;
                7'd28:quarter_sine=16'sd10394;
                7'd29:quarter_sine=16'sd10702;
                7'd30:quarter_sine=16'sd11003;
                7'd31:quarter_sine=16'sd11297;
                7'd32:quarter_sine=16'sd11585;
                7'd33:quarter_sine=16'sd11866;
                7'd34:quarter_sine=16'sd12140;
                7'd35:quarter_sine=16'sd12406;
                7'd36:quarter_sine=16'sd12665;
                7'd37:quarter_sine=16'sd12916;
                7'd38:quarter_sine=16'sd13160;
                7'd39:quarter_sine=16'sd13395;
                7'd40:quarter_sine=16'sd13623;
                7'd41:quarter_sine=16'sd13842;
                7'd42:quarter_sine=16'sd14053;
                7'd43:quarter_sine=16'sd14256;
                7'd44:quarter_sine=16'sd14449;
                7'd45:quarter_sine=16'sd14635;
                7'd46:quarter_sine=16'sd14811;
                7'd47:quarter_sine=16'sd14978;
                7'd48:quarter_sine=16'sd15137;
                7'd49:quarter_sine=16'sd15286;
                7'd50:quarter_sine=16'sd15426;
                7'd51:quarter_sine=16'sd15557;
                7'd52:quarter_sine=16'sd15679;
                7'd53:quarter_sine=16'sd15791;
                7'd54:quarter_sine=16'sd15893;
                7'd55:quarter_sine=16'sd15986;
                7'd56:quarter_sine=16'sd16069;
                7'd57:quarter_sine=16'sd16143;
                7'd58:quarter_sine=16'sd16207;
                7'd59:quarter_sine=16'sd16261;
                7'd60:quarter_sine=16'sd16305;
                7'd61:quarter_sine=16'sd16340;
                7'd62:quarter_sine=16'sd16364;
                7'd63:quarter_sine=16'sd16379;
                7'd64:quarter_sine=16'sd16384;
                default:quarter_sine=0;
            endcase
        end
    endfunction
    function signed [15:0] sine_sample;
        input [7:0] phase;
        reg [6:0] index;
        reg signed [15:0] value;
        begin
            index=phase[6]?7'd64-{1'b0,phase[5:0]}:{1'b0,phase[5:0]};
            value=quarter_sine(index);
            sine_sample=phase[7]?-value:value;
        end
    endfunction
    // Q22 normalized sine, interpolated between 256 full-turn samples.
    function signed [31:0] sine_interp;
        input [31:0] phase;
        reg signed [15:0] a,b;
        reg signed [16:0] delta;
        reg signed [25:0] interpolation;
        reg signed [31:0] base;
        begin
            a=sine_sample(phase[31:24]);b=sine_sample(phase[31:24]+8'd1);
            delta=$signed({b[15],b})-$signed({a[15],a});
            interpolation=delta*$signed({1'b0,phase[23:16]});
            base={{16{a[15]}},a};
            sine_interp=(base<<<8)+interpolation;
        end
    endfunction
    function signed [31:0] toward_zero;
        input signed [31:0] value,step;
        begin
            if(value>step)toward_zero=value-step;
            else if(value< -step)toward_zero=value+step;
            else toward_zero=0;
        end
    endfunction
    function signed [31:0] rounded_counts;
        input signed [31:0] value;
        begin rounded_counts=value>=0?(value+32768)>>>16:-(((-value)+32768)>>>16);end
    endfunction
    reg signed [31:0] d1,d2,n1,n2,sx,sy,cx,cy,offset1,offset2,v1,v2;
    reg signed [63:0] wide;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=WAIT_TARGET;tick<=0;loss_ticks<=0;record_age<=AGE_TICKS;record_good<=0;
            center1<=0;center2<=0;entry1_q16<=0;entry2_q16<=0;phase_x<=0;phase_y<=0;
            target1<=0;target2<=0;velocity1_q16<=0;velocity2_q16<=0;
        end else begin
            tick<=ms_tick?0:tick+1'b1;
            if(!enable || !feedback_ready || restart)begin
                state<=WAIT_TARGET;loss_ticks<=0;record_age<=AGE_TICKS;record_good<=0;
                phase_x<=0;phase_y<=0;
                target1<=position1;target2<=position2;velocity1_q16<=0;velocity2_q16<=0;
            end else begin
                if(result_update)begin record_good<=target_valid && !comm_timeout;record_age<=0;end
                else if(record_age<AGE_TICKS)record_age<=record_age+1'b1;
                if(fresh_target)begin
                    state<=WAIT_TARGET;loss_ticks<=0;
                    target1<=position1;target2<=position2;velocity1_q16<=0;velocity2_q16<=0;
                end else if(state==WAIT_TARGET)begin
                    target1<=position1;target2<=position2;velocity1_q16<=0;velocity2_q16<=0;
                    if(target_present)loss_ticks<=0;
                    else if(loss_ticks>=LOSS_TICKS-1)begin
                        state<=ENTER_CENTER;loss_ticks<=0;phase_x<=0;phase_y<=0;
                        d1=encoder_delta(zero1,angle1,CLOCKWISE_COUNT_INCREASE1!=0);
                        d2=encoder_delta(zero2,angle2,CLOCKWISE_COUNT_INCREASE2!=0);
                        center1<=position1+d1;center2<=position2+d2;
                        entry1_q16<=(-d1)<<<16;entry2_q16<=(-d2)<<<16;
                    end else loss_ticks<=loss_ticks+1'b1;
                end else if(ms_tick)begin
                    if(state==ENTER_CENTER)begin
                        n1=toward_zero(entry1_q16,ENTRY_X_STEP);
                        n2=toward_zero(entry2_q16,ENTRY_Y_STEP);
                        target1<=center1+rounded_counts(n1);target2<=center2+rounded_counts(n2);
                        velocity1_q16<=(n1-entry1_q16)*1000;velocity2_q16<=(n2-entry2_q16)*1000;
                        entry1_q16<=n1;entry2_q16<=n2;
                        if(n1==0 && n2==0 && at_target1 && at_target2 &&
                            reference1==center1 && reference2==center2)state<=SINE_RUN;
                    end else begin
                        sx=sine_interp(phase_x);sy=sine_interp(phase_y);
                        cx=sine_interp(phase_x+32'h40000000);cy=sine_interp(phase_y+32'h40000000);
                        offset1=sx<<<5;
                        wide=sy;wide=wide*Y_AMPLITUDE;offset2=wide>>>6;
                        wide=cx;wide=wide*X_VMAX_Q16;v1=wide>>>22;
                        wide=cy;wide=wide*Y_VMAX_Q16;v2=wide>>>22;
                        target1<=center1+(CLOCKWISE_COUNT_INCREASE1?rounded_counts(offset1):-rounded_counts(offset1));
                        target2<=center2+(CLOCKWISE_COUNT_INCREASE2?rounded_counts(offset2):-rounded_counts(offset2));
                        velocity1_q16<=CLOCKWISE_COUNT_INCREASE1?v1:-v1;
                        velocity2_q16<=CLOCKWISE_COUNT_INCREASE2?v2:-v2;
                        phase_x<=phase_x+X_INC;phase_y<=phase_y+Y_INC;
                    end
                end
            end
        end
    end
`ifndef SYNTHESIS
    initial if(CLK_HZ<1000 || CLK_HZ%1000!=0 || LOSS_MS<1 || RX_TIMEOUT_MS<1 ||
        X_PERIOD_MS<1000 || Y_PERIOD_MS<1000 || ENTRY_X_DEG_S<1 || ENTRY_Y_DEG_S<1)
        $fatal(1,"Invalid sine search clock/timing parameters");
`endif
endmodule


// Both bytes must be newly received in the current manual session. Values
// 0..360 move CCW from the front; FFFF explicitly stops; others are ignored.
// Quarter-wave constants normalize |vx|+|vy| to SPEED_MM_S, so car mixing
// preserves direction without exceeding the existing manual wheel target.
module chassis_heading_control #(
    parameter integer CLK_HZ=50000000,
    parameter integer SPEED_MM_S=747,
    parameter integer CHANGE_BLANK_US=20
)(
    input wire clk,rst_n,enabled,command_valid,
    input wire [7:0] command_code,command_data,
    output wire selected,drive_enable,
    output reg command_commit,
    output wire signed [15:0] forward_mm_s,lateral_mm_s
);
    localparam integer BLANK_TICKS=(CLK_HZ*64'd1*CHANGE_BLANK_US)/1000000;
    localparam integer BW=BLANK_TICKS>0?$clog2(BLANK_TICKS+1):1;
    reg owner,moving,have_high,have_low;
    reg [7:0] high_byte,low_byte;
    reg [8:0] angle_degrees;
    reg [BW-1:0] blank_count;
    reg signed [15:0] vx,vy;
    assign selected=enabled && owner;
    assign drive_enable=selected && moving && blank_count==0;
    assign forward_mm_s=selected?vx:16'sd0;
    assign lateral_mm_s=selected?vy:16'sd0;

    function [15:0] quarter_lateral;
        input [6:0] degrees;
        begin
            // Each RHS contains constants/parameters only. The entire table
            // is computed at elaboration; no runtime multiply or divider.
            case(degrees)
                7'd0:quarter_lateral=(64'd1*SPEED_MM_S*16'd0+16384)>>15;
                7'd1:quarter_lateral=(64'd1*SPEED_MM_S*16'd562+16384)>>15;
                7'd2:quarter_lateral=(64'd1*SPEED_MM_S*16'd1106+16384)>>15;
                7'd3:quarter_lateral=(64'd1*SPEED_MM_S*16'd1632+16384)>>15;
                7'd4:quarter_lateral=(64'd1*SPEED_MM_S*16'd2142+16384)>>15;
                7'd5:quarter_lateral=(64'd1*SPEED_MM_S*16'd2636+16384)>>15;
                7'd6:quarter_lateral=(64'd1*SPEED_MM_S*16'd3116+16384)>>15;
                7'd7:quarter_lateral=(64'd1*SPEED_MM_S*16'd3583+16384)>>15;
                7'd8:quarter_lateral=(64'd1*SPEED_MM_S*16'd4038+16384)>>15;
                7'd9:quarter_lateral=(64'd1*SPEED_MM_S*16'd4480+16384)>>15;
                7'd10:quarter_lateral=(64'd1*SPEED_MM_S*16'd4912+16384)>>15;
                7'd11:quarter_lateral=(64'd1*SPEED_MM_S*16'd5333+16384)>>15;
                7'd12:quarter_lateral=(64'd1*SPEED_MM_S*16'd5744+16384)>>15;
                7'd13:quarter_lateral=(64'd1*SPEED_MM_S*16'd6146+16384)>>15;
                7'd14:quarter_lateral=(64'd1*SPEED_MM_S*16'd6539+16384)>>15;
                7'd15:quarter_lateral=(64'd1*SPEED_MM_S*16'd6925+16384)>>15;
                7'd16:quarter_lateral=(64'd1*SPEED_MM_S*16'd7302+16384)>>15;
                7'd17:quarter_lateral=(64'd1*SPEED_MM_S*16'd7672+16384)>>15;
                7'd18:quarter_lateral=(64'd1*SPEED_MM_S*16'd8036+16384)>>15;
                7'd19:quarter_lateral=(64'd1*SPEED_MM_S*16'd8393+16384)>>15;
                7'd20:quarter_lateral=(64'd1*SPEED_MM_S*16'd8744+16384)>>15;
                7'd21:quarter_lateral=(64'd1*SPEED_MM_S*16'd9089+16384)>>15;
                7'd22:quarter_lateral=(64'd1*SPEED_MM_S*16'd9429+16384)>>15;
                7'd23:quarter_lateral=(64'd1*SPEED_MM_S*16'd9764+16384)>>15;
                7'd24:quarter_lateral=(64'd1*SPEED_MM_S*16'd10095+16384)>>15;
                7'd25:quarter_lateral=(64'd1*SPEED_MM_S*16'd10421+16384)>>15;
                7'd26:quarter_lateral=(64'd1*SPEED_MM_S*16'd10743+16384)>>15;
                7'd27:quarter_lateral=(64'd1*SPEED_MM_S*16'd11061+16384)>>15;
                7'd28:quarter_lateral=(64'd1*SPEED_MM_S*16'd11375+16384)>>15;
                7'd29:quarter_lateral=(64'd1*SPEED_MM_S*16'd11686+16384)>>15;
                7'd30:quarter_lateral=(64'd1*SPEED_MM_S*16'd11994+16384)>>15;
                7'd31:quarter_lateral=(64'd1*SPEED_MM_S*16'd12299+16384)>>15;
                7'd32:quarter_lateral=(64'd1*SPEED_MM_S*16'd12601+16384)>>15;
                7'd33:quarter_lateral=(64'd1*SPEED_MM_S*16'd12901+16384)>>15;
                7'd34:quarter_lateral=(64'd1*SPEED_MM_S*16'd13199+16384)>>15;
                7'd35:quarter_lateral=(64'd1*SPEED_MM_S*16'd13495+16384)>>15;
                7'd36:quarter_lateral=(64'd1*SPEED_MM_S*16'd13789+16384)>>15;
                7'd37:quarter_lateral=(64'd1*SPEED_MM_S*16'd14081+16384)>>15;
                7'd38:quarter_lateral=(64'd1*SPEED_MM_S*16'd14372+16384)>>15;
                7'd39:quarter_lateral=(64'd1*SPEED_MM_S*16'd14662+16384)>>15;
                7'd40:quarter_lateral=(64'd1*SPEED_MM_S*16'd14951+16384)>>15;
                7'd41:quarter_lateral=(64'd1*SPEED_MM_S*16'd15238+16384)>>15;
                7'd42:quarter_lateral=(64'd1*SPEED_MM_S*16'd15525+16384)>>15;
                7'd43:quarter_lateral=(64'd1*SPEED_MM_S*16'd15812+16384)>>15;
                7'd44:quarter_lateral=(64'd1*SPEED_MM_S*16'd16098+16384)>>15;
                7'd45:quarter_lateral=(64'd1*SPEED_MM_S*16'd16384+16384)>>15;
                7'd46:quarter_lateral=(64'd1*SPEED_MM_S*16'd16670+16384)>>15;
                7'd47:quarter_lateral=(64'd1*SPEED_MM_S*16'd16956+16384)>>15;
                7'd48:quarter_lateral=(64'd1*SPEED_MM_S*16'd17243+16384)>>15;
                7'd49:quarter_lateral=(64'd1*SPEED_MM_S*16'd17530+16384)>>15;
                7'd50:quarter_lateral=(64'd1*SPEED_MM_S*16'd17817+16384)>>15;
                7'd51:quarter_lateral=(64'd1*SPEED_MM_S*16'd18106+16384)>>15;
                7'd52:quarter_lateral=(64'd1*SPEED_MM_S*16'd18396+16384)>>15;
                7'd53:quarter_lateral=(64'd1*SPEED_MM_S*16'd18687+16384)>>15;
                7'd54:quarter_lateral=(64'd1*SPEED_MM_S*16'd18979+16384)>>15;
                7'd55:quarter_lateral=(64'd1*SPEED_MM_S*16'd19273+16384)>>15;
                7'd56:quarter_lateral=(64'd1*SPEED_MM_S*16'd19569+16384)>>15;
                7'd57:quarter_lateral=(64'd1*SPEED_MM_S*16'd19867+16384)>>15;
                7'd58:quarter_lateral=(64'd1*SPEED_MM_S*16'd20167+16384)>>15;
                7'd59:quarter_lateral=(64'd1*SPEED_MM_S*16'd20469+16384)>>15;
                7'd60:quarter_lateral=(64'd1*SPEED_MM_S*16'd20774+16384)>>15;
                7'd61:quarter_lateral=(64'd1*SPEED_MM_S*16'd21082+16384)>>15;
                7'd62:quarter_lateral=(64'd1*SPEED_MM_S*16'd21393+16384)>>15;
                7'd63:quarter_lateral=(64'd1*SPEED_MM_S*16'd21707+16384)>>15;
                7'd64:quarter_lateral=(64'd1*SPEED_MM_S*16'd22025+16384)>>15;
                7'd65:quarter_lateral=(64'd1*SPEED_MM_S*16'd22347+16384)>>15;
                7'd66:quarter_lateral=(64'd1*SPEED_MM_S*16'd22673+16384)>>15;
                7'd67:quarter_lateral=(64'd1*SPEED_MM_S*16'd23004+16384)>>15;
                7'd68:quarter_lateral=(64'd1*SPEED_MM_S*16'd23339+16384)>>15;
                7'd69:quarter_lateral=(64'd1*SPEED_MM_S*16'd23679+16384)>>15;
                7'd70:quarter_lateral=(64'd1*SPEED_MM_S*16'd24024+16384)>>15;
                7'd71:quarter_lateral=(64'd1*SPEED_MM_S*16'd24375+16384)>>15;
                7'd72:quarter_lateral=(64'd1*SPEED_MM_S*16'd24732+16384)>>15;
                7'd73:quarter_lateral=(64'd1*SPEED_MM_S*16'd25096+16384)>>15;
                7'd74:quarter_lateral=(64'd1*SPEED_MM_S*16'd25466+16384)>>15;
                7'd75:quarter_lateral=(64'd1*SPEED_MM_S*16'd25843+16384)>>15;
                7'd76:quarter_lateral=(64'd1*SPEED_MM_S*16'd26229+16384)>>15;
                7'd77:quarter_lateral=(64'd1*SPEED_MM_S*16'd26622+16384)>>15;
                7'd78:quarter_lateral=(64'd1*SPEED_MM_S*16'd27024+16384)>>15;
                7'd79:quarter_lateral=(64'd1*SPEED_MM_S*16'd27435+16384)>>15;
                7'd80:quarter_lateral=(64'd1*SPEED_MM_S*16'd27856+16384)>>15;
                7'd81:quarter_lateral=(64'd1*SPEED_MM_S*16'd28288+16384)>>15;
                7'd82:quarter_lateral=(64'd1*SPEED_MM_S*16'd28730+16384)>>15;
                7'd83:quarter_lateral=(64'd1*SPEED_MM_S*16'd29185+16384)>>15;
                7'd84:quarter_lateral=(64'd1*SPEED_MM_S*16'd29652+16384)>>15;
                7'd85:quarter_lateral=(64'd1*SPEED_MM_S*16'd30132+16384)>>15;
                7'd86:quarter_lateral=(64'd1*SPEED_MM_S*16'd30626+16384)>>15;
                7'd87:quarter_lateral=(64'd1*SPEED_MM_S*16'd31136+16384)>>15;
                7'd88:quarter_lateral=(64'd1*SPEED_MM_S*16'd31662+16384)>>15;
                7'd89:quarter_lateral=(64'd1*SPEED_MM_S*16'd32206+16384)>>15;
                7'd90:quarter_lateral=(64'd1*SPEED_MM_S*16'd32768+16384)>>15;
                default:quarter_lateral=0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n)begin:heading
        reg [15:0] assembled;
        reg [8:0] degrees;
        reg [6:0] quarter;
        reg [1:0] quadrant;
        reg signed [15:0] x,y;
        if(!rst_n)begin
            owner<=0;moving<=0;have_high<=0;have_low<=0;
            high_byte<=0;low_byte<=0;angle_degrees<=0;
            blank_count<=0;vx<=0;vy<=0;command_commit<=0;
        end else begin
            command_commit<=0;
            if(blank_count!=0)blank_count<=blank_count-1'b1;
            if(!enabled)begin
                owner<=0;moving<=0;have_high<=0;have_low<=0;
                blank_count<=0;vx<=0;vy<=0;
            end else if(command_valid)begin
                if(command_code==8'h31 && command_data<=4)begin
                    // An explicit old-style direction/stop takes over. It
                    // must also discard any incomplete angle transaction.
                    owner<=0;moving<=0;have_high<=0;have_low<=0;
                    blank_count<=0;vx<=0;vy<=0;
                end else if((command_code==8'h39 && have_low) ||
                            (command_code==8'h3a && have_high))begin
                    assembled=command_code==8'h39 ? {command_data,low_byte}:{high_byte,command_data};
                    have_high<=0;have_low<=0;
                    if(assembled==16'hffff)begin
                        owner<=1;moving<=0;vx<=0;vy<=0;blank_count<=0;command_commit<=1;
                    end else if(assembled<=360)begin
                        degrees=assembled==360?9'd0:assembled[8:0];
                        if(degrees>=270)begin quadrant=3;quarter=degrees-270;end
                        else if(degrees>=180)begin quadrant=2;quarter=degrees-180;end
                        else if(degrees>=90)begin quadrant=1;quarter=degrees-90;end
                        else begin quadrant=0;quarter=degrees[6:0];end
                        y=quarter_lateral(quarter);x=SPEED_MM_S-y;
                        // Equal diagonal components keep the other two
                        // wheels truly stopped when the speed is odd.
                        if(quarter==45)begin x=SPEED_MM_S/2;y=SPEED_MM_S/2;end
                        case(quadrant)
                            0:begin vx<= x;vy<=-y;end
                            1:begin vx<=-y;vy<=-x;end
                            2:begin vx<=-x;vy<= y;end
                            3:begin vx<= y;vy<= x;end
                        endcase
                        // Only entering/restarting needs a source-switch
                        // blank. Repeated/updated headings keep the wheel
                        // sample, ramp and independent PI contexts running.
                        if(!owner || !moving)blank_count<=BLANK_TICKS;
                        owner<=1;moving<=SPEED_MM_S>0;angle_degrees<=degrees;command_commit<=1;
                    end
                end else if(command_code==8'h39)begin
                    high_byte<=command_data;have_high<=1;
                end else if(command_code==8'h3a)begin
                    low_byte<=command_data;have_low<=1;
                end
            end
        end
    end
endmodule

// Distance PID outer loop. Body forward is +X, right is +Y, consistent

// Shadow distance bytes commit only on 2D 02. 2D 01 prepares without motion.
module sight_distance_control #(
    parameter integer CLK_HZ=50000000,
    parameter integer INITIAL_DISTANCE_MM=1000,
    parameter integer FORWARD_ENCODER=0,
    parameter integer ENCODER_INCREASE_RIGHT=0,
    parameter integer MAX_SPEED_MM_S=120,
    parameter integer DEADBAND_MM=20,RESUME_MM=30,
    parameter integer DISTANCE_TIMEOUT_MS=250,
    parameter integer UPDATE_MS=20,
    parameter integer PID_KP_Q16=`FPGA_B_SIGHT_DISTANCE_CONTROL_PID_KP_Q16_1,
    // Ki*Ts and Kd/Ts; change these too if UPDATE_MS changes.
    parameter integer PID_KI_STEP_Q16=`FPGA_B_SIGHT_DISTANCE_CONTROL_PID_KI_STEP_Q16_1,PID_KD_STEP_Q8=`FPGA_B_SIGHT_DISTANCE_CONTROL_PID_KD_STEP_Q8_1,
    parameter integer PID_I_LIMIT_MM_S=40,
    parameter integer PID_D_FILTER_SHIFT=`FPGA_B_SIGHT_DISTANCE_CONTROL_PID_D_FILTER_SHIFT_1
)(
    input wire clk,rst_n,command_valid,
    input wire [7:0] command_code,command_data,
    input wire distance_valid,
    input wire measurement_allowed,
    input wire [23:0] distance_mm,
    input wire bearing_ready,
    input wire [12:0] bearing_encoder,
    output reg selected,active,
    output wire drive_enable,
    output wire signed [15:0] forward_mm_s,lateral_mm_s,
    output reg [15:0] target_distance_mm,staged_distance_mm,
    output reg pid_update
);
    localparam integer MS_TICKS=CLK_HZ/1000;
    localparam integer CW=MS_TICKS>1?$clog2(MS_TICKS):1;
    localparam integer MAX_INTERVAL=DISTANCE_TIMEOUT_MS>UPDATE_MS?DISTANCE_TIMEOUT_MS:UPDATE_MS;
    localparam integer AGE_W=MAX_INTERVAL>0?$clog2(MAX_INTERVAL+1):1;
    localparam signed [63:0] SPEED_LIMIT_Q16=64'sd65536*MAX_SPEED_MM_S;
    localparam signed [63:0] I_LIMIT_Q16=64'sd65536*PID_I_LIMIT_MM_S;
    localparam signed [63:0] D_LIMIT_Q8=64'sd256*MAX_SPEED_MM_S;
    localparam integer I_W=I_LIMIT_Q16>0?$clog2(I_LIMIT_Q16+1)+1:1;
    localparam integer D_W=D_LIMIT_Q8>0?$clog2(D_LIMIT_Q8+1)+1:1;
    localparam integer VECTOR_W=MAX_SPEED_MM_S>0?$clog2(64'd16384*MAX_SPEED_MM_S+8193)+1:16;
    localparam [63:0] PID_MAX_PI=PID_KP_Q16>PID_KI_STEP_Q16?PID_KP_Q16:PID_KI_STEP_Q16;
    localparam [63:0] PID_MAX_COEFFICIENT=PID_MAX_PI>PID_KD_STEP_Q8?PID_MAX_PI:PID_KD_STEP_Q8;
    // A 24-bit unsigned range minus a 16-bit target needs signed 25 bits;

    localparam integer PID_W=26+$clog2(PID_MAX_COEFFICIENT+1);
    localparam integer CALC_W=PID_W+AGE_W+2;
    localparam integer DIV_W=$clog2(CALC_W+1);
    reg [CW-1:0] tick;
    wire ms_tick=tick==MS_TICKS-1;
    reg [AGE_W-1:0] distance_age;
    reg [23:0] measured_distance;
    reg have_distance,in_band;
    reg [2:0] pid_state;
    reg signed [24:0] sample_error;
    reg [12:0] sample_bearing;
    reg [AGE_W-1:0] sample_dt,scale_dt;
    reg [AGE_W-1:0] scale_bit;
    reg signed [CALC_W-1:0] p_work,i_work,d_numerator,i_scale_shift,i_scale_sum;
    reg [CALC_W-1:0] divide_bits;
    reg [AGE_W:0] divide_remainder;
    reg [AGE_W-1:0] divide_denominator;
    reg [DIV_W-1:0] divide_remaining;
    reg divide_negative;
    reg [3:0] bit_number;
    reg multiplying;
    reg [15:0] magnitude;
    reg signed [VECTOR_W-1:0] cosine_shift,sine_shift,cosine_sum,sine_sum;
    reg signed [15:0] vx,vy;
    reg signed [I_W-1:0] integral_q16;
    reg signed [D_W-1:0] derivative_q8;
    reg signed [24:0] previous_error;
    reg previous_error_valid;
    wire sample_authorized=selected && active && measurement_allowed && bearing_ready;
    // The Ethernet permission is a level; local distance_valid is a one-clock
    // NEW TOF event, so do not use that pulse as a continuous drive enable.
    // Gate physical motion immediately on permission/bearing loss or expiry.
    // The sequential stop also discards the vector, requiring a fresh sample
    // after recovery instead of replaying the previously committed command.
    wire distance_expired=distance_age>=DISTANCE_TIMEOUT_MS;
    wire qualified=sample_authorized && have_distance && !distance_expired;
    assign drive_enable=qualified && (vx!=0 || vy!=0);
    assign forward_mm_s=qualified?vx:16'sd0;
    assign lateral_mm_s=qualified?vy:16'sd0;
    function signed [15:0] quarter_sine;
        input [6:0] index;
        begin case(index)
                7'd0:quarter_sine=16'sd0;
                7'd1:quarter_sine=16'sd402;
                7'd2:quarter_sine=16'sd804;
                7'd3:quarter_sine=16'sd1205;
                7'd4:quarter_sine=16'sd1606;
                7'd5:quarter_sine=16'sd2006;
                7'd6:quarter_sine=16'sd2404;
                7'd7:quarter_sine=16'sd2801;
                7'd8:quarter_sine=16'sd3196;
                7'd9:quarter_sine=16'sd3590;
                7'd10:quarter_sine=16'sd3981;
                7'd11:quarter_sine=16'sd4370;
                7'd12:quarter_sine=16'sd4756;
                7'd13:quarter_sine=16'sd5139;
                7'd14:quarter_sine=16'sd5520;
                7'd15:quarter_sine=16'sd5897;
                7'd16:quarter_sine=16'sd6270;
                7'd17:quarter_sine=16'sd6639;
                7'd18:quarter_sine=16'sd7005;
                7'd19:quarter_sine=16'sd7366;
                7'd20:quarter_sine=16'sd7723;
                7'd21:quarter_sine=16'sd8076;
                7'd22:quarter_sine=16'sd8423;
                7'd23:quarter_sine=16'sd8765;
                7'd24:quarter_sine=16'sd9102;
                7'd25:quarter_sine=16'sd9434;
                7'd26:quarter_sine=16'sd9760;
                7'd27:quarter_sine=16'sd10080;
                7'd28:quarter_sine=16'sd10394;
                7'd29:quarter_sine=16'sd10702;
                7'd30:quarter_sine=16'sd11003;
                7'd31:quarter_sine=16'sd11297;
                7'd32:quarter_sine=16'sd11585;
                7'd33:quarter_sine=16'sd11866;
                7'd34:quarter_sine=16'sd12140;
                7'd35:quarter_sine=16'sd12406;
                7'd36:quarter_sine=16'sd12665;
                7'd37:quarter_sine=16'sd12916;
                7'd38:quarter_sine=16'sd13160;
                7'd39:quarter_sine=16'sd13395;
                7'd40:quarter_sine=16'sd13623;
                7'd41:quarter_sine=16'sd13842;
                7'd42:quarter_sine=16'sd14053;
                7'd43:quarter_sine=16'sd14256;
                7'd44:quarter_sine=16'sd14449;
                7'd45:quarter_sine=16'sd14635;
                7'd46:quarter_sine=16'sd14811;
                7'd47:quarter_sine=16'sd14978;
                7'd48:quarter_sine=16'sd15137;
                7'd49:quarter_sine=16'sd15286;
                7'd50:quarter_sine=16'sd15426;
                7'd51:quarter_sine=16'sd15557;
                7'd52:quarter_sine=16'sd15679;
                7'd53:quarter_sine=16'sd15791;
                7'd54:quarter_sine=16'sd15893;
                7'd55:quarter_sine=16'sd15986;
                7'd56:quarter_sine=16'sd16069;
                7'd57:quarter_sine=16'sd16143;
                7'd58:quarter_sine=16'sd16207;
                7'd59:quarter_sine=16'sd16261;
                7'd60:quarter_sine=16'sd16305;
                7'd61:quarter_sine=16'sd16340;
                7'd62:quarter_sine=16'sd16364;
                7'd63:quarter_sine=16'sd16379;
                7'd64:quarter_sine=16'sd16384;
                default:quarter_sine=0;
            endcase
        end
    endfunction
    function signed [15:0] sine;
        input [7:0] phase;
        reg [6:0] index;
        reg signed [15:0] n;
        begin
            index=phase[6]?7'd64-{1'b0,phase[5:0]}:{1'b0,phase[5:0]};
            n=quarter_sine(index);
            sine=phase[7]?-n:n;
        end
    endfunction
    function signed [15:0] round_q14;
        input signed [31:0] value;
        begin round_q14=value>=0?(value+8192)>>>14:-(((-value)+8192)>>>14);end
    endfunction
    // Coefficients are elaboration-time constants. Explicit shift/add keeps
    // the range PID free of runtime multiplication operators/DSP inference.
    function signed [PID_W-1:0] constant_gain;
        input signed [25:0] value;
        input [31:0] coefficient;
        reg signed [PID_W-1:0] extended_value,total;
        integer bit_index;
        begin
            extended_value={{(PID_W-26){value[25]}},value};total=0;
            for(bit_index=0;bit_index<32;bit_index=bit_index+1)
                if(coefficient[bit_index])total=total+(extended_value<<<bit_index);
            constant_gain=total;
        end
    endfunction
    function signed [CALC_W-1:0] nominal_times;
        input signed [CALC_W-1:0] value;
        integer n;
        begin
            nominal_times=0;
            for(n=0;n<31;n=n+1)if((UPDATE_MS>>n)&1)nominal_times=nominal_times+(value<<<n);
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin:sight
        reg signed [24:0] error_mm;
        reg signed [31:0] speed;
        reg signed [CALC_W-1:0] i_next,d_raw,d_next,total_q16,scaled_i;
        reg [CALC_W-1:0] divided;
        reg [AGE_W:0] trial;
        reg [12:0] delta,rounded_angle;
        reg [7:0] phase;
        reg signed [VECTOR_W-1:0] nx,ny;
        if(!rst_n)begin
            selected<=0;active<=0;target_distance_mm<=INITIAL_DISTANCE_MM;
            staged_distance_mm<=INITIAL_DISTANCE_MM;tick<=0;distance_age<=DISTANCE_TIMEOUT_MS;
            measured_distance<=0;have_distance<=0;in_band<=1;
            pid_state<=0;pid_update<=0;sample_error<=0;sample_bearing<=0;sample_dt<=UPDATE_MS;
            scale_dt<=0;scale_bit<=0;p_work<=0;i_work<=0;d_numerator<=0;
            i_scale_shift<=0;i_scale_sum<=0;divide_bits<=0;divide_remainder<=0;
            divide_denominator<=1;divide_remaining<=0;divide_negative<=0;
            multiplying<=0;bit_number<=0;magnitude<=0;
            cosine_shift<=0;sine_shift<=0;cosine_sum<=0;sine_sum<=0;vx<=0;vy<=0;
            integral_q16<=0;derivative_q8<=0;previous_error<=0;previous_error_valid<=0;
        end else begin
            tick<=ms_tick?0:tick+1'b1;
            pid_update<=0;
            if(ms_tick && distance_age<DISTANCE_TIMEOUT_MS)distance_age<=distance_age+1'b1;
            if(!sample_authorized || (distance_expired && !distance_valid) ||
               (distance_valid && distance_mm==0))begin
                // Invalid distance/target/bearing or no fresh range: stop all
                // wheels, cancel pending work and clear PID restart history.
                vx<=0;vy<=0;have_distance<=0;in_band<=1;
                distance_age<=DISTANCE_TIMEOUT_MS;multiplying<=0;pid_state<=0;
                integral_q16<=0;derivative_q8<=0;previous_error<=0;previous_error_valid<=0;
            end else if(distance_valid && !multiplying && pid_state==0)begin
                // One local TOF event starts one PID transaction. No timer
                // repeats a measurement, and pre-apply samples are discarded.
                measured_distance<=distance_mm;distance_age<=0;have_distance<=1;
                error_mm=$signed({1'b0,distance_mm})-$signed({9'b0,target_distance_mm});
                sample_error<=error_mm;sample_bearing<=bearing_encoder;
                sample_dt<=previous_error_valid?(distance_age==0?1:distance_age):UPDATE_MS;
                scale_dt<=previous_error_valid?(distance_age==0?1:distance_age):UPDATE_MS;
                p_work<=constant_gain(error_mm,PID_KP_Q16);
                i_scale_shift<=constant_gain(error_mm,PID_KI_STEP_Q16);i_scale_sum<=0;scale_bit<=0;
                d_raw=previous_error_valid?constant_gain(error_mm-previous_error,PID_KD_STEP_Q8):0;
                d_numerator<=nominal_times(d_raw);
                pid_state<=1;
            end else if(multiplying)begin
                nx=cosine_sum+(magnitude[0]?cosine_shift:32'sd0);
                ny=sine_sum+(magnitude[0]?sine_shift:32'sd0);
                cosine_sum<=nx;sine_sum<=ny;
                cosine_shift<=cosine_shift<<<1;sine_shift<=sine_shift<<<1;magnitude<=magnitude>>1;
                if(bit_number==15)begin
                    vx<=round_q14(nx);vy<=round_q14(ny);multiplying<=0;
                end else bit_number<=bit_number+1'b1;
            end else if(pid_state==1)begin
                // Ki*Ts is scaled to the actual interval between accepted
                // samples. A serial adder avoids a variable multiplier.
                scaled_i=i_scale_sum+(scale_dt[0]?i_scale_shift:0);
                i_scale_sum<=scaled_i;i_scale_shift<=i_scale_shift<<<1;scale_dt<=scale_dt>>1;
                if(scale_bit==AGE_W-1)begin
                    divide_bits<=scaled_i<0?-scaled_i:scaled_i;divide_negative<=scaled_i<0;
                    divide_remainder<=0;divide_denominator<=UPDATE_MS;divide_remaining<=CALC_W;
                    pid_state<=2;
                end else scale_bit<=scale_bit+1'b1;
            end else if(pid_state==2 || pid_state==3)begin
                // The same restoring divider computes I*dt/Tnom and
                // D*Tnom/dt exactly, with signed truncation toward zero.
                trial={divide_remainder[AGE_W-1:0],divide_bits[CALC_W-1]};
                divided={divide_bits[CALC_W-2:0],1'b0};
                if(trial>={1'b0,divide_denominator})begin
                    trial=trial-divide_denominator;divided[0]=1;
                end
                divide_bits<=divided;divide_remainder<=trial;divide_remaining<=divide_remaining-1'b1;
                if(divide_remaining==1)begin
                    if(pid_state==2)begin
                        i_next=$signed(integral_q16)+(divide_negative?-$signed(divided):$signed(divided));
                        if(i_next>I_LIMIT_Q16)i_next=I_LIMIT_Q16;
                        if(i_next<-I_LIMIT_Q16)i_next=-I_LIMIT_Q16;
                        i_work<=i_next;
                        divide_bits<=d_numerator<0?-d_numerator:d_numerator;divide_negative<=d_numerator<0;
                        divide_remainder<=0;divide_denominator<=sample_dt;divide_remaining<=CALC_W;pid_state<=3;
                    end else begin
                        d_raw=divide_negative?-$signed(divided):$signed(divided);
                        if(d_raw>D_LIMIT_Q8)d_raw=D_LIMIT_Q8;
                        if(d_raw<-D_LIMIT_Q8)d_raw=-D_LIMIT_Q8;
                        d_numerator<=d_raw;pid_state<=4;
                    end
                end
            end else if(pid_state==4)begin
                    pid_state<=0;pid_update<=1;error_mm=sample_error;
                    if((error_mm<=DEADBAND_MM && error_mm>=-DEADBAND_MM) ||
                       (in_band && error_mm<RESUME_MM && error_mm>-RESUME_MM))begin
                        vx<=0;vy<=0;in_band<=1;
                        integral_q16<=0;derivative_q8<=0;previous_error_valid<=0;
                    end else begin
                        // Range_dot = -unit_line_of_sight dot velocity.
                        // Positive range error requests motion toward target.
                        i_next=i_work;d_raw=d_numerator;
                        d_next=$signed(derivative_q8)+
                            ((d_raw-$signed(derivative_q8))>>>PID_D_FILTER_SHIFT);
                        total_q16=p_work+i_next+(d_next<<<8);
                        // Conditional integration prevents winding up against
                        // either speed limit, while permitting unwinding.
                        if((total_q16>SPEED_LIMIT_Q16 && error_mm>0) ||
                           (total_q16<-SPEED_LIMIT_Q16 && error_mm<0))begin
                            i_next=$signed(integral_q16);
                            total_q16=p_work+i_next+(d_next<<<8);
                        end
                        integral_q16<=i_next;derivative_q8<=d_next;
                        previous_error<=error_mm;previous_error_valid<=1;
                        if(total_q16>SPEED_LIMIT_Q16)total_q16=SPEED_LIMIT_Q16;
                        if(total_q16<-SPEED_LIMIT_Q16)total_q16=-SPEED_LIMIT_Q16;
                        speed=total_q16>=0?(total_q16+32768)>>>16:
                            -(((-total_q16)+32768)>>>16);
                        delta=ENCODER_INCREASE_RIGHT?
                            sample_bearing-FORWARD_ENCODER:FORWARD_ENCODER-sample_bearing;
                        rounded_angle=delta+13'd16;phase=rounded_angle[12:5];
                        cosine_shift<=speed>=0?sine(phase+8'd64):-sine(phase+8'd64);
                        sine_shift<=speed>=0?sine(phase):-sine(phase);
                        magnitude<=speed>=0?speed:-speed;cosine_sum<=0;sine_sum<=0;
                        bit_number<=0;multiplying<=1;in_band<=0;
                    end
            end
            if(command_valid)begin
                // Range PID/PWM runs autonomously; 31 packets are manual
                // input only and never cancel a sample or release this owner.
                if(command_code==8'h2d && (command_data==0 || command_data==1 ||
                    command_data==3 || (command_data==2 && selected)))begin
                    integral_q16<=0;derivative_q8<=0;previous_error_valid<=0;
                    have_distance<=0;pid_state<=0;pid_update<=0;
                end
                if(command_code==8'h2e)staged_distance_mm[7:0]<=command_data;
                else if(command_code==8'h2f)staged_distance_mm[15:8]<=command_data;
                else if(command_code==8'h2d)case(command_data)
                    8'h01:begin
                        selected<=1;active<=0;vx<=0;vy<=0;multiplying<=0;
                        have_distance<=0;pid_state<=0;in_band<=1;
                    end
                    8'h02:if(selected)begin
                        target_distance_mm<=staged_distance_mm;active<=staged_distance_mm!=0;
                        vx<=0;vy<=0;multiplying<=0;pid_state<=0;in_band<=1;
                    end
                    // Cancel only the applied motion; retain mode ownership
                    // and both distance registers for a later 2D 02 reapply.
                    8'h03:begin active<=0;vx<=0;vy<=0;multiplying<=0;end
                    8'h00:begin selected<=0;active<=0;vx<=0;vy<=0;multiplying<=0;end
                    default:begin end
                endcase
            end
        end
    end
endmodule

// Port of the measured MotorControl_Update in D:/HAl/driver.
// Signed counts/10ms Q8, PI/feedforward in PWM-percent Q16; duty is 0.01%.
// One radix-4 serial multiplier serves target conversion, P, I and FF.
// Compatibility fault inputs are ignored: abnormal automatic stops stay off.
module chassis_hal_wheel_speed #(
    parameter integer CLK_HZ=50000000,
    parameter integer ENCODER_CPR=450,CIRCUMFERENCE_MM=204,
    parameter integer ENCODER_REVERSE=0,FORWARD_LEVEL=1,
    parameter integer SAMPLE_MS=10,MAX_SPEED_MM_S=22667,
    parameter integer MAX_DUTY=300,CHANGE_BLANK_US=20,
    parameter integer KP_Q24=`FPGA_B_CHASSIS_HAL_WHEEL_SPEED_KP_Q24_1,KI_STEP_Q24=(`FPGA_B_CHASSIS_MODEL_KI_BASE_Q24*SAMPLE_MS+5)/10,
    parameter integer FEEDFORWARD_Q24=`FPGA_B_CHASSIS_HAL_WHEEL_SPEED_FEEDFORWARD_Q24_1,
    parameter integer REFERENCE_RATE=`FPGA_B_CHASSIS_HAL_WHEEL_SPEED_REFERENCE_RATE_1,TARGET_LIMIT_COUNTS=1000,
    parameter integer START_PWM_CENTI=500,START_TIME_MS=80,REVERSE_SETTLE_MS=30
)(
    input wire clk,rst_n,enable,clear_fault,group_fault,
    input wire signed [31:0] target_mm_s,encoder_count,
    output reg [13:0] duty,
    output wire direction,drive_enable,
    output wire fault
);
    localparam integer TICKS=(CLK_HZ/1000)*SAMPLE_MS;
    localparam integer CW=TICKS>1?$clog2(TICKS):1;
    localparam integer BLANK_TICKS=(CLK_HZ*64'd1*CHANGE_BLANK_US)/1000000;
    localparam integer BW=BLANK_TICKS>0?$clog2(BLANK_TICKS+1):1;
    localparam [63:0] SCALE_NUM=(64'd1<<24)*ENCODER_CPR*10;
    localparam [31:0] COUNTS_SCALE=(SCALE_NUM+(CIRCUMFERENCE_MM*1000)/2)/(CIRCUMFERENCE_MM*1000);
    localparam [31:0] GAIN_MAX_A=KP_Q24>KI_STEP_Q24?KP_Q24:KI_STEP_Q24;
    localparam [31:0] GAIN_MAX_B=GAIN_MAX_A>FEEDFORWARD_Q24?GAIN_MAX_A:FEEDFORWARD_Q24;
    localparam [31:0] COEFFICIENT_MAX=GAIN_MAX_B>COUNTS_SCALE?GAIN_MAX_B:COUNTS_SCALE;
    localparam integer COEFF_W=COEFFICIENT_MAX>0?$clog2(64'd1+COEFFICIENT_MAX):1;
    localparam integer MAG_W=MAX_SPEED_MM_S>0?$clog2(64'd1+MAX_SPEED_MM_S):1;

    localparam integer INPUT_W=MAG_W>25?MAG_W:25;
    localparam integer PRODUCT_W=INPUT_W+COEFF_W+2;
    localparam integer MUL_CYCLES=(COEFF_W+1)/2;
    localparam integer MBW=MUL_CYCLES>1?$clog2(MUL_CYCLES):1;
    localparam integer LIMIT_CENTI=MAX_DUTY<0?0:(MAX_DUTY>1000?10000:MAX_DUTY*10);
    localparam signed [31:0] OUTPUT_LIMIT_Q16=(LIMIT_CENTI*65536+50)/100;
    localparam signed [31:0] START_LIMIT_Q16=
        ((START_PWM_CENTI>LIMIT_CENTI?LIMIT_CENTI:START_PWM_CENTI)*65536+50)/100;
    localparam signed [31:0] TARGET_LIMIT_Q8=TARGET_LIMIT_COUNTS*256;
    localparam signed [31:0] RAMP_STEP_Q8=(64'd256*REFERENCE_RATE*SAMPLE_MS+500)/1000;
    // Q24 time reproduces the C float boundary at the nominal 10ms period:
    // 0.08f-8*0.01f remains slightly positive, so the boost checks 9 samples.
    localparam [63:0] DT_Q24=((64'd1<<24)*SAMPLE_MS)/1000;
    localparam [63:0] START_Q24=((64'd1<<24)*START_TIME_MS)/1000;
    localparam [63:0] REVERSE_Q24=((64'd1<<24)*REVERSE_SETTLE_MS)/1000;
    localparam integer START_SAMPLES=(START_Q24+DT_Q24-1)/DT_Q24;
    localparam integer REVERSE_SAMPLES=(REVERSE_Q24+DT_Q24-1)/DT_Q24;
    localparam integer SW=START_SAMPLES>0?$clog2(START_SAMPLES+1):1;
    localparam integer RW=REVERSE_SAMPLES>0?$clog2(REVERSE_SAMPLES+1):1;
    localparam IDLE=0,MULTIPLY=1,TARGET=2,RAMP=3,P_STORE=4,I_STORE=5,FF_STORE=6,OUTPUT=7;
    reg [2:0] state,return_state;
    reg [CW-1:0] tick;
    reg [BW-1:0] blank_count;
    reg signed [31:0] previous_count,measured_q8,reference_mm_s,target_q8;
    reg signed [24:0] reference_q8,error_q8;
    reg signed [31:0] integral_q16,p_q16,i_candidate_q16,ff_q16,lower_q16;
    reg positive,direction_valid,sample_valid,target_positive;
    reg [SW-1:0] start_remaining;
    reg [RW-1:0] reverse_wait;
    reg [COEFF_W-1:0] multiplier;
    reg [PRODUCT_W-1:0] product,product_shift;
    reg [MBW-1:0] bit_number;
    reg multiply_negative;
    wire [PRODUCT_W-1:0] digit3=product_shift+(product_shift<<1);
    wire [PRODUCT_W-1:0] term=multiplier[1]?(multiplier[0]?digit3:product_shift<<1):
        (multiplier[0]?product_shift:{PRODUCT_W{1'b0}});
    wire [PRODUCT_W-1:0] next_product=product+term;
    wire signed [31:0] raw_delta=encoder_count-previous_count;
    wire signed [63:0] oriented_delta=ENCODER_REVERSE?-$signed({{32{raw_delta[31]}},raw_delta}):
        $signed({{32{raw_delta[31]}},raw_delta});
    wire signed [63:0] normalized_measured;
    generate if(SAMPLE_MS==10)begin:nominal_sample
        assign normalized_measured=oriented_delta<<<8;
    end else begin:other_sample
        assign normalized_measured=((oriented_delta<<<11)+(oriented_delta<<<9))/SAMPLE_MS;
    end endgenerate

    // Constant helper also used by historical arithmetic regressions.
    function signed [63:0] times_constant;
        input signed [31:0] value;
        input integer coefficient;
        reg signed [63:0] wide,positive_terms,negative_terms;
        reg [31:0] magnitude;
        integer k;
        begin
            wide=value;positive_terms=0;negative_terms=0;
            magnitude=coefficient<0?-coefficient:coefficient;
            for(k=0;k<32;k=k+1)begin
                if(magnitude[0])begin
                    if(magnitude[1])begin
                        negative_terms=negative_terms+(wide<<<k);
                        magnitude=(magnitude>>1)+1'b1;
                    end else begin
                        positive_terms=positive_terms+(wide<<<k);
                        magnitude=magnitude>>1;
                    end
                end else magnitude=magnitude>>1;
            end
            times_constant=coefficient<0?negative_terms-positive_terms:positive_terms-negative_terms;
        end
    endfunction
    function signed [31:0] gain_result;
        input [PRODUCT_W-1:0] value;
        input negative;
        reg [PRODUCT_W-1:0] rounded;
        begin
            rounded=(value+32768)>>16; // Q8*Q24 -> PWM-percent Q16
            gain_result=negative?-$signed(rounded[31:0]):$signed(rounded[31:0]);
        end
    endfunction
    assign direction=positive?FORWARD_LEVEL:!FORWARD_LEVEL;
    assign drive_enable=enable && blank_count==0;
    assign fault=1'b0;
    always @(posedge clk or negedge rst_n)begin:control
        reg signed [31:0] requested,q8_target,feedback,error,ref_mag,new_reference;
        reg signed [31:0] candidate,base,output_value,chosen_integral;
        reg [31:0] magnitude,absolute_speed;
        reg [SW-1:0] remaining;
        reg [RW:0] wait_next;
        reg dir_known,dir_positive,brake;
        if(!rst_n)begin
            state<=IDLE;return_state<=IDLE;tick<=0;blank_count<=0;previous_count<=0;
            measured_q8<=0;reference_mm_s<=0;target_q8<=0;reference_q8<=0;error_q8<=0;
            integral_q16<=0;p_q16<=0;i_candidate_q16<=0;ff_q16<=0;lower_q16<=0;
            positive<=1;direction_valid<=0;sample_valid<=0;target_positive<=1;duty<=0;
            start_remaining<=0;reverse_wait<=0;multiplier<=0;product<=0;product_shift<=0;
            bit_number<=0;multiply_negative<=0;
        end else begin
            sample_valid<=0;
            if(!enable)begin
                state<=IDLE;tick<=0;blank_count<=0;previous_count<=encoder_count;
                measured_q8<=0;reference_mm_s<=0;target_q8<=0;reference_q8<=0;error_q8<=0;
                integral_q16<=0;duty<=0;direction_valid<=0;start_remaining<=0;reverse_wait<=0;
            end else begin
                tick<=tick==TICKS-1?0:tick+1'b1;
                if(blank_count!=0)blank_count<=blank_count-1'b1;
                case(state)
                    IDLE:if(tick==TICKS-1)begin
                        previous_count<=encoder_count;
                        // Saturation is arithmetic representation only; never
                        // latch a fault, reset a sample, or disable the bridge.
                        if(normalized_measured>64'sd8388608)measured_q8<=32'sd8388608;
                        else if(normalized_measured<-64'sd8388608)measured_q8<=-32'sd8388608;
                        else measured_q8<=normalized_measured[31:0];
                        requested=target_mm_s;
                        if(requested>MAX_SPEED_MM_S)requested=MAX_SPEED_MM_S;
                        if(requested<-MAX_SPEED_MM_S)requested=-MAX_SPEED_MM_S;
                        reference_mm_s<=requested;target_positive<=requested>=0;
                        magnitude=requested<0?-requested:requested;
                        product_shift<=magnitude;multiplier<=COUNTS_SCALE;product<=0;
                        multiply_negative<=requested<0;bit_number<=0;
                        return_state<=TARGET;state<=MULTIPLY;
                    end
                    MULTIPLY:begin
                        product<=next_product;product_shift<=product_shift<<2;multiplier<=multiplier>>2;
                        if(bit_number==MUL_CYCLES-1)state<=return_state;
                        else bit_number<=bit_number+1'b1;
                    end
                    TARGET:begin
                        q8_target=gain_result(product,multiply_negative);
                        if(q8_target>TARGET_LIMIT_Q8)q8_target=TARGET_LIMIT_Q8;
                        if(q8_target<-TARGET_LIMIT_Q8)q8_target=-TARGET_LIMIT_Q8;
                        target_q8<=q8_target;state<=RAMP;
                    end
                    RAMP:begin
                        if(target_q8==0)begin
                            reference_q8<=0;integral_q16<=0;duty<=0;
                            direction_valid<=0;start_remaining<=0;reverse_wait<=0;
                            sample_valid<=1;state<=IDLE;
                        end else begin
                            dir_known=direction_valid;dir_positive=positive;brake=0;
                            remaining=start_remaining;
                            absolute_speed=measured_q8<0?-measured_q8:measured_q8;
                            feedback=target_positive?measured_q8:-measured_q8;
                            if(!dir_known && feedback< -32'sd1280)begin
                                dir_known=1;dir_positive=!target_positive;
                            end
                            if(dir_known && dir_positive!=target_positive)begin
                                reference_q8<=0;integral_q16<=0;duty<=0;
                                wait_next=absolute_speed<=1280?reverse_wait+1'b1:0;
                                reverse_wait<=wait_next[RW-1:0];
                                if(wait_next<REVERSE_SAMPLES)brake=1;
                                else dir_known=0;
                            end
                            if(brake)begin
                                direction_valid<=1;positive<=dir_positive;
                                sample_valid<=1;state<=IDLE;
                            end else begin
                                if(!dir_known)begin
                                    dir_positive=target_positive;direction_valid<=1;
                                    positive<=target_positive;reverse_wait<=0;
                                    remaining=START_SAMPLES;integral_q16<=0;ref_mag=0;
                                    if(positive!=target_positive)blank_count<=BLANK_TICKS;
                                end else ref_mag=reference_q8<0?-reference_q8:reference_q8;
                                requested=target_q8<0?-target_q8:target_q8;
                                if(requested-ref_mag>RAMP_STEP_Q8)new_reference=ref_mag+RAMP_STEP_Q8;
                                else if(requested-ref_mag<-RAMP_STEP_Q8)new_reference=ref_mag-RAMP_STEP_Q8;
                                else new_reference=requested;
                                reference_q8<=dir_positive?new_reference:-new_reference;
                                error=new_reference-feedback;error_q8<=error;
                                lower_q16<=remaining!=0 && feedback<new_reference?START_LIMIT_Q16:0;
                                start_remaining<=remaining!=0?remaining-1'b1:0;
                                product_shift<=error<0?-error:error;multiplier<=KP_Q24;product<=0;
                                multiply_negative<=error<0;bit_number<=0;
                                return_state<=P_STORE;state<=MULTIPLY;
                            end
                        end
                    end
                    P_STORE:begin
                        p_q16<=gain_result(product,multiply_negative);
                        product_shift<=error_q8<0?-$signed(error_q8):$signed(error_q8);
                        multiplier<=KI_STEP_Q24;product<=0;bit_number<=0;
                        multiply_negative<=error_q8<0;return_state<=I_STORE;state<=MULTIPLY;
                    end
                    I_STORE:begin
                        candidate=integral_q16+gain_result(product,multiply_negative);
                        if(candidate>OUTPUT_LIMIT_Q16)candidate=OUTPUT_LIMIT_Q16;
                        if(candidate<-OUTPUT_LIMIT_Q16)candidate=-OUTPUT_LIMIT_Q16;
                        i_candidate_q16<=candidate;
                        product_shift<=reference_q8<0?-$signed(reference_q8):$signed(reference_q8);
                        multiplier<=FEEDFORWARD_Q24;product<=0;bit_number<=0;
                        multiply_negative<=0;return_state<=FF_STORE;state<=MULTIPLY;
                    end
                    FF_STORE:begin ff_q16<=gain_result(product,1'b0);state<=OUTPUT;end
                    OUTPUT:begin
                        base=ff_q16+p_q16;candidate=base+i_candidate_q16;
                        chosen_integral=integral_q16;
                        if(!((candidate>OUTPUT_LIMIT_Q16 && error_q8>0) ||
                             (candidate<lower_q16 && error_q8<0)))chosen_integral=i_candidate_q16;
                        integral_q16<=chosen_integral;
                        output_value=base+chosen_integral;
                        if(output_value>OUTPUT_LIMIT_Q16)output_value=OUTPUT_LIMIT_Q16;
                        if(output_value<lower_q16)output_value=lower_q16;
                        duty<=(times_constant(output_value,100)+32768)>>>16;
                        sample_valid<=1;state<=IDLE;
                    end
                    default:state<=IDLE;
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    initial if(SAMPLE_MS<1 || SAMPLE_MS>50 || TICKS<=4*MUL_CYCLES+8 || TARGET_LIMIT_COUNTS>32767 ||
        MAX_SPEED_MM_S<1 || MAX_DUTY<0 || MAX_DUTY>1000 || KP_Q24<0 || KI_STEP_Q24<0 ||
        FEEDFORWARD_Q24<0 || START_PWM_CENTI<0 || START_TIME_MS<0 || REVERSE_SETTLE_MS<0)
        $fatal(1,"Invalid model wheel parameters");
`endif
endmodule



// Historical standalone regression model; not instantiated by top.
// Independent wheel speed PI. All scale factors are parameters. Runtime
// products share bit-serial adders; this loop introduces no '*' DSP inference.
// No elapsed-time no-feedback/stall shutdown: zero counts keep PI active.
// Duty remains bounded; explicit stop/reset and implausible count jumps remain.
module chassis_wheel_speed #(
    parameter integer CLK_HZ=50000000,
    parameter integer ENCODER_CPR=4096,CIRCUMFERENCE_MM=204,
    parameter integer ENCODER_REVERSE=0,FORWARD_LEVEL=1,
    parameter integer SAMPLE_MS=10,RAMP_STEP=4,
    parameter integer KP_SHIFT=6,KI_SHIFT=10,
    parameter integer FF_Q16=163840,MAX_DUTY=600,
    parameter integer MAX_SPEED_MM_S=250,
    parameter integer CHANGE_BLANK_US=20,
    parameter integer COUNT_SCALE_BITS=16,
    parameter integer MAX_COUNTS_PER_SAMPLE=ENCODER_CPR/4,
    parameter integer HIGH_SPEED_RAMP_STEP=RAMP_STEP,
    parameter integer HIGH_SPEED_RAMP_THRESHOLD_MM_S=250
)(
    input wire clk,rst_n,enable,clear_fault,group_fault,
    input wire signed [31:0] target_mm_s,encoder_count,
    output reg [9:0] duty,
    output wire direction,drive_enable,
    output reg fault
);
    localparam integer TICKS=(CLK_HZ/1000)*SAMPLE_MS;
    localparam integer CW=TICKS>1?$clog2(TICKS):1;
    localparam integer BLANK_TICKS=(CLK_HZ/1000000)*CHANGE_BLANK_US;
    localparam integer BW=BLANK_TICKS>0?$clog2(BLANK_TICKS+1):1;
    localparam [63:0] SCALE_NUM=(64'd1<<COUNT_SCALE_BITS)*ENCODER_CPR*SAMPLE_MS;
    localparam [31:0] COUNTS_SCALE=(SCALE_NUM+(CIRCUMFERENCE_MM*1000)/2)/(CIRCUMFERENCE_MM*1000);
    // Retain the original arithmetic ranges, but do not build 48-bit serial
    // adders for the default 22/26-bit nonnegative products.
    function integer bounded_width;
        input [63:0] limit;
        input integer maximum;
        integer n;
        begin
            n=$clog2(limit+1);if(n<1)n=1;
            bounded_width=n>maximum?maximum:n;
        end
    endfunction
    localparam integer MAG_W=bounded_width(MAX_SPEED_MM_S,16);
    localparam integer COUNTS_W=bounded_width(64'd1*COUNTS_SCALE*MAX_SPEED_MM_S,48);
    localparam integer FF_W=FF_Q16<0?48:bounded_width(64'd1*FF_Q16*MAX_SPEED_MM_S,48);
    localparam integer REF_W=bounded_width(MAX_SPEED_MM_S,31)+1;
    localparam integer MEASURE_W=bounded_width(64'd256*MAX_COUNTS_PER_SAMPLE,31)+1;
    localparam integer INTEGRAL_W=bounded_width(64'd256*MAX_DUTY,31)+1;
    reg [CW-1:0] tick;
    reg [BW-1:0] blank_count;
    reg signed [31:0] previous_count,work_error;
    reg signed [MEASURE_W-1:0] measured_q8,work_measured;
    reg signed [REF_W-1:0] reference_mm_s,work_reference;
    reg signed [INTEGRAL_W-1:0] integral_q8;
    reg [MAG_W-1:0] multiplier;
    reg [COUNTS_W-1:0] counts_shift,counts_product;
    reg [FF_W-1:0] ff_shift,ff_product;
    reg [3:0] bit_number;
    reg multiplying,positive;
    assign direction=positive?FORWARD_LEVEL:!FORWARD_LEVEL;
    assign drive_enable=enable && !fault && !group_fault && reference_mm_s!=0 &&
        duty!=0 && blank_count==0 && target_mm_s!=0;
    always @(posedge clk or negedge rst_n)begin:wheel
        reg signed [31:0] next_reference,requested,delta,n,oriented,err,icandidate,u,ramp_step,feedforward;
        reg [31:0] magnitude;
        reg signed [63:0] wide;
        reg [COUNTS_W-1:0] cp;
        reg [FF_W-1:0] fp;
        if(!rst_n)begin
            duty<=0;fault<=0;tick<=0;blank_count<=0;previous_count<=0;
            measured_q8<=0;reference_mm_s<=0;integral_q8<=0;
            multiplier<=0;counts_shift<=0;ff_shift<=0;counts_product<=0;ff_product<=0;
            bit_number<=0;multiplying<=0;positive<=1;work_error<=0;work_measured<=0;work_reference<=0;
        end else if(!enable || clear_fault)begin
            duty<=0;fault<=0;tick<=0;blank_count<=BLANK_TICKS;
            previous_count<=encoder_count;measured_q8<=0;reference_mm_s<=0;
            integral_q8<=0;multiplying<=0;
        end else begin
            if(blank_count!=0)blank_count<=blank_count-1'b1;
            tick<=tick==TICKS-1?0:tick+1'b1;
            if(fault || group_fault || target_mm_s==0)begin
                duty<=0;integral_q8<=0;reference_mm_s<=0;multiplying<=0;
                previous_count<=encoder_count;measured_q8<=0;
                if(target_mm_s==0)blank_count<=BLANK_TICKS;
            end else if(multiplying)begin
                cp=counts_product+(multiplier[0]?counts_shift:{COUNTS_W{1'b0}});
                fp=ff_product+(multiplier[0]?ff_shift:{FF_W{1'b0}});
                counts_product<=cp;ff_product<=fp;
                counts_shift<=counts_shift<<1;ff_shift<=ff_shift<<1;multiplier<=multiplier>>1;
                if(bit_number==15)begin
                    // Count product Q(COUNT_SCALE_BITS) -> counts/sample Q8.

                    err=$signed(cp>>(COUNT_SCALE_BITS-8))-work_measured;
                    icandidate=integral_q8+(err>>>(KI_SHIFT-8));
                    // Signed integral cancels feedforward overestimation too;
                    // a zero lower bound would leave faster wheels too fast.
                    if(icandidate<-(MAX_DUTY<<8))icandidate=-(MAX_DUTY<<8);
                    if(icandidate>(MAX_DUTY<<8))icandidate=MAX_DUTY<<8;
                    // Keep feedforward within actuator range so a large velocity
                    // cannot overwhelm all negative PI correction after a unit change.
                    feedforward=$signed(fp>>16);
                    if(feedforward>MAX_DUTY)feedforward=MAX_DUTY;
                    u=feedforward+(err>>>KP_SHIFT)+(icandidate>>>8);
                    if((u>=0 && u<=MAX_DUTY) || (u>MAX_DUTY && err<0) || (u<0 && err>0))
                        integral_q8<=icandidate;
                    if(u<0)u=0;else if(u>MAX_DUTY)u=MAX_DUTY;
                    duty<=u[9:0];multiplying<=0;work_error<=err;
                end else bit_number<=bit_number+1'b1;
            end else if(tick==TICKS-1)begin
                // Subtract modulo 32 bits before direction normalization.
                delta=encoder_count-previous_count;previous_count<=encoder_count;
                if(ENCODER_REVERSE)delta=-delta;
                wide=delta;
                if(wide>MAX_COUNTS_PER_SAMPLE || wide<-MAX_COUNTS_PER_SAMPLE)begin fault<=1;duty<=0;end
                else begin
                    n=measured_q8+(((delta<<<8)-measured_q8)>>>1);
                    measured_q8<=n;
                    requested=target_mm_s;
                    if(requested>MAX_SPEED_MM_S)requested=MAX_SPEED_MM_S;
                    if(requested<-MAX_SPEED_MM_S)requested=-MAX_SPEED_MM_S;
                    ramp_step=(requested>HIGH_SPEED_RAMP_THRESHOLD_MM_S || requested<-HIGH_SPEED_RAMP_THRESHOLD_MM_S)?HIGH_SPEED_RAMP_STEP:RAMP_STEP;
                    next_reference=reference_mm_s;
                    if(next_reference<requested)begin
                        next_reference=next_reference+ramp_step;
                        if(next_reference>requested)next_reference=requested;
                    end else if(next_reference>requested)begin
                        next_reference=next_reference-ramp_step;
                        if(next_reference<requested)next_reference=requested;
                    end
                    // Always visit zero before changing physical direction.
                    if((reference_mm_s>0 && next_reference<0) || (reference_mm_s<0 && next_reference>0))next_reference=0;
                    reference_mm_s<=next_reference;
                    if(next_reference==0)begin duty<=0;integral_q8<=0;blank_count<=BLANK_TICKS;end
                    else begin
                        if((next_reference>0)!=positive)begin
                            positive<=next_reference>0;duty<=0;integral_q8<=0;blank_count<=BLANK_TICKS;
                        end
                        oriented=next_reference>0?n:-n;
                        work_measured<=oriented;work_reference<=next_reference;
                        magnitude=next_reference>=0?next_reference:-next_reference;
                        multiplier<=magnitude[MAG_W-1:0];counts_shift<=COUNTS_SCALE;
                        ff_shift<=FF_Q16;counts_product<=0;ff_product<=0;bit_number<=0;multiplying<=1;
                    end
                end
            end
        end
    end
endmodule

// from the UART's most recent opcode/data and never change gimbal state.
module chassis_uart_control #(
    parameter integer CLK_HZ=50000000,
    parameter integer CHANGE_BLANK_US=20
)(
    input wire clk,rst_n,command_valid,
    input wire [7:0] command_code,command_data,
    output reg [2:0] mode=3'd4,
    output wire signed [15:0] forward_unit,lateral_unit,
    output wire drive_enable
);
    localparam integer BLANK_TICKS=(CLK_HZ/1000000)*CHANGE_BLANK_US;
    localparam integer BW=BLANK_TICKS>0 ? $clog2(BLANK_TICKS+1) : 1;
    reg [BW-1:0] blank_count=0;
    assign forward_unit=mode==0 ? 16'sd1 : (mode==1 ? -16'sd1 : 16'sd0);
    // The measured vehicle wiring reverses the requested left/right travel;
    // keep the command names stable and invert only the lateral vector.
    assign lateral_unit=mode==2 ? -16'sd1 : (mode==3 ? 16'sd1 : 16'sd0);
    assign drive_enable=rst_n && mode<4 && blank_count==0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin mode<=4;blank_count<=0;end
        else begin
            if(blank_count!=0)blank_count<=blank_count-1'b1;
            if(command_valid && command_code==8'h2d && command_data<=3)begin
                // A distance-mode transition must never replay old 31 motion.
                mode<=4;blank_count<=0;
            end else if(command_valid && command_code==8'h31 && command_data<=4 && mode!=command_data[2:0])begin
                mode<=command_data[2:0];
                // Allow the car sign pipeline and all H-bridges to go idle
                // before applying a different direction. Stop gates at once.
                blank_count<=BLANK_TICKS;
            end
        end
    end
endmodule

// A leads B: 00 -> 10 -> 11 -> 01 -> 00 adds four counts. B leads A
// subtracts four. Both pins are synchronized; diagonal transitions are ignored.
module chassis_encoder_ab #(
    parameter integer FILTER_CYCLES=0
)(
    input wire clk,rst_n,a,b,
    output reg signed [31:0] count,
    output reg step_valid,step_positive,invalid_transition
);
    (* async_reg="true" *) reg [1:0] ab_meta,ab_sync;
    wire [1:0] qualified_ab;
    generate if(FILTER_CYCLES>1)begin:input_filter
        localparam integer FW=$clog2(FILTER_CYCLES);
        reg [FW-1:0] stable_a,stable_b;
        reg [1:0] filtered;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin stable_a<=0;stable_b<=0;filtered<=0;end
            else begin
                if(ab_sync[1]==filtered[1])stable_a<=0;
                else if(stable_a==FILTER_CYCLES-1)begin filtered[1]<=ab_sync[1];stable_a<=0;end
                else stable_a<=stable_a+1'b1;
                if(ab_sync[0]==filtered[0])stable_b<=0;
                else if(stable_b==FILTER_CYCLES-1)begin filtered[0]<=ab_sync[0];stable_b<=0;end
                else stable_b<=stable_b+1'b1;
            end
        end
        assign qualified_ab=filtered;
    end else begin:unfiltered
        assign qualified_ab=ab_sync;
    end endgenerate
    localparam integer WARM_CYCLES=FILTER_CYCLES>1?FILTER_CYCLES+4:4;
    localparam integer WW=$clog2(WARM_CYCLES+1);
    reg [1:0] previous;
    reg [WW-1:0] warmup;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin ab_meta<=0;ab_sync<=0;end
        else begin ab_meta<={a,b};ab_sync<=ab_meta;end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            previous<=0;warmup<=0;count<=0;step_valid<=0;step_positive<=0;invalid_transition<=0;
        end else begin
            step_valid<=0;invalid_transition<=0;
            previous<=qualified_ab;
            if(warmup<WARM_CYCLES)warmup<=warmup+1'b1;
            else case({previous,qualified_ab})
                4'b0010,4'b1011,4'b1101,4'b0100:begin count<=count+32'sd1;step_valid<=1;step_positive<=1;end
                4'b0001,4'b0111,4'b1110,4'b1000:begin count<=count-32'sd1;step_valid<=1;step_positive<=0;end
                4'b0011,4'b1100,4'b0110,4'b1001:invalid_transition<=1;
                default:begin end
            endcase
        end
    end
endmodule

// Keep the UART modules in this existing project source so a GUI with an
// older cached source list can still elaborate the manual gimbal controller.

// Every command, including commands handled elsewhere, consumes its payload.
// 26 01/00: enter/leave; 29 dx: ID1; 2A dy: ID2 (signed int8).

module uart_gimbal_manual #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    parameter integer PACKET_TIMEOUT_MS=20
)(
    input wire clk,rst_n,rx,
    input wire self_select_parent,
    output reg manual_mode,enter_manual,dx_valid,dy_valid,
    output reg signed [7:0] dx,dy,
    output reg command_valid,
    output reg [7:0] command_code,command_data,
    output reg feature_guard_mode,
    output reg feature_region_selected,
    output reg [1:0] tracking_mode,
    output reg static_tracking_mode,static_tracking_hold,
    output reg all_target_guard_mode,selected_tracking_mode,
    output reg self_select_mode
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer HALF_TICKS=BIT_TICKS/2;
    localparam integer BW=BIT_TICKS>1?$clog2(BIT_TICKS):1;
    localparam integer TIMEOUT_TICKS=(CLK_HZ/1000)*PACKET_TIMEOUT_MS;
    localparam integer PW=TIMEOUT_TICKS>1?$clog2(TIMEOUT_TICKS):1;
    localparam IDLE=0,START=1,DATA=2,STOP=3,RECOVER=4;
    (* async_reg="true" *) reg rx_meta,rx_sync;
    reg [2:0] state;
    reg [BW-1:0] tick;
    reg [2:0] bit_index;
    reg [7:0] shift;
    reg byte_valid,frame_error;
    reg [7:0] byte_data;
    reg waiting_data;
    reg [7:0] command;
    reg [PW-1:0] packet_age;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=rx;rx_sync<=rx_meta;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;tick<=0;bit_index<=0;shift<=0;
            byte_valid<=0;frame_error<=0;byte_data<=0;
        end else begin
            byte_valid<=0;frame_error<=0;
            case(state)
                IDLE:if(!rx_sync) begin state<=START;tick<=HALF_TICKS-1;end
                START:if(tick!=0) tick<=tick-1'b1;
                    else if(rx_sync) state<=IDLE;
                    else begin state<=DATA;tick<=BIT_TICKS-1;bit_index<=0;end
                DATA:if(tick!=0) tick<=tick-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync;tick<=BIT_TICKS-1;
                        if(bit_index==7) state<=STOP;
                        else bit_index<=bit_index+1'b1;
                    end
                STOP:if(tick!=0) tick<=tick-1'b1;
                    else if(rx_sync) begin byte_data<=shift;byte_valid<=1;state<=IDLE;end
                    else begin frame_error<=1;state<=RECOVER;end
                RECOVER:if(rx_sync) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            command_valid<=0;command_code<=0;command_data<=0;
            waiting_data<=0;command<=0;packet_age<=0;
        end else begin
            command_valid<=0;
            if(waiting_data) begin
                if(packet_age==TIMEOUT_TICKS-1) begin waiting_data<=0;packet_age<=0;end
                else packet_age<=packet_age+1'b1;
            end
            if(frame_error) begin waiting_data<=0;packet_age<=0;end
            else if(byte_valid) begin
                packet_age<=0;
                if(waiting_data && packet_age!=TIMEOUT_TICKS-1) begin
                    // Unknown opcodes still own exactly one payload byte.
                    // A payload may itself equal any opcode; never rescan it.
                    waiting_data<=0;
                    command_valid<=1;command_code<=command;command_data<=byte_data;
                end else begin
                    command<=byte_data;waiting_data<=1;
                end
            end
        end
    end

    // Command events update persistent state. The latest command/data values
    // are never used as level-sensitive mode enables; subsequent unrelated
    // commands cannot cancel guard/manual state or replay an earlier command.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;enter_manual<=0;tracking_mode<=0;
            static_tracking_mode<=0;static_tracking_hold<=0;
            all_target_guard_mode<=0;
            selected_tracking_mode<=0;
            self_select_mode<=0;
            dx_valid<=0;dy_valid<=0;dx<=0;dy<=0;
        end else begin
            enter_manual<=0;dx_valid<=0;dy_valid<=0;
            if(command_valid && ((command_code==8'h0e && command_data<=1) ||
                (command_code==8'h21 && command_data==2) ||
                (command_code==8'h26 && command_data<=1) ||
                (command_code==8'h28 && command_data==1) ||
                (command_code==8'h2c && (command_data==3 || (command_data==4 && static_tracking_mode))) ||
                (command_code==8'h2d && command_data==1)))self_select_mode<=0;
            if(command_valid) case(command_code)
                8'h0e:if(command_data==0 || command_data==1) begin
                    // Select/leave the region workflow. Every selection needs
                    // a subsequent 21 01, even if old coordinates are confirmed.
                    feature_region_selected<=command_data[0];
                    feature_guard_mode<=0;
                    if(command_data==1) begin
                        manual_mode<=0;static_tracking_mode<=0;static_tracking_hold<=0;
                        all_target_guard_mode<=0;
                        selected_tracking_mode<=0;
                    end
                end
                8'h21:if(command_data==1 && feature_region_selected) begin
                    // Confirmation is the only guard entry. It also releases
                    // manual positioning so the angle anchor is captured now.
                    feature_guard_mode<=1;manual_mode<=0;
                    all_target_guard_mode<=0;
                    selected_tracking_mode<=0;
                end else if(command_data==2) feature_guard_mode<=0;
                8'h26:if(command_data==0 || command_data==1) begin
                    manual_mode<=command_data[0];
                    static_tracking_mode<=0;static_tracking_hold<=0;
                    selected_tracking_mode<=0;
                    enter_manual<=command_data[0] && !manual_mode;
                    if(command_data==1)begin feature_guard_mode<=0;all_target_guard_mode<=0;end
                end
                8'h28:if(command_data==0 || command_data==1)begin
                    all_target_guard_mode<=command_data[0];
                    if(command_data==1)begin
                        // Whole-region guard holds entry pose and announces
                        // scene entries; top masks visual following entirely.
                        manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;
                        static_tracking_mode<=0;static_tracking_hold<=0;
                        selected_tracking_mode<=0;
                    end
                end
                8'h2c:if(command_data<=2) begin
                    // A profile command changes tuning only. Mode entry/exit
                    // belongs to its explicit command; never drop a static
                    // lock, applied distance control, guard, manual or hold.
                    tracking_mode<=command_data[1:0];
                end else if(command_data==3) begin
                    // Static coordinates use the saved shared profile.
                    // Target ownership is independent of profile selection.
                    static_tracking_mode<=1;static_tracking_hold<=0;
                    manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;
                    all_target_guard_mode<=0;
                    selected_tracking_mode<=0;
                end else if(command_data==4 && static_tracking_mode) begin
                    static_tracking_mode<=0;static_tracking_hold<=1;
                    selected_tracking_mode<=0;
                end
                8'h2d:if(command_data==1)begin
                    // Distance preparation keeps the selected static target
                    // under continuous visual tracking, including after hold.
                    static_tracking_mode<=1;static_tracking_hold<=0;
                    manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;
                    all_target_guard_mode<=0;
                    selected_tracking_mode<=0;
                end
                // Applied feature/static parents keep their full control path.
                // 38 01/00 enters/exits selection; 03/04 applies/cancels a
                // target inside it. Cancel must not exit selection or rearm
                // loss search. Legacy standalone03/04 keeps its old owner.
                8'h38:if(command_data==1)begin
                    if(self_select_parent===1'b1)self_select_mode<=1;
                end else if(command_data==0)self_select_mode<=0;
                else if(command_data==3)begin
                    if(self_select_parent===1'b1)self_select_mode<=1;
                    else begin
                        self_select_mode<=0;
                        selected_tracking_mode<=1;static_tracking_mode<=1;static_tracking_hold<=0;
                        manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;all_target_guard_mode<=0;
                    end
                end else if(command_data==4)begin
                    if(!self_select_mode && selected_tracking_mode)begin
                        selected_tracking_mode<=0;static_tracking_mode<=0;static_tracking_hold<=1;
                    end
                end
                8'h29:if(manual_mode) begin dx<=$signed(command_data);dx_valid<=1;end
                8'h2a:if(manual_mode) begin dy<=$signed(command_data);dy_valid<=1;end
                default:begin end
            endcase
        end
    end
endmodule

// Four editable pixel-space vertices for a future motor travel limiter.
// Storage only: independent of manual gimbal mode, with no motor/display use.
// 24 00..04 selects a point; 21 02 resets; 21 01 marks the region confirmed;
// 22/23 signed int8 pixels update only the selected point's X/Y coordinate.
module uart_region_store(
    input wire clk,rst_n,command_valid,
    input wire [7:0] command_code,command_data,
    output reg [15:0] point1_x,point1_y,point2_x,point2_y,
        point3_x,point3_y,point4_x,point4_y,
    output reg [2:0] selected_point,
    output reg confirmed
);
    wire [15:0] selected_x=selected_point==1 ? point1_x :
        (selected_point==2 ? point2_x : (selected_point==3 ? point3_x : point4_x));
    wire [15:0] selected_y=selected_point==1 ? point1_y :
        (selected_point==2 ? point2_y : (selected_point==3 ? point3_y : point4_y));
    function [15:0] move_pixel;
        input [15:0] coordinate,maximum;
        input signed [7:0] delta;
        reg signed [17:0] sum;
        begin
            sum=$signed({2'b00,coordinate})+$signed({{10{delta[7]}},delta});
            if(sum<0) move_pixel=0;
            else if(sum>$signed({2'b00,maximum})) move_pixel=maximum;
            else move_pixel=sum[15:0];
        end
    endfunction
    wire [15:0] next_x=move_pixel(selected_x,16'd1279,$signed(command_data));
    wire [15:0] next_y=move_pixel(selected_y,16'd719,$signed(command_data));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            point1_x<=400;point1_y<=200;point2_x<=879;point2_y<=200;
            point3_x<=879;point3_y<=519;point4_x<=400;point4_y<=519;
            selected_point<=0;confirmed<=0;
        end else if(command_valid) begin
            case(command_code)
                8'h24:if(command_data<=4) selected_point<=command_data[2:0];
                8'h21:if(command_data==2) begin
                    point1_x<=400;point1_y<=200;point2_x<=879;point2_y<=200;
                    point3_x<=879;point3_y<=519;point4_x<=400;point4_y<=519;
                    selected_point<=0;confirmed<=0;
                end else if(command_data==1) confirmed<=1;
                8'h22:if(selected_point!=0 && next_x!=selected_x) begin
                    case(selected_point)
                        1:point1_x<=next_x;
                        2:point2_x<=next_x;
                        3:point3_x<=next_x;
                        4:point4_x<=next_x;
                        default:begin end
                    endcase
                    confirmed<=0;
                end
                8'h23:if(selected_point!=0 && next_y!=selected_y) begin
                    case(selected_point)
                        1:point1_y<=next_y;
                        2:point2_y<=next_y;
                        3:point3_y<=next_y;
                        4:point4_y<=next_y;
                        default:begin end
                    endcase
                    confirmed<=0;
                end
                default:begin end
            endcase
        end
    end
endmodule


// Residual stays in [-112,112]/225 of a count, rounding the accumulated

// Only add/subtract/compare are used; no extra runtime DSP is required.
module gimbal_manual_step(
    input wire clk,rst_n,clear,valid,
    input wire signed [7:0] units,
    output reg done,
    output reg signed [9:0] counts
);
    reg [7:0] remaining;
    reg negative;
    reg signed [9:0] remainder;
    reg signed [9:0] accumulated;
    wire signed [9:0] sum=remainder+(negative?-10'sd256:10'sd256);
    wire signed [9:0] correction=sum>10'sd337 ? 10'sd2 :
        (sum>10'sd112 ? 10'sd1 : (sum< -10'sd337 ? -10'sd2 : -10'sd1));
    wire signed [9:0] next_remainder=sum-(correction==10'sd2 ? 10'sd450 :
        (correction==10'sd1 ? 10'sd225 : (correction== -10'sd2 ? -10'sd450 : -10'sd225)));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin remaining<=0;negative<=0;remainder<=0;accumulated<=0;done<=0;counts<=0;end
        else begin
            done<=0;
            if(clear) begin remaining<=0;remainder<=0;accumulated<=0;counts<=0;end
            else if(remaining!=0) begin
                remainder<=next_remainder;accumulated<=accumulated+correction;
                remaining<=remaining-1'b1;
                if(remaining==1) begin counts<=accumulated+correction;done<=1;end
            end else if(valid) begin
                remaining<=units[7]?(~units+8'd1):units;
                negative<=units[7];accumulated<=0;
                if(units==0) begin counts<=0;done<=1;end
            end
        end
    end
endmodule


// Independent motor-angle bounds from the four points' axis-aligned extents.


// Anchor once per 0E 01 session at the current multi-turn motor positions.
// Lower bounds round up and upper bounds round down, remaining inside the
// requested angular interval. A shared restoring divider uses no extra DSP.
module feature_region_limit #(
    parameter integer X_COUNT_INCREASE=1,
    parameter integer Y_COUNT_INCREASE=1
)(
    input wire clk,rst_n,armed,confirmed,feedback_ready,
    input wire [15:0] point1_x,point1_y,point2_x,point2_y,
        point3_x,point3_y,point4_x,point4_y,setpoint_x,setpoint_y,
    input wire signed [31:0] position1,position2,target1,target2,velocity1,velocity2,
    output wire ready,
    output wire signed [31:0] limited_target1,limited_target2,
        limited_velocity1,limited_velocity2,
    output reg signed [31:0] min1,max1,min2,max2,
    output wire signed [31:0] initial_position1,initial_position2
);
    function [15:0] low2;
        input [15:0] a,b;
        begin low2=a<b ? a : b;end
    endfunction
    function [15:0] high2;
        input [15:0] a,b;
        begin high2=a>b ? a : b;end
    endfunction
    wire [15:0] xmin=low2(low2(point1_x,point2_x),low2(point3_x,point4_x));
    wire [15:0] xmax=high2(high2(point1_x,point2_x),high2(point3_x,point4_x));
    wire [15:0] ymin=low2(low2(point1_y,point2_y),low2(point3_y,point4_y));
    wire [15:0] ymax=high2(high2(point1_y,point2_y),high2(point3_y,point4_y));
    wire geometry_ok=xmin<xmax && ymin<ymax && xmax<1280 && ymax<720 &&
        setpoint_x<1280 && setpoint_y<720;
    reg anchored,have_bounds;
    reg signed [31:0] anchor1,anchor2;
    assign initial_position1=anchor1;
    assign initial_position2=anchor2;
    reg [15:0] applied_xmin,applied_xmax,applied_ymin,applied_ymax,applied_sx,applied_sy;
    wire dirty=xmin!=applied_xmin || xmax!=applied_xmax || ymin!=applied_ymin ||
        ymax!=applied_ymax || setpoint_x!=applied_sx || setpoint_y!=applied_sy;
    assign ready=armed && confirmed && feedback_ready && geometry_ok && anchored && have_bounds && !dirty &&
        min1<=max1 && min2<=max2;
    reg [1:0] state,phase;
    localparam IDLE=0,PREPARE=1,DIVIDE=2,STORE=3;
    reg signed [16:0] delta[0:3];
    reg [31:0] numerator,quotient;
    reg [10:0] remainder,denominator;
    reg [5:0] bit_index;
    reg negative;
    reg signed [31:0] pending_min1,pending_max1,pending_min2;
    wire [11:0] trial={remainder,numerator[31]};
    wire take_bit=trial>={1'b0,denominator};
    wire [31:0] magnitude=delta[phase]<0 ? -$signed(delta[phase]) : $signed(delta[phase]);
    // Ceiling for the lower bound; floor for the upper bound.
    wire signed [31:0] rounded_offset=negative ?
        (-$signed(quotient)-((phase[0] && remainder!=0) ? 32'sd1 : 32'sd0)) :
        ($signed(quotient)+((!phase[0] && remainder!=0) ? 32'sd1 : 32'sd0));
    function signed [31:0] add_position;
        input signed [31:0] base,offset;
        reg signed [32:0] sum;
        begin
            sum=$signed({base[31],base})+$signed({offset[31],offset});
            if(sum>33'sd2147483647) add_position=32'sh7fffffff;
            else if(sum< -33'sd2147483648) add_position=32'sh80000000;
            else add_position=sum[31:0];
        end
    endfunction
    wire signed [31:0] bound_value=add_position(phase[1] ? anchor2 : anchor1,rounded_offset);
    assign limited_target1=!armed ? target1 : (!ready ? position1 :
        (target1<min1 ? min1 : (target1>max1 ? max1 : target1)));
    assign limited_target2=!armed ? target2 : (!ready ? position2 :
        (target2<min2 ? min2 : (target2>max2 ? max2 : target2)));
    // A clipped target uses position correction without stale feedforward.
    // At a boundary discard any feedforward pointing out of the interval.
    assign limited_velocity1=!armed ? velocity1 :
        (!ready || target1<min1 || target1>max1 ||
        ((limited_target1<=min1 || position1<=min1) && velocity1<0) ||
        ((limited_target1>=max1 || position1>=max1) && velocity1>0) ? 32'sd0 : velocity1);
    assign limited_velocity2=!armed ? velocity2 :
        (!ready || target2<min2 || target2>max2 ||
        ((limited_target2<=min2 || position2<=min2) && velocity2<0) ||
        ((limited_target2>=max2 || position2>=max2) && velocity2>0) ? 32'sd0 : velocity2);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            anchored<=0;have_bounds<=0;anchor1<=0;anchor2<=0;
            applied_xmin<=0;applied_xmax<=0;applied_ymin<=0;applied_ymax<=0;applied_sx<=0;applied_sy<=0;
            state<=IDLE;phase<=0;delta[0]<=0;delta[1]<=0;delta[2]<=0;delta[3]<=0;
            numerator<=0;quotient<=0;remainder<=0;denominator<=1;bit_index<=0;negative<=0;
            pending_min1<=0;pending_max1<=0;pending_min2<=0;min1<=0;max1<=0;min2<=0;max2<=0;
        end else if(!armed || !feedback_ready) begin
            anchored<=0;have_bounds<=0;state<=IDLE;
        end else if(!anchored) begin
            anchor1<=position1;anchor2<=position2;anchored<=1;have_bounds<=0;state<=IDLE;
        end else if(!confirmed || !geometry_ok) begin
            have_bounds<=0;state<=IDLE;
        end else if(state!=IDLE && dirty) begin
            have_bounds<=0;state<=IDLE;
        end else case(state)
            IDLE:if(!have_bounds || dirty) begin
                applied_xmin<=xmin;applied_xmax<=xmax;applied_ymin<=ymin;applied_ymax<=ymax;
                applied_sx<=setpoint_x;applied_sy<=setpoint_y;
                delta[0]<=X_COUNT_INCREASE ?
                    $signed({1'b0,xmin})-$signed({1'b0,setpoint_x}) :
                    $signed({1'b0,setpoint_x})-$signed({1'b0,xmax});
                delta[1]<=X_COUNT_INCREASE ?
                    $signed({1'b0,xmax})-$signed({1'b0,setpoint_x}) :
                    $signed({1'b0,setpoint_x})-$signed({1'b0,xmin});
                delta[2]<=Y_COUNT_INCREASE ?
                    $signed({1'b0,ymin})-$signed({1'b0,setpoint_y}) :
                    $signed({1'b0,setpoint_y})-$signed({1'b0,ymax});
                delta[3]<=Y_COUNT_INCREASE ?
                    $signed({1'b0,ymax})-$signed({1'b0,setpoint_y}) :
                    $signed({1'b0,setpoint_y})-$signed({1'b0,ymin});
                have_bounds<=0;phase<=0;state<=PREPARE;
            end
            PREPARE:begin
                numerator<=magnitude<<5;
                denominator<=11'd45;
                negative<=delta[phase]<0;quotient<=0;remainder<=0;bit_index<=31;state<=DIVIDE;
            end
            DIVIDE:begin
                remainder<=take_bit ? trial-{1'b0,denominator} : trial;
                quotient<={quotient[30:0],take_bit};numerator<={numerator[30:0],1'b0};
                if(bit_index==0) state<=STORE;
                else bit_index<=bit_index-1'b1;
            end
            STORE:begin
                case(phase)
                    0:pending_min1<=bound_value;
                    1:pending_max1<=bound_value;
                    2:pending_min2<=bound_value;
                    3:begin
                        min1<=pending_min1;max1<=pending_max1;min2<=pending_min2;max2<=bound_value;
                        have_bounds<=1;
                    end
                endcase
                if(phase==3) state<=IDLE;
                else begin phase<=phase+1'b1;state<=PREPARE;end
            end
            default:state<=IDLE;
        endcase
    end
endmodule


// Outside dwell begins at the actual clipped motor reference. Brief invalid
// records share the visual last-good grace; after 300ms, a separate continuous
// loss dwell starts. Either a boundary dwell or confirmed loss may request home.
// Reacquisition checks a NEW visual angle pair, not the image bounding box.
module feature_guard_return #(
    parameter integer CLK_HZ=50000000,
    parameter integer OUTSIDE_TIMEOUT_MS=5000,
    parameter integer TARGET_LOSS_MS=300,
    parameter integer HOME_SETTLE_MS=100,
    parameter integer BOUNDARY_TOLERANCE_COUNTS=23
)(
    input wire clk,rst_n,armed,limits_ready,feedback_ready,manual_override,tracking_active,
    input wire target_update,target_valid,
    input wire [15:0] center_x,center_y,point1_x,point1_y,point2_x,point2_y,
        point3_x,point3_y,point4_x,point4_y,
    input wire signed [31:0] target1,target2,min1,max1,min2,max2,
        initial_position1,initial_position2,position1,position2,reference1,reference2,
    input wire at_target1,at_target2,vision_command_valid,vision_hold,vision_tracking,
    output wire return_override,vision_suspend,
    output reg home_done
);
    localparam integer OUT_TICKS=(CLK_HZ/1000)*OUTSIDE_TIMEOUT_MS;
    localparam integer HOME_TICKS=(CLK_HZ/1000)*HOME_SETTLE_MS;
    localparam integer LOSS_TICKS=(CLK_HZ/1000)*TARGET_LOSS_MS;
    localparam integer OW=OUT_TICKS>1?$clog2(OUT_TICKS+1):1;
    localparam integer HW=HOME_TICKS>1?$clog2(HOME_TICKS+1):1;
    localparam integer LW=LOSS_TICKS>1?$clog2(LOSS_TICKS+1):1;
    localparam MONITOR=0,RETURNING=1,HOME_HOLD=2,REACQUIRE=3;
    reg [1:0] state;
    reg [OW-1:0] outside_count1,outside_count2;
    reg [OW-1:0] lost_count;
    reg [LW-1:0] target_age;
    reg have_record,tracked_once;
    reg [HW-1:0] home_count;
    reg [1:0] last_side1,last_side2;
    wire [1:0] side1=target1<min1?2'd1:(target1>max1?2'd2:2'd0);
    wire [1:0] side2=target2<min2?2'd1:(target2>max2?2'd2:2'd0);
    wire coordinate_valid=target_valid && center_x<1280 && center_y<720 &&
        (center_x!=0 || center_y!=0);
    wire fresh_target=target_update && coordinate_valid;
    wire live_target=fresh_target || (have_record && target_age<LOSS_TICKS);
    wire target_lost=tracked_once && !live_target;
    // Start the dwell timer near the clipped reference. This inward margin
    // affects arrival detection only; the enforced angle bounds stay unchanged.
    // Overshoot still counts as arrival. Home uses both controllers' at_target.
    localparam signed [31:0] EDGE_TOLERANCE=BOUNDARY_TOLERANCE_COUNTS;
    wire edge1=tracking_active && live_target && side1!=0 &&
        reference1==(side1==1?min1:max1) &&
        (side1==1 ? position1<=min1+EDGE_TOLERANCE : position1>=max1-EDGE_TOLERANCE);
    wire edge2=tracking_active && live_target && side2!=0 &&
        reference2==(side2==1?min2:max2) &&
        (side2==1 ? position2<=min2+EDGE_TOLERANCE : position2>=max2-EDGE_TOLERANCE);
    wire timeout1=edge1 && side1==last_side1 && outside_count1>=OUT_TICKS-1;
    wire timeout2=edge2 && side2==last_side2 && outside_count2>=OUT_TICKS-1;
    wire loss_timeout=target_lost && lost_count>=OUT_TICKS-1;
    wire home_reached=at_target1 && at_target2 && reference1==initial_position1 && reference2==initial_position2;
    // Compatibility point ports are deliberately not used here. The same
    // angular decision drives boundary dwell, report status and reacquisition.
    wire angles_inside=side1==0 && side2==0;
    assign return_override=armed && limits_ready && feedback_ready && !manual_override && state!=MONITOR;
    // During reacquisition keep the motors at home while allowing the vision
    // observer to create a fresh command. Never release an old outside target.
    assign vision_suspend=return_override && state!=REACQUIRE;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=MONITOR;outside_count1<=0;outside_count2<=0;home_count<=0;
            lost_count<=0;target_age<=LOSS_TICKS;have_record<=0;tracked_once<=0;
            last_side1<=0;last_side2<=0;home_done<=0;
        end else begin
            home_done<=0;
            if(!armed || !limits_ready || !feedback_ready || manual_override) begin
                state<=MONITOR;outside_count1<=0;outside_count2<=0;home_count<=0;
                last_side1<=0;last_side2<=0;
                lost_count<=0;target_age<=LOSS_TICKS;have_record<=0;tracked_once<=0;
            end else begin
                if(fresh_target)begin target_age<=0;have_record<=1;end
                else if(target_age<LOSS_TICKS)target_age<=target_age+1'b1;
                // No return before the first actual tracked target: the
                // upstream warning/countdown may intentionally send no XY.
                if(live_target && (tracking_active || (vision_command_valid && vision_tracking)))
                    tracked_once<=1;
                case(state)
                MONITOR:begin
                    home_count<=0;
                    lost_count<=target_lost?lost_count+1'b1:0;
                    last_side1<=edge1?side1:2'd0;last_side2<=edge2?side2:2'd0;
                    outside_count1<=!edge1?0:(side1!=last_side1?1:outside_count1+1'b1);
                    outside_count2<=!edge2?0:(side2!=last_side2?1:outside_count2+1'b1);
                    if(timeout1 || timeout2 || loss_timeout) begin
                        state<=RETURNING;outside_count1<=0;outside_count2<=0;lost_count<=0;
                    end
                end
                RETURNING:begin
                    lost_count<=0;
                    if(!home_reached) home_count<=0;
                    else if(home_count>=HOME_TICKS-1) begin
                        state<=HOME_HOLD;home_count<=0;home_done<=1;
                    end else home_count<=home_count+1'b1;
                end
                HOME_HOLD:begin
                    lost_count<=0;
                    // Keep the motors at home while the shared visual kernel
                    // computes a fresh angle. Pixel rectangle is no longer a gate.
                    if(fresh_target && home_reached)state<=REACQUIRE;
                end
                REACQUIRE:begin


                    if((target_update && !coordinate_valid) || !live_target ||
                       (vision_command_valid && (!vision_tracking || !angles_inside)))state<=HOME_HOLD;
                    else if(vision_command_valid && vision_tracking && angles_inside) begin
                        state<=MONITOR;last_side1<=0;last_side2<=0;lost_count<=0;
                    end
                end
                default:state<=MONITOR;
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    initial if(CLK_HZ<1000 || CLK_HZ%1000!=0 || OUT_TICKS<2 || HOME_TICKS<1 ||
        LOSS_TICKS<1 || BOUNDARY_TOLERANCE_COUNTS<0 || BOUNDARY_TOLERANCE_COUNTS>4095)
        $fatal(1,"Feature return clock/timeout invalid");
`endif
endmodule


// Use the same unclipped motor-angle target comparisons as the return logic.
// First fresh angle in a guard session only establishes the comparison state.
// Report inside -> any-axis outside=01, outside -> both axes inside=02.
// Keep the last valid state across target loss; unknown is not an edge.
// Exact angle bounds count as inside.
module feature_region_status(
    input wire clk,rst_n,enabled,limits_ready,target_update,target_valid,comm_timeout,
    input wire [15:0] center_x,center_y,
    input wire signed [31:0] target1,target2,min1,max1,min2,max2,
    output wire ready,
    output reg status_valid,
    output reg [7:0] status_data
);
    wire session_ready=enabled && limits_ready && min1<=max1 && min2<=max2;
    assign ready=session_ready &&
        target_valid && !comm_timeout && center_x<1280 && center_y<720 &&
        (center_x!=0 || center_y!=0);
    wire inside=target1>=min1 && target1<=max1 && target2>=min2 && target2<=max2;
    reg known,last_inside;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin known<=0;last_inside<=0;status_valid<=0;status_data<=0;end
        else begin
            status_valid<=0;
            if(!session_ready) known<=0;
            else if(ready && target_update)begin
                known<=1;last_inside<=inside;
                if(known && inside!=last_inside)begin
                    status_data<=inside?8'h02:8'h01;status_valid<=1;
                end
            end
        end
    end
endmodule

// One serializer owns O_uart_tx: each report is an atomic raw pair 30 <payload>.
// Home completion has priority between packets and keeps one extra request.
// Status traffic retains the latest pending state; disabling status cancels a
// queued status but never truncates a packet already on the wire.
module uart_guard_report #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst_n,home_request,status_enable,status_valid,
    input wire [7:0] status_data,
    output wire tx,
    output reg busy
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer BW=BIT_TICKS>1?$clog2(BIT_TICKS):1;
    reg [BW-1:0] ticks;
    reg [9:0] shift;
    reg [3:0] bit_index;
    reg second_byte,home_pending,status_pending;
    reg [7:0] payload,pending_status;
    assign tx=busy?shift[0]:1'b1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;ticks<=0;shift<=10'h3ff;bit_index<=0;second_byte<=0;
            home_pending<=0;status_pending<=0;payload<=0;pending_status<=0;
        end else begin
            if(home_request && busy) home_pending<=1;
            if(!status_enable) status_pending<=0;
            else if(status_valid)begin status_pending<=1;pending_status<=status_data;end
            if(!busy) begin
                if(home_request || home_pending) begin
                    busy<=1;ticks<=0;shift<={1'b1,8'h30,1'b0};
                    bit_index<=0;second_byte<=0;payload<=8'h00;home_pending<=0;
                end else if(status_enable && (status_valid || status_pending)) begin
                    busy<=1;ticks<=0;shift<={1'b1,8'h30,1'b0};
                    bit_index<=0;second_byte<=0;
                    payload<=status_valid?status_data:pending_status;status_pending<=0;
                end
            end else if(ticks==BIT_TICKS-1) begin
                ticks<=0;
                if(bit_index==9) begin
                    if(!second_byte) begin shift<={1'b1,payload,1'b0};bit_index<=0;second_byte<=1;end
                    else begin busy<=0;shift<=10'h3ff;end
                end else begin shift<={1'b1,shift[9:1]};bit_index<=bit_index+1'b1;end
            end else ticks<=ticks+1'b1;
        end
    end
`ifndef SYNTHESIS
    initial if(BAUD<1 || BIT_TICKS<2) $fatal(1,"UART report clock/baud invalid");
`endif
endmodule

// Speech follows the sender's guard-inside bit, not the local angle limits.
// 25 01..0A maps to speech codes 02..0B, with no local countdown/delay.
// Whole-region entry uses code01: AA 55 01 55 AA, with the shared cooldown.
// A feature confirmation starts a fresh setting transaction; if an inside
// event arrives before 25, retain it until its setting arrives or it leaves.
module guard_voice_control #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    parameter integer COOLDOWN_MS=3000
)(
    input wire clk,rst_n,feature_enabled,all_enabled,
    input wire feature_suppress,feature_rearm,
    input wire command_valid,
    input wire [7:0] command_code,command_data,
    input wire result_update,inside_flag,comm_timeout,
    output wire tx,busy
);
    wire [1:0] mode=all_enabled?2'd2:(feature_enabled?2'd1:2'd0);
    reg [1:0] previous_mode;
    reg inside_seen,seconds_valid,deferred_entry,pending;
    reg [7:0] seconds_code,pending_code;
    reg next_inside,next_seconds_valid,next_deferred,next_pending;
    reg [7:0] next_seconds_code,next_pending_code;
    wire configure=command_valid && command_code==8'h25 && command_data>=1 && command_data<=10;
    wire reconfirm=command_valid && command_code==8'h21 && command_data==1 && feature_enabled;
    wire outside_update=result_update && !comm_timeout && !inside_flag;
    // Missing legacy simulation ports retain their former unmuted behavior.
    wire feature_muted=feature_suppress===1'b1;
    wire feature_rearmed=feature_rearm===1'b1;
    localparam [63:0] COOLDOWN_TICKS=(64'd1*CLK_HZ*COOLDOWN_MS+999)/1000;
    localparam integer CW=COOLDOWN_TICKS>0?$clog2(COOLDOWN_TICKS+1):1;
    reg [CW-1:0] cooldown_left;
    wire frame_done;
    wire request=pending && mode!=0 && mode==previous_mode && !reconfirm &&
        !comm_timeout && !outside_update && cooldown_left==0 &&
        !(mode==1 && (feature_muted || feature_rearmed));
    wire tx_ready;
    uart_voice_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) speech_uart(
        .clk(clk),.rst_n(rst_n),.valid(request),.payload(pending_code),
        .ready(tx_ready),.tx(tx),.busy(busy),.frame_done(frame_done));
    // A global post-frame cooldown: mode/target/config changes cannot bypass
    // it. Existing pending speech is retained only while still authorized;
    // outside/timeout/mode exit keep their original cancellation behavior.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)cooldown_left<=0;
        else if(frame_done)cooldown_left<=COOLDOWN_TICKS[CW-1:0];
        else if(cooldown_left!=0)cooldown_left<=cooldown_left-1'b1;
    end
    always @* begin
        next_inside=inside_seen;next_seconds_valid=seconds_valid;
        next_deferred=deferred_entry;next_pending=pending;
        next_seconds_code=seconds_code;next_pending_code=pending_code;
        if(request && tx_ready)next_pending=0;
        if(mode!=previous_mode || reconfirm)begin
            next_inside=0;next_deferred=0;next_pending=0;next_seconds_valid=0;
        end
        if(configure)begin next_seconds_valid=1;next_seconds_code=command_data+8'd1;end
        if(mode==0)begin
            next_inside=0;next_deferred=0;next_pending=0;
        end else if(comm_timeout)begin
            // Unknown network state is not a new entry. Do not reannounce a
            // continuously present target on reconnect, or queue stale speech.
            next_deferred=0;next_pending=0;
        end else if(!reconfirm)begin
            if(result_update)begin
                if(!inside_flag)begin next_inside=0;next_deferred=0;next_pending=0;end
                else if(!next_inside)begin
                    next_inside=1;
                    if(mode==2 || next_seconds_valid)begin
                        next_pending=1;next_pending_code=mode==2?8'h01:next_seconds_code;
                        next_deferred=0;
                    end else next_deferred=1;
                end
            end
            if(next_deferred && next_inside && next_seconds_valid)begin
                next_pending=1;next_pending_code=next_seconds_code;next_deferred=0;
            end
        end
        // Keep mode, configured seconds, inside memory and cooldown intact.
        // Cancel only future feature speech; never truncate a frame in flight.
        if(mode==1 && feature_muted)begin next_pending=0;next_deferred=0;end
        // Return completion retains seconds/cooldown but starts a fresh entry
        // cycle. Ignore a coincident old record; the next high result may warn.
        if(mode==1 && feature_rearmed)begin next_inside=0;next_deferred=0;next_pending=0;end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            previous_mode<=0;inside_seen<=0;seconds_valid<=0;
            deferred_entry<=0;pending<=0;seconds_code<=0;pending_code<=0;
        end else begin
            previous_mode<=mode;inside_seen<=next_inside;seconds_valid<=next_seconds_valid;
            deferred_entry<=next_deferred;pending<=next_pending;
            seconds_code<=next_seconds_code;pending_code<=next_pending_code;
        end
    end
`ifndef SYNTHESIS
    initial if(CLK_HZ<1000 || COOLDOWN_MS<0)$fatal(1,"Invalid speech cooldown parameters");
`endif
endmodule

// Dedicated speech UART: one accepted payload -> AA 55 <payload> 55 AA.
// Ready/valid handshake lets the caller retain one pending announcement.
// Once started, all five bytes finish even if the guard mode changes.
module uart_voice_tx #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst_n,valid,
    input wire [7:0] payload,
    output wire ready,tx,
    output reg busy,
    output wire frame_done
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer TW=BIT_TICKS>1?$clog2(BIT_TICKS):1;
    reg [TW-1:0] ticks;
    reg [9:0] shift;
    reg [3:0] bit_index;
    reg [2:0] byte_index;
    reg [7:0] message;
    assign ready=!busy;
    assign tx=busy?shift[0]:1'b1;
    // Assert during the final stop-bit clock, sampled when busy drops.
    assign frame_done=busy && ticks==BIT_TICKS-1 && bit_index==9 && byte_index==4;
    function [7:0] frame_byte;
        input [2:0] index;
        input [7:0] code;
        begin case(index)
            0,4:frame_byte=8'haa;
            1,3:frame_byte=8'h55;
            2:frame_byte=code;
            default:frame_byte=8'hff;
        endcase end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            busy<=0;ticks<=0;shift<=10'h3ff;bit_index<=0;byte_index<=0;message<=0;
        end else if(!busy)begin
            if(valid)begin
                busy<=1;ticks<=0;shift<={1'b1,8'haa,1'b0};
                bit_index<=0;byte_index<=0;message<=payload;
            end
        end else if(ticks==BIT_TICKS-1)begin
            ticks<=0;
            if(bit_index==9)begin
                if(byte_index==4)begin busy<=0;shift<=10'h3ff;end
                else begin
                    byte_index<=byte_index+1'b1;bit_index<=0;
                    shift<={1'b1,frame_byte(byte_index+1'b1,message),1'b0};
                end
            end else begin shift<={1'b1,shift[9:1]};bit_index<=bit_index+1'b1;end
        end else ticks<=ticks+1'b1;
    end
`ifndef SYNTHESIS
    initial if(BAUD<1 || BIT_TICKS<2)$fatal(1,"Speech UART clock/baud invalid");
`endif
endmodule

// Compatibility wrapper for standalone completion tests: one event -> 30 00.
module uart_home_report #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst_n,request,
    output wire tx,busy
);
    uart_guard_report #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) report(
        .clk(clk),.rst_n(rst_n),.home_request(request),
        .status_enable(1'b0),.status_valid(1'b0),.status_data(8'd0),.tx(tx),.busy(busy));
endmodule

// The TOF receiver is defined in this always-listed source so stale GUI
// project manifests cannot turn it into a black box. Keep exactly one
// definition; user_source/tof_uart_rx.v is now an empty compatibility file.
`timescale 1ns/1ps

// TOFSense-F2 Mini UART active-output receiver.
//
// Wiring:
//   sensor TX (3.3 V TTL) -> sensor_tx input
//   sensor GND             -> FPGA GND
//   sensor VCC             -> regulated 5 V supply
//
// The sensor's default protocol is 921600 baud, 8 data bits, no parity,
// one stop bit.  A valid output frame is 16 bytes long and contains the
// distance in millimetres at bytes 8..10, little endian.
//
// distance_valid and frame_error are one-clock active-high event pulses.
// distance_mm keeps the last accepted distance in millimetres.
module tof_uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 921_600
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        sensor_tx,
    output reg         distance_valid,
    output reg         frame_error,
    output reg [23:0]  distance_mm
);

    // A fractional NCO gives an accurate 16x UART sampling tick at 50 MHz:
    // 50 MHz / (921600 * 16) is not an integer.
    localparam integer NCO_WIDTH = 32;
    localparam [63:0] NCO_MODULUS = 64'd4294967296;
    localparam [63:0] BAUD_TICK_INC =
        ((64'd1 << NCO_WIDTH) * BAUD_RATE * 16) / CLK_FREQ_HZ;

    reg [31:0] baud_accum;
    reg        baud_tick;

    reg sensor_tx_meta;
    reg sensor_tx_sync;

    localparam [1:0] UART_IDLE  = 2'd0;
    localparam [1:0] UART_START = 2'd1;
    localparam [1:0] UART_DATA  = 2'd2;
    localparam [1:0] UART_STOP  = 2'd3;

    reg [1:0] uart_state;
    reg [3:0] oversample_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;
    reg [7:0] rx_byte;
    reg       rx_byte_valid;
    reg       uart_error;

    reg [7:0] frame_buf [0:15];
    reg [4:0] frame_index;
    reg [7:0] frame_sum;
    reg       frame_active;
    reg measurement_valid;
    reg measurement_error;
    integer   i;

    // Synchronize the sensor input and generate the fractional baud tick.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sensor_tx_meta <= 1'b1;
            sensor_tx_sync <= 1'b1;
            baud_accum     <= 32'd0;
            baud_tick      <= 1'b0;
        end else begin
            sensor_tx_meta <= sensor_tx;
            sensor_tx_sync <= sensor_tx_meta;

            baud_tick <= 1'b0;
            if (({32'd0, baud_accum} + BAUD_TICK_INC) >= NCO_MODULUS) begin
                baud_accum <= {32'd0, baud_accum} + BAUD_TICK_INC - NCO_MODULUS;
                baud_tick  <= 1'b1;
            end else begin
                baud_accum <= baud_accum + BAUD_TICK_INC;
            end
        end
    end

    // 16x oversampled, 8N1 UART receiver.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_state       <= UART_IDLE;
            oversample_count <= 4'd0;
            bit_index        <= 3'd0;
            rx_shift         <= 8'd0;
            rx_byte          <= 8'd0;
            rx_byte_valid    <= 1'b0;
            uart_error       <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;
            uart_error    <= 1'b0;

            case (uart_state)
                UART_IDLE: begin
                    oversample_count <= 4'd0;
                    if (!sensor_tx_sync) begin
                        uart_state <= UART_START;
                    end
                end

                UART_START: begin
                    if (baud_tick) begin
                        if (oversample_count == 4'd7) begin
                            oversample_count <= 4'd0;
                            if (!sensor_tx_sync) begin
                                uart_state <= UART_DATA;
                                bit_index  <= 3'd0;
                            end else begin
                                uart_state <= UART_IDLE;
                            end
                        end else begin
                            oversample_count <= oversample_count + 4'd1;
                        end
                    end
                end

                UART_DATA: begin
                    if (baud_tick) begin
                        if (oversample_count == 4'd15) begin
                            oversample_count       <= 4'd0;
                            rx_shift[bit_index]   <= sensor_tx_sync;
                            if (bit_index == 3'd7) begin
                                uart_state <= UART_STOP;
                            end else begin
                                bit_index <= bit_index + 3'd1;
                            end
                        end else begin
                            oversample_count <= oversample_count + 4'd1;
                        end
                    end
                end

                UART_STOP: begin
                    if (baud_tick) begin
                        if (oversample_count == 4'd15) begin
                            oversample_count <= 4'd0;
                            uart_state       <= UART_IDLE;
                            if (sensor_tx_sync) begin
                                rx_byte       <= rx_shift;
                                rx_byte_valid <= 1'b1;
                            end else begin
                                uart_error <= 1'b1;
                            end
                        end else begin
                            oversample_count <= oversample_count + 4'd1;
                        end
                    end
                end

                default: uart_state <= UART_IDLE;
            endcase
        end
    end

    // Parse NLink_TOFSense_Frame0. The byte layout is:
    // 57 00 reserved id time[31:0] distance[23:0] status
    // signal_strength[15:0] range_precision checksum
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_index    <= 5'd0;
            frame_sum      <= 8'd0;
            frame_active   <= 1'b0;
            measurement_valid <= 1'b0;
            distance_mm    <= 24'd0;
            measurement_error <= 1'b0;
            distance_valid <= 1'b0;
            frame_error    <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                frame_buf[i] <= 8'd0;
            end
        end else begin
            measurement_valid <= 1'b0;
            measurement_error <= uart_error;
            distance_valid    <= 1'b0;
            frame_error       <= uart_error;

            if (rx_byte_valid) begin
                if (!frame_active) begin
                    if (rx_byte == 8'h57) begin
                        frame_active    <= 1'b1;
                        frame_index     <= 5'd1;
                        frame_sum       <= 8'h57;
                        frame_buf[0]    <= 8'h57;
                    end
                end else begin
                    frame_buf[frame_index[3:0]] <= rx_byte;

                    if (frame_index < 5'd15) begin
                        frame_sum  <= frame_sum + rx_byte;
                        frame_index <= frame_index + 5'd1;
                    end else begin
                        // At index 15 rx_byte is the checksum, so frame_sum
                        // still contains the sum of bytes 0..14.
                        // Require function 0x00 and a valid checksum.  The
                        // sensor's status byte is retained in the frame but
                        // is model-dependent, so it must not reject a frame.
                        if ((frame_sum == rx_byte) &&
                            (frame_buf[1] == 8'h00)) begin
                            distance_mm    <= {frame_buf[10], frame_buf[9], frame_buf[8]};
                            measurement_valid <= 1'b1;
                            distance_valid <= 1'b1;
                        end else begin
                            measurement_error <= 1'b1;
                            frame_error <= 1'b1;
                        end
                        frame_active <= 1'b0;
                        frame_index  <= 5'd0;
                        frame_sum    <= 8'd0;
                    end
                end
            end
        end
    end

endmodule


// Four independent PI/ramp/direction contexts, one time-multiplexed datapath.

// radix-4 multiplier and add/saturate logic service A,B,C,D in order; PWM,
// encoder capture, blank timers and explicit stop remain live per wheel.
module chassis_four_wheel_shared #(
    parameter integer CLK_HZ=50000000,
    parameter integer ENCODER_CPR_A=450,ENCODER_CPR_B=450,
    parameter integer ENCODER_CPR_C=450,ENCODER_CPR_D=450,CIRCUMFERENCE_MM=204,
    parameter [3:0] ENCODER_REVERSE_MASK=4'b0000,FORWARD_LEVEL_MASK=4'b1111,
    parameter integer SAMPLE_MS=10,MAX_SPEED_MM_S=22667,
    parameter integer MAX_DUTY=300,CHANGE_BLANK_US=20,
    parameter integer KP_Q24=`FPGA_B_CHASSIS_FOUR_WHEEL_SHARED_KP_Q24_1,KI_STEP_Q24=(`FPGA_B_CHASSIS_MODEL_KI_BASE_Q24*SAMPLE_MS+5)/10,
    parameter integer FEEDFORWARD_Q24=`FPGA_B_CHASSIS_FOUR_WHEEL_SHARED_FEEDFORWARD_Q24_1,
    parameter integer REFERENCE_RATE=`FPGA_B_CHASSIS_FOUR_WHEEL_SHARED_REFERENCE_RATE_1,TARGET_LIMIT_COUNTS=1000,
    parameter integer START_PWM_CENTI=500,START_TIME_MS=80,REVERSE_SETTLE_MS=30
)(
    input wire clk,rst_n,enable,
    input wire bypass_speed_ramp,
    // Lane order: A/right rear, B/right front, C/left front, D/left rear.
    input wire [127:0] target_mm_s_bus,encoder_count_bus,
    output wire [55:0] duty_bus,
    output wire [3:0] direction,drive_enable,fault
);
    reg [1:0] lane;
    localparam integer TICKS=(CLK_HZ/1000)*SAMPLE_MS;
    localparam integer CW=TICKS>1?$clog2(TICKS):1;
    localparam integer BLANK_TICKS=(CLK_HZ*64'd1*CHANGE_BLANK_US)/1000000;
    localparam integer BW=BLANK_TICKS>0?$clog2(BLANK_TICKS+1):1;
    localparam [31:0] SCALE_A=((64'd1<<24)*ENCODER_CPR_A*10+(CIRCUMFERENCE_MM*1000)/2)/(CIRCUMFERENCE_MM*1000);
    localparam [31:0] SCALE_B=((64'd1<<24)*ENCODER_CPR_B*10+(CIRCUMFERENCE_MM*1000)/2)/(CIRCUMFERENCE_MM*1000);
    localparam [31:0] SCALE_C=((64'd1<<24)*ENCODER_CPR_C*10+(CIRCUMFERENCE_MM*1000)/2)/(CIRCUMFERENCE_MM*1000);
    localparam [31:0] SCALE_D=((64'd1<<24)*ENCODER_CPR_D*10+(CIRCUMFERENCE_MM*1000)/2)/(CIRCUMFERENCE_MM*1000);
    localparam [31:0] SCALE_AB=SCALE_A>SCALE_B?SCALE_A:SCALE_B;
    localparam [31:0] SCALE_CD=SCALE_C>SCALE_D?SCALE_C:SCALE_D;
    localparam [31:0] SCALE_MAX=SCALE_AB>SCALE_CD?SCALE_AB:SCALE_CD;
    wire [31:0] COUNTS_SCALE=lane==0?SCALE_A:(lane==1?SCALE_B:(lane==2?SCALE_C:SCALE_D));
    localparam [31:0] GAIN_MAX_A=KP_Q24>KI_STEP_Q24?KP_Q24:KI_STEP_Q24;
    localparam [31:0] GAIN_MAX_B=GAIN_MAX_A>FEEDFORWARD_Q24?GAIN_MAX_A:FEEDFORWARD_Q24;
    localparam [31:0] COEFFICIENT_MAX=GAIN_MAX_B>SCALE_MAX?GAIN_MAX_B:SCALE_MAX;
    localparam integer COEFF_W=COEFFICIENT_MAX>0?$clog2(64'd1+COEFFICIENT_MAX):1;
    localparam integer MAG_W=MAX_SPEED_MM_S>0?$clog2(64'd1+MAX_SPEED_MM_S):1;

    localparam integer INPUT_W=MAG_W>25?MAG_W:25;
    localparam integer PRODUCT_W=INPUT_W+COEFF_W+2;
    localparam integer MUL_CYCLES=(COEFF_W+1)/2;
    localparam integer MBW=MUL_CYCLES>1?$clog2(MUL_CYCLES):1;
    localparam integer LIMIT_CENTI=MAX_DUTY<0?0:(MAX_DUTY>1000?10000:MAX_DUTY*10);
    localparam signed [31:0] OUTPUT_LIMIT_Q16=(LIMIT_CENTI*65536+50)/100;
    localparam signed [31:0] START_LIMIT_Q16=
        ((START_PWM_CENTI>LIMIT_CENTI?LIMIT_CENTI:START_PWM_CENTI)*65536+50)/100;
    localparam signed [31:0] TARGET_LIMIT_Q8=TARGET_LIMIT_COUNTS*256;
    localparam signed [31:0] RAMP_STEP_Q8=(64'd256*REFERENCE_RATE*SAMPLE_MS+500)/1000;
    // Q24 time reproduces the C float boundary at the nominal 10ms period:
    // 0.08f-8*0.01f remains slightly positive, so the boost checks 9 samples.
    localparam [63:0] DT_Q24=((64'd1<<24)*SAMPLE_MS)/1000;
    localparam [63:0] START_Q24=((64'd1<<24)*START_TIME_MS)/1000;
    localparam [63:0] REVERSE_Q24=((64'd1<<24)*REVERSE_SETTLE_MS)/1000;
    localparam integer START_SAMPLES=(START_Q24+DT_Q24-1)/DT_Q24;
    localparam integer REVERSE_SAMPLES=(REVERSE_Q24+DT_Q24-1)/DT_Q24;
    localparam integer SW=START_SAMPLES>0?$clog2(START_SAMPLES+1):1;
    localparam integer RW=REVERSE_SAMPLES>0?$clog2(REVERSE_SAMPLES+1):1;
    localparam IDLE=0,MULTIPLY=1,TARGET=2,RAMP=3,P_STORE=4,I_STORE=5,FF_STORE=6,OUTPUT=7,LOAD=8,NEXT=9;
    reg [3:0] state,return_state;
    integer k;
    reg [CW-1:0] tick;
    reg [BW-1:0] blank_count [0:3];
    reg signed [31:0] previous_count [0:3];
    reg signed [31:0] measured_q8 [0:3];
    reg signed [31:0] reference_mm_s [0:3];
    reg signed [31:0] target_q8 [0:3];
    reg signed [24:0] reference_q8 [0:3];
    reg signed [31:0] integral_q16 [0:3];
    reg  positive [0:3];
    reg  direction_valid [0:3];
    reg  sample_valid [0:3];
    reg [SW-1:0] start_remaining [0:3];
    reg [RW-1:0] reverse_wait [0:3];
    reg [13:0] duty [0:3];

    reg signed [24:0] error_q8;
    reg signed [31:0] p_q16,i_candidate_q16,ff_q16,lower_q16;
    reg target_positive;
    reg [31:0] sampled_encoder [0:3],sampled_target [0:3];
    reg sampled_bypass_speed_ramp;
    wire signed [31:0] encoder_count=sampled_encoder[lane];
    wire signed [31:0] target_mm_s=sampled_target[lane];
    reg [COEFF_W-1:0] multiplier;
    reg [PRODUCT_W-1:0] product,product_shift;
    reg [MBW-1:0] bit_number;
    reg multiply_negative;
    wire [PRODUCT_W-1:0] digit3=product_shift+(product_shift<<1);
    wire [PRODUCT_W-1:0] term=multiplier[1]?(multiplier[0]?digit3:product_shift<<1):
        (multiplier[0]?product_shift:{PRODUCT_W{1'b0}});
    wire [PRODUCT_W-1:0] next_product=product+term;
    wire signed [31:0] raw_delta=encoder_count-previous_count[lane];
    wire signed [63:0] oriented_delta=ENCODER_REVERSE_MASK[lane]?-$signed({{32{raw_delta[31]}},raw_delta}):
        $signed({{32{raw_delta[31]}},raw_delta});
    wire signed [63:0] normalized_measured;
    generate if(SAMPLE_MS==10)begin:nominal_sample
        assign normalized_measured=oriented_delta<<<8;
    end else begin:other_sample
        assign normalized_measured=((oriented_delta<<<11)+(oriented_delta<<<9))/SAMPLE_MS;
    end endgenerate

    // Constant helper also used by historical arithmetic regressions.
    function signed [63:0] times_constant;
        input signed [31:0] value;
        input integer coefficient;
        reg signed [63:0] wide,positive_terms,negative_terms;
        reg [31:0] magnitude;
        integer k;
        begin
            wide=value;positive_terms=0;negative_terms=0;
            magnitude=coefficient<0?-coefficient:coefficient;
            for(k=0;k<32;k=k+1)begin
                if(magnitude[0])begin
                    if(magnitude[1])begin
                        negative_terms=negative_terms+(wide<<<k);
                        magnitude=(magnitude>>1)+1'b1;
                    end else begin
                        positive_terms=positive_terms+(wide<<<k);
                        magnitude=magnitude>>1;
                    end
                end else magnitude=magnitude>>1;
            end
            times_constant=coefficient<0?negative_terms-positive_terms:positive_terms-negative_terms;
        end
    endfunction
    function signed [31:0] gain_result;
        input [PRODUCT_W-1:0] value;
        input negative;
        reg [PRODUCT_W-1:0] rounded;
        begin
            rounded=(value+32768)>>16; // Q8*Q24 -> PWM-percent Q16
            gain_result=negative?-$signed(rounded[31:0]):$signed(rounded[31:0]);
        end
    endfunction
    genvar w;
    generate for(w=0;w<4;w=w+1)begin:outputs
        assign duty_bus[14*w+:14]=duty[w];
        assign direction[w]=positive[w]?FORWARD_LEVEL_MASK[w]:!FORWARD_LEVEL_MASK[w];
        assign drive_enable[w]=enable && blank_count[w]==0;
    end endgenerate
    assign fault=4'b0000;
    always @(posedge clk or negedge rst_n)begin:control
        reg signed [31:0] requested,q8_target,feedback,error,ref_mag,new_reference;
        reg signed [31:0] candidate,base,output_value,chosen_integral;
        reg [31:0] magnitude,absolute_speed;
        reg [SW-1:0] remaining;
        reg [RW:0] wait_next;
        reg dir_known,dir_positive,brake;
        if(!rst_n)begin
            state<=IDLE;return_state<=IDLE;tick<=0;lane<=0;
            sampled_bypass_speed_ramp<=0;
            for(k=0;k<4;k=k+1)begin
            sampled_encoder[k]<=0;sampled_target[k]<=0;blank_count[k]<=0;previous_count[k]<=0;
            measured_q8[k]<=0;reference_mm_s[k]<=0;target_q8[k]<=0;reference_q8[k]<=0;error_q8<=0;
            integral_q16[k]<=0;p_q16<=0;i_candidate_q16<=0;ff_q16<=0;lower_q16<=0;
            positive[k]<=1;direction_valid[k]<=0;sample_valid[k]<=0;target_positive<=1;duty[k]<=0;
            start_remaining[k]<=0;reverse_wait[k]<=0;multiplier<=0;product<=0;product_shift<=0;
            bit_number<=0;multiply_negative<=0;
            end
        end else begin
            for(k=0;k<4;k=k+1)sample_valid[k]<=0;
            if(!enable)begin
                lane<=0;
                sampled_bypass_speed_ramp<=0;
                for(k=0;k<4;k=k+1)begin
                state<=IDLE;tick<=0;blank_count[k]<=0;previous_count[k]<=encoder_count_bus[32*k+:32];
                measured_q8[k]<=0;reference_mm_s[k]<=0;target_q8[k]<=0;reference_q8[k]<=0;error_q8<=0;
                integral_q16[k]<=0;duty[k]<=0;direction_valid[k]<=0;start_remaining[k]<=0;reverse_wait[k]<=0;
                end
            end else begin
                tick<=tick==TICKS-1?0:tick+1'b1;
                for(k=0;k<4;k=k+1)
                    if(blank_count[k]!=0)blank_count[k]<=blank_count[k]-1'b1;
                case(state)
                    IDLE:if(tick==TICKS-1)begin
                        // Freeze policy with the four-wheel input snapshot;
                        // a mid-job mode switch cannot mix ramped/direct lanes.
                        sampled_bypass_speed_ramp<=bypass_speed_ramp===1'b1;
                        for(k=0;k<4;k=k+1)begin
                            sampled_encoder[k]<=encoder_count_bus[32*k+:32];
                            sampled_target[k]<=target_mm_s_bus[32*k+:32];
                        end
                        lane<=0;state<=LOAD;
                    end
                    LOAD:begin
                        previous_count[lane]<=encoder_count;
                        // Saturation is arithmetic representation only; never
                        // latch a fault, reset a sample, or disable the bridge.
                        if(normalized_measured>64'sd8388608)measured_q8[lane]<=32'sd8388608;
                        else if(normalized_measured<-64'sd8388608)measured_q8[lane]<=-32'sd8388608;
                        else measured_q8[lane]<=normalized_measured[31:0];
                        requested=target_mm_s;
                        if(requested>MAX_SPEED_MM_S)requested=MAX_SPEED_MM_S;
                        if(requested<-MAX_SPEED_MM_S)requested=-MAX_SPEED_MM_S;
                        reference_mm_s[lane]<=requested;target_positive<=requested>=0;
                        magnitude=requested<0?-requested:requested;
                        product_shift<=magnitude;multiplier<=COUNTS_SCALE;product<=0;
                        multiply_negative<=requested<0;bit_number<=0;
                        return_state<=TARGET;state<=MULTIPLY;
                    end
                    MULTIPLY:begin
                        product<=next_product;product_shift<=product_shift<<2;multiplier<=multiplier>>2;
                        if(bit_number==MUL_CYCLES-1)state<=return_state;
                        else bit_number<=bit_number+1'b1;
                    end
                    TARGET:begin
                        q8_target=gain_result(product,multiply_negative);
                        if(q8_target>TARGET_LIMIT_Q8)q8_target=TARGET_LIMIT_Q8;
                        if(q8_target<-TARGET_LIMIT_Q8)q8_target=-TARGET_LIMIT_Q8;
                        target_q8[lane]<=q8_target;state<=RAMP;
                    end
                    RAMP:begin
                        if(target_q8[lane]==0)begin
                            reference_q8[lane]<=0;integral_q16[lane]<=0;duty[lane]<=0;
                            direction_valid[lane]<=0;start_remaining[lane]<=0;reverse_wait[lane]<=0;
                            sample_valid[lane]<=1;state<=NEXT;
                        end else begin
                            dir_known=direction_valid[lane];dir_positive=positive[lane];brake=0;
                            remaining=start_remaining[lane];
                            absolute_speed=measured_q8[lane]<0?-measured_q8[lane]:measured_q8[lane];
                            feedback=target_positive?measured_q8[lane]:-measured_q8[lane];
                            if(!dir_known && feedback< -32'sd1280)begin
                                dir_known=1;dir_positive=!target_positive;
                            end
                            if(dir_known && dir_positive!=target_positive)begin
                                reference_q8[lane]<=0;integral_q16[lane]<=0;duty[lane]<=0;
                                wait_next=absolute_speed<=1280?reverse_wait[lane]+1'b1:0;
                                reverse_wait[lane]<=wait_next[RW-1:0];
                                if(wait_next<REVERSE_SAMPLES)brake=1;
                                else dir_known=0;
                            end
                            if(brake)begin
                                direction_valid[lane]<=1;positive[lane]<=dir_positive;
                                sample_valid[lane]<=1;state<=NEXT;
                            end else begin
                                if(!dir_known)begin
                                    dir_positive=target_positive;direction_valid[lane]<=1;
                                    positive[lane]<=target_positive;reverse_wait[lane]<=0;
                                    remaining=START_SAMPLES;integral_q16[lane]<=0;ref_mag=0;
                                    if(positive[lane]!=target_positive)blank_count[lane]<=BLANK_TICKS;
                                end else ref_mag=reference_q8[lane]<0?-reference_q8[lane]:reference_q8[lane];
                                requested=target_q8[lane]<0?-target_q8[lane]:target_q8[lane];
                                if(sampled_bypass_speed_ramp)new_reference=requested;
                                else if(requested-ref_mag>RAMP_STEP_Q8)new_reference=ref_mag+RAMP_STEP_Q8;
                                else if(requested-ref_mag<-RAMP_STEP_Q8)new_reference=ref_mag-RAMP_STEP_Q8;
                                else new_reference=requested;
                                reference_q8[lane]<=dir_positive?new_reference:-new_reference;
                                error=new_reference-feedback;error_q8<=error;
                                lower_q16<=remaining!=0 && feedback<new_reference?START_LIMIT_Q16:0;
                                start_remaining[lane]<=remaining!=0?remaining-1'b1:0;
                                product_shift<=error<0?-error:error;multiplier<=KP_Q24;product<=0;
                                multiply_negative<=error<0;bit_number<=0;
                                return_state<=P_STORE;state<=MULTIPLY;
                            end
                        end
                    end
                    P_STORE:begin
                        p_q16<=gain_result(product,multiply_negative);
                        product_shift<=error_q8<0?-$signed(error_q8):$signed(error_q8);
                        multiplier<=KI_STEP_Q24;product<=0;bit_number<=0;
                        multiply_negative<=error_q8<0;return_state<=I_STORE;state<=MULTIPLY;
                    end
                    I_STORE:begin
                        candidate=integral_q16[lane]+gain_result(product,multiply_negative);
                        if(candidate>OUTPUT_LIMIT_Q16)candidate=OUTPUT_LIMIT_Q16;
                        if(candidate<-OUTPUT_LIMIT_Q16)candidate=-OUTPUT_LIMIT_Q16;
                        i_candidate_q16<=candidate;
                        product_shift<=reference_q8[lane]<0?-$signed(reference_q8[lane]):$signed(reference_q8[lane]);
                        multiplier<=FEEDFORWARD_Q24;product<=0;bit_number<=0;
                        multiply_negative<=0;return_state<=FF_STORE;state<=MULTIPLY;
                    end
                    FF_STORE:begin ff_q16<=gain_result(product,1'b0);state<=OUTPUT;end
                    OUTPUT:begin
                        base=ff_q16+p_q16;candidate=base+i_candidate_q16;
                        chosen_integral=integral_q16[lane];
                        if(!((candidate>OUTPUT_LIMIT_Q16 && error_q8>0) ||
                             (candidate<lower_q16 && error_q8<0)))chosen_integral=i_candidate_q16;
                        integral_q16[lane]<=chosen_integral;
                        output_value=base+chosen_integral;
                        if(output_value>OUTPUT_LIMIT_Q16)output_value=OUTPUT_LIMIT_Q16;
                        if(output_value<lower_q16)output_value=lower_q16;
                        duty[lane]<=(times_constant(output_value,100)+32768)>>>16;
                        sample_valid[lane]<=1;state<=NEXT;
                    end
                    NEXT:if(lane==3)state<=IDLE;
                         else begin lane<=lane+1'b1;state<=LOAD;end
                    default:state<=IDLE;
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk)if(rst_n && enable && tick==TICKS-1 && state!=IDLE)
        $fatal(1,"Shared wheel engine missed the next sample");
    initial if(SAMPLE_MS<1 || SAMPLE_MS>50 || TICKS<=4*(4*MUL_CYCLES+10) || TARGET_LIMIT_COUNTS>32767 ||
        MAX_SPEED_MM_S<1 || MAX_DUTY<0 || MAX_DUTY>1000 || KP_Q24<0 || KI_STEP_Q24<0 ||
        FEEDFORWARD_Q24<0 || START_PWM_CENTI<0 || START_TIME_MS<0 || REVERSE_SETTLE_MS<0)
        $fatal(1,"Invalid shared model wheel parameters");
`endif
endmodule

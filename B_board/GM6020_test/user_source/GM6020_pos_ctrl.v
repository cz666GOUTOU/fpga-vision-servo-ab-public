`include "fpga_b_example_config.vh"
// 1 kHz GM6020 position--acceleration cascade controller.

//
// The calculation is deliberately spread across four 50 MHz clocks after
// each feedback frame.  This is only 80 ns of the 1 ms sample interval and
// avoids a slow multiplier chain in the FPGA timing path.
module GM6020_pos_ctrl #(
    parameter integer CLK_HZ = 50000000,
    parameter integer COMMAND_REVERSE = 1,
    parameter integer CLOCKWISE_COUNT_INCREASE = 1,
    parameter integer FEEDBACK_TIMEOUT_MS = 10
)(
    input wire clk, input wire rst_n, input wire enable,
    input wire feedback_valid,
    input wire [12:0] angle,
    input wire signed [15:0] speed_rpm,

    input wire [12:0] target_angle_register,
    output reg signed [15:0] command,
    output reg active,
    output reg signed [31:0] position_counts,
    output reg signed [31:0] target_counts,
    output reg signed [15:0] acceleration_rpm_s,
    output reg signed [15:0] position_error_counts
);
    localparam integer FEEDBACK_TIMEOUT_CYCLES =
        (CLK_HZ / 1000) * FEEDBACK_TIMEOUT_MS;
    localparam [2:0] IDLE = 3'd0, OUTER = 3'd1, INNER_EST = 3'd2,
                     INNER_FF = 3'd3, INNER_OUT = 3'd4;



    localparam signed [31:0] POS_I_LIMIT_Q14 = `FPGA_B_GM6020_POS_CTRL_POS_I_LIMIT_Q14_1;
    localparam signed [31:0] ACC_I_LIMIT_Q10 = `FPGA_B_GM6020_POS_CTRL_ACC_I_LIMIT_Q10_1;
    localparam signed [31:0] A_REF_LIMIT = `FPGA_B_GM6020_POS_CTRL_A_REF_LIMIT_1;         // rpm/s
    localparam signed [31:0] COMMAND_LIMIT = `FPGA_B_GM6020_POS_CTRL_COMMAND_LIMIT_1;

    reg [12:0] applied_target_angle, last_angle;
    reg signed [15:0] last_speed_rpm;
    reg angle_valid;
    localparam integer AGE_W=FEEDBACK_TIMEOUT_CYCLES>0?$clog2(FEEDBACK_TIMEOUT_CYCLES+1):1;
    reg [AGE_W-1:0] feedback_age;
    reg [2:0] control_state;

    reg signed [24:0] position_integral_q14; // +/-16384000
    reg signed [23:0] acceleration_integral_q10; // +/-5120000
    reg signed [17:0] acceleration_filtered; // LPF of +/-100000
    reg signed [17:0] acceleration_error_previous; // abs <= 102502 (LPF rounding)
    reg signed [28:0] acceleration_derivative_filtered; // abs < 205005000, including LPF rounding
    reg signed [31:0] work_position_error;
    reg signed [15:0] work_speed;
    reg signed [7:0] work_speed_delta; // clipped to +/-100
    reg signed [12:0] work_a_ref; // +/-2500
    reg signed [17:0] work_acceleration_error;
    reg signed [28:0] work_acceleration_derivative;
    reg signed [22:0] work_feedforward; // abs < 2.81 million
    reg signed [17:0] work_inner_pd; // abs < 74000

    wire [12:0] target_angle = target_angle_register;

    function signed [31:0] clamp32;
        input signed [31:0] value;
        input signed [31:0] lower;
        input signed [31:0] upper;
        begin
            if (value > upper) clamp32 = upper;
            else if (value < lower) clamp32 = lower;
            else clamp32 = value;
        end
    endfunction

    function signed [31:0] wrapped_delta;
        input [12:0] target;
        input [12:0] actual;
        reg signed [31:0] d;
        begin
            d = $signed({1'b0, target}) - $signed({1'b0, actual});
            if (d == 32'sd4096)
                d = CLOCKWISE_COUNT_INCREASE ? 32'sd4096 : -32'sd4096;
            else if (d > 32'sd4096) d = d - 32'sd8192;
            else if (d < -32'sd4096) d = d + 32'sd8192;
            wrapped_delta = d;
        end
    endfunction

    // Shift/add implementation of the 1 kHz cascade:
    //   a_ref = 1.20*e_pos + I_pos + 0.16*de_pos/dt
    //   u = (0.03*a_ref + speed)/0.0117 + .50*e_acc + I_acc
    //       + .00010*de_acc/dt
    always @(posedge clk or negedge rst_n) begin : control_sequential
        reg signed [31:0] t_position, t_target_delta, t_position_error_rate;
        reg signed [31:0] t_position_p, t_position_d;
        reg signed [31:0] t_position_i_candidate, t_position_i_next;
        reg signed [31:0] t_a_ref_candidate;
        reg signed [31:0] t_acceleration_raw, t_acceleration_filtered;
        reg signed [31:0] t_acceleration_derivative_raw;
        reg signed [31:0] t_acceleration_derivative_filtered;
        reg signed [31:0] t_acceleration_i_candidate, t_acceleration_i_next;
        reg signed [31:0] t_command_candidate, t_command_next;
        if (!rst_n) begin
            command <= 16'sd0;
            active <= 1'b0;
            position_counts <= 32'sd0;
            target_counts <= 32'sd0;
            acceleration_rpm_s <= 16'sd0;
            position_error_counts <= 16'sd0;
            // A flip-flop asynchronous reset must use a constant. The first
            // valid feedback synchronously captures the requested target.
            applied_target_angle <= 13'd0;
            last_angle <= 13'd0;
            last_speed_rpm <= 16'sd0;
            angle_valid <= 1'b0;
            feedback_age <= 32'd0;
            control_state <= IDLE;
            position_integral_q14 <= 32'sd0;
            acceleration_integral_q10 <= 32'sd0;
            acceleration_filtered <= 32'sd0;
            acceleration_error_previous <= 32'sd0;
            acceleration_derivative_filtered <= 32'sd0;
            work_position_error <= 32'sd0;
            work_speed <= 32'sd0;
            work_speed_delta <= 32'sd0;
            work_a_ref <= 32'sd0;
            work_acceleration_error <= 32'sd0;
            work_acceleration_derivative <= 32'sd0;
            work_feedforward <= 32'sd0;
            work_inner_pd <= 32'sd0;
        end else if (!enable) begin
            command <= 16'sd0;
            active <= 1'b0;
            position_counts <= 32'sd0;
            target_counts <= 32'sd0;
            acceleration_rpm_s <= 16'sd0;
            position_error_counts <= 16'sd0;
            applied_target_angle <= target_angle;
            last_angle <= 13'd0;
            last_speed_rpm <= 16'sd0;
            angle_valid <= 1'b0;
            feedback_age <= 32'd0;
            control_state <= IDLE;
            position_integral_q14 <= 32'sd0;
            acceleration_integral_q10 <= 32'sd0;
            acceleration_filtered <= 32'sd0;
            acceleration_error_previous <= 32'sd0;
            acceleration_derivative_filtered <= 32'sd0;
        end else if (!feedback_valid &&
                     feedback_age >= FEEDBACK_TIMEOUT_CYCLES - 1) begin
            // Fail safe after 10 ms without a feedback frame.
            command <= 16'sd0;
            active <= 1'b0;
            position_counts <= 32'sd0;
            target_counts <= 32'sd0;
            acceleration_rpm_s <= 16'sd0;
            position_error_counts <= 16'sd0;
            angle_valid <= 1'b0;
            control_state <= IDLE;
            position_integral_q14 <= 32'sd0;
            acceleration_integral_q10 <= 32'sd0;
            acceleration_filtered <= 32'sd0;
            acceleration_error_previous <= 32'sd0;
            acceleration_derivative_filtered <= 32'sd0;
        end else begin
            if (feedback_valid) feedback_age <= 32'd0;
            else feedback_age <= feedback_age + 1'b1;

            case (control_state)
                IDLE: if (feedback_valid) begin
                    last_angle <= angle;
                    last_speed_rpm <= speed_rpm;
                    if (!angle_valid) begin
                        t_target_delta = wrapped_delta(target_angle, angle);
                        position_counts <= 32'sd0;
                        target_counts <= t_target_delta;
                        applied_target_angle <= target_angle;
                        angle_valid <= 1'b1;
                        command <= 16'sd0;
                        active <= 1'b1;
                        position_integral_q14 <= 32'sd0;
                        acceleration_integral_q10 <= 32'sd0;
                        acceleration_filtered <= 32'sd0;
                        acceleration_error_previous <= 32'sd0;
                        acceleration_derivative_filtered <= 32'sd0;
                    end else if (target_angle != applied_target_angle) begin
                        t_position = position_counts + wrapped_delta(angle, last_angle);
                        t_target_delta = wrapped_delta(target_angle, angle);
                        position_counts <= t_position;
                        target_counts <= t_position + t_target_delta;
                        applied_target_angle <= target_angle;
                        // A streaming position reference must not interrupt
                        // torque or reset the acceleration estimator each frame.
                        // Keep I/filter history and compute the new target in
                        // this feedback sample, just like a normal PID update.
                        work_position_error <= t_target_delta;
                        work_speed <= speed_rpm;
                        work_speed_delta <= clamp32($signed(speed_rpm) -
                            $signed(last_speed_rpm), -32'sd100, 32'sd100);
                        control_state <= OUTER;
                    end else begin
                        t_position = position_counts + wrapped_delta(angle, last_angle);
                        position_counts <= t_position;
                        work_position_error <= target_counts - t_position;
                        work_speed <= speed_rpm;
                        // A physically implausible feedback jump is bounded
                        // before the discrete differentiator.
                        work_speed_delta <= clamp32($signed(speed_rpm) -
                            $signed(last_speed_rpm), -32'sd100, 32'sd100);
                        control_state <= OUTER;
                    end
                end

                OUTER: begin
                    // 1.203125*e: 1 + 1/8 + 1/16 + 1/64.
                    t_position_p = work_position_error +
                        (work_position_error >>> 3) +
                        (work_position_error >>> 4) +
                        (work_position_error >>> 6);
                    // -speed*137, then 0.15625*de/dt for the D term.
                    t_position_error_rate = -((work_speed <<< 7) +
                        (work_speed <<< 3) + work_speed);
                    t_position_d = (t_position_error_rate >>> 3) +
                        (t_position_error_rate >>> 5);
                    t_position_i_candidate = clamp32(position_integral_q14 +
                        work_position_error + (work_position_error >>> 2) +
                        (work_position_error >>> 4),
                        -POS_I_LIMIT_Q14, POS_I_LIMIT_Q14);
                    t_a_ref_candidate = clamp32(t_position_p + t_position_d +
                        (t_position_i_candidate >>> 14),
                        -A_REF_LIMIT, A_REF_LIMIT);
                    if ((t_a_ref_candidate < A_REF_LIMIT &&
                         t_a_ref_candidate > -A_REF_LIMIT) ||
                        (t_a_ref_candidate >= A_REF_LIMIT &&
                         work_position_error < 0) ||
                        (t_a_ref_candidate <= -A_REF_LIMIT &&
                         work_position_error > 0))
                        t_position_i_next = t_position_i_candidate;
                    else
                        t_position_i_next = position_integral_q14;
                    position_integral_q14 <= t_position_i_next;
                    work_a_ref <= clamp32(t_position_p + t_position_d +
                        (t_position_i_next >>> 14),
                        -A_REF_LIMIT, A_REF_LIMIT);
                    if (work_position_error > 32'sd32767)
                        position_error_counts <= 16'sd32767;
                    else if (work_position_error < -32'sd32768)
                        position_error_counts <= -16'sd32768;
                    else
                        position_error_counts <= work_position_error[15:0];
                    control_state <= INNER_EST;
                end

                INNER_EST: begin

                    // alpha is 1/16+1/64+1/256 = 0.08203125.
                    t_acceleration_raw = (work_speed_delta <<< 10) -
                        (work_speed_delta <<< 4) - (work_speed_delta <<< 3);
                    // abs(work_speed_delta)<=100 => abs(raw)<=100000.
                    // No second full-width acceleration limiter is needed.
                    t_acceleration_filtered = acceleration_filtered +
                        ((t_acceleration_raw - acceleration_filtered) >>> 4) +
                        ((t_acceleration_raw - acceleration_filtered) >>> 6) +
                        ((t_acceleration_raw - acceleration_filtered) >>> 8);
                    work_acceleration_error <= work_a_ref - t_acceleration_filtered;
                    t_acceleration_derivative_raw =
                        ((work_a_ref - t_acceleration_filtered -
                          acceleration_error_previous) <<< 10) -
                        ((work_a_ref - t_acceleration_filtered -
                          acceleration_error_previous) <<< 4) -
                        ((work_a_ref - t_acceleration_filtered -
                          acceleration_error_previous) <<< 3);
                    // Derivative LPF alpha = 1/8-1/32+1/128 = 0.1015625.
                    t_acceleration_derivative_filtered =
                        acceleration_derivative_filtered +
                        ((t_acceleration_derivative_raw -
                          acceleration_derivative_filtered) >>> 3) -
                        ((t_acceleration_derivative_raw -
                          acceleration_derivative_filtered) >>> 5) +
                        ((t_acceleration_derivative_raw -
                          acceleration_derivative_filtered) >>> 7);
                    acceleration_filtered <= t_acceleration_filtered;
                    acceleration_error_previous <= work_a_ref - t_acceleration_filtered;
                    acceleration_derivative_filtered <=
                        t_acceleration_derivative_filtered;
                    work_acceleration_derivative <=
                        t_acceleration_derivative_filtered;
                    if (t_acceleration_filtered > 32'sd32767)
                        acceleration_rpm_s <= 16'sd32767;
                    else if (t_acceleration_filtered < -32'sd32768)
                        acceleration_rpm_s <= -16'sd32768;
                    else
                        acceleration_rpm_s <= t_acceleration_filtered[15:0];
                    control_state <= INNER_FF;
                end

                INNER_FF: begin
                    // 2.5625*a_ref + 85.5*speed is the plant inverse.
                    work_feedforward <= (work_a_ref <<< 1) +
                        (work_a_ref >>> 1) + (work_a_ref >>> 4) +
                        (work_speed <<< 6) + (work_speed <<< 4) +
                        (work_speed <<< 2) + work_speed + (work_speed >>> 1);
                    // .5*e_acc + .0001068*de_acc/dt.
                    work_inner_pd <= (work_acceleration_error >>> 1) +
                        (work_acceleration_derivative >>> 13) -
                        (work_acceleration_derivative >>> 16);
                    control_state <= INNER_OUT;
                end

                INNER_OUT: begin
                    t_acceleration_i_candidate = clamp32(acceleration_integral_q10 +
                        (work_acceleration_error <<< 4) +
                        (work_acceleration_error <<< 3) +
                        (work_acceleration_error <<< 1),
                        -ACC_I_LIMIT_Q10, ACC_I_LIMIT_Q10);
                    t_command_candidate = work_feedforward + work_inner_pd +
                        (t_acceleration_i_candidate >>> 10);
                    if ((t_command_candidate < COMMAND_LIMIT &&
                         t_command_candidate > -COMMAND_LIMIT) ||
                        (t_command_candidate >= COMMAND_LIMIT &&
                         work_acceleration_error < 0) ||
                        (t_command_candidate <= -COMMAND_LIMIT &&
                         work_acceleration_error > 0))
                        t_acceleration_i_next = t_acceleration_i_candidate;
                    else
                        t_acceleration_i_next = acceleration_integral_q10;
                    t_command_next = clamp32(work_feedforward + work_inner_pd +
                        (t_acceleration_i_next >>> 10),
                        -COMMAND_LIMIT, COMMAND_LIMIT);
                    acceleration_integral_q10 <= t_acceleration_i_next;
                    command <= COMMAND_REVERSE ? -$signed(t_command_next[15:0]) :
                        $signed(t_command_next[15:0]);
                    active <= 1'b1;
                    control_state <= IDLE;
                end

                default: control_state <= IDLE;
            endcase
        end
    end
endmodule

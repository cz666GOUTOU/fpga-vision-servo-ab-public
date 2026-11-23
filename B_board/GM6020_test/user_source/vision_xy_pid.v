// Two independent camera-coordinate PIDs. All ports use the 50 MHz app clock.
// Actuator assignment, direction, setpoints and gain units are selected by top.
module vision_xy_pid #(
    parameter integer X_KP_Q8=32, X_KI_Q8=0, X_KD_Q8=4,
    parameter integer Y_KP_Q8=32, Y_KI_Q8=0, Y_KD_Q8=4,
    parameter integer ERROR_REVERSE=0,
    parameter integer FRAME_WIDTH=1280, FRAME_HEIGHT=720,
    parameter integer OUTPUT_LIMIT=23, INTEGRAL_LIMIT=4,
    parameter integer DEADBAND_PIXELS=3
)(
    input wire clk, rst_n,
    input wire result_update, target_valid, comm_timeout,
    input wire clear_history,
    input wire enable_x, enable_y,
    input wire [15:0] center_x, center_y,
    input wire [15:0] setpoint_x, setpoint_y,
    output wire output_valid,
    output wire output_valid_x, output_valid_y,
    output wire tracking_valid,
    output wire signed [15:0] control_x, control_y,
    output wire signed [16:0] error_x, error_y
);
    wire valid_x,valid_y;
    // Either zero coordinate is the camera's no-target sentinel. Both axes
    // must stop together for a sentinel, invalid flag, timeout or bad range.
    wire tracking = target_valid && !comm_timeout &&
        (center_x != 16'd0) && (center_y != 16'd0) &&
        (center_x < FRAME_WIDTH) && (center_y < FRAME_HEIGHT);
    assign tracking_valid=tracking;
    vision_axis_pid #(.KP_Q8(X_KP_Q8),.KI_Q8(X_KI_Q8),.KD_Q8(X_KD_Q8),
        .ERROR_REVERSE(ERROR_REVERSE),
        .OUTPUT_LIMIT(OUTPUT_LIMIT),.INTEGRAL_LIMIT(INTEGRAL_LIMIT),
        .DEADBAND_PIXELS(DEADBAND_PIXELS)) x_pid (
        .clk(clk),.rst_n(rst_n),.enable(tracking && enable_x),
        .sample_valid(result_update),.clear_history(clear_history),
        .setpoint(setpoint_x),.measurement(center_x),
        .output_valid(valid_x),.control(control_x),.error_pixels(error_x));
    vision_axis_pid #(.KP_Q8(Y_KP_Q8),.KI_Q8(Y_KI_Q8),.KD_Q8(Y_KD_Q8),
        .ERROR_REVERSE(ERROR_REVERSE),
        .OUTPUT_LIMIT(OUTPUT_LIMIT),.INTEGRAL_LIMIT(INTEGRAL_LIMIT),
        .DEADBAND_PIXELS(DEADBAND_PIXELS)) y_pid (
        .clk(clk),.rst_n(rst_n),.enable(tracking && enable_y),
        .sample_valid(result_update),.clear_history(clear_history),
        .setpoint(setpoint_y),.measurement(center_y),
        .output_valid(valid_y),.control(control_y),.error_pixels(error_y));
    assign output_valid=valid_x && valid_y;
    assign output_valid_x=valid_x;
    assign output_valid_y=valid_y;
endmodule

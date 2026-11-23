// Camera-coordinate PID. One update per accepted UDP camera sample.
// KP/KI/KD use Q8 fixed point. KI and KD include the camera sample period:
// Positional PID, like the motor position outer loop: P/I on position error,
// D on measured motion (not target changes), with a 1/4 low-pass filter.
// e is setpoint-measurement by default, measurement-setpoint if ERROR_REVERSE=1.
// Output units are determined by the gains and the downstream actuator mapping.
module vision_axis_pid #(
    parameter integer KP_Q8 = 32,
    parameter integer KI_Q8 = 0,
    parameter integer KD_Q8 = 4,
    parameter integer ERROR_REVERSE = 0, // 1: measurement - setpoint
    parameter integer OUTPUT_LIMIT = 23,
    parameter integer INTEGRAL_LIMIT = 4,
    parameter integer DEADBAND_PIXELS = 3
)(
    input wire clk, rst_n,
    input wire enable,
    input wire sample_valid,
    input wire clear_history,
    input wire [15:0] setpoint, measurement,
    output reg output_valid,
    output reg signed [15:0] control,
    output reg signed [16:0] error_pixels
);
    localparam [2:0] IDLE=0, TERMS=1, SUM=2, COMMIT=3;
    localparam signed [63:0] OUT_LIMIT_Q8 = OUTPUT_LIMIT * 64'sd256;
    localparam signed [63:0] I_LIMIT_Q8 = INTEGRAL_LIMIT * 64'sd256;
    reg [2:0] state;
    reg history_valid;
    reg signed [63:0] error_sample, measurement_sample, previous_measurement;
    reg signed [63:0] derivative_filtered_q8;
    reg signed [63:0] integral_q8, candidate_i, p_term, d_term, candidate_sum;
    reg signed [63:0] next_i, next_sum;
    reg signed [63:0] derivative_raw_q8, derivative_next_q8, filter_delta;
    function signed [63:0] coordinate_error;
        input [15:0] target, value;
        reg signed [63:0] e;
        begin
            e = ERROR_REVERSE ?
                $signed({1'b0,value}) - $signed({1'b0,target}) :
                $signed({1'b0,target}) - $signed({1'b0,value});
            coordinate_error = (e >= -DEADBAND_PIXELS && e <= DEADBAND_PIXELS) ? 64'sd0 : e;
        end
    endfunction
    function signed [63:0] bound_i;
        input signed [63:0] value;
        begin
            if(value>I_LIMIT_Q8) bound_i=I_LIMIT_Q8;
            else if(value< -I_LIMIT_Q8) bound_i= -I_LIMIT_Q8;
            else bound_i=value;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; history_valid<=0;
            error_sample<=0; measurement_sample<=0; previous_measurement<=0; integral_q8<=0;
            derivative_filtered_q8<=0;
            candidate_i<=0; p_term<=0; d_term<=0; candidate_sum<=0;
            output_valid<=0; control<=0; error_pixels<=0;
        end else if(!enable || clear_history) begin
            state<=IDLE; history_valid<=0;
            previous_measurement<=0; integral_q8<=0; derivative_filtered_q8<=0;
            output_valid<=0; control<=0; error_pixels<=0;
            // Process the first frame of a new target with clean I/D history.
            if(enable && clear_history && sample_valid) begin
                error_sample <= coordinate_error(setpoint,measurement);
                measurement_sample <= $signed({1'b0,measurement});
                state<=TERMS;
            end
        end else begin
            output_valid<=0;
            case(state)
                IDLE: if(sample_valid) begin
                    // Unsigned coordinates must be widened BEFORE subtraction.
                    error_sample <= coordinate_error(setpoint,measurement);
                    measurement_sample <= $signed({1'b0,measurement});
                    state<=TERMS;
                end
                TERMS: begin
                    p_term<=KP_Q8*error_sample;
                    candidate_i <= (error_sample==0) ? 64'sd0 :
                        bound_i(integral_q8+KI_Q8*error_sample);
                    derivative_raw_q8 = ERROR_REVERSE ?
                        ((measurement_sample-previous_measurement)<<<8) :
                        ((previous_measurement-measurement_sample)<<<8);
                    filter_delta = derivative_raw_q8-derivative_filtered_q8;
                    // Symmetric truncation avoids a negative rounding bias.
                    derivative_next_q8 = history_valid ? derivative_filtered_q8 +
                        ((filter_delta<0) ? -((-filter_delta)>>>2) : (filter_delta>>>2)) : 64'sd0;
                    derivative_filtered_q8 <= (error_sample==0) ? 64'sd0 : derivative_next_q8;
                    d_term <= (error_sample==0) ? 64'sd0 :
                        ((KD_Q8*derivative_next_q8)>>>8);
                    state<=SUM;
                end
                SUM: begin
                    candidate_sum<=p_term+candidate_i+d_term;
                    state<=COMMIT;
                end
                COMMIT: begin
                    // Conditional integration permits unwinding saturation.
                    if((candidate_sum>OUT_LIMIT_Q8 && error_sample>0) ||
                       (candidate_sum< -OUT_LIMIT_Q8 && error_sample<0))
                        next_i=integral_q8;
                    else next_i=candidate_i;
                    next_sum=p_term+next_i+d_term;
                    if(next_sum>OUT_LIMIT_Q8) control<=OUTPUT_LIMIT;
                    else if(next_sum< -OUT_LIMIT_Q8) control<= -OUTPUT_LIMIT;
                    // Divide toward zero to avoid a persistent -1 bias.
                    else if(next_sum<0) control<= -((-next_sum)>>>8);
                    else control<=next_sum>>>8;
                    integral_q8<=next_i;
                    previous_measurement<=measurement_sample; history_valid<=1;
                    error_pixels<=error_sample[16:0];
                    output_valid<=1; state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    initial begin
        if(KP_Q8<0 || KI_Q8<0 || KD_Q8<0 ||
           OUTPUT_LIMIT<1 || OUTPUT_LIMIT>32767 || INTEGRAL_LIMIT<0 || DEADBAND_PIXELS<0)
            $fatal(1,"vision_axis_pid: invalid parameters");
    end
    // synthesis translate_on
endmodule

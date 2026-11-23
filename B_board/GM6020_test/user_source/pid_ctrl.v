module pid_ctrl #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer INTEGRAL_HZ = 100,
    parameter integer MAX_OUT = 1000,
    parameter integer MIN_OUT = -1000,
    parameter integer INTEGRAL_LIMIT = 1000,
    // Conservative gains for measured G(s)=0.145/(0.067*s+1), 100 Hz updates.
    parameter integer KP = 6,
    parameter integer KI = 1,
    parameter integer KD = 1,
    // Feed-forward term. The controller adds KF * target to the PID result.
    // Its unit is output-unit per target-unit; set to zero to disable it.
    parameter integer KF = 0,
    parameter integer EXTERNAL_SAMPLE = 0
)(
    input wire clk,
    input wire rst_n,
    input wire signed [15:0] target,
    input wire signed [15:0] value,
    output reg signed [15:0] out,
    input wire sample_valid // Used only when EXTERNAL_SAMPLE=1; same clk domain.
);
    // Gains are integers. KI and KD must include the chosen sampling period.
    // target/value must use the same units and be synchronous to clk.
    localparam integer STATE_COUNT = 8;
    localparam integer STATE_BIT = $clog2(STATE_COUNT);
    localparam integer INTEGRAL_COUNT = CLK_HZ / INTEGRAL_HZ;
    localparam integer INTEGRAL_BIT = (INTEGRAL_COUNT > 1) ? $clog2(INTEGRAL_COUNT) : 1;
    localparam [STATE_BIT-1:0]
        WAIT_COUNT = 0, GET_ERROR = 1, GET_K = 2, GET_I = 3,
        GET_D = 4, GET_SUM = 5, CHECK_I = 6, GET_OUT = 7;
    localparam signed [63:0] I_LIMIT = INTEGRAL_LIMIT;
    localparam signed [63:0] OUT_MAX = MAX_OUT;
    localparam signed [63:0] OUT_MIN = MIN_OUT;

    reg [INTEGRAL_BIT-1:0] integral_count;
    reg [STATE_BIT-1:0] state;
    // Sign-extend inputs before subtraction; wide intermediates prevent wrap.
    reg signed [63:0] target_sample, value_sample;
    reg signed [63:0] last_error, error_value;
    reg signed [63:0] K, I, D, F;
    reg signed [63:0] integral_raw, integral_candidate;
    reg signed [63:0] candidate_sum, output_sum;
    wire timer_tick = (integral_count == INTEGRAL_COUNT - 1);
    wire sample_tick = EXTERNAL_SAMPLE ? sample_valid : timer_tick;

    // Free-running timer: computation states do not lengthen the sample period.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) integral_count <= 0;
        else if (timer_tick) integral_count <= 0;
        else integral_count <= integral_count + 1'b1;
    end

    // Capture on sample_tick, commit seven clocks later. The sampling period
    // must be at least eight clocks so every sample can be processed.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_COUNT;
            target_sample <= 0;
            value_sample <= 0;
            last_error <= 0;
            error_value <= 0;
            K <= 0;
            I <= 0;
            D <= 0;
            F <= 0;
            integral_raw <= 0;
            integral_candidate <= 0;
            candidate_sum <= 0;
            output_sum <= 0;
            out <= 16'sd0;
        end else begin
            case (state)
                WAIT_COUNT: begin
                    if (sample_tick) begin
                        target_sample <= target;
                        value_sample <= value;
                        state <= GET_ERROR;
                    end
                end
                GET_ERROR: begin
                    error_value <= target_sample - value_sample;
                    state <= GET_K;
                end
                GET_K: begin
                    K <= KP * error_value;
                    F <= KF * target_sample;
                    state <= GET_I;
                end
                GET_I: begin
                    integral_raw <= I + KI * error_value;
                    state <= GET_D;
                end
                GET_D: begin
                    if (integral_raw > I_LIMIT) integral_candidate <= I_LIMIT;
                    else if (integral_raw < -I_LIMIT) integral_candidate <= -I_LIMIT;
                    else integral_candidate <= integral_raw;
                    D <= KD * (error_value - last_error);
                    state <= GET_SUM;
                end
                GET_SUM: begin
                    candidate_sum <= K + F + integral_candidate + D;
                    state <= CHECK_I;
                end
                CHECK_I: begin
                    // Reject integral growth that pushes a saturated output
                    // further outward, while allowing the integral to unwind.
                    if (((candidate_sum > OUT_MAX) && (error_value > 0)) ||
                        ((candidate_sum < OUT_MIN) && (error_value < 0))) begin
                        output_sum <= K + F + I + D;
                    end else begin
                        I <= integral_candidate;
                        output_sum <= candidate_sum;
                    end
                    state <= GET_OUT;
                end
                GET_OUT: begin
                    if (output_sum > OUT_MAX) out <= MAX_OUT;
                    else if (output_sum < OUT_MIN) out <= MIN_OUT;
                    else out <= output_sum[15:0];
                    last_error <= error_value;
                    state <= WAIT_COUNT;
                end
                default: begin
                    state <= WAIT_COUNT;
                    I <= 0;
                F <= 0;
                    last_error <= 0;
                    out <= 0;
                end
            endcase
        end
    end

    // synthesis translate_off
    initial begin
        if (CLK_HZ <= 0 || INTEGRAL_HZ <= 0 || INTEGRAL_COUNT < STATE_COUNT)
            $fatal(1, "PID sample interval must be at least eight clocks");
        if (MIN_OUT < -32768 || MAX_OUT > 32767 || MIN_OUT > 0 || MAX_OUT < 0)
            $fatal(1, "Output limits must contain zero and fit signed 16 bits");
        if (INTEGRAL_LIMIT < 0 || KP < 0 || KI < 0 || KD < 0 || KF < 0)
            $fatal(1, "Integral limit and PID gains must be nonnegative");
    end
    // synthesis translate_on
endmodule

module motor #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer PWM_HZ = 50_000,
    parameter integer BRAKE_AT_ZERO = 0,
    parameter integer DUTY_STEPS = 1000
)(
    input wire clk,
    input wire enable,
    input wire [$clog2(DUTY_STEPS+1)-1:0] duty_cycle, // 0..DUTY_STEPS = 0..100%.
    input wire direction,       // 1: forward, 0: reverse.
    output wire M_POS,
    output wire M_NEG,
    output wire PWM_OUT
);
    // Inputs must be synchronous to clk. Require 0 < PWM_HZ <= CLK_HZ.
    // For an exact PWM_HZ, CLK_HZ must be an integer multiple of PWM_HZ.
    localparam integer PWM_CYCLES = CLK_HZ / PWM_HZ;
    localparam integer COUNT_WIDTH = (PWM_CYCLES > 1) ? $clog2(PWM_CYCLES) : 1;
    localparam integer DUTY_WIDTH = $clog2(PWM_CYCLES + 1);
    localparam integer INPUT_WIDTH=$clog2(DUTY_STEPS+1);
    wire [INPUT_WIDTH-1:0] duty_units = duty_cycle>DUTY_STEPS?DUTY_STEPS:duty_cycle;
    // Widen before multiplication to avoid integer overflow.
    // Exact duty steps require PWM_CYCLES to be a multiple of DUTY_STEPS.
    wire [63:0] requested_ticks;
    generate if(PWM_CYCLES==DUTY_STEPS)begin:direct_duty
        // Equal carrier period and duty scale: one clock per duty unit.
        // Avoid a multiplier/divider that some mappers retain as a DSP.
        assign requested_ticks={{(64-INPUT_WIDTH){1'b0}},duty_units};
    end else if(PWM_CYCLES%DUTY_STEPS==0)begin:integer_duty
        // Exact integer scale, expressed as constant shifts/adds so the new
        // 1kHz closed-loop PWM does not introduce a DSP multiplier/divider.
        function [63:0] scale_ticks;
            input [INPUT_WIDTH-1:0] value;
            reg [63:0] acc;
            integer k;
            begin
                acc=0;
                for(k=0;k<32;k=k+1)
                    if(((PWM_CYCLES/DUTY_STEPS)>>k)&1)acc=acc+({{(64-INPUT_WIDTH){1'b0}},value}<<k);
                scale_ticks=acc;
            end
        endfunction
        assign requested_ticks=scale_ticks(duty_units);
    end else begin:scaled_duty
        assign requested_ticks=({{(64-INPUT_WIDTH){1'b0}},duty_units}*PWM_CYCLES)/DUTY_STEPS;
    end endgenerate

    // FPGA register power-up values. The top-level enable/reset gate also
    // holds all three outputs low during user-mode startup and reset.
    // These values do not control pins before FPGA configuration completes.
    reg [COUNT_WIDTH-1:0] pwm_count = 0;
    reg [DUTY_WIDTH-1:0] active_ticks = 0;
    reg active_direction = 0;
    reg running = 0;

    wire short_brake = BRAKE_AT_ZERO && active_ticks==0;
    assign M_POS = enable && running && (short_brake || active_direction);
    assign M_NEG = enable && running && (short_brake || !active_direction);
    assign PWM_OUT = enable && running && (pwm_count < active_ticks);

    always @(posedge clk) begin
        if (!enable) begin
            pwm_count <= 0;
            active_ticks <= 0;
            active_direction <= 0;
            running <= 0;
        end else if (!running || pwm_count == PWM_CYCLES - 1) begin
            // Start a complete period with a consistent duty/direction pair.
            pwm_count <= 0;
            active_ticks <= requested_ticks[DUTY_WIDTH-1:0];
            active_direction <= direction;
            running <= 1;
        end else begin
            pwm_count <= pwm_count + 1'b1;
        end
    end

endmodule


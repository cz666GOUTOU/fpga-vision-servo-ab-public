// Structural outline only; not the detection / tracking / control implementation.
// This four-stage sketch is illustrative, not the original internal FSM.
// Evaluation and result construction are intentionally left as integration points.
// All outputs stay zero; valid / update / command signals never assert.
// No parameter defaults, thresholds, coefficients, tables or submodule bodies.
`timescale 1ns / 1ps

module a38_sad16_core (
    input wire clk,
    input wire rst_n,
    input wire cancel,
    input wire job_commit,
    input wire job_abort,
    input wire feature_we,
    input wire [11:0] feature_address,
    input wire [15:0] feature_data,
    input wire start,
    input wire initialize,
    input wire [5:0] init_x,
    input wire [5:0] init_y,
    input wire host_req,
    input wire [1:0] host_op,
    input wire [7:0] host_addr,
    input wire [31:0] host_wdata,
    output wire host_ready,
    output wire host_ack,
    output wire host_error,
    output wire [31:0] host_rdata,
    input wire search_window,
    input wire freeze_learning,
    input wire recovery_probe,
    input wire recovery_reset,
    output wire recovery_pending,
    output wire busy,
    output wire done,
    output wire initialized,
    output wire valid,
    output wire [5:0] best_x,
    output wire [5:0] best_y,
    output wire [17:0] best_score,
    output wire [17:0] second_score,
    output wire [31:0] cycles
);
    localparam [1:0] ST_WAIT = 2'd0, ST_PREPARE = 2'd1,
                     ST_EVALUATE = 2'd2, ST_FORMAT = 2'd3;
    reg [1:0] outline_stage;

    // TODO: connect an implemented evaluation stage and its completion event.
    // Keeping this event low prevents a sketch from publishing fabricated results.
    wire evaluation_complete = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            outline_stage <= ST_WAIT;
        else if (cancel || job_abort)
            outline_stage <= ST_WAIT;
        else begin
            case (outline_stage)
                ST_WAIT: begin
                    // Stage 1: job input.
                    if (start) outline_stage <= ST_PREPARE;
                end
                ST_PREPARE: begin
                    // Stage 2: sample preparation.
                    // TODO: prepare the application-specific working record.
                    outline_stage <= ST_EVALUATE;
                end
                ST_EVALUATE: begin
                    // Stage 3: match evaluation.
                    // TODO: compute; no scoring / filtering / control law here.
                    if (evaluation_complete) outline_stage <= ST_FORMAT;
                end
                ST_FORMAT: begin
                    // Stage 4: result formatting.
                    // TODO: publish a coherent implemented result and qualifier.
                    outline_stage <= ST_WAIT;
                end
                default: outline_stage <= ST_WAIT;
            endcase
        end
    end

    // Inactive outputs are deliberate; this outline cannot drive a real loop.
    assign host_ready = 0;
    assign host_ack = 0;
    assign host_error = 0;
    assign host_rdata = 0;
    assign recovery_pending = 0;
    assign busy = 0;
    assign done = 0;
    assign initialized = 0;
    assign valid = 0;
    assign best_x = 0;
    assign best_y = 0;
    assign best_score = 0;
    assign second_score = 0;
    assign cycles = 0;
endmodule

// Structural outline only; not the detection / tracking / control implementation.
// This four-stage sketch is illustrative, not the original internal FSM.
// Evaluation and result construction are intentionally left as integration points.
// All outputs stay zero; valid / update / command signals never assert.
// No parameter defaults, thresholds, coefficients, tables or submodule bodies.
`timescale 1ns / 1ps

module zhencha_multi_ccl (
    input wire clk,
    input wire rst_n,
    input wire detect_en,
    input wire pre_frame_vsync,
    input wire pre_frame_de,
    input wire [23:0] pre_rgb,
    output wire [3:0] box_valid,
    output wire [35:0] box_xmin,
    output wire [35:0] box_xmax,
    output wire [31:0] box_ymin,
    output wire [31:0] box_ymax,
    output wire overflow,
    input wire gain_change,
    output wire result_update,
    output wire result_ready,
    output wire [1:0] result_fresh
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
        else if (!detect_en || pre_frame_vsync || gain_change)
            outline_stage <= ST_WAIT;
        else begin
            case (outline_stage)
                ST_WAIT: begin
                    // Stage 1: frame input.
                    if (detect_en && pre_frame_de) outline_stage <= ST_PREPARE;
                end
                ST_PREPARE: begin
                    // Stage 2: region preparation.
                    // TODO: prepare the application-specific working record.
                    outline_stage <= ST_EVALUATE;
                end
                ST_EVALUATE: begin
                    // Stage 3: motion evaluation.
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
    assign box_valid = 0;
    assign box_xmin = 0;
    assign box_xmax = 0;
    assign box_ymin = 0;
    assign box_ymax = 0;
    assign overflow = 0;
    assign result_update = 0;
    assign result_ready = 0;
    assign result_fresh = 0;
endmodule

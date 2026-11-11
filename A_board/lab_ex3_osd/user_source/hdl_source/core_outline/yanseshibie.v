// Structural outline only; not the detection / tracking / control implementation.
// This four-stage sketch is illustrative, not the original internal FSM.
// Evaluation and result construction are intentionally left as integration points.
// All outputs stay zero; valid / update / command signals never assert.
// No parameter defaults, thresholds, coefficients, tables or submodule bodies.
`timescale 1ns / 1ps

module yanseshibie (
    input wire clk,
    input wire rst_n,
    input wire detect_en,
    input wire pre_frame_vsync,
    input wire pre_frame_de,
    input wire [23:0] pre_rgb,
    output wire square_valid,
    output wire triangle_valid,
    output wire result_update,
    output wire target_valid,
    output wire [15:0] target_id,
    output wire [15:0] center_x,
    output wire [15:0] center_y,
    output wire red_seen_frame,
    output wire green_seen_frame,
    output wire [8:0] square_xmin,
    output wire [8:0] square_xmax,
    output wire [8:0] triangle_xmin,
    output wire [8:0] triangle_xmax,
    output wire [7:0] square_ymin,
    output wire [7:0] square_ymax,
    output wire [7:0] triangle_ymin,
    output wire [7:0] triangle_ymax,
    output wire [43:0] guard_targets,
    output wire [71:0] frame_candidate
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
        else if (!detect_en || pre_frame_vsync)
            outline_stage <= ST_WAIT;
        else begin
            case (outline_stage)
                ST_WAIT: begin
                    // Stage 1: frame input.
                    if (detect_en && pre_frame_de) outline_stage <= ST_PREPARE;
                end
                ST_PREPARE: begin
                    // Stage 2: candidate preparation.
                    // TODO: prepare the application-specific working record.
                    outline_stage <= ST_EVALUATE;
                end
                ST_EVALUATE: begin
                    // Stage 3: shape evaluation.
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
    assign square_valid = 0;
    assign triangle_valid = 0;
    assign result_update = 0;
    assign target_valid = 0;
    assign target_id = 0;
    assign center_x = 0;
    assign center_y = 0;
    assign red_seen_frame = 0;
    assign green_seen_frame = 0;
    assign square_xmin = 0;
    assign square_xmax = 0;
    assign triangle_xmin = 0;
    assign triangle_xmax = 0;
    assign square_ymin = 0;
    assign square_ymax = 0;
    assign triangle_ymin = 0;
    assign triangle_ymax = 0;
    assign guard_targets = 0;
    assign frame_candidate = 0;
endmodule

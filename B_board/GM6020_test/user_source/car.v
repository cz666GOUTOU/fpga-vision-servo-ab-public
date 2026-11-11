module car #(
    // Wheel centers: length 172 mm, width 198 mm. Wheel diameter: 65 mm.
    parameter integer HALF_LENGTH_MM = 86,
    parameter integer HALF_WIDTH_MM = 99,
    // 1: top X drawing above (default); 0: all four handednesses reversed.
    parameter integer REVERSE_ROLLERS = 1
)(
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire signed [15:0] forward_mm_s,
    input wire signed [15:0] lateral_mm_s,
    input wire signed [15:0] yaw_deg_s,
    output reg out_valid,
    // Wheel peripheral LINEAR speeds, mm/s; not encoder counts or RPM.
    // Wide outputs preserve mixed-command sums without wrap or clipping.
    output reg signed [31:0] speed_fl,
    output reg signed [31:0] speed_fr,
    output reg signed [31:0] speed_rl,
    output reg signed [31:0] speed_rr
);
    // Ground-contact constraint: u_i = vx_i + q_i*vy_i.
    // TOP X drawing: q_FL=q_RR=+1; q_FR=q_RL=-1.
    // Its yaw arm is a-b, not a+b. Opposite handedness uses a+b.
    localparam signed [63:0] A = HALF_LENGTH_MM;
    localparam signed [63:0] B = HALF_WIDTH_MM;
    localparam signed [63:0] YAW_ARM = REVERSE_ROLLERS ? A-B : A+B;
    wire signed [63:0] vx = {{48{forward_mm_s[15]}}, forward_mm_s};
    wire signed [63:0] vy = {{48{lateral_mm_s[15]}}, lateral_mm_s};
    wire signed [63:0] wz = {{48{yaw_deg_s[15]}}, yaw_deg_s};
    // Signed division truncates toward zero, equally in both yaw directions.
    // Degrees/s -> radians/s: pi ~= 314159/100000 (error < 1 ppm).
    wire signed [63:0] turn = (wz * YAW_ARM * 64'sd314159) / 64'sd18000000;
    wire signed [63:0] fl = REVERSE_ROLLERS ? vx+vy+turn : vx-vy-turn;
    wire signed [63:0] fr = REVERSE_ROLLERS ? vx-vy-turn : vx+vy+turn;
    wire signed [63:0] rl = REVERSE_ROLLERS ? vx-vy+turn : vx+vy-turn;
    wire signed [63:0] rr = REVERSE_ROLLERS ? vx+vy-turn : vx-vy+turn;

    // Inputs are synchronous to clk. Capture all four speeds on a valid edge.
    // Invalid cycles hold the command; reset clears all outputs.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speed_fl <= 0; speed_fr <= 0; speed_rl <= 0; speed_rr <= 0;
            out_valid <= 0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                speed_fl <= fl[31:0]; speed_fr <= fr[31:0];
                speed_rl <= rl[31:0]; speed_rr <= rr[31:0];
            end
        end
    end
endmodule


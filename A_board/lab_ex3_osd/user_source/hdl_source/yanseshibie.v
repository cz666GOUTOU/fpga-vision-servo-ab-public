// Class 2 is BLUE TARGET; green/triangle identifiers are interface aliases.
// Streaming observer, fixed 4x4 sampling. No frame RAM; RGB path is untouched.
// Keep the connected-component implementation in the same translation unit for
// Tang Dynasty runs that rebuild a stale .prj source list.
`include "color_ccl_pipeline.v"
module yanseshibie #(
    parameter integer H_ACTIVE=1280, V_ACTIVE=720,
    // Original HDMI observer stays at 1.  The control observer sees the
    // first RGB of each four-pixel ISP beat, preserving the same 4x4 grid.
    parameter integer PIXELS_PER_CLK=1, SHARED_SPATIAL=0,
    parameter [7:0] COLOR_MIN=112,
    parameter [8:0] COLOR_MARGIN=48,
    parameter [7:0] GREEN_MIN=112,
    parameter [8:0] GREEN_MARGIN=48,
    parameter integer MIN_PIXELS=6, MIN_SIDE=2,
    parameter [7:0] RED_SUPPORT_MIN=80,
    parameter [8:0] RED_SUPPORT_RG_MARGIN=16, RED_SUPPORT_RB_MARGIN=24,
    parameter [7:0] GREEN_SUPPORT_MIN=96,
    parameter [8:0] GREEN_SUPPORT_MARGIN=24,
    // Optional ratio-based dark colour extension. Legacy thresholds stay active.
    parameter integer DARK_COLOR_ENABLE=1,
    parameter [7:0] DARK_RED_MIN=48, DARK_GREEN_MIN=64,
    parameter [7:0] DARK_RED_SUPPORT_MIN=40, DARK_GREEN_SUPPORT_MIN=48
)(
    input clk, rst_n, detect_en, pre_frame_vsync, pre_frame_de,
    input [23:0] pre_rgb,
    output square_valid, triangle_valid,
    output reg result_update, target_valid,
    output reg [15:0] target_id, center_x, center_y,
    output reg red_seen_frame, green_seen_frame,
    output [8:0] square_xmin, square_xmax, triangle_xmin, triangle_xmax,
    output [7:0] square_ymin, square_ymax, triangle_ymin, triangle_ymax,
    output reg [43:0] guard_targets,
    output wire [71:0] frame_candidate
);
    wire spatial_en=SHARED_SPATIAL ? 1'b1 : detect_en;
    wire [33:0] red_candidate_box,green_candidate_box;
    wire [8:0] raw_red_xmin,raw_red_xmax,raw_blue_xmin,raw_blue_xmax;
    wire [7:0] raw_red_ymin,raw_red_ymax,raw_blue_ymin,raw_blue_ymax;
    assign {square_xmin,square_xmax,square_ymin,square_ymax}=red_candidate_box;
    assign {triangle_xmin,triangle_xmax,triangle_ymin,triangle_ymax}=green_candidate_box;
    reg [10:0] x;
    reg [9:0] y;
    reg vs_d;
    wire boundary=pre_frame_vsync & ~vs_d;
    wire sample=pre_frame_de && !pre_frame_vsync && x[1:0]==0 && y[1:0]==0;
    // The final active pixel is x=H_ACTIVE-1 (low bits are 2'b11), so the
    // line-end event must not be gated by the 4x4 sample phase.
    // Finish one logical 4x4 row only on the fourth source line. This keeps
    // run-length/connected-region statistics in the same 320x180 domain as
    // x[10:2] and y[9:2].
    wire line_end=pre_frame_de && x==H_ACTIVE-PIXELS_PER_CLK && y[1:0]==2'd3;
    wire [9:0] r={2'b0,pre_rgb[23:16]}, g={2'b0,pre_rgb[15:8]}, b={2'b0,pre_rgb[7:0]};
    // Exact ratio tests on eight-bit channels. Dividing a nonnegative
    // integer bound by 2/4 is a wire slice, including odd-value boundaries.
    wire [9:0] r_three={1'b0,pre_rgb[23:16],1'b0}+r;
    wire [9:0] b_three={1'b0,pre_rgb[7:0],1'b0}+b;
    wire red_half_ge_g=(pre_rgb[23:17]>=pre_rgb[15:8]);
    wire red_half_ge_b=(pre_rgb[23:17]>=pre_rgb[7:0]);
    wire blue_half_ge_r=(pre_rgb[7:1]>=pre_rgb[23:16]);
    wire blue_half_ge_g=(pre_rgb[7:1]>=pre_rgb[15:8]);
    wire dark_red=DARK_COLOR_ENABLE && (r>=DARK_RED_MIN) &&
        red_half_ge_g && red_half_ge_b;
    wire dark_green=DARK_COLOR_ENABLE && (b>=DARK_GREEN_MIN) &&
        blue_half_ge_r && blue_half_ge_g;
    // Keep the original predicates, OR a stricter relative-dominance seed.
    // No hard brightness-band switch: brightening cannot hit a band seam.
    wire red=((r>=COLOR_MIN)&&(r>=g+{1'b0,COLOR_MARGIN})&&
        (r>=b+{1'b0,COLOR_MARGIN})) || dark_red;
    wire green=((b>=GREEN_MIN)&&(b>=r+{1'b0,GREEN_MARGIN})&&
        (b>=g+{1'b0,GREEN_MARGIN})) || dark_green;
    // Strong pixels identify the colour; weak pixels support the connected
    // silhouette under illumination shifts.  The seed test is local to each
    // retained component, never a whole-frame permission to accept weak noise.
    // Dark support completes a dim silhouette, but does not bypass the SAME
    // component's >=4 seeds / >=1/8 seed fraction, shape, or denoise gates.
    // Default seeds are already contained in support. Keep the explicit
    // union for parameter overrides that do not satisfy that implication.
    localparam RED_SEED_IN_SUPPORT=(COLOR_MIN>=RED_SUPPORT_MIN) &&
        (COLOR_MARGIN>=RED_SUPPORT_RG_MARGIN) &&
        (COLOR_MARGIN>=RED_SUPPORT_RB_MARGIN) &&
        (DARK_RED_MIN>=DARK_RED_SUPPORT_MIN);
    localparam BLUE_SEED_IN_SUPPORT=(GREEN_MIN>=GREEN_SUPPORT_MIN) &&
        (GREEN_MARGIN>=GREEN_SUPPORT_MARGIN) &&
        (DARK_GREEN_MIN>=DARK_GREEN_SUPPORT_MIN);
    wire red_support=(!RED_SEED_IN_SUPPORT && red) ||
        ((r>=RED_SUPPORT_MIN) && (r>=g+{1'b0,RED_SUPPORT_RG_MARGIN}) &&
         (r>=b+{1'b0,RED_SUPPORT_RB_MARGIN})) ||
        (DARK_COLOR_ENABLE && (r>=DARK_RED_SUPPORT_MIN) &&
         (pre_rgb[15:8]<=r_three[9:2]) && red_half_ge_b);
    wire green_support=(!BLUE_SEED_IN_SUPPORT && green) ||
        ((b>=GREEN_SUPPORT_MIN) && (b>=r+{1'b0,GREEN_SUPPORT_MARGIN}) &&
         (b>=g+{1'b0,GREEN_SUPPORT_MARGIN})) ||
        (DARK_COLOR_ENABLE && (b>=DARK_GREEN_SUPPORT_MIN) &&
         (pre_rgb[23:16]<=b_three[9:2]) && (pre_rgb[15:8]<=b_three[9:2]));
    wire su,tu,red_frame_good,green_frame_good;
    assign frame_candidate={green_seen_frame,red_seen_frame,
        green_frame_good,red_frame_good,green_candidate_box,red_candidate_box};
    // Publish on boundary+3: boxes/valid are settled on boundary+2.
    // Emit invalid records as well, including when recognition is disabled.
    reg [2:0] publish_delay;
    wire [9:0] red_xsum={1'b0,square_xmin}+{1'b0,square_xmax};
    wire [8:0] red_ysum={1'b0,square_ymin}+{1'b0,square_ymax};
    wire [9:0] green_xsum={1'b0,triangle_xmin}+{1'b0,triangle_xmax};
    wire [8:0] green_ysum={1'b0,triangle_ymin}+{1'b0,triangle_ymax};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            publish_delay<=0;result_update<=0;target_valid<=0;
            target_id<=0;center_x<=0;center_y<=0;guard_targets<=0;
        end else begin
            publish_delay<={publish_delay[1:0],boundary};
            result_update<=publish_delay[2];
            if(publish_delay[2]) begin
                guard_targets<={detect_en && triangle_valid && green_frame_good,
                    detect_en && square_valid && red_frame_good,
                    green_ysum,1'b1,green_xsum,1'b1,red_ysum,1'b1,red_xsum,1'b1};
                target_valid<=detect_en && (square_valid || triangle_valid);
                if(detect_en && square_valid) begin
                    target_id<=16'd1;
                    center_x<={5'b0,red_xsum,1'b1};
                    center_y<={6'b0,red_ysum,1'b1};
                end else if(detect_en && triangle_valid) begin
                    target_id<=16'd2;
                    center_x<={5'b0,green_xsum,1'b1};
                    center_y<={6'b0,green_ysum,1'b1};
                end else begin target_id<=0;center_x<=0;center_y<=0;end
            end
        end
    end
    // Match object_box_overlay: x0=4*xmin, x1=4*xmax+3 (inclusive).
    // Integer center=floor((x0+x1)/2)=2*(xmin+xmax)+1; same for Y.
    // Widen BEFORE adding; do not truncate the half-cell before scaling.

    // Green-only 3x3 majority filter in the 4x4 sampled domain.  This removes
    // isolated weak green pixels before connected-component tracking.  The
    // centre's strong label follows the SAME window/output coordinate as the
    // support mask; counting any strong pixel in the window would inflate the
    // seed fraction by dilating seeds into neighbouring weak pixels.
    // Three physical rows hold {strong seed, support mask}. Rotate bank
    // roles instead of copying/clearing five 320-bit register vectors.
    // Metadata masks unwritten cells to zero, including a disable/re-enable
    // in the middle of a source line; RAM contents themselves are not reset.
    reg [1:0] green_write_bank;
    wire [1:0] green_next_bank=(green_write_bank==2'd2)?2'd0:green_write_bank+2'd1;
    reg [2:0] green_bank_valid;
    reg [8:0] green_bank_first [0:2];
    reg [8:0] green_bank_last [0:2];
    wire [1:0] green_bank_read [0:2];
    wire [1:0] green_bank_masked [0:2];
    // Prefetch the sampled column corresponding to the NEXT x value. All
    // banks are read together so rotating roles at a line end adds no cycle.
    wire [10:0] green_next_x=(!rst_n || pre_frame_vsync)?11'd0:
        (pre_frame_de?((x==H_ACTIVE-PIXELS_PER_CLK)?11'd0:x+PIXELS_PER_CLK):x);
    wire [8:0] green_read_col=green_next_x[10:2];
    wire green_cache_write=rst_n && spatial_en && !boundary && sample;
    genvar green_bank;
    generate for(green_bank=0;green_bank<3;green_bank=green_bank+1) begin:g_green_rows
        color_mask_row_ram row_ram(
            .clk(clk),.write_en(green_cache_write && green_write_bank==green_bank),
            .write_addr(x[10:2]),.write_data({green,green_support}),
            .read_addr(green_read_col),.read_data(green_bank_read[green_bank]));
        assign green_bank_masked[green_bank]=(green_bank_valid[green_bank] &&
            x[10:2]>=green_bank_first[green_bank] && x[10:2]<=green_bank_last[green_bank])?
            green_bank_read[green_bank]:2'b00;
    end endgenerate
    wire [1:0] green_top_word=(green_write_bank==2'd0)?green_bank_masked[1]:
                              (green_write_bank==2'd1)?green_bank_masked[2]:green_bank_masked[0];
    wire [1:0] green_mid_word=(green_write_bank==2'd0)?green_bank_masked[2]:
                              (green_write_bank==2'd1)?green_bank_masked[0]:green_bank_masked[1];
    integer green_meta;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n || !spatial_en || boundary) begin
            green_write_bank<=0;
            green_bank_valid<=0;
            for(green_meta=0;green_meta<3;green_meta=green_meta+1) begin
                green_bank_first[green_meta]<=0;
                green_bank_last[green_meta]<=0;
            end
        end else begin
            if(sample) begin
                green_bank_valid[green_write_bank]<=1'b1;
                if(!green_bank_valid[green_write_bank]) begin
                    green_bank_first[green_write_bank]<=x[10:2];
                    green_bank_last[green_write_bank]<=x[10:2];
                end else begin
                    if(x[10:2]<green_bank_first[green_write_bank])
                        green_bank_first[green_write_bank]<=x[10:2];
                    if(x[10:2]>green_bank_last[green_write_bank])
                        green_bank_last[green_write_bank]<=x[10:2];
                end
            end
            if(line_end) begin
                green_write_bank<=green_next_bank;
                green_bank_valid[green_next_bank]<=1'b0;
            end
        end
    end
    reg green_seed_m1;
    reg green_t2,green_t1,green_m2,green_m1,green_b2,green_b1;
    reg green_f_sample,green_f_hit,green_f_seed;
    reg [8:0] green_f_x;
    reg [7:0] green_f_y;
    wire green_top_bit=green_top_word[0];
    wire green_mid_bit=green_mid_word[0];
    wire [3:0] green_votes={3'b0,green_t2}+{3'b0,green_t1}+{3'b0,green_top_bit}+
                           {3'b0,green_m2}+{3'b0,green_m1}+{3'b0,green_mid_bit}+
                           {3'b0,green_b2}+{3'b0,green_b1}+{3'b0,green_support};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n || !spatial_en || boundary) begin
            green_seed_m1<=0;
            green_t2<=0; green_t1<=0; green_m2<=0; green_m1<=0;
            green_b2<=0; green_b1<=0;
            green_f_sample<=0; green_f_hit<=0; green_f_seed<=0; green_f_x<=0; green_f_y<=0;
        end else begin
            green_f_sample<=0;
            green_f_seed<=0;
            if(sample) begin
                if(x[10:2]>=2 && y[9:2]>=2) begin
                    green_f_sample<=1'b1;
                    green_f_hit<=green_votes>=4'd5;
                    // Causal output is tagged (x,y); its centre is (x-1,y-1).
                    green_f_seed<=(green_votes>=4'd5) && green_seed_m1;
                    green_f_x<=x[10:2];
                    green_f_y<=y[9:2];
                end
                green_seed_m1<=green_mid_word[1];
                if(x[10:2]==0) begin
                    green_t2<=green_top_bit; green_t1<=green_top_bit;
                    green_m2<=green_mid_bit; green_m1<=green_mid_bit;
                    green_b2<=green_support; green_b1<=green_support;
                end else begin
                    green_t2<=green_t1; green_t1<=green_top_bit;
                    green_m2<=green_m1; green_m1<=green_mid_bit;
                    green_b2<=green_b1; green_b1<=green_support;
                end
            end
        end
    end

    reg red_seen, green_seen;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            red_seen<=1'b0; green_seen<=1'b0;
            red_seen_frame<=1'b0; green_seen_frame<=1'b0;
        end else if(!spatial_en) begin
            red_seen<=1'b0; green_seen<=1'b0;
            red_seen_frame<=1'b0; green_seen_frame<=1'b0;
        end else if(boundary) begin
            red_seen_frame<=red_seen;
            green_seen_frame<=green_seen;
            red_seen<=1'b0;
            green_seen<=1'b0;
        end else if(sample) begin
            if(red) red_seen<=1'b1;
            if(green) green_seen<=1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x<=0; y<=0; vs_d<=0; end
        else begin
            vs_d<=pre_frame_vsync;
            if(pre_frame_vsync) begin x<=0; y<=0; end
            else if(pre_frame_de) begin
                if(x==H_ACTIVE-PIXELS_PER_CLK) begin x<=0; y<=(y==V_ACTIVE-1)?0:y+1'b1; end
                else x<=x+PIXELS_PER_CLK;
            end
        end
    end
    // Red compact colour target, not an exact circle/ellipse classifier.
    color_ccl_pipeline #(.SHAPE(0),.MIN_PIXELS(16),.MIN_SIDE(MIN_SIDE),
        .MIN_WIDTH(4),.MAX_WIDTH(220),.MIN_HEIGHT(4),.MAX_HEIGHT(140),
        .CONFIRM_FRAMES(2),.GRID_WIDTH(H_ACTIVE/4),.GRID_HEIGHT(V_ACTIVE/4),
        .REQUIRE_SEED(1),.MIN_STRONG_PIXELS(4),.SEED_RATIO_SHIFT(3),
        .SEPARATE_CONFIRM(SHARED_SPATIAL)) square (
        .clk(clk),.rst_n(rst_n),.enable(spatial_en),.boundary(boundary),
        .confirm_enable(detect_en),.candidate_box(red_candidate_box),
        .de(pre_frame_de),.sample(sample),.hit(red_support),.strong_hit(red),
        .line_end(line_end),.x(x[10:2]),.y(y[9:2]),
        .frame_good(red_frame_good),.valid(square_valid),.update(su),.out_xmin(raw_red_xmin),.out_xmax(raw_red_xmax),
        .out_ymin(raw_red_ymin),.out_ymax(raw_red_ymax));
    // Blue compact colour target; preserve the existing majority denoiser.
    color_ccl_pipeline #(.SHAPE(2),.MIN_PIXELS(16),.MIN_SIDE(4),.CONFIRM_FRAMES(2),
        .REQUIRE_SEED(1),.MIN_STRONG_PIXELS(4),.SEED_RATIO_SHIFT(3),
        .SEPARATE_CONFIRM(SHARED_SPATIAL)) triangle (
        .clk(clk),.rst_n(rst_n),.enable(spatial_en),.boundary(boundary),
        .confirm_enable(detect_en),.candidate_box(green_candidate_box),
        .de(pre_frame_de),.sample(green_f_sample),.hit(green_f_hit),.strong_hit(green_f_seed),
        .line_end(line_end),.x(green_f_x),.y(green_f_y),
        .frame_good(green_frame_good),.valid(triangle_valid),.update(tu),.out_xmin(raw_blue_xmin),.out_xmax(raw_blue_xmax),
        .out_ymin(raw_blue_ymin),.out_ymax(raw_blue_ymax));

endmodule

// Simple dual-port synchronous inferred RAM; no generated IP is required.
// Read-during-write data are never consumed from the current write bank.
// That bank becomes a previous row only after the fourth source line ends.
module color_mask_row_ram(
    input clk,write_en,
    input [8:0] write_addr,read_addr,
    input [1:0] write_data,
    output reg [1:0] read_data
);
    (* ram_style = "bram" *) reg [1:0] pixels [0:319];
    always @(posedge clk) begin
        read_data<=pixels[read_addr];
        if(write_en) pixels[write_addr]<=write_data;
    end
endmodule

// Heuristic for one solid, near-upright object per color, not a general classifier.
// Snapshot at VS rising; publish after three blanking clocks, never per pixel.
module color_shape_stats #(
    // SHAPE: 0=circle, 1=triangle
    parameter integer SHAPE=0, MIN_PIXELS=16, MIN_SIDE=4
)(
    input clk,rst_n,enable,boundary,de,sample,hit,line_end,
    input [8:0] x, input [7:0] y,
    output reg valid,update,
    output reg [8:0] out_xmin,out_xmax,
    output reg [7:0] out_ymin,out_ymax
);
    reg [8:0] xmin,xmax,sxmin,sxmax;
    reg [7:0] ymin,ymax,symin,symax;
    reg [16:0] count,saved_count;
    reg [9:0] row_count,first_width,last_width,previous_width;
    reg [7:0] rises,falls,saved_rises,saved_falls;
    reg [9:0] first_saved,last_saved,width;
    reg [8:0] height;
    reg [18:0] area;
    reg collecting;
    reg [1:0] phase;
    // 4x4 sampling gives at most one hit per bounding-box grid cell.
    // Compare 100*count with percentage*area in the same 26-bit domain.
    wire [25:0] count100={9'b0,saved_count}*26'd100;
    wire [25:0] area15={7'b0,area}*26'd15;
    wire [25:0] area20={7'b0,area}*26'd20;
    wire [25:0] area85={7'b0,area}*26'd85;
    wire [11:0] width_ext={2'b0,width},height_ext={3'b0,height};
    // A full-frame result is background leakage, not a single object.
    // The limits still allow targets up to roughly half of the 720p frame.
    wire bbox_not_full=(width<10'd300) && (height<9'd170);
    wire widening=({1'b0,last_saved}>={first_saved,1'b0}) && saved_falls<=2;
    wire narrowing=({1'b0,first_saved}>={last_saved,1'b0}) && saved_rises<=2;
    wire shape_ok=(SHAPE==1) ?
        // The colour mask and non-full-frame bounding box are the reliable
        // hardware observables. Fill/slope tests are too sensitive to ISP
        // colour leakage and 4x4 sampling, so keep only broad geometry.
        (bbox_not_full && saved_count>=MIN_PIXELS && width>=MIN_SIDE && height>=MIN_SIDE &&
         width_ext <= (height_ext*12'd4) && height_ext <= (width_ext*12'd4)) :
        (bbox_not_full && saved_count>=MIN_PIXELS && width>=MIN_SIDE && height>=MIN_SIDE &&
         (width_ext*12'd2) <= (height_ext*12'd5) &&
         (height_ext*12'd2) <= (width_ext*12'd5));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            xmin<=511;xmax<=0;ymin<=255;ymax<=0;count<=0;
            sxmin<=0;sxmax<=0;symin<=0;symax<=0;saved_count<=0;
            row_count<=0;first_width<=0;last_width<=0;previous_width<=0;
            rises<=0;falls<=0;saved_rises<=0;saved_falls<=0;
            first_saved<=0;last_saved<=0;width<=0;height<=0;area<=0;
            collecting<=0;phase<=0;valid<=0;update<=0;
            out_xmin<=0;out_xmax<=0;out_ymin<=0;out_ymax<=0;
        end else begin
            update<=0;
            if(!enable) begin
                xmin<=511;xmax<=0;ymin<=255;ymax<=0;count<=0;
                row_count<=0;first_width<=0;last_width<=0;previous_width<=0;
                rises<=0;falls<=0;collecting<=0;phase<=0;valid<=0;
            end else if(boundary) begin
                // A result is valid only for the frame that produced it.
                // Clear the previous frame's box before starting a new
                // accumulation; otherwise an absent object leaves a stale
                // full-frame box enabled forever.
                valid<=1'b0;
                sxmin<=xmin;sxmax<=xmax;symin<=ymin;symax<=ymax;saved_count<=count;
                width<=count!=0?({1'b0,xmax}-{1'b0,xmin}+10'd1):0;
                height<=count!=0?({1'b0,ymax}-{1'b0,ymin}+9'd1):0;
                first_saved<=first_width;last_saved<=last_width;
                saved_rises<=rises;saved_falls<=falls;
                phase<=collecting?1:0;
                xmin<=511;xmax<=0;ymin<=255;ymax<=0;count<=0;
                row_count<=0;first_width<=0;last_width<=0;previous_width<=0;
                rises<=0;falls<=0;collecting<=0;
            end else begin
                if(de) collecting<=1;
                if(sample && hit) begin
                    count<=count+1'b1;row_count<=row_count+1'b1;
                    if(x<xmin) xmin<=x;
                    if(x>xmax) xmax<=x;
                    if(y<ymin) ymin<=y;
                    if(y>ymax) ymax<=y;
                end
                // H_ACTIVE is a multiple of four: last sample precedes line_end.
                if(line_end) begin
                    row_count<=0;
                    if(row_count!=0) begin
                        if(first_width==0) first_width<=row_count;
                        else begin
                            // At 4x4 sampling an ideal triangle often changes
                            // by exactly one grid cell per row group. Count
                            // that one-cell change as a real slope.
                            if(row_count>previous_width) rises<=rises+1'b1;
                            if(previous_width>row_count) falls<=falls+1'b1;
                        end
                        last_width<=row_count;previous_width<=row_count;
                    end
                end
                // Widen operands before multiplication. Without this, Verilog
                // evaluates width*height at the 10-bit operand width and large
                // objects wrap before being stored in the 19-bit area register.
                if(phase==1) begin area<={9'b0,width}*{10'b0,height};phase<=2;end
                else if(phase==2) begin
                    valid<=saved_count>=MIN_PIXELS && width>=MIN_SIDE && height>=MIN_SIDE && shape_ok;
                    out_xmin<=sxmin;out_xmax<=sxmax;out_ymin<=symin;out_ymax<=symax;
                    update<=1;phase<=0;
                end
            end
        end
    end
endmodule

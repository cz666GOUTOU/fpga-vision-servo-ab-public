// Streaming 4x4 colour connected-region tracker.
// One longest run is retained per logical row; adjacent runs overlap with a
// one-cell tolerance and form the current candidate component.
module color_ccl_pipeline #(
    parameter integer SHAPE=0, MIN_PIXELS=6, MIN_SIDE=2,
    parameter integer MIN_WIDTH=0, MAX_WIDTH=319,
    parameter integer MIN_HEIGHT=0, MAX_HEIGHT=179,
    parameter integer CONFIRM_FRAMES=1,
    parameter integer GRID_WIDTH=320, GRID_HEIGHT=180,
    parameter integer REQUIRE_SEED=0, MIN_STRONG_PIXELS=4, SEED_RATIO_SHIFT=3,
    parameter integer SEPARATE_CONFIRM=0
)(
    input clk, rst_n, enable, boundary, de, sample, hit, line_end,
    input strong_hit,
    input [8:0] x, input [7:0] y,
    output reg valid, update,
    output reg [8:0] out_xmin,out_xmax,
    output reg [7:0] out_ymin,out_ymax,
    output reg frame_good,
    input confirm_enable,
    output wire [33:0] candidate_box
);
    // 320 samples per logical row in the installed 720p red/blue path.
    // Keep accumulated component counts wide across missing frame boundaries.
    // Legacy triangle and other geometries retain their original widths.
    localparam integer ROW_COUNT_BITS=(GRID_WIDTH==320 && GRID_HEIGHT==180 &&
                                      (SHAPE==0 || SHAPE==2)) ? 9 : 10;
    reg run_active;
    reg [8:0] run_start,run_end;
    reg [ROW_COUNT_BITS-1:0] run_len;
    reg [ROW_COUNT_BITS-1:0] run_seed_count;
    // Keep the longest run in each logical 4x4 row.  This prevents a small
    // late noise run from replacing the real object run.
    reg row_best_active;
    reg [8:0] row_best_start,row_best_end;
    reg [ROW_COUNT_BITS-1:0] row_best_len;
    reg [ROW_COUNT_BITS-1:0] row_best_seed_count;
    reg [8:0] prev_start,prev_end;
    reg prev_valid;
    reg [16:0] comp_count;
    reg [16:0] comp_seed_count;
    reg [8:0] comp_xmin,comp_xmax;
    reg [7:0] comp_ymin,comp_ymax;
    reg [8:0] best_xmin,best_xmax;
    reg [7:0] best_ymin,best_ymax;
    reg [16:0] best_count;
    reg [16:0] best_seed_count;
    reg [7:0] best_profile_rows,best_profile_rises,best_profile_falls;
    reg [1:0] phase;
    reg [16:0] pub_count;
    reg [16:0] pub_seed_count;
    reg [8:0] pub_xmin,pub_xmax;
    reg [7:0] pub_ymin,pub_ymax;
    // Lean localization: original out_* remains raw, so shape/confirmation and
    // next-frame decisions do NOT receive predicted coordinates as evidence.
    reg [8:0] reference_width;
    reg [7:0] reference_height;
    reg signed [1:0] lead_x,lead_y;
    wire [9:0] current_sum_x={1'b0,pub_xmin}+{1'b0,pub_xmax};
    wire [9:0] previous_sum_x={1'b0,out_xmin}+{1'b0,out_xmax};
    wire [8:0] current_sum_y={1'b0,pub_ymin}+{1'b0,pub_ymax};
    wire [8:0] previous_sum_y={1'b0,out_ymin}+{1'b0,out_ymax};
    wire signed [10:0] delta_sum_x=$signed({1'b0,current_sum_x})-$signed({1'b0,previous_sum_x});
    wire signed [9:0] delta_sum_y=$signed({1'b0,current_sum_y})-$signed({1'b0,previous_sum_y});
    // Minimum-step variant: no variable magnitude decoding, only +/- one
    // DS4 cell when observed centre motion exceeds the quantization deadband.
    function signed [1:0] clipped_half_step;
      input signed [10:0] delta;
      begin
        if(delta>=11'sd4)clipped_half_step=2'sd1;
        else if(delta<=-11'sd4)clipped_half_step=-2'sd1;
        else clipped_half_step=2'sd0;
      end
    endfunction
    wire [8:0] report_xmin=pub_xmin+{{7{lead_x[1]}},lead_x};
    wire [8:0] report_xmax=pub_xmax+{{7{lead_x[1]}},lead_x};
    wire [7:0] report_ymin=pub_ymin+{{6{lead_y[1]}},lead_y};
    wire [7:0] report_ymax=pub_ymax+{{6{lead_y[1]}},lead_y};
    // Raw geometry belongs to this published frame, before temporal hold.
    assign candidate_box={report_xmin,report_xmax,report_ymin,report_ymax};
    reg [7:0] profile_rows,profile_rises,profile_falls;
    reg [7:0] pub_profile_rows,pub_profile_rises,pub_profile_falls;
    reg [9:0] profile_prev_width;
    reg profile_have_width;
    // Red-only coarse roundness; no extra mask/row/frame memory.
    reg [9:0] round_first,round_last,round_max;
    // Capture only the predicates consumed after component selection.
    reg best_round_ends,best_broad_ends,best_pointed_ends;
    reg pub_round_ends,pub_broad_ends,pub_pointed_ends;
    wire [12:0] live_first4={1'b0,round_first,2'b0};
    wire [12:0] live_last4={1'b0,round_last,2'b0};
    wire [12:0] live_max3=({3'b0,round_max}<<1)+{3'b0,round_max};
    wire [11:0] live_end_sum={2'b0,round_first}+{2'b0,round_last};
    wire live_round_ends=(live_first4<=live_max3)&&(live_last4<=live_max3);
    wire live_broad_ends=(live_first4>=live_max3)&&(live_last4>=live_max3);
    wire live_pointed_ends=((live_end_sum<<1)<=({2'b0,round_max}+12'd2));
    reg [7:0] peak_first,peak_last;
    // Store only the consumed span in snapshots. Eleven bits preserve the
    // original modular arithmetic even for reversed/wrapped row endpoints.
    wire [10:0] live_peak_span={3'b0,peak_last}-{3'b0,peak_first}+11'd1;
    reg [10:0] best_peak_span,pub_peak_span;
    wire [10:0] peak_span=pub_peak_span;
    wire [9:0] published_width={1'b0,pub_xmax}-{1'b0,pub_xmin}+10'd1;
    wire [8:0] published_height={1'b0,pub_ymax}-{1'b0,pub_ymin}+9'd1;
    reg [18:0] area;
    (* dsp_style="yes" *) wire [18:0] area_product=published_width*published_height;
    reg [9:0] width,height;
    // The shape test is performed on the published component, not the
    // working-frame accumulator (which is cleared at frame boundary).
    // Cancel the common factor 10 in the 30%..70% fill comparisons.
    // Exact integer inequalities; extend BEFORE all shifts/additions.
    wire [21:0] count_ext={5'b0,pub_count},area_ext={3'b0,area};
    wire [21:0] count10=(count_ext<<3)+(count_ext<<1);
    wire [21:0] area3=(area_ext<<1)+area_ext;
    wire [21:0] area7=(area_ext<<3)-area_ext;
    wire [11:0] w={2'b0,width},h={2'b0,height};
    wire bbox_ok=(width<10'd300)&&(height<10'd170);
    wire [11:0] w3=(w<<1)+w,h3=(h<<1)+h;
    // Current red/blue classes accept compact regular colour regions.
    // Widen before scaling; w/h are <=1023, so 4*max fits twelve bits.
    // Keep the unused legacy SHAPE=1 triangle contract unchanged.
    wire ratio_ok=(SHAPE==1) ? ((w<=h*12'd2)&&(h<=w*12'd3)) :
                  ((w<=(h<<2))&&(h<=(w<<2)));
    // Isolated candidate V1: coarse silhouette only, no new image RAM.
    wire [21:0] count16=count_ext<<4;
    wire [21:0] area11=(area_ext<<3)+(area_ext<<1)+area_ext;
    wire [21:0] area15=(area_ext<<4)-area_ext;
    wire [21:0] area14=(area_ext<<4)-(area_ext<<1);
    wire [10:0] changes={3'b0,pub_profile_rises}+{3'b0,pub_profile_falls};
    wire [9:0] short_side=(width<height)?width:height;
    wire round_ends=pub_round_ends;
    wire [11:0] flat8={1'b0,pub_profile_rises,3'b0};
    wire [11:0] rows5=({4'b0,pub_profile_rows}<<2)+{4'b0,pub_profile_rows};
    wire [11:0] rows6=({4'b0,pub_profile_rows}<<2)+({4'b0,pub_profile_rows}<<1);
    wire round_changes=((peak_span<<1)<=({1'b0,height}+11'd2));
    wire broad_ends=pub_broad_ends;
    wire pointed_ends=pub_pointed_ends;
    wire plateau_ok=(short_side<12)?(broad_ends&&count16>=area14):
        (((peak_span<<3)>=(({1'b0,height}<<2)+{1'b0,height}))||
         (((peak_span<<1)>={1'b0,height})&&pointed_ends));
    wire rectangular_profile=plateau_ok&&(height>=5);
    function near8;
      input [8:0] a,b;
      reg signed [9:0] delta;
      begin
        delta=$signed({1'b0,a})-$signed({1'b0,b});
        near8=(~|delta[9:3]) || (&delta[9:3]) || (delta==10'sd8);
      end
    endfunction
    wire tracking_near=valid && near8(pub_xmin,out_xmin) &&
        near8({1'b0,pub_ymin},{1'b0,out_ymin}) &&
        near8(pub_xmax,out_xmax) && near8({1'b0,pub_ymax},{1'b0,out_ymax});
    wire [21:0] area9=(area_ext<<3)+area_ext;
    wire fill_ok=(SHAPE==1)?((count10>=area3)&&(count10<=area7)):
                 (SHAPE==0)?((count16>=(tracking_near?area9:area11))&&(count16<area14)):
                 (count16>=(tracking_near?area9:area11));
    wire profile_ok=(SHAPE==1)?((pub_profile_rows>=4)&&(pub_profile_rises>=2)&&
        ({1'b0,pub_profile_falls}<={1'b0,pub_profile_rises}+9'd1)):
        (SHAPE==0)?(round_ends&&round_changes):
        rectangular_profile;
    wire dimensions_ok=(width>=MIN_WIDTH) && (width<=MAX_WIDTH) &&
                       (height>=MIN_HEIGHT) && (height<=MAX_HEIGHT);
    wire bounds_ok=(pub_xmin<=pub_xmax)&&(pub_ymin<=pub_ymax)&&
                   (pub_xmax<GRID_WIDTH)&&(pub_ymax<GRID_HEIGHT);
    wire shape_ok=bbox_ok && ratio_ok && fill_ok;
    // Widen before scaling: 8*seed >= support implements a 1/8 fraction
    // without a divider/DSP. Only seeds belonging to the selected row runs
    // contribute; unrelated strong-colour noise cannot qualify a weak blob.
    wire comp_seed_ok=(REQUIRE_SEED==0) ||
        ((comp_seed_count>=MIN_STRONG_PIXELS) &&
         ({comp_seed_count,{SEED_RATIO_SHIFT{1'b0}}} >=
          {{SEED_RATIO_SHIFT{1'b0}},comp_count}));
    wire pub_seed_ok=(REQUIRE_SEED==0) ||
        ((pub_seed_count>=MIN_STRONG_PIXELS) &&
         ({pub_seed_count,{SEED_RATIO_SHIFT{1'b0}}} >=
          {{SEED_RATIO_SHIFT{1'b0}},pub_count}));
    // Reject unseeded candidates BEFORE best-component selection, so a
    // larger weak-only region on other rows cannot hide a smaller target.
    wire select_current=comp_seed_ok && (comp_count>best_count);
    // Relax geometry only; seed qualification and publication timing remain unchanged.
    wire candidate_ok=pub_seed_ok && ((SHAPE==0) ? (pub_count>=MIN_PIXELS && dimensions_ok && bounds_ok && ratio_ok && fill_ok && profile_ok) :
                      (pub_count>=MIN_PIXELS && width>=MIN_SIDE &&
                       height>=MIN_SIDE && shape_ok && profile_ok));
    localparam integer CONFIRM_WIDTH=(CONFIRM_FRAMES<2)?1:$clog2(CONFIRM_FRAMES+1);
    reg [CONFIRM_WIDTH-1:0] confirm_count,miss_count;
    wire run_continue=run_active && (x==run_end+9'd1);
    wire cur_run_valid=run_active && (run_len>=10'd2);
    wire selected_row_valid=cur_run_valid || row_best_active;
    wire [8:0] selected_row_start=(cur_run_valid &&
                         (!row_best_active || run_len>=row_best_len)) ? run_start : row_best_start;
    wire [8:0] selected_row_end=(cur_run_valid &&
                         (!row_best_active || run_len>=row_best_len)) ? run_end : row_best_end;
    wire [ROW_COUNT_BITS-1:0] selected_row_len=(cur_run_valid &&
                         (!row_best_active || run_len>=row_best_len)) ? run_len : row_best_len;
    wire [ROW_COUNT_BITS-1:0] selected_row_seed_count=(cur_run_valid &&
                         (!row_best_active || run_len>=row_best_len)) ? run_seed_count : row_best_seed_count;
    wire run_overlap=prev_valid && (run_end+9'd1>=prev_start) &&
                      (run_start<=prev_end+9'd1);

    always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        reference_width<=0;reference_height<=0;lead_x<=0;lead_y<=0;
        run_active<=0;run_start<=0;run_end<=0;run_len<=0;
        run_seed_count<=0;row_best_seed_count<=0;
        row_best_active<=0;row_best_start<=0;row_best_end<=0;row_best_len<=0;
        prev_start<=0;prev_end<=0;prev_valid<=0;
        comp_count<=0;comp_xmin<=0;comp_xmax<=0;comp_ymin<=0;comp_ymax<=0;
        comp_seed_count<=0;best_seed_count<=0;pub_seed_count<=0;
        best_count<=0;best_xmin<=0;best_xmax<=0;best_ymin<=0;best_ymax<=0;
        best_profile_rows<=0;best_profile_rises<=0;best_profile_falls<=0;
        phase<=0;area<=0;width<=0;height<=0;valid<=0;update<=0;frame_good<=0;
        pub_count<=0;pub_xmin<=0;pub_xmax<=0;pub_ymin<=0;pub_ymax<=0;
        profile_rows<=0;profile_rises<=0;profile_falls<=0;
        pub_profile_rows<=0;pub_profile_rises<=0;pub_profile_falls<=0;
        profile_prev_width<=0;profile_have_width<=0;
        round_first<=0;round_last<=0;round_max<=0;
        peak_first<=0;peak_last<=0;best_peak_span<=11'd1;pub_peak_span<=11'd1;
        // All zero widths satisfy the original three predicates.
        best_round_ends<=1;best_broad_ends<=1;best_pointed_ends<=1;
        pub_round_ends<=1;pub_broad_ends<=1;pub_pointed_ends<=1;
        confirm_count<=0;miss_count<=0;
        out_xmin<=0;out_xmax<=0;out_ymin<=0;out_ymax<=0;
      end else begin
        update<=0;
        if(!enable || boundary) frame_good<=0;
        if(!enable) begin
          reference_width<=0;reference_height<=0;lead_x<=0;lead_y<=0;
          run_active<=0;prev_valid<=0;comp_count<=0;best_count<=0;
          run_seed_count<=0;row_best_seed_count<=0;comp_seed_count<=0;best_seed_count<=0;pub_seed_count<=0;
          row_best_active<=0;row_best_len<=0;
          profile_rows<=0;profile_rises<=0;profile_falls<=0;
          profile_have_width<=0;
          phase<=0;valid<=0;confirm_count<=0;miss_count<=0;
        end else if(boundary) begin
          // Publish the largest seed-qualified component from the frame.
          // Green preserves its original invalid-at-boundary behavior.
          // Red commits coordinates only with an accepted candidate below.
          if(SHAPE==1) valid<=0;
          pub_count<=select_current ? comp_count : best_count;
          pub_seed_count<=select_current ? comp_seed_count : best_seed_count;
          pub_xmin<=select_current ? comp_xmin : best_xmin;
          pub_xmax<=select_current ? comp_xmax : best_xmax;
          pub_ymin<=select_current ? comp_ymin : best_ymin;
          pub_ymax<=select_current ? comp_ymax : best_ymax;
          pub_profile_rows<=select_current ? profile_rows : best_profile_rows;
          pub_profile_rises<=select_current ? profile_rises : best_profile_rises;
          pub_profile_falls<=select_current ? profile_falls : best_profile_falls;
          if(SHAPE==0 || SHAPE==2) begin
            pub_peak_span<=select_current ? live_peak_span : best_peak_span;
            pub_round_ends<=select_current ? live_round_ends : best_round_ends;
            pub_broad_ends<=select_current ? live_broad_ends : best_broad_ends;
            pub_pointed_ends<=select_current ? live_pointed_ends : best_pointed_ends;
          end
          // Empty red frames must also reach phase 2 to count a miss.
          phase<=((SHAPE==0 || SHAPE==2) || select_current || best_count!=0) ? 1 : 0;
          if(SHAPE==1 && (!SEPARATE_CONFIRM || confirm_enable)) begin
            out_xmin<=select_current ? comp_xmin : best_xmin;
            out_xmax<=select_current ? comp_xmax : best_xmax;
            out_ymin<=select_current ? comp_ymin : best_ymin;
            out_ymax<=select_current ? comp_ymax : best_ymax;
          end
          run_active<=0;prev_valid<=0;comp_count<=0;best_count<=0;
          run_seed_count<=0;row_best_seed_count<=0;comp_seed_count<=0;best_seed_count<=0;
          row_best_active<=0;row_best_len<=0;
          profile_rows<=0;profile_rises<=0;profile_falls<=0;
          profile_have_width<=0;
        end else begin
          if(sample && hit) begin
            if(run_continue) begin
              run_end<=x;run_len<=run_len+1'b1;
              run_seed_count<=run_seed_count+{9'b0,strong_hit};
            end
            else begin
              // Retain the longest completed run in this logical row.
              if(run_active && run_len>=2 &&
                 (!row_best_active || run_len>row_best_len)) begin
                row_best_active<=1'b1;
                row_best_start<=run_start;
                row_best_end<=run_end;
                row_best_len<=run_len;
                row_best_seed_count<=run_seed_count;
              end
              run_active<=1;run_start<=x;run_end<=x;run_len<=1;
              run_seed_count<={9'b0,strong_hit};
            end
          end
          if(line_end) begin
            if(selected_row_valid) begin
              // Compare the selected row against the previous row, not a
              // discarded short/noise run.
              if(prev_valid && (selected_row_end+9'd1>=prev_start) &&
                 (selected_row_start<=prev_end+9'd1)) begin
                comp_count<=comp_count+selected_row_len;
                comp_seed_count<=comp_seed_count+selected_row_seed_count;
                if(selected_row_start<comp_xmin) comp_xmin<=selected_row_start;
                if(selected_row_end>comp_xmax) comp_xmax<=selected_row_end;
                comp_ymax<=y;
                if(SHAPE==0 || SHAPE==2) begin
                  round_last<=selected_row_len;
                  if(SHAPE==2 && profile_rows==1)round_first<=selected_row_len;
                  if(selected_row_len>round_max) begin
                    round_max<=selected_row_len;
                    if({1'b0,selected_row_len}>{1'b0,round_max}+11'd1)peak_first<=y;
                    peak_last<=y;
                  end else if({1'b0,selected_row_len}+11'd1>={1'b0,round_max})peak_last<=y;
                end
                begin
                  if(profile_have_width) begin
                    if(SHAPE==0 || SHAPE==2) begin
                      if(({1'b0,selected_row_len}<={1'b0,profile_prev_width}+11'd1)&&
                         ({1'b0,profile_prev_width}<={1'b0,selected_row_len}+11'd1))
                        profile_rises<=profile_rises+1'b1;
                    end else begin
                      if(selected_row_len>profile_prev_width)profile_rises<=profile_rises+1'b1;
                      else if(selected_row_len<profile_prev_width)profile_falls<=profile_falls+1'b1;
                    end
                  end
                  profile_prev_width<=selected_row_len;
                  profile_have_width<=1'b1;
                  profile_rows<=profile_rows+1'b1;
                end
              end else begin
                if(select_current) begin
                  best_count<=comp_count;best_xmin<=comp_xmin;best_xmax<=comp_xmax;
                  best_seed_count<=comp_seed_count;
                  best_ymin<=comp_ymin;best_ymax<=comp_ymax;
                  best_profile_rows<=profile_rows;
                  best_profile_rises<=profile_rises;
                  best_profile_falls<=profile_falls;
                  if(SHAPE==0 || SHAPE==2) begin
                    best_peak_span<=live_peak_span;
                    best_round_ends<=live_round_ends;
                    best_broad_ends<=live_broad_ends;
                    best_pointed_ends<=live_pointed_ends;
                  end
                end
                comp_count<=selected_row_len;comp_xmin<=selected_row_start;comp_xmax<=selected_row_end;
                comp_seed_count<=selected_row_seed_count;
                comp_ymin<=y;comp_ymax<=y;
                if(SHAPE==0 || SHAPE==2) begin
                  round_first<=selected_row_len;round_last<=selected_row_len;
                  round_max<=selected_row_len;peak_first<=y;peak_last<=y;
                end
                profile_rows<=1;
                profile_rises<=0;profile_falls<=0;
                profile_prev_width<=selected_row_len;
                profile_have_width<=1'b1;
              end
              prev_start<=selected_row_start;prev_end<=selected_row_end;prev_valid<=1;
            end else begin
              prev_valid<=0;
            end
            run_active<=0;run_len<=0;
            run_seed_count<=0;row_best_seed_count<=0;
            row_best_active<=0;row_best_len<=0;
          end
          if(phase==1) begin
            // One small correction is captured in the existing phase1 slot.
            // Frame width/height reference is seeded only before confirmation.
            if(SHAPE==0 || SHAPE==2)begin
              if(!valid)begin
                reference_width<=published_width[8:0];
                reference_height<=published_height[7:0];
              end
              if(tracking_near && published_width>{1'b0,reference_width}+10'd1 &&
                 pub_xmin>=2 && pub_xmax<GRID_WIDTH-2)
                lead_x<=clipped_half_step(delta_sum_x);
              else lead_x<=0;
              if(tracking_near && published_height>{1'b0,reference_height}+9'd1 &&
                 pub_ymin>=2 && pub_ymax<GRID_HEIGHT-2)
                lead_y<=clipped_half_step({delta_sum_y[9],delta_sum_y});
              else lead_y<=0;
            end else begin lead_x<=0;lead_y<=0;end
            area<=area_product;
            width<=pub_xmax-pub_xmin+1;
            height<=pub_ymax-pub_ymin+1;
            phase<=2;
          end
          else if(phase==2) begin
            frame_good<=candidate_ok;
            if(SHAPE==1) begin
              valid<=candidate_ok;
            end else if(candidate_ok) begin
              miss_count<=0;
              if(confirm_count<CONFIRM_FRAMES) confirm_count<=confirm_count+1'b1;
              if(confirm_count>=CONFIRM_FRAMES-1) valid<=1'b1;
              if(!SEPARATE_CONFIRM || confirm_enable) begin
                out_xmin<=pub_xmin;out_xmax<=pub_xmax;
                out_ymin<=pub_ymin;out_ymax<=pub_ymax;
              end
            end else begin
              // Final SIM candidate: current observation is required for output valid.
              // Keep confidence for <=2 empty frames solely to permit prompt real reacquisition.
              valid<=0;
              if(pub_seed_ok && pub_count>=MIN_PIXELS) begin
                valid<=0;confirm_count<=0;miss_count<=2;
              end else if(miss_count>=2) begin
                valid<=0;confirm_count<=0;
              end else miss_count<=miss_count+1'b1;
            end
            update<=1;phase<=0;
          end
        end
        // Shared spatial work continues in the background. Each consumer
        // owns its confirmation history; disabling control must clear only
        // that history, without throwing away the displayed-frame candidate.
        if(SEPARATE_CONFIRM && !confirm_enable) begin
          lead_x<=0;lead_y<=0;
          valid<=0;confirm_count<=0;miss_count<=0;
        end
      end
    end
endmodule

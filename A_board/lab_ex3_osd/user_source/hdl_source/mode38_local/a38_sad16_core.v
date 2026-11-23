`include "fpga_a_public_tuning.vh"
// CSI focus-first SAD; five data ERAMs plus one coefficient ROM / six hard add-sub paths.
// 16x16 samples. Scale +/-1/16 and angle +/-5deg around the last accepted pose.
// No new external interface; nominal center remains best_x/y * 4 + 64 pixels.
module a38_sad16_core #(
    parameter [17:0] MAX_SAD=`FPGA_A_SAD_MAX, MIN_GAP=`FPGA_A_SAD_MIN_GAP,
    parameter [7:0] MIN_TEXTURE=`FPGA_A_SAD_MIN_TEXTURE,
    parameter integer COVERAGE_ENABLE=1, EDGE_ENABLE=0
)(
    input wire clk,rst_n,cancel,
    input wire job_commit,job_abort,
    input wire feature_we,input wire [11:0] feature_address,
    input wire [15:0] feature_data,
    input wire start,initialize,input wire [5:0] init_x,init_y,
    // Isolated prototype: idle-only template CSR, no additional array.
    input wire host_req,input wire [1:0] host_op,input wire [7:0] host_addr,
    input wire [31:0] host_wdata,output wire host_ready,
    output reg host_ack,host_error,output reg [31:0] host_rdata,
    input wire search_window,freeze_learning,
    // Private capture/core interface; no top-level or SD protocol change.
    input wire recovery_probe,recovery_reset,
    output wire recovery_pending,
    output wire busy,output reg done,initialized,valid,
    output reg [5:0] best_x,best_y,
    output reg [17:0] best_score,second_score,
    output reg [31:0] cycles
);
    localparam IDLE=0,COEF_INIT=1,COEF_MUL=2,COEF_SAVE=3,COEF_SPAN=4,
        OP_START=5,INIT=6,MEAN=7,SCORE=8,ADAPT=9,OP_DONE=10,FLUSH=11,
        GLOBAL_SETUP=12,GLOBAL_NEXT=13,SCAN_PREP=14,SCAN=15,GLOBAL_DECIDE=16,
        LOCAL_SETUP=17,LOCAL_POSE=18,LOCAL_NEXT=19,LOCAL_FINISH=20,CHECK=21,
        RETRY=22,ACCEPT=23,UPDATE_SETUP=24,COPY=25,COPY_WAIT=26,FINISH=27,
        LOCAL_PREP=28,GUARD_PROPOSAL=29,GUARD_PRIOR=30,
        WAIT_COMMIT=31,VERIFY_ALT=32,VERIFY_DECIDE=33,EDGE_FINISH=34,EDGE_MIX=35;
    localparam HOST_READ_A=36,HOST_READ_B=37,HOST_WRITE_A=38,
        HOST_WRITE_B=39,HOST_WRITE_C=40,HOST_FLUSH=41;
    reg [6:0] host_word_addr;reg [15:0] host_word;
    reg [1:0] host_drain;reg [7:0] restore_count;reg restore_meta;
    localparam [17:0] LIMIT=18'h3ffff;
    localparam [9:0] ANCHOR_BASE=10'd768,BACKUP_BASE=10'd896;
    reg [5:0] state,coef_return,flush_return;
    reg [3:0] operation_mode;
    reg [3:0] operation_reason;
    reg focus_mode;
    reg weak_focus;
    reg [7:0] center_min,center_max;
    wire wide_focus=COVERAGE_ENABLE && weak_focus;
    wire edge_active=EDGE_ENABLE && wide_focus;
    reg signed [13:0] step3_u,step3_v,step5_u,step5_v;
    reg [5:0] edge_pipe;
    reg [6:0] edge_group0,edge_group1;
    reg [17:0] edge_previous_row,edge_accumulator;
    reg [8:0] edge_previous_h;
    reg [21:0] edge_centered;
    reg [15:0] template_hold;
    wire edge_raw_slot=edge_active && state==SCORE && edge_pipe[1];
    wire edge_abs_slot=edge_active && edge_pipe[3];
    wire edge_acc_slot=edge_active && edge_pipe[5];
    assign busy=state!=IDLE;
    (* ram_style="bram" *) reg [15:0] patch_mem[0:3199];
    (* ram_style="bram" *) reg [17:0] work_mem[0:1023];
    reg [15:0] patch_q;
    reg [17:0] work_q;
    reg write_en,patch_we_half,work_we_half;
    reg [9:0] write_addr,work_addr_half;
    reg [11:0] patch_addr_half;
    reg [15:0] patch_data_half;
    reg [17:0] write_data,work_data_half;
    // Local reset qualification cuts the global reset's 2589-load data net.
    // Writes still have the original reset/cancel guard at the RAM edge.
    (* syn_preserve="true", syn_keep="true" *) reg memory_run;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)memory_run<=1'b0;
        else memory_run<=1'b1;
    always @(negedge clk)begin
        patch_we_half<=memory_run && !cancel && !job_abort && feature_we && !busy && feature_address<3200;
        patch_addr_half<=feature_address;patch_data_half<=feature_data;
        work_we_half<=memory_run && !cancel && !job_abort && write_en;
        work_addr_half<=write_addr;work_data_half<=write_data;
    end
    reg [6:0] scale_q,pose_scale,global_scale,local_base_scale,best_scale;
    reg [3:0] angle_q,pose_angle,best_angle;
    reg [6:0] anchor_scale;
    reg [3:0] anchor_angle;
    function [6:0] scale_option;
        input [6:0] value;input [1:0] choice;
        reg [7:0] delta,next_value;
        begin
            delta=({1'b0,value}+8'd8)>>4;
            case(choice)
                1:begin next_value={1'b0,value}-delta;scale_option=next_value<32?7'd32:next_value[6:0];end
                2:begin next_value={1'b0,value}+delta;scale_option=next_value>112?7'd112:next_value[6:0];end
                default:scale_option=value;
            endcase
        end
    endfunction
    function [3:0] angle_option;
        input [3:0] value;input [1:0] choice;
        begin case(choice)
            1:angle_option=value==0?4'd0:value-1'b1;
            2:angle_option=value==12?4'd12:value+1'b1;
            default:angle_option=value;
        endcase end
    endfunction
    function [8:0] cosine;
        input [3:0] angle;
        begin case(angle)
            0,12:cosine=222;1,11:cosine=232;2,10:cosine=241;
            3,9:cosine=247;4,8:cosine=252;5,7:cosine=255;default:cosine=256;
        endcase end
    endfunction
    function [7:0] sine_magnitude;
        input [3:0] angle;
        begin case(angle)
            0,12:sine_magnitude=128;1,11:sine_magnitude=108;2,10:sine_magnitude=88;
            3,9:sine_magnitude=66;4,8:sine_magnitude=44;5,7:sine_magnitude=22;default:sine_magnitude=0;
        endcase end
    endfunction
    // Store exact final signed steps, not compressed coefficients.
    // 1024x29 fits two 1024x18 blocks (one more than the old ROM).
    // All multiplication/division below is elaboration-only.
    function [28:0] coefficient_cell;
        input integer index;
        integer angle,scale_value,c,s,deficit,positive_v,negative_tie,u,v;
        begin
            angle=index/128;if(angle>6)angle=6;scale_value=index%128;
            c=cosine(angle[3:0]);s=sine_magnitude(angle[3:0]);
            deficit=(scale_value*(256-c)+15)/32;
            positive_v=(scale_value*s+16)/32;
            negative_tie=((scale_value*s)%32)==16;
            u=scale_value*8-deficit;
            v=-(positive_v-negative_tie);
            coefficient_cell={u[9:0],positive_v[8:0],v[9:0]};
        end
    endfunction
    function [2:0] coefficient_band;
        input [3:0] angle;
        begin case(angle)
            0,12:coefficient_band=0;1,11:coefficient_band=1;
            2,10:coefficient_band=2;3,9:coefficient_band=3;
            4,8:coefficient_band=4;5,7:coefficient_band=5;
            default:coefficient_band=6;
        endcase end
    endfunction
    (* ram_style="bram" *) reg [28:0] coefficient_rom[0:1023];
    integer coefficient_index;
    initial for(coefficient_index=0;coefficient_index<1024;coefficient_index=coefficient_index+1)
        coefficient_rom[coefficient_index]=coefficient_cell(coefficient_index);
    reg [28:0] coefficient_q;
    wire [9:0] coefficient_address={coefficient_band(pose_angle),pose_scale};
    // Same registered read and original seven COEF_MUL clocks.
    always @(posedge clk)coefficient_q<=coefficient_rom[coefficient_address];
    reg [2:0] multiply_count;
    reg signed [10:0] step_u;
    reg signed [9:0] step_v;
    reg signed [14:0] span_x,span_y;
    reg signed [15:0] sample_x,sample_y,row_x,row_y;
    reg [5:0] candidate_x,candidate_y,prior_x,prior_y;
    reg [8:0] issue_count;
    wire issue=(state==INIT || state==MEAN || state==SCORE || state==ADAPT) &&
        issue_count<(focus_mode?9'd64:9'd256);
    wire [3:0] focus_row=wide_focus?({issue_count[5:3],1'b0}+{3'd0,issue_count[5]}):({1'b0,issue_count[5:3]}+4'd4);
    wire [2:0] focus_pair=wide_focus?({issue_count[2:1],1'b0}+{2'd0,issue_count[2]}):({1'b0,issue_count[2:1]}+3'd2);
    wire signed [15:0] rounded_x=sample_x+16'sd128,rounded_y=sample_y+16'sd128;
    // Select step operands BEFORE the coordinate arithmetic. The row
    // transition and horizontal advance each use one add/sub pair, instead
    // of independent arithmetic results for every 1/2/3/5-step branch.
    wire compact_wide=focus_mode && wide_focus;
    wire compact_row_end=focus_mode ? issue_count[2:0]==7 : issue_count[3:0]==15;
    wire signed [15:0] compact_u={{5{step_u[10]}},step_u};
    wire signed [15:0] compact_v={{6{step_v[9]}},step_v};
    wire signed [15:0] compact_3u={{2{step3_u[13]}},step3_u};
    wire signed [15:0] compact_3v={{2{step3_v[13]}},step3_v};
    wire signed [15:0] compact_5u={{2{step5_u[13]}},step5_u};
    wire signed [15:0] compact_5v={{2{step5_v[13]}},step5_v};
    wire signed [15:0] compact_row_step_u=compact_wide ?
        (issue_count[5:3]==3 ? compact_3u : (compact_u<<<1)) : compact_u;
    wire signed [15:0] compact_row_step_v=compact_wide ?
        (issue_count[5:3]==3 ? compact_3v : (compact_v<<<1)) : compact_v;
    wire signed [15:0] compact_pixel_step_u=(compact_wide && issue_count[0]) ?
        (issue_count[2:1]==1 ? compact_5u : compact_3u) : compact_u;
    wire signed [15:0] compact_pixel_step_v=(compact_wide && issue_count[0]) ?
        (issue_count[2:1]==1 ? compact_5v : compact_3v) : compact_v;
    wire signed [15:0] compact_next_row_x=row_x-compact_row_step_v;
    wire signed [15:0] compact_next_row_y=row_y+compact_row_step_u;
    wire signed [15:0] compact_next_pixel_x=sample_x+compact_pixel_step_u;
    wire signed [15:0] compact_next_pixel_y=sample_y+compact_pixel_step_v;

    // Pose preparation is infrequent. Share a 15-bit carry operation across
    // 3u/3v/5u/5v and the two spans. All truncation stays at the old widths.
    // multiply_count is idle here and is reused; no new state counter.
    reg signed [14:0] compact_prep_a,compact_prep_b;
    reg compact_prep_sub;
    wire signed [14:0] compact_prep_u={{4{step_u[10]}},step_u};
    wire signed [14:0] compact_prep_v={{5{step_v[9]}},step_v};
    always @*begin
        compact_prep_a=compact_prep_u;compact_prep_b=compact_prep_v;compact_prep_sub=0;
        case(multiply_count)
            0:begin compact_prep_a=compact_prep_u<<<1;compact_prep_b=compact_prep_u;end
            1:begin compact_prep_a=compact_prep_v<<<1;compact_prep_b=compact_prep_v;end
            2:begin compact_prep_a=compact_prep_u<<<2;compact_prep_b=compact_prep_u;end
            3:begin compact_prep_a=compact_prep_v<<<2;compact_prep_b=compact_prep_v;end
            4:compact_prep_sub=1;
            default:begin end
        endcase
    end
    wire [14:0] compact_prep_sum=compact_prep_a+
        (compact_prep_b^{15{compact_prep_sub}})+{14'd0,compact_prep_sub};

    reg request0,request1,request2,read_valid;
    reg phase0,phase1,phase2,read_phase;
    reg [6:0] group0,group1,group2,read_group;
    reg [7:0] pixel_x0,pixel_y0;
    reg [11:0] row_address1,address2;
    reg [5:0] col_address1;
    reg odd1,odd2,read_odd,bad1,operation_bad;
    reg [7:0] first_pixel_q;
    wire [7:0] first_pixel=first_pixel_q;
    wire [7:0] last_pixel=read_odd?patch_q[15:8]:patch_q[7:0];
    wire [15:0] aligned_word={last_pixel,first_pixel_q};
    wire group_ready=read_valid && read_phase;
    reg [9:0] operation_base;
    reg [7:0] operation_mean,template_mean,backup_mean,anchor_mean;
    reg [7:0] focus_template_mean,focus_backup_mean,focus_anchor_mean;
    reg [13:0] focus_stats,wide_stats;
    wire edge_row_read=edge_active && state==SCORE && request2 && phase2;
    wire template_read=request2 && !phase2 && (state==SCORE || state==ADAPT);
    reg [9:0] scan_issue;
    reg [4:0] scan_x,scan_y;
    reg scan_valid,scan_last;
    reg [5:0] scan_read_x,scan_read_y;
    wire score_read=state==SCAN && scan_issue<625;
    reg [7:0] copy_issue;
    reg copy_valid,copy_restore;
    reg [6:0] copy_index;
    reg [9:0] copy_source,copy_destination;
    wire copy_read=state==COPY && copy_issue<128;
    wire [9:0] work_read_address=state==HOST_READ_A?{3'd0,host_word_addr}:edge_row_read?(10'd753+{7'd0,group2[2:0]}):score_read?10'd128+scan_issue:
        copy_read?copy_source+{3'd0,copy_issue[6:0]}:operation_base+{3'd0,group2};
    always @(posedge clk)begin
        if(rst_n && !cancel && !job_abort && patch_we_half)patch_mem[patch_addr_half]<=patch_data_half;
        if(rst_n && !cancel && !job_abort && work_we_half)work_mem[work_addr_half]<=work_data_half;
        if(request2)patch_q<=patch_mem[address2];
        if(template_read || score_read || copy_read || edge_row_read || state==HOST_READ_A)work_q<=work_mem[work_read_address];
        if(edge_row_read)template_hold<=work_q;
        if(edge_active && state==SCORE && group_ready)edge_previous_row<=work_q;
        if(read_valid && !read_phase)first_pixel_q<=last_pixel;
    end
    reg [17:0] accumulator,stats_acc;
    reg [10:0] bias_code;
    reg weak_update;
    reg [15:0] aligned_patch,aligned_template;
    reg [21:0] difference,centered;
    reg [17:0] absolute_pixels;
    reg [9:0] pair_value;
    wire [53:0] diff_sum,bias_sum,abs_sum,pair_sum,acc_sum,stats_sum;
    // Every 11-bit lane stays positive: no packed-lane borrow/carry leakage.
    a38_dsp_addsub54 difference_dsp(
        .a({32'd0,3'b100,aligned_patch[15:8],3'b100,aligned_patch[7:0]}),
        .b({32'd0,3'b000,aligned_template[15:8],3'b000,aligned_template[7:0]}),
        .subtract(1'b1),.sum(diff_sum));
    a38_dsp_addsub54 bias_dsp(.a({32'd0,difference}),
        .b({32'd0,bias_code,bias_code}),.subtract(1'b1),.sum(bias_sum));
    wire [21:0] abs_input=edge_abs_slot?edge_centered:centered;
    wire [10:0] d0=abs_input[10:0],d1=abs_input[21:11];
    wire [8:0] residual0=difference[8:0],residual1=difference[19:11];
    wire edge_first_pair=focus_mode?(edge_group1[2:0]==(wide_focus?0:2)):(edge_group1[2:0]==0);
    wire edge_first_row=focus_mode?(edge_group1[6:3]==(wide_focus?0:4)):(edge_group1[6:3]==0);
    wire [8:0] horizontal_left=(edge_first_pair?residual1:residual0)^9'h100;
    wire [8:0] horizontal_right=(edge_first_pair?residual0:edge_previous_h)^9'h100;
    wire [8:0] vertical_left=residual0^9'h100;
    wire [8:0] vertical_right=edge_previous_row[8:0]^9'h100;
    wire [21:0] edge_a={edge_first_row?11'd512:{1'b0,1'b1,vertical_left},{1'b0,1'b1,horizontal_left}};
    wire [21:0] edge_b={edge_first_row?11'd0:{2'd0,vertical_right},{2'd0,horizontal_right}};
    a38_dsp_addsub54 absolute_dsp(
        .a({32'd0,(d1[9]?{2'd0,d1[8:0]}:11'd512),(d0[9]?{2'd0,d0[8:0]}:11'd512)}),
        .b({32'd0,(d1[9]?11'd0:d1),(d0[9]?11'd0:d0)}),.subtract(1'b1),.sum(abs_sum));
    a38_dsp_addsub54 pair_dsp(.a({45'd0,absolute_pixels[8:0]}),
        .b({45'd0,absolute_pixels[17:9]}),.subtract(1'b0),.sum(pair_sum));
    reg [15:0] adapted_word;
    reg [7:0] adapted_low;
    // Exact delta correction, one synchronous 512x20 ERAM. Align
    // pixel/phase/group/valid with its read; one extra ADAPT clock.
    wire [7:0] blend_old=read_phase?work_q[15:8]:work_q[7:0];
    wire signed [8:0] blend_delta=$signed({1'b0,last_pixel})-$signed({1'b0,blend_old});
    wire [19:0] correction_word;
    a38_learning_rom learning_rom(.clk(clk),.address(blend_delta),.q(correction_word));
    reg [7:0] blend_old_q;
    reg blend_slow_q,blend_weak_q,blend_valid_q,blend_phase_q;
    reg [6:0] blend_group_q;
    wire signed [8:0] correction=blend_slow_q ? $signed({{4{correction_word[4]}},correction_word[4:0]}) :
        (blend_weak_q ? $signed({{2{correction_word[11]}},correction_word[11:5]}) :
        $signed({correction_word[19],correction_word[19:12]}));
    wire signed [9:0] blended_sum=$signed({2'd0,blend_old_q})+correction;
    wire [7:0] blended_pixel=blended_sum[7:0];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin blend_valid_q<=0;blend_phase_q<=0;blend_group_q<=0;
            blend_old_q<=0;blend_slow_q<=0;blend_weak_q<=0;end
        else begin
            blend_valid_q<=state==ADAPT && read_valid && !cancel && !job_abort;
            blend_phase_q<=read_phase;blend_group_q<=read_group;
            blend_old_q<=blend_old;blend_slow_q<=operation_reason==5;blend_weak_q<=weak_update;
        end
    end
    reg adapted_valid,adapted_last;
    reg [6:0] adapted_group;
    wire [15:0] stats_word=state==ADAPT ? adapted_word : aligned_word;
    wire [8:0] stats_pair={1'b0,stats_word[7:0]}+{1'b0,stats_word[15:8]};
    wire focus_stats_active=state==INIT || state==ADAPT;
    wire [6:0] stats_group=state==ADAPT ? adapted_group : read_group;
    wire stats_in_focus=stats_group[6:3]>=4 && stats_group[6:3]<12 &&
        stats_group[2:0]>=2 && stats_group[2:0]<6;
    wire stats_in_wide=(stats_group[6]==stats_group[3]) && (stats_group[2]==stats_group[0]);
    wire [13:0] wide_increment=stats_in_wide?{5'd0,stats_pair}:14'd0;
    wire [17:0] edge_weighted=focus_mode?edge_accumulator:(edge_accumulator`FPGA_A_EDGE_WEIGHT_SHIFT_EXPR);
    // The cost accumulator is idle during model writes; reuse that DSP
    // for the centre mean instead of adding another arithmetic macro.
    reg [17:0] best_reference,alternative_fast,alternative_reference;
    reg [17:0] pass_best,pass_second,global_best,global_second,fast_cost,proposal_cost;
    reg [18:0] rank_best;
    // Rank arithmetic borrows this DSP only after accumulation has retired.
    // CHECK reuses rank_best for final rank; no extra state or pipeline clock.
    wire rank_slot=(state==OP_DONE && operation_reason==3) ||
        state==CHECK || state==VERIFY_DECIDE;
    wire [17:0] rank_fast_operand=state==CHECK?best_score:
        (state==VERIFY_DECIDE?second_score:fast_cost);
    wire [17:0] rank_reference_operand=state==CHECK?best_reference:
        (state==VERIFY_DECIDE?alternative_reference:accumulator);
    a38_dsp_addsub54 accumulator_dsp(
        .a(rank_slot?`FPGA_A_RANK_FAST_OPERAND:
            {36'd0,(focus_stats_active?{4'd0,focus_stats}:(edge_acc_slot?edge_accumulator:accumulator))}),
        .b(rank_slot?{36'd0,rank_reference_operand}:
            {36'd0,(state==EDGE_MIX?edge_weighted:(focus_stats_active?{9'd0,stats_pair}:{8'd0,pair_value}))}),
        .subtract(1'b0),.sum(acc_sum));
    a38_dsp_addsub54 statistics_dsp(.a((edge_active && state==SCORE)?{32'd0,edge_a}:{22'd0,wide_stats,stats_acc}),
        .b((edge_active && state==SCORE)?{32'd0,edge_b}:{22'd0,wide_increment,9'd0,stats_pair}),
        .subtract(edge_active && state==SCORE),.sum(stats_sum));
    reg [4:0] pipe_valid,pipe_last;
    always @(posedge clk)begin
        if(group_ready)begin aligned_patch<=aligned_word;aligned_template<=edge_active && state==SCORE?template_hold:work_q;end
        if(edge_raw_slot)edge_centered<=stats_sum[21:0];
        difference<=diff_sum[21:0];centered<=bias_sum[21:0];
        absolute_pixels<={abs_sum[19:11],abs_sum[8:0]};pair_value<=pair_sum[9:0];
        if(state==ADAPT && blend_valid_q && !blend_phase_q)adapted_low<=blended_pixel;
        if(state==ADAPT && blend_valid_q && blend_phase_q)begin
            adapted_word<={blended_pixel,adapted_low};
            adapted_group<=blend_group_q;
        end
    end

    reg anchor_pending;
    reg [6:0] anchor_group;
    reg [15:0] anchor_word;
    reg [7:0] texture_min,texture_max;
    wire [7:0] word_min=first_pixel<last_pixel?first_pixel:last_pixel;
    wire [7:0] word_max=first_pixel>last_pixel?first_pixel:last_pixel;
    wire [7:0] next_min=texture_min<word_min?texture_min:word_min;
    wire [7:0] next_max=texture_max>word_max?texture_max:word_max;
    reg [1:0] drain,coarse_choice,local_scale_choice,local_angle_choice,fine_col,fine_row,high_count;
    reg local_center,use_backup,fallback_anchor,backup_ready,pending_valid,fallback_select;
    wire [6:0] recovery_scale=(use_backup && fallback_anchor)?anchor_scale:scale_q;
    wire [3:0] recovery_angle=(use_backup && fallback_anchor)?anchor_angle:angle_q;
    assign recovery_pending=pending_valid;
    reg [5:0] pending_x,pending_y;
    reg [9:0] candidate_index;
    reg [5:0] pass_x,pass_y,global_x,global_y;
    reg [5:0] pass_second_x,pass_second_y,global_second_x,global_second_y;
    wire [18:0] final_rank=rank_best;
    wire [18:0] alternative_rank=(second_score==LIMIT || alternative_reference==LIMIT)?
        19'h7fffe:acc_sum[18:0];
    wire [18:0] rank_gap=(final_rank`FPGA_A_RANK_GAP_SHIFT_EXPR)>`FPGA_A_RANK_GAP_FLOOR ? (final_rank`FPGA_A_RANK_GAP_SHIFT_EXPR) : `FPGA_A_RANK_GAP_FLOOR;
    wire [18:0] pose_rank=(fast_cost==LIMIT || accumulator==LIMIT)?19'h7fffe:
        acc_sum[18:0];
    // Full encoded coordinates are0..63: one signed7-bit difference
    // preserves -63..63. Only fixed range predicates are needed, not abs().
    function near2;input signed [6:0] d;
        begin near2=!(|d[6:1]) || (&d[6:1]) || d==7'sd2;end
    endfunction
    function near4;input signed [6:0] d;
        begin near4=!(|d[6:2]) || (&d[6:2]) || d==7'sd4;end
    endfunction
    function near7;input signed [6:0] d;
        begin near7=!(|d[6:3]) || ((&d[6:3]) && (|d[2:0]));end
    endfunction
    function near24;input signed [6:0] d;
        begin
            // Nonnegative0..24; negative-24..-1. No offset adder.
            near24=d[6] ? ((&d[6:5]) && (|d[4:3])) :
                (!(|d[6:5]) && (!( &d[4:3]) || !(|d[2:0])));
        end
    endfunction
    wire signed [6:0] scan_delta_x=$signed({1'b0,scan_read_x})-$signed({1'b0,pass_x});
    wire signed [6:0] scan_delta_y=$signed({1'b0,scan_read_y})-$signed({1'b0,pass_y});
    wire alternative=!near2(scan_delta_x) || !near2(scan_delta_y);
    wire [17:0] gap=(best_score`FPGA_A_GAP_SHIFT_EXPR)>MIN_GAP?(best_score`FPGA_A_GAP_SHIFT_EXPR):MIN_GAP;
    wire [17:0] pass_gap=(pass_best`FPGA_A_GAP_SHIFT_EXPR)>MIN_GAP?(pass_best`FPGA_A_GAP_SHIFT_EXPR):MIN_GAP;
    wire [6:0] fine_x={1'b0,(local_center?prior_x:global_x)}+{5'd0,fine_col}-7'd1;
    wire [6:0] fine_y={1'b0,(local_center?prior_y:global_y)}+{5'd0,fine_row}-7'd1;
    wire signed [6:0] prior_delta_x=$signed({1'b0,best_x})-$signed({1'b0,prior_x});
    wire signed [6:0] prior_delta_y=$signed({1'b0,best_y})-$signed({1'b0,prior_y});
    wire signed [6:0] pending_delta_x=$signed({1'b0,best_x})-$signed({1'b0,pending_x});
    wire signed [6:0] pending_delta_y=$signed({1'b0,best_y})-$signed({1'b0,pending_y});
    wire prior_near7=near7(prior_delta_x) && near7(prior_delta_y);
    wire prior_near4=near4(prior_delta_x) && near4(prior_delta_y);
    wire pending_near24=near24(pending_delta_x) && near24(pending_delta_y);
    wire [9:0] selected_base=use_backup?(fallback_anchor?ANCHOR_BASE:BACKUP_BASE):10'd0;
    wire [7:0] selected_mean=use_backup?(fallback_anchor?anchor_mean:backup_mean):template_mean;
    wire [7:0] selected_focus_mean=use_backup?(fallback_anchor?focus_anchor_mean:focus_backup_mean):focus_template_mean;
    wire [9:0] reference_base=use_backup?selected_base:BACKUP_BASE;
    wire [7:0] reference_mean=use_backup?selected_mean:backup_mean;
    assign host_ready=state==IDLE && !start;
    wire [31:0] packed_meta={4'd0,weak_focus,angle_q,scale_q,template_mean,focus_template_mean};
    wire meta_valid=host_wdata[31:28]==0 && host_wdata[26:23]<=12 &&
        host_wdata[22:16]>=32 && host_wdata[22:16]<=112;
    wire inside_search=!search_window ||
        (candidate_x>=4 && candidate_x<=44 && candidate_y>=13 && candidate_y<=35);
    wire [17:0] bounded_cost=inside_search?accumulator:18'h3ffff;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;done<=0;initialized<=0;valid<=0;cycles<=0;focus_mode<=0;host_ack<=0;host_error<=0;host_rdata<=0;host_word_addr<=0;host_word<=0;host_drain<=0;restore_count<=0;restore_meta<=0;
            weak_focus<=0;center_min<=255;center_max<=0;wide_stats<=0;
            step3_u<=0;step3_v<=0;step5_u<=0;step5_v<=0;
            edge_pipe<=0;edge_group0<=0;edge_group1<=0;edge_previous_h<=0;edge_accumulator<=0;
            best_x<=24;best_y<=24;best_score<=LIMIT;second_score<=LIMIT;
            anchor_scale<=64;anchor_angle<=6;scale_q<=64;angle_q<=6;pose_scale<=64;pose_angle<=6;best_scale<=64;best_angle<=6;
            global_scale<=64;local_base_scale<=64;coef_return<=OP_START;operation_mode<=INIT;
            operation_reason<=0;flush_return<=FINISH;operation_base<=0;operation_mean<=0;
            template_mean<=0;backup_mean<=0;anchor_mean<=0;
            focus_template_mean<=0;focus_backup_mean<=0;focus_anchor_mean<=0;focus_stats<=0;
            multiply_count<=0;
            step_u<=512;step_v<=0;span_x<=4096;span_y<=4096;
            sample_x<=0;sample_y<=0;row_x<=0;row_y<=0;
            candidate_x<=24;candidate_y<=24;prior_x<=24;prior_y<=24;issue_count<=0;
            request0<=0;request1<=0;request2<=0;read_valid<=0;
            phase0<=0;phase1<=0;phase2<=0;read_phase<=0;
            group0<=0;group1<=0;group2<=0;read_group<=0;pixel_x0<=0;pixel_y0<=0;
            row_address1<=0;address2<=0;col_address1<=0;odd1<=0;odd2<=0;read_odd<=0;bad1<=0;operation_bad<=0;
            write_en<=0;write_addr<=0;write_data<=0;
            accumulator<=0;stats_acc<=0;bias_code<=512;weak_update<=0;
            pipe_valid<=0;pipe_last<=0;adapted_valid<=0;adapted_last<=0;
            anchor_pending<=0;anchor_group<=0;anchor_word<=0;texture_min<=255;texture_max<=0;
            drain<=0;coarse_choice<=0;local_scale_choice<=0;local_angle_choice<=0;fine_col<=0;fine_row<=0;
            local_center<=0;use_backup<=0;fallback_anchor<=0;backup_ready<=0;pending_valid<=0;fallback_select<=0;
            pending_x<=0;pending_y<=0;high_count<=0;
            candidate_index<=0;pass_x<=0;pass_y<=0;global_x<=24;global_y<=24;
            pass_best<=LIMIT;pass_second<=LIMIT;global_best<=LIMIT;global_second<=LIMIT;
            pass_second_x<=0;pass_second_y<=0;global_second_x<=0;global_second_y<=0;
            best_reference<=LIMIT;alternative_fast<=LIMIT;alternative_reference<=LIMIT;
            fast_cost<=LIMIT;proposal_cost<=LIMIT;rank_best<=19'h7fffe;
            scan_issue<=0;scan_x<=0;scan_y<=0;scan_valid<=0;scan_last<=0;scan_read_x<=0;scan_read_y<=0;
            copy_issue<=0;copy_valid<=0;copy_restore<=0;copy_index<=0;copy_source<=0;copy_destination<=0;
        end else begin
            done<=0;write_en<=0;host_ack<=0;host_error<=0;
            edge_pipe<={edge_pipe[4:0],edge_active && state==SCORE && group_ready};
            if(edge_active && state==SCORE && group_ready)edge_group0<=read_group;
            edge_group1<=edge_group0;
            if(edge_raw_slot)begin
                edge_previous_h<=residual1;
                write_en<=1;write_addr<=10'd753+{7'd0,edge_group1[2:0]};write_data<={residual1,residual0};
            end
            if(edge_acc_slot)edge_accumulator<=acc_sum[17:0];
            request0<=issue;request1<=request0;request2<=request1;read_valid<=request2;
            pipe_valid<={pipe_valid[3:0],state==SCORE && group_ready};
            pipe_last<={pipe_last[3:0],state==SCORE && group_ready && read_group==(focus_mode && !wide_focus?7'd93:7'd127)};
            adapted_valid<=state==ADAPT && blend_valid_q && blend_phase_q;
            adapted_last<=blend_valid_q && blend_phase_q && blend_group_q==127;
            scan_valid<=score_read;copy_valid<=copy_read;
            if(issue)begin
                issue_count<=issue_count+1'b1;pixel_x0<=rounded_x[15:8];pixel_y0<=rounded_y[15:8];
                phase0<=issue_count[0];group0<=focus_mode?{focus_row,focus_pair}:issue_count[7:1];
                if(compact_row_end)begin
                    row_x<=compact_next_row_x;row_y<=compact_next_row_y;
                    sample_x<=compact_next_row_x;sample_y<=compact_next_row_y;
                end else begin sample_x<=compact_next_pixel_x;sample_y<=compact_next_pixel_y;end
            end
            if(request0)begin
                row_address1<=({5'd0,pixel_y0[6:0]}<<5)+({5'd0,pixel_y0[6:0]}<<3);
                col_address1<=pixel_x0[6:1];odd1<=pixel_x0[0];
                bad1<=pixel_x0>=80 || pixel_y0>=80;
                if(pixel_x0>=80 || pixel_y0>=80)operation_bad<=1;
                phase1<=phase0;group1<=group0;
            end
            if(request1)begin address2<=bad1?12'd0:row_address1+{6'd0,col_address1};odd2<=odd1;phase2<=phase1;group2<=group1;end
            if(request2)begin read_odd<=odd2;read_phase<=phase2;read_group<=group2;end
            if(copy_read)begin copy_issue<=copy_issue+1'b1;copy_index<=copy_issue[6:0];end
            if(busy)cycles<=cycles+1'b1;
            if(anchor_pending)begin write_en<=1;write_addr<=ANCHOR_BASE+anchor_group;write_data<={2'd0,anchor_word};anchor_pending<=0;end
            // A malformed tail can revoke speculative SEARCH, never template updates.
            // Capture asserts abort only for an uncommitted acquired frame.
            if(job_abort && !job_commit && !cancel)begin
                state<=IDLE;valid<=0;done<=0;write_en<=0;anchor_pending<=0;
                request0<=0;request1<=0;request2<=0;read_valid<=0;
                pipe_valid<=0;pipe_last<=0;adapted_valid<=0;scan_valid<=0;copy_valid<=0;
                pending_valid<=0;high_count<=0;edge_pipe<=0;edge_accumulator<=0;
            end else if(cancel)begin
                state<=IDLE;initialized<=0;valid<=0;request0<=0;request1<=0;request2<=0;read_valid<=0;
                pipe_valid<=0;pipe_last<=0;adapted_valid<=0;write_en<=0;anchor_pending<=0;
                scan_valid<=0;copy_valid<=0;backup_ready<=0;pending_valid<=0;fallback_select<=0;use_backup<=0;high_count<=0;
                scale_q<=64;angle_q<=6;weak_focus<=0;edge_pipe<=0;edge_accumulator<=0;
            end else case(state)
                IDLE:if(host_req && host_ready)begin
                    case(host_op)
                        0:if(!initialized)begin host_ack<=1;host_error<=1;end
                          else if(host_addr==128)begin host_rdata<=packed_meta;host_ack<=1;end
                          else if(host_addr<128)begin host_word_addr<=host_addr[6:0];state<=HOST_READ_A;end
                          else begin host_ack<=1;host_error<=1;end
                        1:if(host_addr<128 && host_addr==restore_count)begin
                            host_word_addr<=host_addr[6:0];host_word<=host_wdata[15:0];
                            restore_count<=restore_count+1'b1;state<=HOST_WRITE_A;
                          end else if(host_addr==128 && restore_count==128 && meta_valid)begin
                            weak_focus<=host_wdata[27];angle_q<=host_wdata[26:23];scale_q<=host_wdata[22:16];
                            anchor_angle<=host_wdata[26:23];anchor_scale<=host_wdata[22:16];
                            template_mean<=host_wdata[15:8];backup_mean<=host_wdata[15:8];anchor_mean<=host_wdata[15:8];
                            focus_template_mean<=host_wdata[7:0];focus_backup_mean<=host_wdata[7:0];focus_anchor_mean<=host_wdata[7:0];
                            restore_meta<=1;host_ack<=1;
                          end else begin host_ack<=1;host_error<=1;end
                        2:begin
                            initialized<=0;valid<=0;backup_ready<=0;pending_valid<=0;high_count<=0;
                            fallback_select<=0;use_backup<=0;restore_count<=0;restore_meta<=0;host_ack<=1;
                          end
                        3:begin
                            host_ack<=1;
                            if(restore_count==128 && restore_meta)begin initialized<=1;backup_ready<=1;valid<=0;end
                            else begin initialized<=0;host_error<=1;end
                          end
                    endcase
                end else if(start)begin
                    cycles<=0;valid<=0;best_score<=LIMIT;second_score<=LIMIT;
                    prior_x<=init_x;prior_y<=init_y;best_x<=init_x;best_y<=init_y;
                    use_backup<=0;fallback_anchor<=0;coarse_choice<=0;
                    if(recovery_reset)pending_valid<=0;global_best<=LIMIT;global_second<=LIMIT;
                    best_scale<=scale_q;best_angle<=angle_q;
                    if(initialize)begin
                        initialized<=0;backup_ready<=0;pending_valid<=0;fallback_select<=0;high_count<=0;
                        anchor_scale<=64;anchor_angle<=6;scale_q<=64;angle_q<=6;pose_scale<=64;pose_angle<=6;best_scale<=64;best_angle<=6;
                        if(init_x>48 || init_y>48)state<=FINISH;
                        else begin
                            focus_mode<=0;
                            candidate_x<=init_x;candidate_y<=init_y;operation_mode<=INIT;operation_reason<=0;
                            texture_min<=255;texture_max<=0;center_min<=255;center_max<=0;weak_focus<=0;coef_return<=OP_START;state<=COEF_INIT;
                        end
                    end else if(!initialized || init_x>48 || init_y>48)state<=FINISH;
                    else state<=GLOBAL_SETUP;
                end
                HOST_READ_A:state<=HOST_READ_B;
                HOST_READ_B:begin host_rdata<={16'd0,work_q[15:0]};host_ack<=1;state<=IDLE;end
                HOST_WRITE_A:begin write_en<=1;write_addr<={3'd0,host_word_addr};write_data<={2'd0,host_word};state<=HOST_WRITE_B;end
                HOST_WRITE_B:begin write_en<=1;write_addr<=ANCHOR_BASE+host_word_addr;write_data<={2'd0,host_word};state<=HOST_WRITE_C;end
                HOST_WRITE_C:begin write_en<=1;write_addr<=BACKUP_BASE+host_word_addr;write_data<={2'd0,host_word};host_drain<=0;state<=HOST_FLUSH;end
                HOST_FLUSH:if(host_drain==2)begin host_ack<=1;state<=IDLE;end else host_drain<=host_drain+1'b1;
                COEF_INIT:begin
                    multiply_count<=0;state<=COEF_MUL;
                end
                COEF_MUL:begin
                    // Preserve the old coefficient-stage and result cycles.
                    if(multiply_count==6)state<=COEF_SAVE;else multiply_count<=multiply_count+1'b1;
                end
                COEF_SAVE:begin
                    step_u<=$signed({1'b0,coefficient_q[28:19]});
                    step_v<=pose_angle<6?$signed(coefficient_q[9:0]):$signed({1'b0,coefficient_q[18:10]});
                    multiply_count<=0;state<=COEF_SPAN;
                end
                COEF_SPAN:begin
                    case(multiply_count)
                        0:step3_u<=compact_prep_sum[13:0];
                        1:step3_v<=compact_prep_sum[13:0];
                        2:step5_u<=compact_prep_sum[13:0];
                        3:step5_v<=compact_prep_sum[13:0];
                        4:span_x<=compact_prep_sum<<<3;
                        5:span_y<=compact_prep_sum<<<3;
                        default:begin end
                    endcase
                    if(multiply_count==5)state<=coef_return;
                    else multiply_count<=multiply_count+1'b1;
                end
                OP_START:begin
                    sample_x<=$signed({2'd0,candidate_x,8'd0})+16'sd4096-(focus_mode && !wide_focus?(span_x>>>1):span_x);
                    sample_y<=$signed({2'd0,candidate_y,8'd0})+16'sd4096-(focus_mode && !wide_focus?(span_y>>>1):span_y);
                    row_x<=$signed({2'd0,candidate_x,8'd0})+16'sd4096-(focus_mode && !wide_focus?(span_x>>>1):span_x);
                    row_y<=$signed({2'd0,candidate_y,8'd0})+16'sd4096-(focus_mode && !wide_focus?(span_y>>>1):span_y);
                    issue_count<=0;stats_acc<=0;focus_stats<=0;wide_stats<=0;accumulator<=0;operation_bad<=0;edge_pipe<=0;edge_accumulator<=0;
                    request0<=0;request1<=0;request2<=0;read_valid<=0;pipe_valid<=0;pipe_last<=0;adapted_valid<=0;
                    state<=operation_mode;
                end
                INIT:if(group_ready)begin
                    if(stats_in_focus)begin
                        focus_stats<=acc_sum[13:0];
                        if(word_min<center_min)center_min<=word_min;
                        if(word_max>center_max)center_max<=word_max;
                    end
                    wide_stats<=stats_sum[31:18];
                    write_en<=1;write_addr<={3'd0,read_group};write_data<={2'd0,aligned_word};
                    anchor_pending<=1;anchor_group<=read_group;anchor_word<=aligned_word;
                    stats_acc<=stats_sum[17:0];texture_min<=next_min;texture_max<=next_max;
                    if(read_group==127)begin
                        template_mean<=stats_sum[15:8];anchor_mean<=stats_sum[15:8];backup_mean<=stats_sum[15:8];
                        weak_focus<=COVERAGE_ENABLE && center_max-center_min<16;
                        focus_template_mean<=COVERAGE_ENABLE && center_max-center_min<16?stats_sum[31:24]:focus_stats[13:6];
                        focus_anchor_mean<=COVERAGE_ENABLE && center_max-center_min<16?stats_sum[31:24]:focus_stats[13:6];
                        focus_backup_mean<=COVERAGE_ENABLE && center_max-center_min<16?stats_sum[31:24]:focus_stats[13:6];
                        initialized<=!operation_bad && next_max-next_min>=MIN_TEXTURE;
                        valid<=!operation_bad && next_max-next_min>=MIN_TEXTURE;best_score<=0;second_score<=LIMIT;
                        copy_source<=0;copy_destination<=BACKUP_BASE;copy_restore<=0;copy_issue<=0;
                        drain<=0;flush_return<=COPY;state<=FLUSH;
                    end
                end
                MEAN:if(group_ready)begin
                    stats_acc<=stats_sum[17:0];
                    if(read_group==(focus_mode && !wide_focus?7'd93:7'd127))begin
                        bias_code<=11'd512+(focus_mode?{3'd0,stats_sum[13:6]}:{3'd0,stats_sum[15:8]})-{3'd0,operation_mean};
                        operation_mode<=SCORE;state<=OP_START;
                    end
                end
                SCORE:if(pipe_valid[4])begin
                    accumulator<=acc_sum[17:0];
                    if(pipe_last[4])begin
                        if(operation_bad)accumulator<=LIMIT;
                        else if(focus_mode)accumulator<={acc_sum[15:0],2'b0};
                        state<=edge_active?EDGE_FINISH:OP_DONE;
                    end
                end
                EDGE_FINISH:state<=EDGE_MIX;
                EDGE_MIX:begin
                    accumulator<=operation_bad?LIMIT:(acc_sum>=LIMIT?LIMIT:acc_sum[17:0]);
                    state<=OP_DONE;
                end
                OP_DONE:case(operation_reason)
                    1:begin
                        write_en<=1;write_addr<=10'd128+candidate_index;write_data<=bounded_cost;
                        if(bounded_cost<pass_best)begin pass_best<=bounded_cost;pass_x<=candidate_x;pass_y<=candidate_y;end
                        state<=candidate_index==624?SCAN_PREP:GLOBAL_NEXT;
                    end
                    2:begin
                        fast_cost<=accumulator;
                        operation_base<=reference_base;operation_mean<=reference_mean;focus_mode<=0;
                        operation_reason<=3;operation_mode<=MEAN;state<=OP_START;
                    end
                    3:begin
                        if(inside_search && pose_rank<rank_best)begin
                            rank_best<=pose_rank;best_reference<=accumulator;best_score<=fast_cost;best_x<=candidate_x;best_y<=candidate_y;best_scale<=pose_scale;best_angle<=pose_angle;
                        end
                        state<=LOCAL_NEXT;
                    end
                    6:begin proposal_cost<=accumulator;state<=GUARD_PRIOR;end
                    7:begin
                        if(accumulator<=(MAX_SAD`FPGA_A_STRICT_SCORE_SHIFT_EXPR) && {1'b0,proposal_cost}>{1'b0,accumulator}+{1'b0,gap})state<=RETRY;
                        else state<=WAIT_COMMIT;
                    end
                    8:begin
                        alternative_fast<=accumulator;
                        operation_base<=reference_base;operation_mean<=reference_mean;focus_mode<=0;
                        operation_reason<=9;operation_mode<=MEAN;state<=OP_START;
                    end
                    9:begin second_score<=alternative_fast;alternative_reference<=accumulator;state<=VERIFY_DECIDE;end
                    default:state<=FINISH;
                endcase
                GLOBAL_SETUP:begin
                    pose_scale<=scale_option(recovery_scale,coarse_choice);pose_angle<=recovery_angle;
                    candidate_x<=0;candidate_y<=0;candidate_index<=0;pass_best<=LIMIT;pass_second<=LIMIT;pass_x<=0;pass_y<=0;pass_second_x<=0;pass_second_y<=0;
                    operation_base<=selected_base;operation_mean<=selected_focus_mean;focus_mode<=1;operation_reason<=1;operation_mode<=MEAN;
                    coef_return<=OP_START;state<=COEF_INIT;
                end
                GLOBAL_NEXT:begin
                    candidate_index<=candidate_index+1'b1;
                    if(candidate_x==48)begin candidate_x<=0;candidate_y<=candidate_y+6'd2;end else candidate_x<=candidate_x+6'd2;
                    operation_mode<=MEAN;focus_mode<=1;state<=OP_START;
                end
                SCAN_PREP:begin scan_issue<=0;scan_x<=0;scan_y<=0;scan_valid<=0;state<=SCAN;end
                SCAN:begin
                    if(score_read)begin
                        scan_last<=scan_issue==624;scan_read_x<={scan_x,1'b0};scan_read_y<={scan_y,1'b0};scan_issue<=scan_issue+1'b1;
                        if(scan_x==24)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;
                    end
                    if(scan_valid)begin
                        if(alternative && work_q<pass_second)begin pass_second<=work_q;pass_second_x<=scan_read_x;pass_second_y<=scan_read_y;end
                        if(scan_last)state<=GLOBAL_DECIDE;
                    end
                end
                GLOBAL_DECIDE:begin
                    if(pass_best<global_best)begin global_best<=pass_best;global_second<=pass_second;global_x<=pass_x;global_y<=pass_y;global_scale<=pose_scale;global_second_x<=pass_second_x;global_second_y<=pass_second_y;end
                    if(coarse_choice==2 || (coarse_choice==0 && pass_best<=MAX_SAD && {1'b0,pass_second}>{1'b0,pass_best}+{1'b0,pass_gap}))state<=LOCAL_SETUP;
                    else begin coarse_choice<=coarse_choice+1'b1;state<=GLOBAL_SETUP;end
                end
                LOCAL_SETUP:begin
                    local_base_scale<=global_scale;local_center<=0;local_scale_choice<=0;local_angle_choice<=0;
                    rank_best<=19'h7fffe;best_score<=LIMIT;second_score<=global_second;
                    best_x<=global_x;best_y<=global_y;best_scale<=global_scale;best_angle<=recovery_angle;state<=LOCAL_POSE;
                end
                LOCAL_POSE:begin
                    pose_scale<=scale_option(local_base_scale,local_scale_choice);pose_angle<=angle_option(recovery_angle,local_angle_choice);
                    fine_col<=0;fine_row<=0;coef_return<=LOCAL_PREP;state<=COEF_INIT;
                end
                LOCAL_PREP:begin
                    if(fine_x>48 || fine_y>48)state<=LOCAL_NEXT;
                    else begin
                        candidate_x<=fine_x[5:0];candidate_y<=fine_y[5:0];operation_base<=selected_base;operation_mean<=selected_focus_mean;focus_mode<=1;
                        operation_reason<=2;operation_mode<=MEAN;state<=OP_START;
                    end
                end
                LOCAL_NEXT:begin
                    if(fine_col!=2)begin fine_col<=fine_col+1'b1;state<=LOCAL_PREP;end
                    else if(fine_row!=2)begin fine_col<=0;fine_row<=fine_row+1'b1;state<=LOCAL_PREP;end
                    else if(local_angle_choice!=2)begin local_angle_choice<=local_angle_choice+1'b1;state<=LOCAL_POSE;end
                    else if(local_scale_choice!=2)begin local_angle_choice<=0;local_scale_choice<=local_scale_choice+1'b1;state<=LOCAL_POSE;end
                    else if(!local_center)begin local_center<=1;local_scale_choice<=0;local_angle_choice<=0;state<=LOCAL_POSE;end
                    else state<=CHECK;
                end
                CHECK:begin
                    rank_best<=acc_sum[18:0];
                    // A low adaptive-template score alone cannot qualify or train a match.
                    if(best_score<=MAX_SAD && best_reference<=({1'b0,MAX_SAD}`FPGA_A_REFERENCE_LIMIT_SHIFT_EXPR))state<=VERIFY_ALT;
                    else state<=RETRY;
                end
                VERIFY_ALT:begin
                    // Re-score the coarse competing basin at the FINAL pose against
                    // both templates. No comparisons between different scale scores.
                    pose_scale<=best_scale;pose_angle<=best_angle;
                    candidate_x<=global_second_x;candidate_y<=global_second_y;
                    operation_base<=selected_base;operation_mean<=selected_focus_mean;focus_mode<=1;
                    operation_reason<=8;operation_mode<=MEAN;coef_return<=OP_START;state<=COEF_INIT;
                end
                VERIFY_DECIDE:begin
                    if({1'b0,second_score}>{1'b0,best_score}+{1'b0,gap} &&
                       {1'b0,alternative_rank}>{1'b0,final_rank}+{1'b0,rank_gap})begin
                        if(!use_backup && backup_ready && !prior_near7)state<=GUARD_PROPOSAL;
                        else state<=WAIT_COMMIT;
                    end else state<=RETRY;
                end
                WAIT_COMMIT:if(job_commit)state<=ACCEPT;
                GUARD_PROPOSAL:begin
                    pose_scale<=best_scale;pose_angle<=best_angle;candidate_x<=best_x;candidate_y<=best_y;
                    operation_base<=BACKUP_BASE;operation_mean<=focus_backup_mean;focus_mode<=1;operation_reason<=6;operation_mode<=MEAN;
                    coef_return<=OP_START;state<=COEF_INIT;
                end
                GUARD_PRIOR:begin candidate_x<=prior_x;candidate_y<=prior_y;operation_reason<=7;operation_mode<=MEAN;state<=OP_START;end
                RETRY:begin
                    high_count<=0;
                    if(!use_backup)begin
                        use_backup<=1;fallback_anchor<=fallback_select || !backup_ready;
                        coarse_choice<=0;global_best<=LIMIT;global_second<=LIMIT;state<=GLOBAL_SETUP;
                    end else begin valid<=0;pending_valid<=0;fallback_select<=!fallback_select;state<=FINISH;end
                end
                ACCEPT:begin
                    if((use_backup || recovery_probe) && (!pending_valid || !pending_near24))begin
                        valid<=0;pending_valid<=1;pending_x<=best_x;pending_y<=best_y;high_count<=0;state<=FINISH;
                    end else begin
                        valid<=1;pending_valid<=0;fallback_select<=0;scale_q<=best_scale;angle_q<=best_angle;
                        if(use_backup)begin
                            copy_source<=selected_base;copy_destination<=0;copy_restore<=1;copy_issue<=0;high_count<=0;state<=COPY;
                        end else if(freeze_learning)state<=FINISH;
                        else if(best_score<=(MAX_SAD`FPGA_A_STRICT_SCORE_SHIFT_EXPR) && best_reference<=({1'b0,MAX_SAD}+({1'b0,MAX_SAD}`FPGA_A_STRICT_SCORE_SHIFT_EXPR)))begin
                            high_count<=high_count`FPGA_A_BACKUP_PERIOD_COMPARE_EXPR?2'd0:high_count+1'b1;weak_update<=0;state<=UPDATE_SETUP;
                        end else if(best_score<=(MAX_SAD-(MAX_SAD`FPGA_A_WEAK_SCORE_SHIFT_EXPR)) && best_reference<=({1'b0,MAX_SAD}`FPGA_A_REFERENCE_LIMIT_SHIFT_EXPR) && prior_near4)begin
                            high_count<=0;weak_update<=1;state<=UPDATE_SETUP;
                        end else begin high_count<=0;state<=FINISH;end
                    end
                end
                UPDATE_SETUP:begin
                    candidate_x<=best_x;candidate_y<=best_y;pose_scale<=best_scale;pose_angle<=best_angle;
                    operation_base<=0;operation_reason<=4;operation_mode<=ADAPT;focus_mode<=0;coef_return<=OP_START;state<=COEF_INIT;
                end
                ADAPT:if(adapted_valid)begin
                    wide_stats<=stats_sum[31:18];
                    if(stats_in_focus)focus_stats<=acc_sum[13:0];
                    write_en<=1;write_addr<=operation_base+{3'd0,adapted_group};write_data<={2'd0,adapted_word};stats_acc<=stats_sum[17:0];
                    if(adapted_last)begin
                        if(operation_reason==4)begin template_mean<=stats_sum[15:8];focus_template_mean<=wide_focus?stats_sum[31:24]:focus_stats[13:6];end
                        else begin backup_mean<=stats_sum[15:8];focus_backup_mean<=wide_focus?stats_sum[31:24]:focus_stats[13:6];end
                        drain<=0;flush_return<=(!weak_update && operation_reason==4)?LOCAL_FINISH:FINISH;state<=FLUSH;
                    end
                end
                LOCAL_FINISH:begin operation_base<=BACKUP_BASE;operation_reason<=5;operation_mode<=ADAPT;state<=OP_START;end
                FLUSH:begin if(drain==2)state<=flush_return;else drain<=drain+1'b1;end
                COPY:if(copy_valid)begin
                    write_en<=1;write_addr<=copy_destination+{3'd0,copy_index};write_data<=work_q;
                    if(copy_index==127)begin drain<=0;state<=COPY_WAIT;end
                end
                COPY_WAIT:begin
                    if(drain==2)begin
                        if(copy_restore)begin template_mean<=selected_mean;focus_template_mean<=selected_focus_mean;end else backup_ready<=1;
                        state<=FINISH;
                    end else drain<=drain+1'b1;
                end
                FINISH:if(job_commit)begin done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end

endmodule

// No external init file. Negative division is mathematical floor, not Verilog
// truncation toward zero; this preserves the original unsigned blend exactly.
module a38_learning_rom(input wire clk,input wire [8:0] address,output reg [19:0] q);
    (* ram_style="bram" *) reg [19:0] memory[0:511];
    integer i,d,n,strong_value,weak_value,slow_value;
    initial begin
        for(i=0;i<512;i=i+1)begin
            d=i<256?i:i-512;n=`FPGA_A_LEARN_STRONG_NUM_EXPR;
            strong_value=n<0?-((-n+`FPGA_A_LEARN_STRONG_FLOOR_BIAS)/`FPGA_A_LEARN_STRONG_DENOM):n/`FPGA_A_LEARN_STRONG_DENOM;
            weak_value=`FPGA_A_LEARN_WEAK_EXPR;slow_value=`FPGA_A_LEARN_SLOW_EXPR;
            memory[i]={strong_value[7:0],weak_value[6:0],slow_value[4:0]};
        end
    end
    always @(posedge clk)q<=memory[address];
endmodule

// One owned patch, speculative search after its final write, full-raster commit.
// Never stalls ISP. Prediction selects an ROI, never an output measurement.
module a38_sad16_capture #(
    parameter integer H_ACTIVE=1280,V_ACTIVE=720
)(
    input wire clk,rst_n,config_update,input wire [40:0] configuration,
    input wire [15:0] source_frame_id,
    input wire [95:0] rgb,input wire valid,user,last,
    output reg result_update,output reg [53:0] result,
    output reg protocol_error,
    output wire core_busy,
    output reg template_request,template_load,
    input wire template_done,template_error,
    input wire host_req,input wire [1:0] host_op,input wire [7:0] host_addr,input wire [31:0] host_wdata,
    output wire host_ready,host_ack,host_error,output wire [31:0] host_rdata
);
    reg [7:0] epoch,guard_context,job_guard_context;
    reg [15:0] current_source_frame,job_source_frame;
    reg enabled,running;
    reg template_mode,template_record,storage_wait,reset_pending,load_started,template_armed,record_complete,searching,search_hit;
    reg [7:0] storage_epoch;
    wire storage_eligible=!storage_wait && !reset_pending && !host_req &&
        (!template_mode || (template_record ? !record_complete : template_armed));

    reg [10:0] center_x,roi_left,job_left;
    reg [9:0] center_y,roi_top,job_top;
    reg [5:0] job_init_x,job_init_y;
    reg user_d,in_frame,capturing;
    reg [8:0] column;
    reg [9:0] row;
    reg [11:0] word_count,capture_row_base;
    reg [7:0] first_sample;
    reg feature_we,start,initialize;
    reg [11:0] feature_address;
    reg [15:0] feature_data;
    reg job_active,job_started,job_commit,job_abort;
    reg [7:0] frame_seq,job_frame,last_frame;
    reg history_valid,motion_valid;
    reg recovery_misses;
    reg [3:0] recovery_phase,last_probe;
    reg job_probe,job_probe_reset;
    reg signed [8:0] probe_dx,probe_dy;
    // Overlapping local ROIs, never a whole-frame identity detector.
    always @*begin
        probe_dx=0;probe_dy=0;
        // Return to the last measured ROI between neighboring probes.
        // An occluded target may reappear at home while a neighbor is tested.
        case(recovery_phase)
            1:probe_dx=128;
            3:probe_dx=-128;
            5:probe_dy=-128;
            7:probe_dy=128;
            9:begin probe_dx=128;probe_dy=-128;end
            11:begin probe_dx=-128;probe_dy=-128;end
            13:begin probe_dx=128;probe_dy=128;end
            15:begin probe_dx=-128;probe_dy=128;end
            default:begin end
        endcase
    end
    reg signed [5:0] velocity_x,velocity_y;
    reg [10:0] predicted_x;
    reg [9:0] predicted_y;
    wire done,initialized,matched,recovery_pending;
    // A newly acquired object may reverse toward the original position.
    // Search opposite the last successful neighboring probe first; thereafter
    // use the same home-interleaved bounded schedule. No truth input.
    wire [3:0] opposite_probe=last_probe[3]?(last_probe^4'd6):(last_probe^4'd2);
    wire probe_active=recovery_misses && initialized && !searching && !template_record;
    wire [5:0] best_x,best_y;
    wire [17:0] best_score,second_score;
    wire [31:0] core_cycles;
    // Selection epoch/enable/run changes cancel. A guard-only refresh does not.
    // Coordinates may have advanced since the HDMI mailbox was captured.
    wire hard_config=config_update && configuration[30:21]!={epoch,enabled,running};
    wire cancel=(hard_config || !enabled || !running || reset_pending) && !storage_wait;
    a38_sad16_core core(.clk(clk),.rst_n(rst_n),.cancel(cancel),
        .job_commit(job_commit),.job_abort(job_abort),
        .feature_we(feature_we),.feature_address(feature_address),.feature_data(feature_data),
        .start(start),.initialize(initialize),.init_x(job_init_x),.init_y(job_init_y),
        .host_req(host_req),.host_op(host_op),.host_addr(host_addr),.host_wdata(host_wdata),
        .host_ready(host_ready),.host_ack(host_ack),.host_error(host_error),.host_rdata(host_rdata),
        .search_window(searching),.freeze_learning(searching || job_probe),
        .recovery_probe(job_probe),.recovery_reset(job_probe_reset),.recovery_pending(recovery_pending),
        .busy(core_busy),.done(done),.initialized(initialized),.valid(matched),
        .best_x(best_x),.best_y(best_y),.best_score(best_score),.second_score(second_score),.cycles(core_cycles));
    wire new_user=user && !user_d;
    wire early_user=new_user && in_frame;
    wire begin_frame=new_user && !in_frame && enabled && running;
    wire [10:0] next_left=searching ? 11'd480 : predicted_x<160 ? 11'd0 :
        (predicted_x>H_ACTIVE-160 ? H_ACTIVE-320 : predicted_x-11'd160);
    wire [9:0] next_top=searching ? 10'd200 : predicted_y<160 ? 10'd0 :
        (predicted_y>V_ACTIVE-160 ? V_ACTIVE-320 : predicted_y-10'd160);
    wire [10:0] left_now=begin_frame?next_left:roi_left;
    wire [9:0] top_now=begin_frame?next_top:roi_top;
    wire [8:0] col_now=begin_frame?9'd0:column;
    wire [9:0] row_now=begin_frame?10'd0:row;
    wire frame_selected=begin_frame ? (!core_busy && !start && !feature_we && !job_active && storage_eligible) : capturing;
    wire take=valid && (in_frame || begin_frame) && !early_user;
    wire line_end=col_now==H_ACTIVE/4-1;
    wire bad_last=take && last!=line_end;
    wire [8:0] left_beat=left_now[10:2];
    wire [8:0] beat_delta=col_now-left_beat;
    wire [9:0] relative_y=row_now-top_now;
    // At fixed 720p, left_beat<=240 and top_now<=400. Underflow
    // wraps to >=272 (9 bits) / >=624 (10 bits), outside the patch.
    // Preserve explicit bounds for all other parameter configurations.
    wire sample_x=(H_ACTIVE==1280 && V_ACTIVE==720) ?
        beat_delta<80 : (col_now>=left_beat && beat_delta<80);
    wire sample_y=(H_ACTIVE==1280 && V_ACTIVE==720) ?
        (relative_y<320 && relative_y[1:0]==0) :
        (row_now>=top_now && relative_y<320 && relative_y[1:0]==0);
    wire sample=take && frame_selected && !bad_last && sample_x && sample_y;
    reg [23:0] pixel;
    always @*case(left_now[1:0])
        0:pixel=rgb[95:72];1:pixel=rgb[71:48];2:pixel=rgb[47:24];default:pixel=rgb[23:0];
    endcase
    wire [9:0] gray_sum={2'd0,pixel[23:16]}+{1'd0,pixel[15:8],1'b0}+{2'd0,pixel[7:0]};
    wire [7:0] gray=gray_sum[9:2];
    wire [10:0] matched_x=job_left+{3'd0,best_x,2'b00}+11'd64;
    wire [9:0] matched_y=job_top+{2'd0,best_y,2'b00}+10'd64;
    wire [7:0] measured_interval=job_frame-last_frame;
    wire [7:0] predict_interval=frame_seq+(in_frame?8'd0:8'd1)-last_frame;
    wire signed [12:0] measured_dx=$signed({2'd0,matched_x})-$signed({2'd0,center_x});
    wire signed [12:0] measured_dy=$signed({3'd0,matched_y})-$signed({3'd0,center_y});
    function signed [5:0] velocity;
        input signed [12:0] difference;input [7:0] interval;
        reg signed [12:0] value;
        begin
            // Conservative shift-only normalisation. Three-frame intervals
            // divide by four; no variable divider/DSP in the ROI selector.
            case(interval)
                1:value=difference;2:value=difference>>>1;
                3,4:value=difference>>>2;default:value=0;
            endcase
            // Called only for qualified differences[-16,16], interval1..4.
            velocity=value[5:0];
        end
    endfunction
    function signed [6:0] project;
        input signed [5:0] step;input [7:0] interval;
        reg signed [6:0] expanded,value;
        begin
            expanded={step[5],step};
            case(interval)
                1:value=expanded;2:value=expanded<<<1;
                3:value=expanded+(expanded<<<1);default:value=0;
            endcase
            // Qualified six-bit velocity is[-16,16]; at most three frames.
            project=value;
        end
    endfunction
    wire search_close=search_hit && measured_dx>=-13'sd16 && measured_dx<=13'sd16 &&
        measured_dy>=-13'sd16 && measured_dy<=13'sd16;
    wire qualified_match=matched && (!searching || search_close);
    wire motion_measurement_ok=history_valid && measured_interval>=1 && measured_interval<=4 &&
        measured_dx>=-13'sd16 && measured_dx<=13'sd16 &&
        measured_dy>=-13'sd16 && measured_dy<=13'sd16;
    wire signed [6:0] predict_dx=motion_valid?project(velocity_x,predict_interval):7'sd0;
    wire signed [6:0] predict_dy=motion_valid?project(velocity_y,predict_interval):7'sd0;
    wire signed [8:0] forecast_dx=probe_active?probe_dx:{{2{predict_dx[6]}},predict_dx};
    wire signed [8:0] forecast_dy=probe_active?probe_dy:{{2{predict_dy[6]}},predict_dy};
    wire signed [12:0] forecast_x=$signed({2'd0,center_x})+$signed({{4{forecast_dx[8]}},forecast_dx});
    wire signed [12:0] forecast_y=$signed({3'd0,center_y})+$signed({{4{forecast_dy[8]}},forecast_dy});
    // SOF can arrive during the preceding committed search. Admission is
    // still safe after that search retires, provided this frame's entire
    // proposed patch has yet to arrive. Keep two whole scanlines of guard.
    // Do not latch the preceding result's stale prediction on its commit edge.
    wire late_admit=in_frame && !capturing && !job_active && !core_busy && storage_eligible &&
        !start && !feature_we && !done && !result_update &&
        ({1'b0,row}+11'd2 < {1'b0,next_top});
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin predicted_x<=640;predicted_y<=360;end
        else if(hard_config)begin predicted_x<=configuration[20:10];predicted_y<=configuration[9:0];end
        else begin
            predicted_x<=forecast_x<64?11'd64:(forecast_x>H_ACTIVE-64?H_ACTIVE-64:forecast_x[10:0]);
            predicted_y<=forecast_y<64?10'd64:(forecast_y>V_ACTIVE-64?V_ACTIVE-64:forecast_y[9:0]);
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            recovery_misses<=0;recovery_phase<=0;last_probe<=3;job_probe<=0;job_probe_reset<=0;
            epoch<=0;guard_context<=0;job_guard_context<=0;current_source_frame<=0;job_source_frame<=0;enabled<=0;running<=0;center_x<=640;center_y<=360;roi_left<=0;roi_top<=0;capture_row_base<=0;
            job_left<=0;job_top<=0;job_init_x<=16;job_init_y<=16;
            template_mode<=0;template_record<=0;storage_wait<=0;reset_pending<=0;load_started<=0;template_armed<=0;
            record_complete<=0;searching<=0;search_hit<=0;storage_epoch<=0;template_request<=0;template_load<=0;
            user_d<=0;in_frame<=0;capturing<=0;column<=0;row<=0;word_count<=0;first_sample<=0;
            feature_we<=0;feature_address<=0;feature_data<=0;start<=0;initialize<=0;
            result_update<=0;result<=0;protocol_error<=0;
            job_active<=0;job_started<=0;job_commit<=0;job_abort<=0;
            frame_seq<=0;job_frame<=0;last_frame<=0;history_valid<=0;motion_valid<=0;velocity_x<=0;velocity_y<=0;
        end else begin
            result_update<=0;
            template_request<=0;
            if(reset_pending && !storage_wait)reset_pending<=0;
            // A mode change cannot revoke an accepted SD/CSR transaction.
            if(storage_wait && template_done)begin
                storage_wait<=0;
                if(storage_epoch==epoch && !hard_config)begin
                    if(template_record)begin
                        result_update<=1;result<={guard_context,current_source_frame,epoch,!template_error,center_x,center_y};
                    end else begin template_armed<=!template_error;end
                end
            end
            if(enabled && running && template_mode && !template_record && !load_started &&
               !storage_wait && !reset_pending && !hard_config && !job_active && !core_busy && !host_req)begin
                template_request<=1;template_load<=1;storage_wait<=1;storage_epoch<=epoch;load_started<=1;
            end
            user_d<=user;feature_we<=0;start<=0;job_abort<=0;
            if(new_user)begin frame_seq<=frame_seq+1'b1;current_source_frame<=source_frame_id+16'd1;end
            if(config_update)guard_context<=configuration[38:31];
            if(hard_config)begin
                recovery_misses<=0;recovery_phase<=0;last_probe<=3;job_probe<=0;job_probe_reset<=0;
                {epoch,enabled,running,center_x,center_y}<=configuration[30:0];
                {template_mode,template_record}<=configuration[40:39];
                template_armed<=0;load_started<=0;record_complete<=0;search_hit<=0;
                searching<=configuration[40] && !configuration[39] && configuration[21];
                if(storage_wait)reset_pending<=1;
                in_frame<=0;capturing<=0;column<=0;row<=0;word_count<=0;
                job_active<=0;job_started<=0;job_commit<=0;frame_seq<=0;
                history_valid<=0;motion_valid<=0;velocity_x<=0;velocity_y<=0;
            end else if(enabled && running)begin
                if(begin_frame)begin
                    in_frame<=1;capturing<=frame_selected;column<=0;row<=0;word_count<=0;capture_row_base<=0;
                    roi_left<=next_left;roi_top<=next_top;
                    if(frame_selected)begin
                        job_probe<=probe_active;
                        job_probe_reset<=job_probe!=probe_active || (probe_active && (job_left!=next_left || job_top!=next_top));
                        job_left<=next_left;job_top<=next_top;
                        // Prior remains the measured position in this ROI.
                        job_init_x<=(searching || probe_active)?6'd24:(center_x-next_left-11'd64)>>2;
                        job_init_y<=(searching || probe_active)?6'd24:(center_y-next_top-10'd64)>>2;
                        job_active<=1;job_started<=0;job_commit<=0;job_frame<=frame_seq+1'b1;job_source_frame<=source_frame_id+16'd1;job_guard_context<=guard_context;
                    end
                end
                if(late_admit)begin
                    capturing<=1;word_count<=0;capture_row_base<=0;
                    job_probe<=probe_active;
                    job_probe_reset<=job_probe!=probe_active || (probe_active && (job_left!=next_left || job_top!=next_top));
                    roi_left<=next_left;roi_top<=next_top;job_left<=next_left;job_top<=next_top;
                    job_init_x<=(searching || probe_active)?6'd24:(center_x-next_left-11'd64)>>2;
                    job_init_y<=(searching || probe_active)?6'd24:(center_y-next_top-10'd64)>>2;
                    job_active<=1;job_started<=0;job_commit<=0;job_frame<=frame_seq;job_source_frame<=current_source_frame;job_guard_context<=guard_context;
                end
                if(sample)begin
                    if(!beat_delta[0])first_sample<=gray;
                    else begin
                        feature_we<=1;feature_address<=capture_row_base+{6'd0,beat_delta[6:1]};
                        feature_data<={gray,first_sample};word_count<=word_count+1'b1;
                    end
                end
                // Wait for the final registered feature_we to retire to RAM.
                if(job_active && !job_started && !core_busy && !feature_we && word_count==3200 &&
                   (initialized || job_commit))begin
                    start<=1;initialize<=template_record || !initialized;job_started<=1;
                end
                if(take && !bad_last)begin
                    if(line_end)begin
                        column<=0;
                        if(frame_selected && sample_y)
                            capture_row_base<=capture_row_base+12'd40;
                        if(row_now==V_ACTIVE-1)begin
                            row<=0;in_frame<=0;capturing<=0;
                            if(frame_selected)begin
                                if(word_count==3200)job_commit<=1;
                                else begin
                                    job_abort<=1;job_active<=0;job_started<=0;start<=0;
                                    result_update<=1;result<={job_guard_context,job_source_frame,epoch,1'b0,center_x,center_y};protocol_error<=1;motion_valid<=0;
                                end
                            end
                        end else row<=row_now+1'b1;
                    end else column<=col_now+1'b1;
                end
                if(early_user || bad_last)begin
                    recovery_misses<=0;recovery_phase<=0;
                    in_frame<=0;capturing<=0;feature_we<=0;word_count<=0;column<=0;row<=0;protocol_error<=1;
                    // Malformed skipped frames cannot revoke an older committed job.
                    if(frame_selected || (job_active && !job_commit))begin
                        job_abort<=1;job_active<=0;job_started<=0;job_commit<=0;start<=0;
                        result_update<=1;result<={job_guard_context,job_source_frame,epoch,1'b0,center_x,center_y};motion_valid<=0;
                    end
                end
                if(done && job_active && job_started && job_commit)begin
                    job_active<=0;job_started<=0;
                    if(matched && job_probe)last_probe<=recovery_phase;
                    if(searching || template_record || matched)begin
                        recovery_misses<=0;recovery_phase<=0;
                    end else if(!recovery_misses)begin
                        recovery_misses<=1'b1;
                        recovery_phase<=opposite_probe;
                    end
                    else if(job_probe)begin
                        // Leave a rejected ROI promptly. A credible first
                        // candidate holds this exact ROI for independent confirmation.
                        if(!recovery_pending)recovery_phase<=recovery_phase+1'b1;
                    end
                    if(template_mode && template_record)begin
                        record_complete<=1;
                        if(matched && initialized)begin template_request<=1;template_load<=0;storage_wait<=1;storage_epoch<=epoch;end
                        else begin result_update<=1;result<={job_guard_context,job_source_frame,epoch,1'b0,center_x,center_y};end
                    end else begin
                        result_update<=1;result<={job_guard_context,job_source_frame,epoch,qualified_match,matched_x,matched_y};
                        if(searching)begin
                            search_hit<=matched;
                            if(qualified_match)searching<=0;
                        end
                    end
                    if(matched && !(template_mode && template_record))begin
                        center_x<=matched_x;center_y<=matched_y;
                        velocity_x<=motion_measurement_ok?velocity(measured_dx,measured_interval):6'sd0;
                        velocity_y<=motion_measurement_ok?velocity(measured_dy,measured_interval):6'sd0;
                        // Large-velocity prediction would steal the opposite search margin
                        // on a fast reversal. Keep full symmetric range in that case.
                        motion_valid<=motion_measurement_ok;
                        last_frame<=job_frame;history_valid<=1;
                    end else motion_valid<=0;
                end
            end else begin in_frame<=0;capturing<=0;job_active<=0;job_started<=0;job_commit<=0;history_valid<=0;motion_valid<=0;end
        end
    end
endmodule

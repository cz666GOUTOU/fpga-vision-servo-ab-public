// Ordered commands are applied in the HDMI domain, not coalesced across CDC.
// Four corner points, perimeter order 1,2,3,4; one atomic region confirmation.
module guard_roi_commands(
    input wire clk,rst_n,command_valid,frame_boundary,
    input wire [7:0] opcode,value,
    output wire [42:0] configuration,
    output reg changed,
    output wire [3:0] qualify_seconds,
    output reg motion_mode,
    output reg [83:0] preview_points,active_points,
    output reg [2:0] preview_selected,
    output wire editing,
    output reg validate_request,
    input wire validate_ready,validate_done,validate_ok,
    output wire [83:0] validate_points,
    output reg error
);
    // Physical pixel coordinates. Preserve the old outer bounds and handle
    // centres; only the geometry consumer in top truncates to the 4px grid.
    localparam [83:0] INITIAL_POINTS={
        11'd400,10'd519, 11'd879,10'd519, 11'd879,10'd200, 11'd400,10'd200};
    reg enabled,frame_dirty,validating;
    reg [3:0] feature_seconds,motion_seconds;
    assign qualify_seconds=motion_mode ? motion_seconds : feature_seconds;
    reg [7:0] revision;
    reg [3:0] dirty;
    reg [2:0] selected;
    reg [83:0] draft,confirmed;
    (* ram_style="distributed" *) reg [15:0] queue[0:3];
    reg [1:0] wr,rd;
    reg [2:0] count;
    wire pop=count!=0 && !validating && !validate_request;
    wire push=command_valid && (count<4 || pop);
    wire [15:0] cmd=queue[rd];
    wire [7:0] op=cmd[15:8],val=cmd[7:0];
    wire [1:0] selected_index=selected[1:0]-2'd1;
    // Fixed slices avoid a variable bit-offset shifter for a 21-bit word.
    function [20:0] point_word;
        input [83:0] p;input [1:0] n;
        begin case(n)
            0:point_word=p[20:0];1:point_word=p[41:21];
            2:point_word=p[62:42];3:point_word=p[83:63];
            default:point_word=21'd0;
        endcase end
    endfunction
    wire [20:0] dp=point_word(draft,selected_index);
    wire [20:0] cp=point_word(confirmed,selected_index);
    wire signed [11:0] delta={{4{val[7]}},val};
    wire y_move=op==8'h23;
    wire [10:0] axis_value=y_move ? {1'b0,dp[9:0]} : dp[20:10];
    wire [10:0] axis_limit=y_move ? 11'd719 : 11'd1279;
    wire signed [11:0] moved=$signed({1'b0,axis_value})+delta;
    wire [10:0] clamped_axis=moved<0 ? 11'd0 :
        (moved>$signed({1'b0,axis_limit}) ? axis_limit : moved[10:0]);
    wire [20:0] moved_point=y_move ? {dp[20:10],clamped_axis[9:0]} : {clamped_axis,dp[9:0]};
    // 21 01 validates the whole draft, including deselected dirty corners.
    // Queued edits cannot pop during request/validation, so the candidate
    // stays stable without another full point-table register.
    assign validate_points=draft;
    integer point;
    assign editing=selected!=0 || |dirty || validating || validate_request || frame_dirty;
    // Retain the controller's legacy configuration/bounds contract; polygon
    // coordinates and seconds are local synchronous metadata, never CDC buses.
    assign configuration={revision,enabled,8'd129,8'd50,9'd219,9'd100};
    always @(posedge clk)if(rst_n && push)queue[wr]<={opcode,value};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            enabled<=0;revision<=0;changed<=0;feature_seconds<=3;motion_seconds<=0;motion_mode<=0;
            draft<=INITIAL_POINTS;confirmed<=INITIAL_POINTS;
            preview_points<=INITIAL_POINTS;active_points<=INITIAL_POINTS;
            selected<=0;preview_selected<=0;dirty<=0;frame_dirty<=0;
            validate_request<=0;validating<=0;
            error<=0;wr<=0;rd<=0;count<=0;
        end else begin
            changed<=0;error<=command_valid && !push;
            if(push)wr<=wr+1'b1;
            if(pop)rd<=rd+1'b1;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
            if(frame_boundary)begin
                preview_points<=draft;active_points<=confirmed;preview_selected<=selected;
                frame_dirty<=0;
            end
            if(validate_request && validate_ready)begin validate_request<=0;validating<=1;end
            if(validating && validate_done)begin
                validating<=0;
                if(validate_ok)begin
                    confirmed<=draft;dirty<=0;selected<=0;
                    changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                end else error<=1;
            end
            if(pop)begin
                case(op)
                    8'h0e,8'h0b:begin
                        // 0E02 re-arms an existing session without changing
                        // enabled, any point table, selection, or seconds.
                        // While closed it is a no-op, never an enable request.
                        if(op!=8'h0e || (val==1 || (!motion_mode && (val!=2 || enabled))))begin
                            if(op==8'h0e)begin
                                if(val!=2)begin enabled<=val[0];motion_mode<=0;end
                            end else if(val==0)enabled<=0;
                            else if(val==1 || val==2)begin enabled<=1;motion_mode<=0;end
                            if(op==8'h0b && (val==1 || val==3))begin
                                draft<=INITIAL_POINTS;confirmed<=INITIAL_POINTS;dirty<=0;selected<=0;
                            end
                            changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                        end
                    end
                    8'h28:begin
                        // Each stop only closes its own session. Re-entering
                        // preserves the shared geometry and saved delay.
                        if(val==1 || motion_mode)begin
                            enabled<=val[0];motion_mode<=1;
                            changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                        end
                    end
                    8'h09,8'h0a:if(enabled)begin
                        enabled<=0;changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                    end
                    8'h24:begin
                        // Front-end contract: point selection is 0..4.
                        selected<=val[2:0];changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                    end
                    8'h25:begin
                        if(motion_mode)motion_seconds<=val[3:0];else feature_seconds<=val[3:0];
                        changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                    end
                    8'h22,8'h23:if(selected!=0)begin
                        for(point=0;point<4;point=point+1)
                            if(selected_index==point)draft[point*21 +: 21]<=moved_point;
                        dirty[selected_index]<=moved_point!=cp;
                        changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                    end
                    8'h21:begin
                        if(val==2)begin
                            draft<=INITIAL_POINTS;confirmed<=INITIAL_POINTS;dirty<=0;selected<=0;
                            changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                        end else if(val==0)begin
                            draft<=confirmed;dirty<=0;selected<=0;
                            changed<=1;revision<=revision+1'b1;frame_dirty<=1;
                        end else if(val==1)begin
                            validate_request<=1;
                        end
                    end
                    default:error<=1;
                endcase
            end
        end
    end
endmodule

module guard_mode_controller #(
    parameter integer QUALIFY_CYCLES=225000000,
    parameter integer LOST_CYCLES=75000000, // legacy parameter; no loss-based return
    parameter integer WATCHDOG_CYCLES=7500000,
    parameter integer BLINK_CYCLES=37500000,
    parameter integer PHOTO_FEATURE=0,
    parameter integer SAD_FEATURE=0,
    parameter integer POLYGON_FEATURE=0,
    parameter integer ALL_FEATURE=0,
    parameter integer SECOND_CYCLES=75000000
)(
    input wire clk,rst_n,frame_boundary,config_update,
    input wire [42:0] configuration,
    input wire result_update,
    // {complete_frame,gray_epoch,green_fresh,red_fresh,gy,gx,ry,rx}
    input wire [52:0] record,
    input wire overflow_async,event_accepted,
    output reg session,triggered,view_recognition,warning_on,
    output reg [8:0] xmin,xmax,
    output reg [7:0] ymin,ymax,
    output reg [7:0] epoch_gray,
    output reg event_pulse,event_wait,cancel_event,
    output reg [15:0] event_id,event_x,event_y,
    input wire photo_pause,
    input wire source_reset,selected_mode,input wire [15:0] selected_id,
    input wire edit_pause,polygon_red_inside,polygon_green_inside,
    input wire [3:0] qualify_seconds,
    input wire mode_request,motion_photo_taken,
    output reg motion_mode,
    output wire [1:0] motion_photo_qualified,
    output wire hud_intrusion,hud_blink,
    output wire [3:0] hud_seconds,
    output wire [4:0] hud_elapsed_half,
    output reg region_update,region_inside
);
    reg [42:0] pending_config;
    reg config_pending;
    reg pending_mode;
    reg [7:0] epoch;
    (* ASYNC_REG="TRUE" *) reg [1:0] overflow_sync;
    reg red_running,green_running;
    // Polygon counters pack seconds[3:0] and exact subsecond ticks[26:0].
    // This avoids an 11-way 30bit threshold ROM/multiplier for 0..10 seconds.
    reg [30:0] red_time,green_time;
    reg [3:0] active_seconds,pending_seconds;
    reg [22:0] watchdog;
    reg [25:0] blink_time; // 0.5s at 75MHz exceeds the previous 25-bit range
    reg blink;
    reg pause_d,edit_d;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin pause_d<=0;edit_d<=0;end
        else begin pause_d<=PHOTO_FEATURE && photo_pause;edit_d<=POLYGON_FEATURE && edit_pause;end
    wire [7:0] next_epoch=epoch+8'd1;
    wire matching=record[51:44]==epoch_gray;
    wire usable=record[52] && matching && !overflow_sync[1];
    wire red_present=record[42];
    wire green_present=record[43];
    wire [10:0] rx=record[10:0],gx=record[31:21];
    wire [9:0] ry=record[20:11],gy=record[41:32];
    wire red_inside=red_present && (POLYGON_FEATURE ? polygon_red_inside :
        (rx>={xmin,2'b00} && rx<={xmax,2'b11} && ry>={ymin,2'b00} && ry<={ymax,2'b11}));
    wire green_inside=green_present && (POLYGON_FEATURE ? polygon_green_inside :
        (gx>={xmin,2'b00} && gx<={xmax,2'b11} && gy>={ymin,2'b00} && gy<={ymax,2'b11}));
    wire red_qualified=POLYGON_FEATURE ? (red_time[30:27]>=active_seconds) : (red_time>=QUALIFY_CYCLES);
    wire green_qualified=POLYGON_FEATURE ? (green_time[30:27]>=active_seconds) : (green_time>=QUALIFY_CYCLES);
    wire immediate=POLYGON_FEATURE && active_seconds==0;
    wire editing_now=POLYGON_FEATURE && edit_pause;
    wire motion_active=(ALL_FEATURE!=0) && motion_mode;
    wire motion_taken=motion_active && motion_photo_taken;
    // Combinational eligibility belongs to this atomic geometry result. The
    // existing photo trigger owns busy handling and the one-entry latch.
    assign motion_photo_qualified={2{motion_active && session && result_update && usable &&
        !config_pending && !editing_now && !(PHOTO_FEATURE && photo_pause) &&
        watchdog<WATCHDOG_CYCLES && !motion_taken}} &
        {green_inside && (green_running || immediate) && green_qualified,
         red_inside && (red_running || immediate) && red_qualified};
    // Display taps only: never feed qualification, photo or network decisions.
    assign hud_intrusion=session && !triggered && !motion_taken &&
        (red_running || green_running) && !editing_now && !(PHOTO_FEATURE && photo_pause) &&
        watchdog<WATCHDOG_CYCLES && !overflow_sync[1];
    assign hud_blink=blink;
    assign hud_seconds=active_seconds;
    // The half-second encoding is monotone over the full unsigned time word.
    // Select after encoding; qualification/photo/network timers stay unchanged.
    wire [4:0] hud_red_half={red_time[30:27],1'b0}+
        ((red_time[26:0]>=SECOND_CYCLES/2) ? 5'd1 : 5'd0);
    wire [4:0] hud_green_half={green_time[30:27],1'b0}+
        ((green_time[26:0]>=SECOND_CYCLES/2) ? 5'd1 : 5'd0);
    wire [4:0] hud_selected_half=(red_running &&
        (!green_running || hud_red_half>=hud_green_half)) ? hud_red_half : hud_green_half;
    assign hud_elapsed_half=hud_intrusion ? hud_selected_half : 5'd0;
    // Only new complete frames can trigger recognition. The watchdog cancels
    // qualification evidence, but loss/invalid frames never re-arm a session.
    // Return uses the explicit configuration path (0E02), retaining the ROI.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            session<=0;triggered<=0;view_recognition<=0;warning_on<=0;
            xmin<=100;xmax<=219;ymin<=50;ymax<=129;
            pending_config<=0;config_pending<=0;pending_mode<=0;motion_mode<=0;epoch<=0;epoch_gray<=0;
            overflow_sync<=0;red_running<=0;green_running<=0;
            red_time<=0;green_time<=0;watchdog<=0;
            active_seconds<=3;pending_seconds<=3;
            blink_time<=0;blink<=1;event_pulse<=0;event_wait<=0;cancel_event<=0;
            event_id<=0;event_x<=0;event_y<=0;
        end else begin
            overflow_sync<={overflow_sync[0],overflow_async};
            event_pulse<=0;cancel_event<=0;
            if(event_accepted)event_wait<=0;
            if(red_running && !red_qualified)begin
                if(POLYGON_FEATURE && red_time[26:0]==SECOND_CYCLES-1)
                    red_time<={red_time[30:27]+4'd1,27'd0};
                else red_time<=red_time+1'b1;
            end
            if(green_running && !green_qualified)begin
                if(POLYGON_FEATURE && green_time[26:0]==SECOND_CYCLES-1)
                    green_time<={green_time[30:27]+4'd1,27'd0};
                else green_time<=green_time+1'b1;
            end
            if(watchdog<WATCHDOG_CYCLES)watchdog<=watchdog+1'b1;
            if(red_running || green_running)begin
                if(blink_time==BLINK_CYCLES-1)begin blink_time<=0;blink<=!blink;end
                else blink_time<=blink_time+1'b1;
            end else begin blink_time<=0;blink<=1;end
            if(frame_boundary)begin
                view_recognition<=triggered;
                warning_on<=session && !triggered && !motion_taken && (red_running || green_running) && blink;
            end
            if(watchdog>=WATCHDOG_CYCLES || overflow_sync[1])begin
                red_running<=0;green_running<=0;
                red_time<=0;green_time<=0;
            end
            if(session && result_update && !config_pending && !editing_now &&
                watchdog<WATCHDOG_CYCLES && !overflow_sync[1])begin
                if(!usable || motion_taken)begin
                    red_running<=0;green_running<=0;
                    red_time<=0;green_time<=0;
                end else if(!triggered)begin
                    if(!red_inside)begin red_running<=0;red_time<=0;end
                    else if(!red_running)begin red_running<=1;red_time<=0;end
                    if(!green_inside)begin green_running<=0;green_time<=0;end
                    else if(!green_running)begin green_running<=1;green_time<=0;end
                    if(!motion_active && ((red_inside && (red_running || immediate) && red_qualified) ||
                       (green_inside && (green_running || immediate) && green_qualified)))begin
                        triggered<=1;event_pulse<=1;event_wait<=1;
                        red_running<=0;green_running<=0;red_time<=0;green_time<=0;
                        if(red_inside && (red_running || immediate) && red_qualified)begin
                            event_id<=SAD_FEATURE && selected_mode ? selected_id : 16'd1;event_x<={5'd0,rx};event_y<={6'd0,ry};
                        end else begin event_id<=2;event_x<={5'd0,gx};event_y<={6'd0,gy};end
                    end
                end
            end
            if(result_update)watchdog<=0;
            // Even the first result after a watchdog lapse may start a NEW
            // interval; discard that frame conservatively and use the next.
            if(frame_boundary && config_pending)begin
                if(config_pending)begin
                    session<=pending_config[34];
                    xmin<=pending_config[8:0];xmax<=pending_config[17:9];
                    ymin<=pending_config[25:18];ymax<=pending_config[33:26];
                    active_seconds<=pending_seconds;
                    motion_mode<=pending_mode;
                end
                epoch<=next_epoch;epoch_gray<=next_epoch^(next_epoch>>1);
                config_pending<=0;
                triggered<=0;view_recognition<=0;warning_on<=0;
                red_running<=0;green_running<=0;
                red_time<=0;green_time<=0;
                event_wait<=0;cancel_event<=1;watchdog<=0;blink_time<=0;blink<=1;
            end
            // A simultaneous new request remains pending for the next frame.
            if(config_update)begin
                pending_config<=configuration;config_pending<=1;
                pending_mode<=(ALL_FEATURE!=0) && mode_request;
                if(POLYGON_FEATURE)pending_seconds<=qualify_seconds;
            end
            if(SAD_FEATURE && source_reset)begin
                epoch<=next_epoch;epoch_gray<=next_epoch^(next_epoch>>1);
                triggered<=0;view_recognition<=0;warning_on<=0;
                red_running<=0;green_running<=0;red_time<=0;green_time<=0;
                event_pulse<=0;event_wait<=0;cancel_event<=1;watchdog<=0;
            end
            if((PHOTO_FEATURE && (photo_pause || pause_d)) ||
               (POLYGON_FEATURE && (edit_pause || edit_d)))begin
                triggered<=0;view_recognition<=0;warning_on<=0;
                red_running<=0;green_running<=0;
                red_time<=0;green_time<=0;
                event_pulse<=0;event_wait<=0;cancel_event<=1;watchdog<=0;
                if((PHOTO_FEATURE && photo_pause!=pause_d) || (POLYGON_FEATURE && edit_pause!=edit_d))begin
                    epoch<=next_epoch;epoch_gray<=next_epoch^(next_epoch>>1);
                end
            end
        end
    end
    wire region_clear=!session || config_pending || editing_now || (SAD_FEATURE && source_reset) ||
        (PHOTO_FEATURE && photo_pause) || overflow_sync[1] || watchdog>=WATCHDOG_CYCLES;
    reg region_session_d;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin region_inside<=0;region_update<=0;region_session_d<=0;end
        else begin
            region_session_d<=session;region_update<=0;
            if(region_clear)begin
                region_inside<=0;
                if(region_inside || region_session_d!=session)region_update<=1;
            end else if(result_update)begin
                region_inside<=usable && (red_inside || green_inside);
                region_update<=1;
            end
        end
    end

endmodule

// Adapt the existing motion observer to the shared two-center geometry record.
// This is metadata only: it neither copies pixels nor changes motion decisions.
// Source ID comes from the existing DDR read-slot mailbox, two clocks BEFORE
// the aligned RGB frame-start at this interface. Bind epoch/ID at that start;
// never join a late result to a newer live camera frame ID.
module motion_guard_record(
    input wire clk,rst_n,enabled,paused,frame_boundary,frame_start,frame_de,
    input wire [15:0] source_id,
    input wire source_good,
    input wire [7:0] epoch,
    input wire result_update,result_ready,overflow,
    input wire [1:0] fresh,
    input wire [35:0] box_xmin,box_xmax,
    input wire [31:0] box_ymin,box_ymax,
    output wire out_update,
    output wire [52:0] record,
    output wire [15:0] photo_record
);
    reg [15:0] frame_id;
    reg [7:0] frame_epoch;
    reg frame_good;
    wire good=frame_good && source_good && source_id==frame_id && result_ready && !overflow;
    wire [9:0] x0sum={1'b0,box_xmin[8:0]}+{1'b0,box_xmax[8:0]};
    wire [9:0] x1sum={1'b0,box_xmin[17:9]}+{1'b0,box_xmax[17:9]};
    wire [8:0] y0sum={1'b0,box_ymin[7:0]}+{1'b0,box_ymax[7:0]};
    wire [8:0] y1sum={1'b0,box_ymin[15:8]}+{1'b0,box_ymax[15:8]};
    // floor((min*4 + max*4+3)/2) = 2*(min+max)+1.
    assign record={good,frame_epoch,(fresh & {2{good}}),
        y1sum,1'b1,x1sum,1'b1,y0sum,1'b1,x0sum,1'b1};
    assign photo_record=frame_id;
    assign out_update=enabled && !paused && !frame_boundary && result_update;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin frame_id<=0;frame_epoch<=0;frame_good<=0;end
        else if(!enabled || paused)frame_good<=0;
        else if(frame_start)begin frame_id<=source_id;frame_epoch<=epoch;frame_good<=source_good;end
        else if(frame_de && (!source_good || source_id!=frame_id))frame_good<=0;
    end
endmodule

// One exact GRID cross product engine, shared by validation and both targets.
// Coordinates are X9/Y8, even for out-of-picture result payloads. Differences
// fit signed10, magnitudes fit 9bits; each product <=511*255 and the signed
// difference fits 19bits. One DSP product; original two 9-cycle fences.
module guard_cross_product(
    input wire clk,rst_n,start,
    input wire [8:0] ax,bx,px,
    input wire [7:0] ay,by,py,
    output reg busy,done,
    output reg signed [18:0] value
);
    wire signed [9:0] dx=$signed({1'b0,bx})-$signed({1'b0,ax});
    wire signed [9:0] dy=$signed({2'b00,by})-$signed({2'b00,ay});
    wire signed [9:0] qx=$signed({1'b0,px})-$signed({1'b0,ax});
    wire signed [9:0] qy=$signed({2'b00,py})-$signed({2'b00,ay});
    // One operand always comes from an 8-bit Y coordinate difference, so
    // each signed product is within +/-130305 and fits signed18 exactly.
    reg signed [9:0] multiply_a,multiply_b,second_a,second_b;
    (* dsp_style="yes" *) wire signed [19:0] product=multiply_a*multiply_b;
    wire signed [17:0] signed_product=product[17:0];
    reg phase;
    reg [3:0] left;
    reg signed [17:0] first;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            busy<=0;done<=0;value<=0;multiply_a<=0;multiply_b<=0;
            second_a<=0;second_b<=0;phase<=0;left<=0;first<=0;
        end else begin
            done<=0;
            if(start && !busy)begin
                multiply_a<=dx;multiply_b<=qy;second_a<=dy;second_b<=qx;
                left<=9;phase<=0;busy<=1;
            end else if(busy)begin
                if(left==1)begin
                    if(!phase)begin
                        first<=signed_product;multiply_a<=second_a;multiply_b<=second_b;
                        left<=9;phase<=1;
                    end else begin
                        value<=$signed({first[17],first})-$signed({signed_product[17],signed_product});
                        busy<=0;done<=1;
                    end
                end else begin
                    left<=left-1'b1;
                end
            end
        end
    end
endmodule

// Strictly convex four-point validation and red/green half-plane tests share
// the ONLY serial cross-product core. Concave/crossed/degenerate edits fail.
// Metadata is held with its frame ID; never join the completed result to a
// newer live record. Invalid/stale frame records still reach the guard FSM.
module guard_polygon_core(
    input wire clk,rst_n,frame_boundary,run,
    input wire [67:0] active_points,validate_points,
    input wire validate_request,
    output wire validate_ready,
    output reg validate_done,validate_ok,
    input wire result_update,overflow_async,
    input wire [52:0] record,
    input wire [15:0] photo_record,
    output reg out_update,
    output reg [52:0] out_record,
    output reg [15:0] out_photo_record,
    output reg [1:0] inside_flags,
    output wire overflow
);
    localparam [2:0] IDLE=0,TURN=1,TURN_WAIT=2,POINT=3,POINT_WAIT=4,PUBLISH=5;
    reg [2:0] state;
    reg validation_job,target;
    reg [1:0] i;
    reg turn_sign,positive_seen,negative_seen,pending,local_overflow;
    reg [68:0] pending_record;
    (* ASYNC_REG="TRUE" *) reg [1:0] overflow_sync;
    assign overflow=overflow_sync[1] || local_overflow;
    wire [67:0] points=validation_job ? validate_points : active_points;
    // Fixed adjacent vertices only: no area/pair-validation index muxes.
    function [16:0] vertex;
        input [67:0] p;
        input [1:0] n;
        reg [16:0] v;
        begin
            case(n)
                0:v=p[16:0];1:v=p[33:17];2:v=p[50:34];3:v=p[67:51];
                default:v=17'd0;
            endcase
            vertex=v;
        end
    endfunction
    wire [16:0] a_vertex=vertex(points,i),b_vertex=vertex(points,i+2'd1),p_vertex=vertex(points,i+2'd2);
    wire [8:0] ax=a_vertex[16:8];
    wire [7:0] ay=a_vertex[7:0];
    wire [8:0] bx=b_vertex[16:8];
    wire [7:0] by=b_vertex[7:0];
    // Floor to a 4px cell ONLY for ROI decision. out_record is never rounded,
    // so control transmission, metadata identity and stored photos stay exact.
    wire [8:0] px=validation_job ? p_vertex[16:8] :
        (target ? out_record[31:23] : out_record[10:2]);
    wire [7:0] py=validation_job ? p_vertex[7:0] :
        (target ? out_record[41:34] : out_record[20:13]);
    wire fresh=target ? out_record[43] : out_record[42];
    wire cross_start=state==TURN || (state==POINT && fresh);
    wire cross_busy,cross_done;
    wire signed [18:0] cross_value;
    guard_cross_product math(.clk(clk),.rst_n(rst_n),.start(cross_start),
        .ax(ax),.ay(ay),.bx(bx),.by(by),.px(px),.py(py),
        .busy(cross_busy),.done(cross_done),.value(cross_value));
    assign validate_ready=state==IDLE && !cross_busy && !cross_done && !frame_boundary;
    // For an accepted convex quad, all four edge products have one sign for
    // interior points. Zero belongs to the boundary; opposite signs reject.
    wire nonzero=cross_value!=0;
    wire positive_next=positive_seen || (nonzero && !cross_value[18]);
    wire negative_next=negative_seen || (nonzero && cross_value[18]);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;validation_job<=0;target<=0;i<=0;turn_sign<=0;
            positive_seen<=0;negative_seen<=0;pending<=0;local_overflow<=0;pending_record<=0;
            overflow_sync<=0;validate_done<=0;validate_ok<=0;
            out_update<=0;out_record<=0;out_photo_record<=0;inside_flags<=0;
        end else begin
            overflow_sync<={overflow_sync[0],overflow_async};validate_done<=0;out_update<=0;
            if(result_update && run && !frame_boundary)begin
                if(pending && !(state==IDLE && !validate_request && !cross_busy && !cross_done))local_overflow<=1;
                pending_record<={record,photo_record};pending<=1;
            end
            case(state)
                IDLE:if(!cross_busy && !cross_done && !frame_boundary)begin
                    if(validate_request)begin
                        validation_job<=1;i<=0;state<=TURN;
                    end else if(pending && run)begin
                        validation_job<=0;out_record<=pending_record[68:16];
                        out_photo_record<=pending_record[15:0];inside_flags<=0;
                        if(!result_update)pending<=0;
                        target<=0;i<=0;positive_seen<=0;negative_seen<=0;state<=POINT;
                    end
                end
                TURN:state<=TURN_WAIT;
                TURN_WAIT:if(cross_done)begin
                    // Strict turns reject duplicates, zero area, collinear
                    // degeneracy, concavity and crossings without a pair FSM.
                    if(!nonzero || (i!=0 && cross_value[18]!=turn_sign))begin
                        validate_done<=1;validate_ok<=0;state<=IDLE;
                    end else if(i==3)begin
                        validate_done<=1;validate_ok<=1;state<=IDLE;
                    end else begin
                        turn_sign<=cross_value[18];i<=i+1'b1;state<=TURN;
                    end
                end
                POINT:begin
                    if(!fresh)begin
                        inside_flags[target]<=0;
                        if(target)state<=PUBLISH;
                        else begin target<=1;i<=0;positive_seen<=0;negative_seen<=0;end
                    end else state<=POINT_WAIT;
                end
                POINT_WAIT:if(cross_done)begin
                    positive_seen<=positive_next;negative_seen<=negative_next;
                    if(i==3)begin
                        inside_flags[target]<=!(positive_next && negative_next);
                        if(target)state<=PUBLISH;
                        else begin target<=1;i<=0;positive_seen<=0;negative_seen<=0;state<=POINT;end
                    end else begin i<=i+1'b1;state<=POINT;end
                end
                PUBLISH:begin out_update<=!overflow;state<=IDLE;end
                default:state<=IDLE;
            endcase
            // Do not cancel a point-confirmation validation at a video frame
            // boundary; only running/pending detection transactions are stale.
            if(!run || frame_boundary || overflow)begin
                pending<=0;out_update<=0;
                if(state==POINT || state==POINT_WAIT || state==PUBLISH)state<=IDLE;
            end
        end
    end
endmodule

// Display-only physical-pixel DDA with 86bit edge and 22bit interval words.
// Compute one physical pixel row in blanking. Four edges only; no frame RAM/IP,
// per-pixel geometry or new video register. Geometry/inside tests stay on the
// original 4px grid in guard_polygon_core. A 3x3 dilation of the original DDA
// gives a 3px stroke, including horizontal edges and clipped screen corners.
module guard_polygon_raster #(
    parameter integer H_ACTIVE=1280
)(
    input wire clk,rst_n,vsync,de,enable,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire [83:0] points,
    input wire [2:0] selected,
    output wire edge_on,handle_on,
    output reg fault
);
    localparam [3:0] WAIT_FRAME=0,INIT=1,DIVIDE=2,INIT_SAVE=3,ROW=4,
        INSERT=5,MERGE_START=6,MERGE=7,FINISH=8,READY=9,
        ROW_READ=10,ROW_ADVANCE=11,ROW_LOOKAHEAD=12;
    reg [3:0] state;
    reg vs_d,de_d,row_ready;
    reg [1:0] edge_index;
    (* ram_style="dram" *) reg [21:0] intervals[0:3];
    // count can equal four, so counters need three bits; addresses need two.
    reg [2:0] count,insert_index,read_index,write_index,span_index,span_count;
    reg [2:0] row_spans;
    reg [21:0] temporary,merged,span,span_next;
    reg [9:0] row_y,init_ylo,init_yhi,divisor;
    reg [10:0] init_x,quotient,remainder;
    reg init_sign,init_down,init_horizontal;
    reg [3:0] div_left;
    function [20:0] vertex;
        input [83:0] p;input [1:0] n;
        reg [20:0] v;
        begin case(n)
                0:v=p[20:0];1:v=p[41:21];2:v=p[62:42];3:v=p[83:63];
                default:v=21'd0;
            endcase
            vertex=v;end
    endfunction
    wire [20:0] a_vertex=vertex(points,edge_index),b_vertex=vertex(points,edge_index+2'd1);
    wire [10:0] xa=a_vertex[20:10],xb=b_vertex[20:10];
    wire [9:0] ya=a_vertex[9:0],yb=b_vertex[9:0];
    wire [10:0] abs_dx=xa>xb ? xa-xb : xb-xa;
    wire [10:0] trial={remainder[9:0],quotient[10]};
    // One widened subtraction supplies both unsigned comparison and result.
    // trial-divisor ranges -1023..2047, including a zero divisor.
    wire [11:0] trial_difference={1'b0,trial}-{2'b00,divisor};
    wire subtract=~trial_difference[11];
    wire [10:0] next_q={quotient[9:0],subtract};
    wire [10:0] next_r=subtract ? trial_difference[10:0] : trial;
    // The per-edge row job is wholly in blanking. Register the RAM read,
    // advance, and lookahead separately instead of a 17-level RAM-DDA chain.
    // Four edges add twelve clocks per row; pixel/RGB/control latency is fixed.
    wire [85:0] edge_data;
    reg [10:0] next_x,leading_x;
    reg [9:0] saved_rem;
    wire horizontal=edge_data[74],negative=edge_data[72];
    wire [9:0] height=edge_data[71:62],ylo=edge_data[61:52],yhi=edge_data[51:42];
    wire [10:0] old_x=edge_data[41:31],step=edge_data[30:20];
    wire [10:0] previous_x=edge_data[85:75];
    // ROW_ADVANCE and ROW_LOOKAHEAD consume the same arithmetic in
    // successive clocks. Select small operands before the shared datapath.
    wire lookahead_phase=state==ROW_LOOKAHEAD;
    wire [9:0] remainder_source=lookahead_phase ? saved_rem : edge_data[9:0];
    wire [10:0] rem_sum={1'b0,remainder_source}+{1'b0,edge_data[19:10]};
    wire [11:0] remainder_difference={1'b0,rem_sum}-{2'b00,height};
    wire carry=~remainder_difference[11];
    // Preserve low-ten-bit remainder and zero-height behavior in both phases.
    wire [9:0] next_rem=carry ? remainder_difference[9:0] : rem_sum[9:0];
    // Modulo-2^11: x-step-carry = x+(~step)+(!carry).
    wire [10:0] step_operand=step^{11{negative}};
    wire [10:0] x_source=lookahead_phase ? next_x : old_x;
    wire [10:0] advanced_x=x_source+step_operand+{10'd0,(negative^carry)};
    wire [10:0] advance_value=row_y>=yhi ? old_x : advanced_x;
    // Union the old 1px intervals at row-1,row,row+1. Each monotonic edge's
    // adjacent intervals share endpoints, so only two extreme x values are
    // needed. Clamp at both vertices; widened y arithmetic prevents wrapping.
    wire [10:0] leading_value=(row_y<ylo || {1'b0,row_y}+11'd1>={1'b0,yhi}) ? next_x : advanced_x;
    wire [10:0] line_lo=horizontal ? old_x : (previous_x<leading_x ? previous_x : leading_x);
    wire [10:0] line_hi=horizontal ? step : (previous_x>leading_x ? previous_x : leading_x);
    wire [10:0] stroke_lo=line_lo==0 ? 11'd0 : line_lo-11'd1;
    wire [10:0] stroke_hi=line_hi==11'd2047 ? 11'd2047 : line_hi+11'd1;
    // INSERT/MERGE/FINISH and active-video lookahead are mutually exclusive.
    // Mux the small ADDRESS, not four independent interval read results.
    wire [1:0] interval_address=state==INSERT ? insert_index[1:0]-2'd1 :
        (state==MERGE ? read_index[1:0] :
        ((state==MERGE_START || state==FINISH) ? 2'd0 : span_index[1:0]+2'd2));
    wire [21:0] interval_word=intervals[interval_address];
    wire [21:0] preceding=interval_word,following=interval_word;
    wire [21:0] merged_next={
        (following[21:11]>merged[21:11] ? following[21:11] : merged[21:11]),merged[10:0]};
    wire [1:0] selected_index=selected[1:0]-2'd1;
    wire [20:0] selected_vertex=vertex(points,selected_index);
    wire [10:0] hx=selected_vertex[20:10];
    wire [9:0] hy=selected_vertex[9:0];
    // Bias the COMPLETE signed coordinate range; no absolute-value mux.
    // A difference outside -6..6 cannot alias into the 13px handle window.
    wire [11:0] handle_x_offset={1'b0,x}-{1'b0,hx}+12'd6;
    wire [10:0] handle_y_offset={1'b0,y}-{1'b0,hy}+11'd6;
    // Same discrete annulus: 4^2 < dx^2+dy^2 <= 6^2, mirrored about index 6.
    function [12:0] ring_row;
        input [3:0] biased_y;
        begin case(biased_y)
            4'd0,4'd12:ring_row=13'b0000001000000;
            4'd1,4'd11:ring_row=13'b0001111111000;
            4'd2,4'd10:ring_row=13'b0011110111100;
            4'd3,4'd9:ring_row=13'b0111000001110;
            4'd4,4'd8:ring_row=13'b0110000000110;
            4'd5,4'd7:ring_row=13'b0110000000110;
            4'd6:ring_row=13'b1100000000011;
            default:ring_row=13'd0;
        endcase end
    endfunction
    wire [12:0] handle_row=ring_row(handle_y_offset[3:0]);
    assign handle_on=enable && de && selected!=0 && selected<=4 &&
        handle_x_offset<=12'd12 && handle_y_offset<=11'd12 &&
        handle_row[handle_x_offset[3:0]];
    assign edge_on=enable && de && row_ready && span_count!=0 && x>=span[10:0] && x<=span[21:11];
    // A single complete write word and shared port enable give every bank
    // NORMAL (no-change) synchronous read/write semantics. ROW_READ and
    // INIT_SAVE/ROW writes are exclusive; the original read edge is retained.
    wire edge_read_enable=state==ROW_READ;
    wire edge_write_enable=rst_n && (state==INIT_SAVE ||
        (state==ROW && row_y>=ylo && row_y<=yhi && !horizontal));
    wire [85:0] edge_write_data=state==INIT_SAVE ?
        {init_x,init_horizontal,init_down,init_sign,divisor,
            init_ylo,init_yhi,init_x,quotient,remainder[9:0],10'd0} :
        {old_x,edge_data[74:42],next_x,edge_data[30:10],
            (row_y<yhi ? saved_rem : edge_data[9:0])};
    wire [99:0] edge_bank_data={14'd0,edge_write_data};
    wire [99:0] edge_bank_q;
    assign edge_data=edge_bank_q[85:0];
    genvar edge_bank;
    generate for(edge_bank=0;edge_bank<5;edge_bank=edge_bank+1)begin:g_edge_bank
        guard_edge_bank20 bank(.clk(clk),
            .ce(edge_read_enable || edge_write_enable),.we(edge_write_enable),
            .address({8'd0,edge_index}),
            .data(edge_bank_data[edge_bank*20+:20]),
            .q(edge_bank_q[edge_bank*20+:20]));
    end endgenerate
    // Interval storage and its original reset qualification are unchanged.
    always @(posedge clk)if(rst_n)begin
        if(state==INSERT)begin
            if(insert_index!=0 && preceding[10:0]>temporary[10:0])intervals[insert_index[1:0]]<=preceding;
            else intervals[insert_index[1:0]]<=temporary;
        end else if(state==MERGE)begin
            if(read_index>=count)intervals[write_index[1:0]]<=merged;
            else if({1'b0,following[10:0]}>{1'b0,merged[21:11]}+12'd1)
                intervals[write_index[1:0]]<=merged;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=WAIT_FRAME;vs_d<=0;de_d<=0;row_ready<=0;fault<=0;edge_index<=0;
            count<=0;insert_index<=0;read_index<=0;write_index<=0;span_index<=0;span_count<=0;row_spans<=0;
            temporary<=0;merged<=0;span<=0;span_next<=0;row_y<=0;
            init_ylo<=0;init_yhi<=0;divisor<=0;init_x<=0;quotient<=0;remainder<=0;
            init_sign<=0;init_down<=0;init_horizontal<=0;div_left<=0;
        end else begin
            vs_d<=vsync;de_d<=de;
            if(de && enable && !row_ready)fault<=1;
            if(de && row_ready && span_count!=0 && x>=span[21:11])begin
                if(span_index+1<span_count)begin
                    span<=span_next;span_index<=span_index+1'b1;
                    span_next<=interval_word;
                end else span_count<=0;
            end
            case(state)
                INIT:begin
                    init_horizontal<=ya==yb;init_down<=ya<yb;
                    if(ya==yb)begin
                        init_x<=xa<xb ? xa : xb;quotient<=xa>xb ? xa : xb;
                        init_ylo<=ya;init_yhi<=ya;
                        divisor<=0;remainder<=0;init_sign<=0;state<=INIT_SAVE;
                    end else begin
                        init_ylo<=ya<yb ? ya : yb;init_yhi<=ya>yb ? ya : yb;
                        init_x<=ya<yb ? xa : xb;
                        init_sign<=ya<yb ? xb<xa : xa<xb;
                        divisor<=ya>yb ? ya-yb : yb-ya;
                        quotient<=abs_dx;remainder<=0;div_left<=11;state<=DIVIDE;
                    end
                end
                DIVIDE:begin
                    quotient<=next_q;remainder<=next_r;
                    if(div_left==1)state<=INIT_SAVE;
                    else div_left<=div_left-1'b1;
                end
                INIT_SAVE:begin
                    if(edge_index==3)begin edge_index<=0;row_y<=0;count<=0;state<=ROW_READ;end
                    else begin edge_index<=edge_index+1'b1;state<=INIT;end
                end
                ROW_READ:state<=ROW_ADVANCE;
                ROW_ADVANCE:begin
                    next_x<=advance_value;saved_rem<=next_rem;state<=ROW_LOOKAHEAD;
                end
                ROW_LOOKAHEAD:begin leading_x<=leading_value;state<=ROW;end
                ROW:begin
                    if({1'b0,row_y}+11'd1>={1'b0,ylo} && {1'b0,row_y}<={1'b0,yhi}+11'd1)begin
                        temporary<={stroke_hi,stroke_lo};insert_index<=count;state<=INSERT;
                    end else if(edge_index==3)state<=MERGE_START;
                    else begin edge_index<=edge_index+1'b1;state<=ROW_READ;end
                end
                INSERT:begin
                    if(insert_index!=0 && preceding[10:0]>temporary[10:0])begin
                        insert_index<=insert_index-1'b1;
                    end else begin
                        count<=count+1'b1;
                        if(edge_index==3)state<=MERGE_START;
                        else begin edge_index<=edge_index+1'b1;state<=ROW_READ;end
                    end
                end
                MERGE_START:begin
                    merged<=interval_word;read_index<=1;write_index<=0;
                    if(count==0)begin row_spans<=0;state<=FINISH;end
                    else state<=MERGE;
                end
                MERGE:begin
                    if(read_index>=count)begin
                        row_spans<=write_index+1'b1;state<=FINISH;
                    end else begin
                        if({1'b0,following[10:0]}<={1'b0,merged[21:11]}+12'd1)merged<=merged_next;
                        else begin
                            write_index<=write_index+1'b1;merged<=following;
                        end
                        read_index<=read_index+1'b1;
                    end
                end
                FINISH:begin
                    span<=interval_word;span_next<=intervals[1];span_index<=0;span_count<=row_spans;row_ready<=1;state<=READY;
                end
                default:begin end
            endcase
            if(de_d && !de && !vsync)begin
                if(state!=READY && enable)fault<=1;
                row_ready<=0;
                // Advance once per completed physical line, independent of the
                // upstream counter's NBA phase at the final pixel/DE fall.
                row_y<=row_y+1'b1;count<=0;edge_index<=0;state<=ROW_READ;
            end
            if(vsync && !vs_d)begin
                edge_index<=0;row_ready<=0;span_count<=0;row_spans<=0;state<=INIT;
            end
        end
    end
endmodule

module guard_send_queue(
    input wire clk,rst_n,cancel,first_tag,first_wait,ready,in_update,
    input wire [81:0] in_record,
    output wire out_update,
    output wire [81:0] out_record,
    output wire accepted
);
    reg pending;
    reg [81:0] saved;
    assign accepted=pending && ready && !cancel;
    assign out_update=!cancel && (pending ? ready : (in_update && !first_tag && !first_wait));
    assign out_record=pending ? saved : in_record;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin pending<=0;saved<=0;end
        else if(cancel)pending<=0;
        else begin
            if(accepted)pending<=0;
            if(in_update && first_tag)begin saved<=in_record;pending<=1;end
        end
    end
endmodule

module guard_warning_osd #(
    parameter integer EXTERNAL_FONT=0
)(
    input wire clk,rst_n,frame_start,de,enable,
    input wire [11:0] x,y,
    output reg ink_d2,
    output wire [7:0] font_char,
    output wire [3:0] font_row,font_col,
    output wire font_request,
    input wire external_font_pixel
);
    reg active,region_q;
    reg [7:0] ch_q;
    reg [3:0] row_q,col_q;
    wire font_pixel;
    wire [11:0] dx=x-12'd1008;
    wire [11:0] dy=y-12'd312;
    reg [7:0] ch;
    always @* case(dx[7:5])
        0:ch="W";1:ch="A";2:ch="R";3:ch="N";
        4:ch="I";5:ch="N";6:ch="G";default:ch=" ";
    endcase
    assign font_char=ch_q;assign font_row=row_q;assign font_col=col_q;
    assign font_request=region_q;
    generate if(EXTERNAL_FONT)begin : g_external_font
        assign font_pixel=external_font_pixel;
    end else begin : g_local_font
        wire [15:0] bits;
        osd_char_lib #(.SMALL_CNT(1)) font(.I_char(ch_q),.I_row(row_q),.O_row_bits(bits));
        assign font_pixel=bits[15-col_q];
    end endgenerate
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin active<=0;region_q<=0;ch_q<=0;row_q<=0;col_q<=0;ink_d2<=0;end
        else begin
            if(frame_start)active<=enable;
            // 2x glyph scale via address bits; same shared 16x16 font/latency.
            region_q<=de && active && x>=1008 && x<1232 && y>=312 && y<344;
            ch_q<=ch;row_q<=dy[4:1];col_q<=dx[4:1];
            ink_d2<=region_q && font_pixel;
        end
    end
endmodule

// Latest complete metadata record plus sticky status update. This is HDMI-only;
// the caller's existing async FIFO crosses the entire 83-bit record atomically.
// A status update never promotes target_valid before the original dwell event.
module guard_region_tx(
    input clk,rst_n,ready,link_ready,enabled,session,motion_mode,triggered,paused,
    input region_update,region_inside,in_update,
    input [81:0] in_record,
    output out_update,output [82:0] out_record
);
    reg dirty,enabled_d,link_d; // link_ready is already result_clk-synchronized by the TX core.
    reg [81:0] saved;
    wire suppress=session && (motion_mode || !triggered || paused);
    wire [81:0] latest=in_update ? in_record : saved;
    wire [81:0] payload=suppress ? 82'd0 : latest;
    wire flag=session && !paused && region_inside;
    assign out_update=enabled && ready && (in_update || region_update || dirty);
    assign out_record={flag,payload};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin dirty<=0;saved<=0;enabled_d<=0;link_d<=0;end
        else begin
            enabled_d<=enabled;link_d<=link_ready;
            if(in_update)saved<=in_record;
            if(out_update)dirty<=0;
            if((region_update || in_update) && !out_update)dirty<=1;
            if(enabled && ((!enabled_d) || (link_ready && !link_d)))dirty<=1;
            if(!enabled)begin dirty<=0;saved<=0;end
            // Never replay an earlier ordinary target on a new guard session.
            if(suppress)saved<=0;
        end
    end
endmodule

// Natural PH1P20K width/depth; only addresses 0..3 are used by the raster.
// No asynchronous memory reset and no extra output register stage.
module guard_edge_bank20(
    input wire clk,ce,we,
    input wire [9:0] address,
    input wire [19:0] data,
    output reg [19:0] q
);
    (* ram_style="bram" *) reg [19:0] memory[0:1023];
    always @(posedge clk)if(ce)begin
        if(we)memory[address]<=data;
        else q<=memory[address];
    end
endmodule

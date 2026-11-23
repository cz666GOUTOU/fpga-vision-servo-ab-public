// Lightweight mode information and manual adjustment HUD; INFO_FEATURE is
// opt-in so older named-port instantiations retain their original display.
module hdmi_mixer #(
    parameter H_OFFSET=128,V_OFFSET=60,IMG_WIDTH=1280,IMG_HEIGHT=720,
    parameter integer DEBUG_MODE=0,SHOW_MODE_NAME=1,SHOW_LATENCY=0,
    parameter integer GUARD_FEATURE=0,PHOTO_FEATURE=0,INFO_FEATURE=0,GUARD_SESSION_FEATURE=0,
    parameter integer TRACK_UI_FEATURE=0
)(
    input I_clk,I_rst_n,I_video_vsync,I_video_hsync,I_video_de,I_video_user,I_video_last,
    input [3:0] I_debug_status,I_proc_mode,
    input I_ae_auto_active,I_ae_target_valid,I_ae_iic_error,input [4:0] I_ae_raw_gain,
    input [3:0] I_latency_enable,output O_video_rd_en,input [23:0] I_video_rd_data,
    output reg O_hdmi_vsync,O_hdmi_hsync,O_hdmi_de,output reg [23:0] O_hdmi_data,
    input [15:0] I_latency_bcd,input [13:0] I_latency_ticks,input I_latency_valid,
    input [15:0] I_detect_latency_bcd,input I_detect_latency_valid,
    input I_guard_warning,I_photo_album,input [5:0] I_photo_index,
    input [6:0] I_photo_count,input [3:0] I_photo_status,
    input I_guard_active,I_guard_recognition,I_guard_motion,I_guard_intrusion,I_guard_region_inside,
    input [3:0] I_guard_seconds,input [4:0] I_guard_elapsed,input [7:0] I_guard_epoch,
    input I_target_update,I_target_valid,I_target_overflow,
    input [15:0] I_target_id,I_target_x,I_target_y,
    input I_object_active,I_motion_active,
    // Display-only metadata; all inputs below are in I_clk (HDMI) domain.
    input I_motion_update,I_motion_ready,I_motion_overflow,
    input [1:0] I_motion_fresh,I_motion_valid,
    input [17:0] I_motion_xmin,I_motion_xmax,
    input [15:0] I_motion_ymin,I_motion_ymax,
    input I_param_update,input [1:0] I_param_kind,input [4:0] I_param_level,
    // Optional display ownership. Legacy instances ignore an unconnected port.
    input I_guard_session,
    input I_sad_active,I_sad_running,I_sad_update,I_sad_valid,
    input [15:0] I_sad_id,I_sad_x,I_sad_y,
    // Optional ordered HDMI-domain display events; ignored by legacy instances.
    input I_track_command_update,input [15:0] I_track_command,
    // Mode ownership exported in I_clk; top commits recognition at blanking.
    output O_static_track_active,output O_range_hold_active
);
    // Fixed three-clock payload/control contract: character -> ROM row -> mix.
    reg [11:0] S_x,S_y;
    reg [2:0] vs_pipe,hs_pipe,de_pipe;
    reg [23:0] rgb_q,rgb_d2;
    assign O_video_rd_en=I_video_de;
    // Small transparent logo at (256,16), beside rather than over the left UI.
    // The offline 64x64 index image avoids enabling the original large ROM.
    // ROM read -> palette register -> existing mix: same three clocks as RGB.
    wire logo_request=I_video_de && S_x>=12'd256 && S_x<12'd320 &&
        S_y>=12'd16 && S_y<12'd80;
    wire [5:0] logo_y=S_y[5:0]-6'd16;
    wire [24:0] logo_pixel;
    reg [1:0] logo_window;
    anlogic_logo_small_rom u_logo_small(.I_clk(I_clk),
        .I_addr({logo_y,S_x[5:0]}),.O_pixel(logo_pixel));
    // END SMALL LOGO
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n)begin S_x<=0;S_y<=0;end
        else if(I_video_user)begin S_x<=0;S_y<=0;end
        else if(I_video_de)begin
            if(I_video_last)begin S_x<=0;S_y<=S_y+1'b1;end
            else S_x<=S_x+1'b1;
        end

    // Same-domain display observer. No output feeds control, SD or UDP.
    wire target_valid,target_locked,lock_visible,target_centered;
    wire [15:0] target_id,target_x,target_y;
    wire sad_owner=INFO_FEATURE && I_sad_active;
    reg sad_l,sad_running_l,sad_live_l,sad_inside_l,sad_saved_l;
    wire [63:0] target_digits;
    wire target_dx_neg,target_dy_neg;
    // Session owns the UI even while editing pauses the business controller.
    // Keep the old active-only interface unless the top explicitly opts in.
    wire guard_ui_session=GUARD_SESSION_FEATURE ? I_guard_session : I_guard_active;
    wire guard_ui_paused=GUARD_FEATURE && GUARD_SESSION_FEATURE && guard_ui_session && !I_guard_active;
    // A selected target uses the same feature-guard HUD, not a second UI.
    // These predicates observe the existing SAD record; none feed control.
    wire sad_guard_owner=sad_owner && GUARD_FEATURE && guard_ui_session && !I_guard_motion;
    wire sad_guard_live=!sad_guard_owner || (I_sad_running && I_sad_valid);
    wire hud_record_current=!sad_owner ||
        (target_id==I_sad_id && target_x==I_sad_x && target_y==I_sad_y);
    wire static_track,track_selected,track_outside;
    wire [1:0] track_speed;
    wire [3:0] track_steps;
    wire range_active,range_valid,range_applied;
    wire [19:0] range_bcd;
    assign O_static_track_active=static_track;
    assign O_range_hold_active=range_active;
    generate if(TRACK_UI_FEATURE)begin:g_track_ui
        tracking_ui_control control(.clk(I_clk),.rst_n(I_rst_n),
            .command_valid(I_track_command_update),.command(I_track_command),
            .guard_tracking(GUARD_FEATURE && guard_ui_session && I_guard_recognition &&
                !I_guard_motion && !guard_ui_paused),.album(I_photo_album),
            .static_track(static_track),.selected_green(track_selected),.speed(track_speed),
            .outside(track_outside),.elapsed_half(track_steps));
        range_ui_control range_control(.clk(I_clk),.rst_n(I_rst_n),
            .command_valid(I_track_command_update),.command(I_track_command),
            .active(range_active),.distance_valid(range_valid),
            .applied(range_applied),.distance_bcd(range_bcd));
    end else begin:g_no_track_ui
        assign static_track=0;assign track_selected=0;assign track_speed=1;
        assign track_outside=0;assign track_steps=0;
        assign range_active=0;assign range_valid=0;assign range_applied=0;assign range_bcd=0;
    end endgenerate
    reg static_track_l,track_selected_l,track_outside_l;
    reg [1:0] track_speed_l;
    reg [3:0] track_steps_l;
    reg range_l,range_valid_l,range_applied_l;
    reg [19:0] range_bcd_l;
    wire info_motion_owner=INFO_FEATURE && !sad_owner && (guard_ui_session ? I_guard_motion : I_motion_active);
    wire [1:0] info_owner=sad_owner ? 2'd3 : info_motion_owner ? 2'd2 : (guard_ui_session ? 2'd1 : 2'd0);
    reg [1:0] info_owner_q;
    reg [1:0] motion_count, motion_count_l;
    reg motion_ready_l,motion_overflow_l,centered_l,motion_seen_ready,motion_rebuild_l;
    reg [3:0] photo_status_l;
    wire [1:0] fresh_boxes=I_motion_fresh & I_motion_valid;
    wire [8:0] mx0=fresh_boxes[0] ? I_motion_xmin[8:0] : I_motion_xmin[17:9];
    wire [8:0] mx1=fresh_boxes[0] ? I_motion_xmax[8:0] : I_motion_xmax[17:9];
    wire [7:0] my0=fresh_boxes[0] ? I_motion_ymin[7:0] : I_motion_ymin[15:8];
    wire [7:0] my1=fresh_boxes[0] ? I_motion_ymax[7:0] : I_motion_ymax[15:8];
    wire motion_box_ok=(|fresh_boxes) && mx0<=mx1 && my0<=my1 && mx1<320 && my1<180;
    // Bounds are inclusive DS4 cells. Centers round down to integer pixels.
    wire [10:0] motion_x=({1'b0,mx0}+{1'b0,mx1})*11'd2+11'd1;
    wire [10:0] motion_y=({2'b0,my0}+{2'b0,my1})*11'd2+11'd1;
    wire [11:0] motion_w=({3'b0,mx1}-{3'b0,mx0}+12'd1)<<2;
    wire [11:0] motion_h=({4'b0,my1}-{4'b0,my0}+12'd1)<<2;
    hud_target_state #(.EXTENDED_METRICS(INFO_FEATURE)) target_state(.clk(I_clk),.rst_n(I_rst_n),
        .sad_mode(sad_owner),.out_x(target_x),.out_y(target_y),
        .enable((sad_owner || (GUARD_FEATURE && I_guard_active && !I_guard_motion) ||
            (INFO_FEATURE && (I_object_active || info_motion_owner))) && (!guard_ui_paused || sad_owner) && !I_photo_album),
        .recognition(I_guard_recognition && (!sad_owner || (sad_guard_owner && sad_guard_live))),.epoch(I_guard_epoch),
        .update(sad_owner ? I_sad_update : info_motion_owner ? I_motion_update : I_target_update),
        .valid(sad_owner ? sad_guard_live : info_motion_owner ? (I_motion_ready && motion_box_ok) : I_target_valid),
        .overflow((INFO_FEATURE && info_owner!=info_owner_q) ||
            (!sad_owner && (info_motion_owner ? (I_motion_overflow || !I_motion_ready) : I_target_overflow))),
        .id(sad_owner ? I_sad_id : info_motion_owner ? (fresh_boxes[0] ? 16'd1 : 16'd2) : I_target_id),
        .x(sad_owner ? I_sad_x : info_motion_owner ? {5'd0,motion_x} : I_target_x),
        .y(sad_owner ? I_sad_y : info_motion_owner ? {5'd0,motion_y} : I_target_y),
        .metric_mode(info_motion_owner),.metric_w(motion_w),.metric_h(motion_h),.out_centered(target_centered),
        .out_valid(target_valid),.locked(target_locked),.lock_visible(lock_visible),
        .out_id(target_id),.digits(target_digits),.dx_negative(target_dx_neg),.dy_negative(target_dy_neg));
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin info_owner_q<=0;motion_count<=0;motion_count_l<=0;
            motion_ready_l<=0;motion_overflow_l<=0;centered_l<=0;photo_status_l<=0;
            motion_seen_ready<=0;motion_rebuild_l<=0;end
        else if(INFO_FEATURE)begin
            info_owner_q<=info_owner;
            if(!info_motion_owner)motion_seen_ready<=0;
            else if(I_motion_ready)motion_seen_ready<=1;
            if(!info_motion_owner || !I_motion_ready || I_motion_overflow)motion_count<=0;
            else if(I_motion_update)motion_count<={1'b0,fresh_boxes[0]}+{1'b0,fresh_boxes[1]};
            if(I_video_user)begin
                motion_count_l<=(target_valid && I_motion_ready && !I_motion_overflow) ? motion_count : 2'd0;
                motion_ready_l<=I_motion_ready;motion_overflow_l<=I_motion_overflow;
                motion_rebuild_l<=motion_seen_ready && !I_motion_ready;
                centered_l<=target_centered;photo_status_l<=I_photo_status;
            end
        end
    end
    // About two seconds at the existing 75 MHz / 1650 / 750 video timing.
    // Queue the last commit between frames, then atomically latch its caption.
    reg param_pending;
    reg [6:0] param_record;
    reg [1:0] param_kind_l;
    reg [4:0] param_level_l;
    reg [6:0] param_frames;
    reg [19:0] param_value_l;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin param_pending<=0;param_record<=0;param_kind_l<=0;param_level_l<=8;param_frames<=0;end
        else if(INFO_FEATURE)begin
            if(I_param_update && I_param_level<=16)begin param_pending<=1;param_record<={I_param_kind,I_param_level};end
            if(I_video_user)begin
                param_pending<=0;
                if(I_photo_album)param_frames<=0;
                else if(I_param_update && I_param_level<=16)begin
                    param_kind_l<=I_param_kind;param_level_l<=I_param_level;param_frames<=121;

                end else if(param_pending)begin
                    param_kind_l<=param_record[6:5];param_level_l<=param_record[4:0];param_frames<=121;

                end else if(param_frames!=0)param_frames<=param_frames-1'b1;
            end
        end
    end
    reg guard_l,recognition_l,motion_l,intrusion_l,valid_l,locked_l,lock_show_l;
    reg [3:0] seconds_l;
    reg [4:0] elapsed_l;
    reg [15:0] id_l;
    reg [63:0] digits_l;
    reg dx_neg_l,dy_neg_l,object_l,motion_active_l,album_l,guard_paused_l;
    reg [4:0] mode_code;
    reg [23:0] frame_bcd;
    integer fi;
    function [4:0] F_mode_code;
        input [3:0] mode;
        begin
            if(mode==12)begin
                if(!I_ae_auto_active || !I_ae_target_valid || I_ae_raw_gain>28)F_mode_code=12;
                else if(I_ae_raw_gain>16)F_mode_code=5'd30;
                else F_mode_code=5'd13+I_ae_raw_gain;
            end else if(mode>=1 && mode<=11)F_mode_code={1'b0,mode};
            else F_mode_code=0;
        end
    endfunction
    // Title glyph IDs, with all unused cells mapped to the blank glyph 63.
    function [5:0] F_mode_glyph;
        input [4:0] title;input [3:0] cell_number;
        begin
            case({title,cell_number})
                9'h000:F_mode_glyph=6'd0;
                9'h001:F_mode_glyph=6'd1;
                9'h002:F_mode_glyph=6'd2;
                9'h003:F_mode_glyph=6'd3;
                9'h010:F_mode_glyph=6'd4;
                9'h011:F_mode_glyph=6'd5;
                9'h012,9'h022,9'h072,9'h082,9'h0a2,9'h0b2,9'h0f2:F_mode_glyph=6'd6;
                9'h013,9'h023,9'h073,9'h083,9'h0a3,9'h0b3,9'h0f3:F_mode_glyph=6'd7;
                9'h020:F_mode_glyph=6'd8;
                9'h021:F_mode_glyph=6'd9;
                9'h030:F_mode_glyph=6'd10;
                9'h031:F_mode_glyph=6'd11;
                9'h032:F_mode_glyph=6'd12;
                9'h033:F_mode_glyph=6'd13;
                9'h040:F_mode_glyph=6'd14;
                9'h041:F_mode_glyph=6'd15;
                9'h042,9'h0e2:F_mode_glyph=6'd16;
                9'h043,9'h0e3:F_mode_glyph=6'd17;
                9'h050:F_mode_glyph=6'd18;
                9'h051:F_mode_glyph=6'd19;
                9'h052:F_mode_glyph=6'd20;
                9'h053:F_mode_glyph=6'd21;
                9'h060:F_mode_glyph=6'd22;
                9'h061:F_mode_glyph=6'd23;
                9'h062:F_mode_glyph=6'd24;
                9'h063:F_mode_glyph=6'd25;
                9'h070:F_mode_glyph=6'd26;
                9'h071,9'h0d1:F_mode_glyph=6'd27;
                9'h080:F_mode_glyph=6'd28;
                9'h081:F_mode_glyph=6'd29;
                9'h090:F_mode_glyph=6'd30;
                9'h091:F_mode_glyph=6'd31;
                9'h092:F_mode_glyph=6'd32;
                9'h093:F_mode_glyph=6'd33;
                9'h0a0:F_mode_glyph=6'd34;
                9'h0a1:F_mode_glyph=6'd35;
                9'h0b0:F_mode_glyph=6'd36;
                9'h0b1:F_mode_glyph=6'd37;
                9'h0c0:F_mode_glyph=6'd38;
                9'h0c1,9'h0e1,9'h101:F_mode_glyph=6'd39;
                9'h0c2:F_mode_glyph=6'd40;
                9'h0c3:F_mode_glyph=6'd41;
                9'h0d0:F_mode_glyph=6'd42;
                9'h0d2:F_mode_glyph=6'd43;
                9'h0d3:F_mode_glyph=6'd44;
                9'h0d4,9'h122:F_mode_glyph=6'd45;
                9'h0d5,9'h123:F_mode_glyph=6'd46;
                9'h0e0,9'h100:F_mode_glyph=6'd47;
                9'h0f0,9'h102,9'h120:F_mode_glyph=6'd48;
                9'h0f1,9'h103,9'h121:F_mode_glyph=6'd49;
                9'h110:F_mode_glyph=6'd50;
                9'h111:F_mode_glyph=6'd51;
                9'h112:F_mode_glyph=6'd52;
                9'h113:F_mode_glyph=6'd53;
                default:F_mode_glyph=6'd63;
            endcase
        end
    endfunction
    function [23:0] F_panel_rgb;
        input [23:0] pixel;
        begin
            F_panel_rgb[23:16]={1'b0,pixel[23:17]}+8'd12;
            F_panel_rgb[15:8] ={1'b0,pixel[15:9]}+8'd12;
            F_panel_rgb[7:0]  ={1'b0,pixel[7:1]}+8'd12;
        end
    endfunction

    // Compile-time text definition: {seven-bit message, five-bit cell} -> ASCII.
    // Runtime reads use the packed synchronous ROM below (one existing stage).
    // 0..11 video modes; 12 AE WAIT; 13..29 the seventeen AE gain captions.
    // 30 brand, 31 counter, 32..36 mode subtitles, 37..41 target states,
    // 42 dwell, 43 qualified, 44..46 class, 47 CX/CY, 48 DX/DY,
    // 49 LOCKED, 50 ACQUIRING, 51 LOST; all other messages/cells are spaces.
    function [7:0] F_text_character;
        input [6:0] message;input [4:0] cell_number;
        begin
            if(message==101)begin
                F_text_character="SAD TARGET          " >> ((19-cell_number)*8);
            end else if(message==100)begin
                case({message,cell_number})
                    12'd3200:F_text_character=8'h53;
                    12'd3201:F_text_character=8'h41;
                    12'd3202:F_text_character=8'h44;
                    12'd3203:F_text_character=8'h20;
                    12'd3204:F_text_character=8'h45;
                    12'd3205:F_text_character=8'h44;
                    12'd3206:F_text_character=8'h49;
                    12'd3207:F_text_character=8'h54;
                    default:F_text_character=8'h20;
                endcase
            end else if(message>=89 && message<=99)begin
                // Compile-time string slicing only; no new runtime text ROM.
                case(message)
                    89:F_text_character="STATIC TRACK        " >> ((19-cell_number)*8);
                    90:F_text_character="GUARD TRACK         " >> ((19-cell_number)*8);
                    91:F_text_character="RED TARGET          " >> ((19-cell_number)*8);
                    92:F_text_character="BLUE TARGET         " >> ((19-cell_number)*8);
                    93:F_text_character="STABLE              " >> ((19-cell_number)*8);
                    94:F_text_character="NORMAL              " >> ((19-cell_number)*8);
                    95:F_text_character="FAST                " >> ((19-cell_number)*8);
                    96:F_text_character="IN                  " >> ((19-cell_number)*8);
                    97:F_text_character="OUT 0.0/5.0S        " >> ((19-cell_number)*8);
                    99:F_text_character="COOP RANGE TRACK    " >> ((19-cell_number)*8);
                    default:F_text_character="WAIT                " >> ((19-cell_number)*8);
                endcase
            end else begin
            case({message,cell_number})
                11'h5c9,11'h5ca,11'h5e3,11'h5e4,11'h5e5,11'h5e6,11'h5eb,
                11'h5ec,11'h5ed,11'h5ee,11'h603,11'h604,11'h605,11'h606,
                11'h60b,11'h60c,11'h60d,11'h60e:F_text_character=8'h2d;
                11'h1c6,11'h1e8,11'h206,11'h229,11'h246,11'h268,11'h286,
                11'h2c6,11'h2e9,11'h306,11'h346,11'h366,11'h386,11'h547:F_text_character=8'h2e;
                11'h3c8,11'h406,11'h426,11'h446,11'h486,11'h4a6,11'h4c6,
                11'h4e6,11'h506,11'h526,11'h54a,11'h564,11'h5c7:F_text_character=8'h2f;
                11'h2c9,11'h309,11'h349,11'h368,11'h369,11'h389,11'h3e4,
                11'h3e5,11'h3e6,11'h3e7,11'h3e8,11'h3e9,11'h48a,11'h545,
                11'h546,11'h548,11'h54c,11'h54d:F_text_character=8'h30;
                11'h1aa,11'h1c5,11'h1c7,11'h1e7,11'h205,11'h228,11'h245,
                11'h267,11'h285:F_text_character=8'h31;
                11'h1c8,11'h1e9,11'h248,11'h2aa,11'h2c5,11'h2c7,11'h2e8,
                11'h305,11'h347,11'h489:F_text_character=8'h32;
                11'h207,11'h32a,11'h345,11'h365,11'h385:F_text_character=8'h33;
                11'h3aa:F_text_character=8'h34;
                11'h1c9,11'h1ea,11'h209,11'h22a,11'h249,11'h26a,11'h289,
                11'h2c8,11'h2ea,11'h308,11'h348,11'h367,11'h388:F_text_character=8'h35;
                11'h247:F_text_character=8'h36;
                11'h208,11'h269,11'h288,11'h307,11'h387,11'h488:F_text_character=8'h37;
                11'h287:F_text_character=8'h38;
                11'h006,11'h022,11'h026,11'h043,11'h0a1,11'h0a6,11'h121,
                11'h124,11'h141,11'h161,11'h180,11'h184,11'h1a0,11'h1c0,
                11'h1e0,11'h1e4,11'h200,11'h220,11'h224,11'h240,11'h260,
                11'h264,11'h280,11'h2a0,11'h2c0,11'h2e0,11'h2e4,11'h300,
                11'h320,11'h324,11'h340,11'h360,11'h380,11'h3a0,11'h3c0,
                11'h402,11'h422,11'h42a,11'h44a,11'h4a2,11'h4c2,11'h4c8,
                11'h4e2,11'h4e9,11'h502,11'h522,11'h528,11'h542,11'h568,
                11'h5c1,11'h643,11'h663:F_text_character=8'h41;
                11'h040,11'h082:F_text_character=8'h42;
                11'h025,11'h06a,11'h100,11'h146,11'h160,11'h3c6,11'h3e0,
                11'h440,11'h46b,11'h4aa,11'h584,11'h587,11'h5e0,11'h5e8,
                11'h627,11'h644:F_text_character=8'h43;
                11'h404,11'h424,11'h467,11'h482,11'h4ad,11'h52c,11'h56e,
                11'h582,11'h600,11'h608,11'h62a:F_text_character=8'h44;
                11'h028,11'h068,11'h083,11'h0c0,11'h0e3,11'h144,11'h181,
                11'h1a5,11'h1c1,11'h1e1,11'h201,11'h221,11'h241,11'h261,
                11'h281,11'h2a5,11'h2c1,11'h2e1,11'h301,11'h321,11'h341,
                11'h361,11'h381,11'h3a5,11'h429,11'h42e,11'h44c,11'h468,
                11'h46a,11'h483,11'h4a4,11'h4ac,11'h4c4,11'h4e4,11'h4ec,
                11'h504,11'h524,11'h52b,11'h56d,11'h581,11'h589,11'h5a2,
                11'h5c4,11'h629,11'h666:F_text_character=8'h45;
                11'h140,11'h428,11'h56b:F_text_character=8'h46;
                11'h003,11'h020,11'h0a0,11'h120,11'h1c3,11'h1e3,11'h203,
                11'h223,11'h243,11'h263,11'h283,11'h2c3,11'h2e3,11'h303,
                11'h323,11'h343,11'h363,11'h383,11'h3c4,11'h400,11'h420,
                11'h4cb,11'h4eb,11'h5c3,11'h64b,11'h665:F_text_character=8'h47;
                11'h060,11'h06b,11'h449:F_text_character=8'h48;
                11'h002,11'h004,11'h041,11'h061,11'h0a5,11'h0c4,11'h0e0,
                11'h185,11'h1e5,11'h225,11'h265,11'h2e5,11'h325,11'h3c5,
                11'h3cb,11'h3cd,11'h40b,11'h463,11'h481,11'h4ca,11'h508,
                11'h50e,11'h562,11'h56a,11'h56c,11'h585,11'h5a8,11'h647,
                11'h649:F_text_character=8'h49;
                11'h4ab,11'h628:F_text_character=8'h4b;
                11'h007,11'h027,11'h084,11'h142,11'h148,11'h3c2,11'h442,
                11'h4a8,11'h4c9,11'h4ef,11'h569,11'h588,11'h5ac,11'h625,
                11'h669:F_text_character=8'h4c;
                11'h122,11'h123,11'h408,11'h460,11'h52a:F_text_character=8'h4d;
                11'h005,11'h042,11'h0a7,11'h0c6,11'h0e1,11'h166,11'h1e6,
                11'h226,11'h266,11'h2e6,11'h326,11'h3c1,11'h3cf,11'h3e1,
                11'h40d,11'h465,11'h4cc,11'h509,11'h510,11'h5a4,11'h5aa,
                11'h64a:F_text_character=8'h4e;
                11'h000,11'h081,11'h0c2,11'h0c5,11'h102,11'h147,11'h149,
                11'h164,11'h165,11'h1a3,11'h2a3,11'h3a3,11'h3c3,11'h3ce,
                11'h409,11'h40c,11'h441,11'h443,11'h461,11'h464,11'h484,
                11'h4a9,11'h4f0,11'h50f,11'h561,11'h626,11'h66a:F_text_character=8'h4f;
                11'h103,11'h1a7,11'h2a7,11'h3a7,11'h44b,11'h48b,11'h610:F_text_character=8'h50;
                11'h566,11'h645:F_text_character=8'h51;
                11'h001,11'h021,11'h044,11'h067,11'h0c1,11'h0e4,11'h101,
                11'h14a,11'h162,11'h403,11'h423,11'h42d,11'h444,11'h4ea,
                11'h50b,11'h529,11'h560,11'h580,11'h586,11'h5a1,11'h5a7,
                11'h5c2,11'h648,11'h664:F_text_character=8'h52;
                11'h024,11'h062,11'h065,11'h080,11'h0a3,11'h0a4,11'h0c3,
                11'h143,11'h3cc,11'h448,11'h4a0,11'h4c0,11'h4e0,11'h4f1,
                11'h500,11'h50d,11'h520,11'h540,11'h54f,11'h66b:F_text_character=8'h53;
                11'h063,11'h066,11'h069,11'h0e5,11'h163,11'h186,11'h1a2,
                11'h2a2,11'h3a2,11'h3e2,11'h40a,11'h42b,11'h462,11'h469,
                11'h46c,11'h4a1,11'h4a3,11'h4c1,11'h4c3,11'h4e1,11'h4e3,
                11'h4e8,11'h4ed,11'h4f2,11'h501,11'h503,11'h50a,11'h521,
                11'h523,11'h541,11'h5a6,11'h5c0,11'h5c5,11'h662,11'h667,
                11'h66c:F_text_character=8'h54;
                11'h0a2,11'h1a1,11'h2a1,11'h3a1,11'h401,11'h421,11'h42c,
                11'h50c,11'h567,11'h646:F_text_character=8'h55;
                11'h0e2,11'h3ca,11'h480:F_text_character=8'h56;
                11'h183:F_text_character=8'h57;
                11'h1a6,11'h1ab,11'h1ca,11'h1eb,11'h20a,11'h22b,11'h24a,
                11'h26b,11'h28a,11'h2a6,11'h2ab,11'h2ca,11'h2eb,11'h30a,
                11'h32b,11'h34a,11'h36a,11'h38a,11'h3a6,11'h3ab,11'h5e1,
                11'h601,11'h611:F_text_character=8'h58;
                11'h023,11'h045,11'h543,11'h5e9,11'h609:F_text_character=8'h59;
                11'h680:F_text_character=8'h50;
                11'h681:F_text_character=8'h48;
                11'h682:F_text_character=8'h4f;
                11'h683:F_text_character=8'h54;
                11'h684:F_text_character=8'h4f;
                11'h685:F_text_character=8'h20;
                11'h686:F_text_character=8'h41;
                11'h687:F_text_character=8'h4c;
                11'h688:F_text_character=8'h42;
                11'h689:F_text_character=8'h55;
                11'h68a:F_text_character=8'h4d;
                12'h6a0:F_text_character=8'h42;
                12'h6a1:F_text_character=8'h41;
                12'h6a2:F_text_character=8'h43;
                12'h6a3:F_text_character=8'h4b;
                12'h6a4:F_text_character=8'h47;
                12'h6a5:F_text_character=8'h52;
                12'h6a6:F_text_character=8'h4f;
                12'h6a7:F_text_character=8'h55;
                12'h6a8:F_text_character=8'h4e;
                12'h6a9:F_text_character=8'h44;
                12'h6ab:F_text_character=8'h4c;
                12'h6ac:F_text_character=8'h45;
                12'h6ad:F_text_character=8'h41;
                12'h6ae:F_text_character=8'h52;
                12'h6af:F_text_character=8'h4e;
                12'h6c0:F_text_character=8'h44;
                12'h6c1:F_text_character=8'h45;
                12'h6c2:F_text_character=8'h54;
                12'h6c3:F_text_character=8'h45;
                12'h6c4:F_text_character=8'h43;
                12'h6c5:F_text_character=8'h54;
                12'h6c7:F_text_character=8'h52;
                12'h6c8:F_text_character=8'h45;
                12'h6c9:F_text_character=8'h41;
                12'h6ca:F_text_character=8'h44;
                12'h6cb:F_text_character=8'h59;
                12'h6e0:F_text_character=8'h54;
                12'h6e1:F_text_character=8'h41;
                12'h6e2:F_text_character=8'h42;
                12'h6e3:F_text_character=8'h4c;
                12'h6e4:F_text_character=8'h45;
                12'h6e6:F_text_character=8'h4f;
                12'h6e7:F_text_character=8'h56;
                12'h6e8:F_text_character=8'h45;
                12'h6e9:F_text_character=8'h52;
                12'h6ea:F_text_character=8'h46;
                12'h6eb:F_text_character=8'h4c;
                12'h6ec:F_text_character=8'h4f;
                12'h6ed:F_text_character=8'h57;
                12'h700:F_text_character=8'h54;
                12'h701:F_text_character=8'h41;
                12'h702:F_text_character=8'h52;
                12'h703:F_text_character=8'h47;
                12'h704:F_text_character=8'h45;
                12'h705:F_text_character=8'h54;
                12'h706:F_text_character=8'h53;
                12'h708:F_text_character=8'h2d;
                12'h720:F_text_character=8'h57;
                12'h721:F_text_character=8'h3a;
                12'h722:F_text_character=8'h2d;
                12'h723:F_text_character=8'h2d;
                12'h724:F_text_character=8'h2d;
                12'h725:F_text_character=8'h2d;
                12'h727:F_text_character=8'h48;
                12'h728:F_text_character=8'h3a;
                12'h729:F_text_character=8'h2d;
                12'h72a:F_text_character=8'h2d;
                12'h72b:F_text_character=8'h2d;
                12'h72c:F_text_character=8'h2d;
                12'h72e:F_text_character=8'h50;
                12'h72f:F_text_character=8'h58;
                12'h740:F_text_character=8'h46;
                12'h741:F_text_character=8'h52;
                12'h742:F_text_character=8'h45;
                12'h743:F_text_character=8'h53;
                12'h744:F_text_character=8'h48;
                12'h746:F_text_character=8'h44;
                12'h747:F_text_character=8'h45;
                12'h748:F_text_character=8'h54;
                12'h749:F_text_character=8'h45;
                12'h74a:F_text_character=8'h43;
                12'h74b:F_text_character=8'h54;
                12'h74c:F_text_character=8'h49;
                12'h74d:F_text_character=8'h4f;
                12'h74e:F_text_character=8'h4e;
                12'h74f:F_text_character=8'h53;
                12'h760:F_text_character=8'h55;
                12'h761:F_text_character=8'h4e;
                12'h762:F_text_character=8'h49;
                12'h763:F_text_character=8'h54;
                12'h764:F_text_character=8'h53;
                12'h765:F_text_character=8'h3a;
                12'h767:F_text_character=8'h50;
                12'h768:F_text_character=8'h49;
                12'h769:F_text_character=8'h58;
                12'h76a:F_text_character=8'h45;
                12'h76b:F_text_character=8'h4c;
                12'h76c:F_text_character=8'h53;
                12'h780:F_text_character=8'h43;
                12'h781:F_text_character=8'h45;
                12'h782:F_text_character=8'h4e;
                12'h783:F_text_character=8'h54;
                12'h784:F_text_character=8'h45;
                12'h785:F_text_character=8'h52;
                12'h786:F_text_character=8'h45;
                12'h787:F_text_character=8'h44;
                12'h7a0:F_text_character=8'h43;
                12'h7a1:F_text_character=8'h45;
                12'h7a2:F_text_character=8'h4e;
                12'h7a3:F_text_character=8'h54;
                12'h7a4:F_text_character=8'h45;
                12'h7a5:F_text_character=8'h52;
                12'h7a7:F_text_character=8'h2b;
                12'h7a8:F_text_character=8'h2f;
                12'h7a9:F_text_character=8'h2d;
                12'h7aa:F_text_character=8'h38;
                12'h7ab:F_text_character=8'h30;
                12'h7ac:F_text_character=8'h2f;
                12'h7ad:F_text_character=8'h34;
                12'h7ae:F_text_character=8'h35;
                12'h800:F_text_character=8'h43;
                12'h801:F_text_character=8'h4f;
                12'h802:F_text_character=8'h4e;
                12'h803:F_text_character=8'h54;
                12'h804:F_text_character=8'h52;
                12'h805:F_text_character=8'h41;
                12'h806:F_text_character=8'h53;
                12'h807:F_text_character=8'h54;
                12'h820:F_text_character=8'h53;
                12'h821:F_text_character=8'h41;
                12'h822:F_text_character=8'h54;
                12'h823:F_text_character=8'h55;
                12'h824:F_text_character=8'h52;
                12'h825:F_text_character=8'h41;
                12'h826:F_text_character=8'h54;
                12'h827:F_text_character=8'h49;
                12'h828:F_text_character=8'h4f;
                12'h829:F_text_character=8'h4e;
                12'h840:F_text_character=8'h44;
                12'h841:F_text_character=8'h47;
                12'h843:F_text_character=8'h2f;
                12'h845:F_text_character=8'h42;
                12'h846:F_text_character=8'h52;
                12'h847:F_text_character=8'h49;
                12'h848:F_text_character=8'h47;
                12'h849:F_text_character=8'h48;
                12'h84a:F_text_character=8'h54;
                12'h84b:F_text_character=8'h4e;
                12'h84c:F_text_character=8'h45;
                12'h84d:F_text_character=8'h53;
                12'h84e:F_text_character=8'h53;
                12'h860:F_text_character=8'h43;
                12'h861:F_text_character=8'h41;
                12'h862:F_text_character=8'h4d;
                12'h863:F_text_character=8'h45;
                12'h864:F_text_character=8'h52;
                12'h865:F_text_character=8'h41;
                12'h867:F_text_character=8'h47;
                12'h868:F_text_character=8'h41;
                12'h869:F_text_character=8'h49;
                12'h86a:F_text_character=8'h4e;
                12'h880:F_text_character=8'h4c;
                12'h881:F_text_character=8'h56;
                12'h883:F_text_character=8'h2d;
                12'h884:F_text_character=8'h2d;
                12'h885:F_text_character=8'h2f;
                12'h886:F_text_character=8'h31;
                12'h887:F_text_character=8'h36;
                12'h88a:F_text_character=8'h2d;
                12'h88b:F_text_character=8'h2e;
                12'h88c:F_text_character=8'h2d;
                12'h88d:F_text_character=8'h2d;
                12'h88e:F_text_character=8'h2d;
                12'h88f:F_text_character=8'h58;
                12'h8a0:F_text_character=8'h50;
                12'h8a1:F_text_character=8'h48;
                12'h8a2:F_text_character=8'h4f;
                12'h8a3:F_text_character=8'h54;
                12'h8a4:F_text_character=8'h4f;
                12'h8a6:F_text_character=8'h4e;
                12'h8a7:F_text_character=8'h4f;
                12'h8a9:F_text_character=8'h43;
                12'h8aa:F_text_character=8'h41;
                12'h8ab:F_text_character=8'h52;
                12'h8ac:F_text_character=8'h44;
                12'h8c0:F_text_character=8'h50;
                12'h8c1:F_text_character=8'h48;
                12'h8c2:F_text_character=8'h4f;
                12'h8c3:F_text_character=8'h54;
                12'h8c4:F_text_character=8'h4f;
                12'h8c6:F_text_character=8'h46;
                12'h8c7:F_text_character=8'h4f;
                12'h8c8:F_text_character=8'h52;
                12'h8c9:F_text_character=8'h4d;
                12'h8ca:F_text_character=8'h41;
                12'h8cb:F_text_character=8'h54;
                12'h8e0:F_text_character=8'h50;
                12'h8e1:F_text_character=8'h48;
                12'h8e2:F_text_character=8'h4f;
                12'h8e3:F_text_character=8'h54;
                12'h8e4:F_text_character=8'h4f;
                12'h8e6:F_text_character=8'h52;
                12'h8e7:F_text_character=8'h45;
                12'h8e8:F_text_character=8'h41;
                12'h8e9:F_text_character=8'h44;
                12'h8ea:F_text_character=8'h59;
                12'h900:F_text_character=8'h50;
                12'h901:F_text_character=8'h48;
                12'h902:F_text_character=8'h4f;
                12'h903:F_text_character=8'h54;
                12'h904:F_text_character=8'h4f;
                12'h906:F_text_character=8'h43;
                12'h907:F_text_character=8'h41;
                12'h908:F_text_character=8'h50;
                12'h909:F_text_character=8'h54;
                12'h90a:F_text_character=8'h55;
                12'h90b:F_text_character=8'h52;
                12'h90c:F_text_character=8'h45;
                12'h920:F_text_character=8'h50;
                12'h921:F_text_character=8'h48;
                12'h922:F_text_character=8'h4f;
                12'h923:F_text_character=8'h54;
                12'h924:F_text_character=8'h4f;
                12'h926:F_text_character=8'h53;
                12'h927:F_text_character=8'h41;
                12'h928:F_text_character=8'h56;
                12'h929:F_text_character=8'h49;
                12'h92a:F_text_character=8'h4e;
                12'h92b:F_text_character=8'h47;
                12'h940:F_text_character=8'h50;
                12'h941:F_text_character=8'h48;
                12'h942:F_text_character=8'h4f;
                12'h943:F_text_character=8'h54;
                12'h944:F_text_character=8'h4f;
                12'h946:F_text_character=8'h4c;
                12'h947:F_text_character=8'h4f;
                12'h948:F_text_character=8'h41;
                12'h949:F_text_character=8'h44;
                12'h94a:F_text_character=8'h49;
                12'h94b:F_text_character=8'h4e;
                12'h94c:F_text_character=8'h47;
                12'h960:F_text_character=8'h50;
                12'h961:F_text_character=8'h48;
                12'h962:F_text_character=8'h4f;
                12'h963:F_text_character=8'h54;
                12'h964:F_text_character=8'h4f;
                12'h966:F_text_character=8'h45;
                12'h967:F_text_character=8'h52;
                12'h968:F_text_character=8'h52;
                12'h969:F_text_character=8'h4f;
                12'h96a:F_text_character=8'h52;
                12'h96c:F_text_character=8'h30;
                12'h96d:F_text_character=8'h36;
                12'h980:F_text_character=8'h50;
                12'h981:F_text_character=8'h48;
                12'h982:F_text_character=8'h4f;
                12'h983:F_text_character=8'h54;
                12'h984:F_text_character=8'h4f;
                12'h986:F_text_character=8'h46;
                12'h987:F_text_character=8'h55;
                12'h988:F_text_character=8'h4c;
                12'h989:F_text_character=8'h4c;
                12'h9a0:F_text_character=8'h50;
                12'h9a1:F_text_character=8'h48;
                12'h9a2:F_text_character=8'h4f;
                12'h9a3:F_text_character=8'h54;
                12'h9a4:F_text_character=8'h4f;
                12'h9a6:F_text_character=8'h42;
                12'h9a7:F_text_character=8'h55;
                12'h9a8:F_text_character=8'h53;
                12'h9a9:F_text_character=8'h59;
                12'h9c0:F_text_character=8'h50;
                12'h9c1:F_text_character=8'h48;
                12'h9c2:F_text_character=8'h4f;
                12'h9c3:F_text_character=8'h54;
                12'h9c4:F_text_character=8'h4f;
                12'h9c6:F_text_character=8'h45;
                12'h9c7:F_text_character=8'h4d;
                12'h9c8:F_text_character=8'h50;
                12'h9c9:F_text_character=8'h54;
                12'h9ca:F_text_character=8'h59;
                12'h9e0:F_text_character=8'h50;
                12'h9e1:F_text_character=8'h48;
                12'h9e2:F_text_character=8'h4f;
                12'h9e3:F_text_character=8'h54;
                12'h9e4:F_text_character=8'h4f;
                12'h9e6:F_text_character=8'h41;
                12'h9e7:F_text_character=8'h52;
                12'h9e8:F_text_character=8'h4d;
                12'h9e9:F_text_character=8'h45;
                12'h9ea:F_text_character=8'h44;
                12'ha00:F_text_character=8'h50;
                12'ha01:F_text_character=8'h48;
                12'ha02:F_text_character=8'h4f;
                12'ha03:F_text_character=8'h54;
                12'ha04:F_text_character=8'h4f;
                12'ha06:F_text_character=8'h45;
                12'ha07:F_text_character=8'h52;
                12'ha08:F_text_character=8'h52;
                12'ha09:F_text_character=8'h4f;
                12'ha0a:F_text_character=8'h52;
                12'ha0c:F_text_character=8'h30;
                12'ha0d:F_text_character=8'h42;
                12'ha20:F_text_character=8'h50;
                12'ha21:F_text_character=8'h48;
                12'ha22:F_text_character=8'h4f;
                12'ha23:F_text_character=8'h54;
                12'ha24:F_text_character=8'h4f;
                12'ha26:F_text_character=8'h45;
                12'ha27:F_text_character=8'h52;
                12'ha28:F_text_character=8'h52;
                12'ha29:F_text_character=8'h4f;
                12'ha2a:F_text_character=8'h52;
                12'ha2c:F_text_character=8'h30;
                12'ha2d:F_text_character=8'h43;
                12'ha40:F_text_character=8'h50;
                12'ha41:F_text_character=8'h48;
                12'ha42:F_text_character=8'h4f;
                12'ha43:F_text_character=8'h54;
                12'ha44:F_text_character=8'h4f;
                12'ha46:F_text_character=8'h45;
                12'ha47:F_text_character=8'h52;
                12'ha48:F_text_character=8'h52;
                12'ha49:F_text_character=8'h4f;
                12'ha4a:F_text_character=8'h52;
                12'ha4c:F_text_character=8'h30;
                12'ha4d:F_text_character=8'h44;
                12'ha60:F_text_character=8'h50;
                12'ha61:F_text_character=8'h48;
                12'ha62:F_text_character=8'h4f;
                12'ha63:F_text_character=8'h54;
                12'ha64:F_text_character=8'h4f;
                12'ha66:F_text_character=8'h45;
                12'ha67:F_text_character=8'h52;
                12'ha68:F_text_character=8'h52;
                12'ha69:F_text_character=8'h4f;
                12'ha6a:F_text_character=8'h52;
                12'ha6c:F_text_character=8'h30;
                12'ha6d:F_text_character=8'h45;
                12'ha80:F_text_character=8'h50;
                12'ha81:F_text_character=8'h48;
                12'ha82:F_text_character=8'h4f;
                12'ha83:F_text_character=8'h54;
                12'ha84:F_text_character=8'h4f;
                12'ha86:F_text_character=8'h45;
                12'ha87:F_text_character=8'h52;
                12'ha88:F_text_character=8'h52;
                12'ha89:F_text_character=8'h4f;
                12'ha8a:F_text_character=8'h52;
                12'ha8c:F_text_character=8'h30;
                12'ha8d:F_text_character=8'h46;
                12'haa0:F_text_character=8'h44;
                12'haa1:F_text_character=8'h45;
                12'haa2:F_text_character=8'h46;
                12'haa4:F_text_character=8'h30;
                12'haa5:F_text_character=8'h38;
                12'h7c0:F_text_character=8'h52;
                12'h7c1:F_text_character=8'h45;
                12'h7c2:F_text_character=8'h42;
                12'h7c3:F_text_character=8'h55;
                12'h7c4:F_text_character=8'h49;
                12'h7c5:F_text_character=8'h4c;
                12'h7c6:F_text_character=8'h44;
                12'h7c8:F_text_character=8'h42;
                12'h7c9:F_text_character=8'h41;
                12'h7ca:F_text_character=8'h43;
                12'h7cb:F_text_character=8'h4b;
                12'h7cc:F_text_character=8'h47;
                12'h7cd:F_text_character=8'h52;
                12'h7ce:F_text_character=8'h4f;
                12'h7cf:F_text_character=8'h55;
                12'h7d0:F_text_character=8'h4e;
                12'h7d1:F_text_character=8'h44;
                12'hac0:F_text_character=8'h53;
                12'hac1:F_text_character=8'h54;
                12'hac2:F_text_character=8'h41;
                12'hac3:F_text_character=8'h54;
                12'hac4:F_text_character=8'h45;
                12'hac6:F_text_character=8'h2f;
                12'hac8:F_text_character=8'h45;
                12'hac9:F_text_character=8'h44;
                12'haca:F_text_character=8'h49;
                12'hacb:F_text_character=8'h54;
                12'hacc:F_text_character=8'h49;
                12'hacd:F_text_character=8'h4e;
                12'hace:F_text_character=8'h47;
                12'hb00:F_text_character=8'h47;
                12'hb01:F_text_character=8'h55;
                12'hb02:F_text_character=8'h41;
                12'hb03:F_text_character=8'h52;
                12'hb04:F_text_character=8'h44;
                12'hb06:F_text_character=8'h2f;
                12'hb08:F_text_character=8'h54;
                12'hb09:F_text_character=8'h52;
                12'hb0a:F_text_character=8'h41;
                12'hb0b:F_text_character=8'h43;
                12'hb0c:F_text_character=8'h4b;
                12'hb0d:F_text_character=8'h49;
                12'hb0e:F_text_character=8'h4e;
                12'hb0f:F_text_character=8'h47;
                12'hae0:F_text_character=8'h43;
                12'hae1:F_text_character=8'h4f;
                12'hae2:F_text_character=8'h4e;
                12'hae3:F_text_character=8'h46;
                12'hae4:F_text_character=8'h49;
                12'hae5:F_text_character=8'h52;
                12'hae6:F_text_character=8'h4d;
                12'hae8:F_text_character=8'h41;
                12'hae9:F_text_character=8'h52;
                12'haea:F_text_character=8'h45;
                12'haeb:F_text_character=8'h41;
                12'h5a0:F_text_character=8'h42;
                12'h5a1:F_text_character=8'h4c;
                12'h5a2:F_text_character=8'h55;
                12'h5a3:F_text_character=8'h45;
                12'h5a4:F_text_character=8'h20;
                12'h5a5:F_text_character=8'h52;
                12'h5a6:F_text_character=8'h45;
                12'h5a7:F_text_character=8'h43;
                12'h5a8:F_text_character=8'h54;
                default:F_text_character=8'h20;
            endcase
            end
        end
    endfunction



    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            sad_saved_l<=0;sad_l<=0;sad_running_l<=0;sad_live_l<=0;sad_inside_l<=0;
            guard_l<=0;guard_paused_l<=0;recognition_l<=0;motion_l<=0;intrusion_l<=0;valid_l<=0;
            locked_l<=0;lock_show_l<=0;seconds_l<=0;elapsed_l<=0;id_l<=0;digits_l<=0;
            dx_neg_l<=0;dy_neg_l<=0;object_l<=0;motion_active_l<=0;album_l<=0;
            mode_code<=0;frame_bcd<=0;
            static_track_l<=0;track_selected_l<=0;track_speed_l<=1;track_outside_l<=0;track_steps_l<=0;
            range_l<=0;range_valid_l<=0;range_applied_l<=0;range_bcd_l<=0;
        end else if(I_video_user)begin
            sad_saved_l<=I_sad_id[15:8]==8'h39;sad_l<=sad_owner;sad_running_l<=I_sad_running;sad_live_l<=I_sad_valid;sad_inside_l<=I_guard_region_inside;
            guard_l<=GUARD_FEATURE && guard_ui_session;guard_paused_l<=guard_ui_paused;
            recognition_l<=I_guard_recognition && !guard_ui_paused;
            motion_l<=I_guard_motion;intrusion_l<=I_guard_intrusion && !guard_ui_paused;
            seconds_l<=I_guard_seconds;elapsed_l<=guard_ui_paused ? 5'd0 : I_guard_elapsed;
            valid_l<=target_valid && (!guard_ui_paused || sad_owner) && hud_record_current && sad_guard_live;
            locked_l<=target_locked && target_valid && !guard_ui_paused &&
                (!sad_guard_owner || (hud_record_current && sad_guard_live));lock_show_l<=lock_visible;
            id_l<=target_id;digits_l<=target_digits;dx_neg_l<=target_dx_neg;dy_neg_l<=target_dy_neg;
            object_l<=I_object_active;motion_active_l<=I_motion_active;album_l<=PHOTO_FEATURE && I_photo_album;
            mode_code<=F_mode_code(I_proc_mode);
            static_track_l<=static_track;track_selected_l<=track_selected;track_speed_l<=track_speed;
            track_outside_l<=track_outside;track_steps_l<=track_steps;
            range_l<=range_active;range_valid_l<=range_valid;
            range_applied_l<=range_applied;range_bcd_l<=range_bcd;
            // Retain the original live six-digit frame counter in the small brand chip.
            for(fi=0;fi<6;fi=fi+1)begin
                if(fi==0)begin
                    if(frame_bcd[3:0]==9)frame_bcd[3:0]<=0;
                    else frame_bcd[3:0]<=frame_bcd[3:0]+1'b1;
                end else if((frame_bcd & ((24'h1 << (fi*4))-1)) ==
                    (24'h999999 & ((24'h1 << (fi*4))-1)))begin
                    if(frame_bcd[fi*4+:4]==9)frame_bcd[fi*4+:4]<=0;
                    else frame_bcd[fi*4+:4]<=frame_bcd[fi*4+:4]+1'b1;
                end
            end
        end
    end
    // One single-read ERAM for frame-constant display metadata. Only this
    // observer is delayed; the video, guard controller and SAD are unchanged.
    // Parameter value, guard fill, return fill are ready four clocks after SOF.
    localparam [7:0] GUARD_BAR_WIDTH=INFO_FEATURE ? 8'd192 : 8'd160;
    (* ram_style="block" *) reg [19:0] hud_metadata_rom [0:1023];
    integer metadata_i,metadata_seconds,metadata_elapsed;
    initial begin
        for(metadata_i=0;metadata_i<1024;metadata_i=metadata_i+1)
            hud_metadata_rom[metadata_i]=20'd0;
        for(metadata_i=0;metadata_i<128;metadata_i=metadata_i+1)
            hud_metadata_rom[metadata_i]=F_parameter_value(metadata_i[6:5],metadata_i[4:0]);
        for(metadata_seconds=0;metadata_seconds<16;metadata_seconds=metadata_seconds+1)
            for(metadata_elapsed=0;metadata_elapsed<32;metadata_elapsed=metadata_elapsed+1)
                if(metadata_seconds==0 || metadata_elapsed>=metadata_seconds*2)
                    hud_metadata_rom[128+metadata_seconds*32+metadata_elapsed]=GUARD_BAR_WIDTH;
                else hud_metadata_rom[128+metadata_seconds*32+metadata_elapsed]=
                    (metadata_elapsed*(GUARD_BAR_WIDTH/2))/metadata_seconds;
        for(metadata_i=0;metadata_i<16;metadata_i=metadata_i+1)
            hud_metadata_rom[640+metadata_i]=F_track_fill(metadata_i[3:0]);
    end
    reg [9:0] hud_metadata_address;
    reg [19:0] hud_metadata_q;
    // No reset on the memory read register: preserve block-memory inference.
    always @(posedge I_clk)hud_metadata_q<=hud_metadata_rom[hud_metadata_address];
    reg [2:0] hud_metadata_step;
    reg [8:0] hud_guard_key;
    reg hud_parameter_due,hud_guard_partial;
    reg [7:0] guard_fill,track_fill;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            hud_metadata_address<=0;hud_metadata_step<=0;hud_guard_key<=0;
            hud_parameter_due<=0;hud_guard_partial<=0;
            param_value_l<=0;guard_fill<=0;track_fill<=0;
        end else begin
            if(hud_metadata_step==2 && hud_parameter_due)param_value_l<=hud_metadata_q;
            if(I_video_user)begin
                hud_metadata_step<=1;
                // Same-edge commands win, then a queued command, then the
                // previous caption. Re-read the latter to recover after a
                // malformed/very short frame interrupts a pending lookup.
                hud_metadata_address<={3'd0,
                    (I_param_update && I_param_level<=16) ? {I_param_kind,I_param_level} :
                    param_pending ? param_record : {param_kind_l,param_level_l}};
                hud_parameter_due<=INFO_FEATURE && !I_photo_album &&
                    ((I_param_update && I_param_level<=16) || param_pending || param_frames!=0);
                hud_guard_key<={I_guard_seconds,I_guard_elapsed};
                hud_guard_partial<=GUARD_FEATURE && guard_ui_session && !guard_ui_paused &&
                    !I_guard_recognition && I_guard_intrusion && I_guard_seconds!=0 &&
                    I_guard_elapsed<{I_guard_seconds,1'b0};
                if(GUARD_FEATURE)begin
                    guard_fill<=0;
                    if(guard_ui_session && !guard_ui_paused &&
                       (I_guard_recognition || (I_guard_intrusion &&
                        (I_guard_seconds==0 || I_guard_elapsed>={I_guard_seconds,1'b0}))))
                        guard_fill<=GUARD_BAR_WIDTH;
                end
            end else case(hud_metadata_step)
                1:begin hud_metadata_address<=10'd128+{1'b0,hud_guard_key};hud_metadata_step<=2;end
                2:begin hud_metadata_address<=10'd640+{6'd0,track_steps_l};hud_metadata_step<=3;end
                3:begin if(hud_guard_partial)guard_fill<=hud_metadata_q[7:0];hud_metadata_step<=4;end
                4:begin track_fill<=hud_metadata_q[7:0];hud_metadata_step<=0;end
                default:begin end
            endcase
        end
    end
    wire [11:0] guard_fill_right=12'd24+{4'd0,guard_fill};
    wire [7:0] lat_char;
    wire [3:0] lat_row,lat_col;
    wire lat_request,lat_region,lat_ink;
    wire shared_pixel;
    generate if(SHOW_LATENCY)begin:g_latency
        latency_osd #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.EXTERNAL_FONT(1),.FONT_PIXEL_DELAYED(1)) u_latency_osd(
            .clk(I_clk),.rst_n(I_rst_n),.frame_start(I_video_user),.de(I_video_de),
            .x(S_x),.y(S_y),.proc_mode(I_proc_mode),.row_enable(I_latency_enable),
            .age_bcd(I_latency_bcd),.age_ticks(I_latency_ticks),.age_valid(I_latency_valid),
            .detect_bcd(I_detect_latency_bcd),.detect_valid(I_detect_latency_valid),
            .region_d2(lat_region),.ink_d2(lat_ink),.font_char(lat_char),
            .font_row(lat_row),.font_col(lat_col),.font_request(lat_request),.external_font_pixel(shared_pixel));
    end else begin:g_no_latency
        assign lat_region=0;assign lat_ink=0;assign lat_request=0;
        assign lat_char=32;assign lat_row=0;assign lat_col=0;
    end endgenerate
    wire photo_ink,photo_region,photo_error;
    wire [7:0] photo_font_character,photo_font_bits;
    wire [3:0] photo_font_row;
    generate if(PHOTO_FEATURE)begin:g_photo
        photo_album_osd #(.EXTERNAL_FONT(1)) album_osd(.clk(I_clk),.rst_n(I_rst_n),.frame_start(I_video_user),.de(I_video_de),
            .album(I_photo_album),.x(S_x),.y(S_y),.index(I_photo_index),.count(I_photo_count),
            .status(I_photo_status),.ink_d2(photo_ink),.region_d2(photo_region),.error_d2(photo_error),
            .font_character(photo_font_character),.font_row(photo_font_row),.external_font_bits(photo_font_bits));
    end else begin:g_no_photo
        assign photo_ink=0;assign photo_region=0;assign photo_error=0;
        assign photo_font_character=8'd32;assign photo_font_row=4'd0;
    end endgenerate

    // Constant metadata lookup, no pixel multiplier or divider.
    function [19:0] F_parameter_value;
        input [1:0] kind;input [4:0] level;
        begin case({kind,level})
            7'h00:F_parameter_value=20'h00500;
            7'h01:F_parameter_value=20'h00563;
            7'h02:F_parameter_value=20'h00625;
            7'h03:F_parameter_value=20'h00688;
            7'h04:F_parameter_value=20'h00750;
            7'h05:F_parameter_value=20'h00813;
            7'h06:F_parameter_value=20'h00875;
            7'h07:F_parameter_value=20'h00938;
            7'h08:F_parameter_value=20'h01000;
            7'h09:F_parameter_value=20'h01125;
            7'h0a:F_parameter_value=20'h01250;
            7'h0b:F_parameter_value=20'h01375;
            7'h0c:F_parameter_value=20'h01500;
            7'h0d:F_parameter_value=20'h01625;
            7'h0e:F_parameter_value=20'h01750;
            7'h0f:F_parameter_value=20'h01875;
            7'h10:F_parameter_value=20'h02000;
            7'h20:F_parameter_value=20'h00500;
            7'h21:F_parameter_value=20'h00563;
            7'h22:F_parameter_value=20'h00625;
            7'h23:F_parameter_value=20'h00688;
            7'h24:F_parameter_value=20'h00750;
            7'h25:F_parameter_value=20'h00813;
            7'h26:F_parameter_value=20'h00875;
            7'h27:F_parameter_value=20'h00938;
            7'h28:F_parameter_value=20'h01000;
            7'h29:F_parameter_value=20'h01125;
            7'h2a:F_parameter_value=20'h01250;
            7'h2b:F_parameter_value=20'h01375;
            7'h2c:F_parameter_value=20'h01500;
            7'h2d:F_parameter_value=20'h01625;
            7'h2e:F_parameter_value=20'h01750;
            7'h2f:F_parameter_value=20'h01875;
            7'h30:F_parameter_value=20'h02000;
            7'h40:F_parameter_value=20'h01000;
            7'h41:F_parameter_value=20'h01125;
            7'h42:F_parameter_value=20'h01250;
            7'h43:F_parameter_value=20'h01375;
            7'h44:F_parameter_value=20'h01500;
            7'h45:F_parameter_value=20'h01625;
            7'h46:F_parameter_value=20'h01750;
            7'h47:F_parameter_value=20'h01875;
            7'h48:F_parameter_value=20'h02000;
            7'h49:F_parameter_value=20'h02250;
            7'h4a:F_parameter_value=20'h02500;
            7'h4b:F_parameter_value=20'h02750;
            7'h4c:F_parameter_value=20'h03000;
            7'h4d:F_parameter_value=20'h03250;
            7'h4e:F_parameter_value=20'h03500;
            7'h4f:F_parameter_value=20'h03750;
            7'h50:F_parameter_value=20'h04000;
            7'h60:F_parameter_value=20'h00016;
            7'h61:F_parameter_value=20'h00024;
            7'h62:F_parameter_value=20'h00032;
            7'h63:F_parameter_value=20'h00040;
            7'h64:F_parameter_value=20'h00048;
            7'h65:F_parameter_value=20'h00056;
            7'h66:F_parameter_value=20'h00064;
            7'h67:F_parameter_value=20'h00072;
            7'h68:F_parameter_value=20'h00080;
            7'h69:F_parameter_value=20'h00081;
            7'h6a:F_parameter_value=20'h00082;
            7'h6b:F_parameter_value=20'h00083;
            7'h6c:F_parameter_value=20'h00085;
            7'h6d:F_parameter_value=20'h00086;
            7'h6e:F_parameter_value=20'h00087;
            7'h6f:F_parameter_value=20'h00088;
            7'h70:F_parameter_value=20'h00089;
            default:F_parameter_value=0;
        endcase end
    endfunction
    function [5:0] F_parameter_glyph;
        input [1:0] kind;input [1:0] cell_number;
        begin case({kind,cell_number})
            4'h0:F_parameter_glyph=10; // 对
            4'h1:F_parameter_glyph=11; // 比
            4'h2,4'h6:F_parameter_glyph=5; // 度
            4'h4:F_parameter_glyph=60; // 饱
            4'h5:F_parameter_glyph=61; // 和
            4'h8:F_parameter_glyph=54; // 数
            4'h9:F_parameter_glyph=55; // 字
            4'ha,4'he:F_parameter_glyph=56; // 增
            4'hb,4'hf:F_parameter_glyph=57; // 益
            4'hc:F_parameter_glyph=58; // 相
            4'hd:F_parameter_glyph=59; // 机
            default:F_parameter_glyph=63;
        endcase end
    endfunction

    // Disjoint text windows share one 8-bit font row and column selector.
    reg region,accent,geometry,text_enable;
    reg [23:0] ink_color;
    reg [6:0] text_id;
    reg [4:0] char_cell;
    // 102 messages x 20 cells fit the SAME 2048x8 ERAM, including blank padding.
    // Keep the immutable text in this source: no external .mem dependency.
    (* ram_style="bram" *) reg [7:0] text_rom[0:2047];
    integer text_init_address,text_init_message,text_init_cell;
    initial begin
        for(text_init_address=0;text_init_address<2048;text_init_address=text_init_address+1)
            text_rom[text_init_address]=8'h20;
        for(text_init_message=0;text_init_message<(INFO_FEATURE ? 102 : (TRACK_UI_FEATURE ? 100 : 89));text_init_message=text_init_message+1)
            for(text_init_cell=0;text_init_cell<20;text_init_cell=text_init_cell+1)
                text_rom[text_init_message*20+text_init_cell]=F_text_character(text_init_message,text_init_cell);
    end
    reg [7:0] text_rom_q;
    wire [10:0] text_rom_address=({4'd0,text_id}<<4)+({4'd0,text_id}<<2)+{6'd0,char_cell};
    // The ROM data port has no reset, allowing ERAM inference. The registered
    // request-valid/override bits below reproduce the original reset-to-space.
    always @(posedge I_clk)text_rom_q<=text_rom[text_rom_address];
    reg [7:0] character;
    reg dynamic_character;
    // All dynamic BCD fields share one nibble selector. Decode a small digit
    // index, rather than building a separate variable part-select per field.
    reg digit_override;
    reg [3:0] digit_index;
    wire [63:0] digit_bank=(text_id==7'd68) ? {44'd0,param_value_l} : digits_l;
    wire [3:0] digit_nibble=digit_bank[{digit_index,2'b00} +:4];
    reg [11:0] tx,ty;
    reg [3:0] line_index;
    wire sad_guard_ui=sad_l && guard_l && !motion_l;
    // A usable selection coordinate is not a live autonomous track.
    // Frame-latched status only; this observer does not drive control.
    wire aim_target_live=valid_l && (!sad_l || (sad_running_l && sad_live_l));
    wire track_card=TRACK_UI_FEATURE && !album_l && !guard_paused_l &&
        ((guard_l && recognition_l && !motion_l) || (!sad_l && !guard_l && (static_track_l || range_l)));
    wire track_exit_card=INFO_FEATURE && track_card && guard_l && track_outside_l;
    function [7:0] F_track_fill;
        input [3:0] half_seconds;
        begin case(half_seconds)
            0:F_track_fill=0;1:F_track_fill=19;2:F_track_fill=38;
            3:F_track_fill=57;4:F_track_fill=76;5:F_track_fill=96;
            6:F_track_fill=115;7:F_track_fill=134;8:F_track_fill=153;
            9:F_track_fill=172;default:F_track_fill=192;
        endcase end
    endfunction
    wire [11:0] track_fill_right=12'd544+{4'd0,track_fill};
    // Caption-only bank: existing mode/parameter Chinese ROM stays untouched.
    function [4:0] F_track_glyph;
        input [6:0] message;input [2:0] cell_number;
        begin case({message,cell_number})
                10'd712:F_track_glyph=5'd0;
                10'd713:F_track_glyph=5'd1;
                10'd714:F_track_glyph=5'd2;
                10'd715:F_track_glyph=5'd3;
                10'd720:F_track_glyph=5'd4;
                10'd721:F_track_glyph=5'd5;
                10'd722:F_track_glyph=5'd2;
                10'd723:F_track_glyph=5'd3;
                10'd728:F_track_glyph=5'd8;
                10'd729:F_track_glyph=5'd6;
                10'd730:F_track_glyph=5'd7;
                10'd731:F_track_glyph=5'd31;
                10'd736:F_track_glyph=5'd10;
                10'd737:F_track_glyph=5'd6;
                10'd738:F_track_glyph=5'd7;
                10'd739:F_track_glyph=5'd31;
                10'd740:F_track_glyph=5'd31;
                10'd744:F_track_glyph=5'd13;
                10'd745:F_track_glyph=5'd14;
                10'd746:F_track_glyph=5'd15;
                10'd747:F_track_glyph=5'd16;
                10'd752:F_track_glyph=5'd13;
                10'd753:F_track_glyph=5'd14;
                10'd754:F_track_glyph=5'd17;
                10'd755:F_track_glyph=5'd18;
                10'd760:F_track_glyph=5'd13;
                10'd761:F_track_glyph=5'd14;
                10'd762:F_track_glyph=5'd19;
                10'd763:F_track_glyph=5'd13;
                10'd768:F_track_glyph=5'd20;
                10'd769:F_track_glyph=5'd21;
                10'd770:F_track_glyph=5'd22;
                10'd776:F_track_glyph=5'd23;
                10'd777:F_track_glyph=5'd24;
                10'd778:F_track_glyph=5'd20;
                10'd779:F_track_glyph=5'd21;
                10'd784:F_track_glyph=5'd25;
                10'd785:F_track_glyph=5'd26;
                10'd786:F_track_glyph=5'd27;
                10'd787:F_track_glyph=5'd17;
                // SAD shares the existing TARGET glyphs and text-ROM port.
                10'd808:F_track_glyph=5'd6;
                10'd809:F_track_glyph=5'd7;
            default:F_track_glyph=5'd31;
        endcase end
    endfunction
    reg track_cn_select;
    reg [4:0] track_glyph;
    reg range_cn_select,range_ascii;
    reg [4:0] range_glyph;
    reg [1:0] range_line;
    wire range_card=TRACK_UI_FEATURE && !sad_l && range_l && !album_l && !guard_l;
    // Small direct caption decoders leave the original 99x20 text ROM intact.
    function [3:0] F_range_glyph;
        input [2:0] message;input [3:0] cell_number;
        begin case({message,cell_number})
            7'h00:F_range_glyph=0;7'h01:F_range_glyph=1;
            7'h02:F_range_glyph=2;7'h03:F_range_glyph=3;
            7'h10:F_range_glyph=4;7'h11:F_range_glyph=5;
            7'h12:F_range_glyph=1;7'h13:F_range_glyph=6;
            7'h20:F_range_glyph=7;7'h21:F_range_glyph=8;
            7'h22:F_range_glyph=9;7'h23:F_range_glyph=10;
            7'h30:F_range_glyph=8;7'h31:F_range_glyph=11;7'h32:F_range_glyph=12;
            7'h40:F_range_glyph=13;7'h41:F_range_glyph=11;7'h42:F_range_glyph=12;
            default:F_range_glyph=15;
        endcase end
    endfunction
    function [7:0] F_range_ascii;
        input [1:0] message;input [4:0] cell_number;
        reg [79:0] word_bits;
        begin
            case(message)
                0:word_bits="RANGE HOLD";
                1:word_bits="SET       ";
                2:word_bits="WAIT DATA ";
                3:word_bits="READY     ";
            endcase
            F_range_ascii=cell_number<10 ? word_bits[79-cell_number*8-:8] : 8'h20;
        end
    endfunction
    wire [3:0] track_prefix_cells=(text_id==101) ? 4'd2 :
        (text_id==92 ? 4'd5 : (text_id==96 ? 4'd3 : 4'd4));
    wire [11:0] track_english_start=12'd24+{4'd0,track_prefix_cells,4'b0000}+12'd8;
    reg [23:0] class_color;
    reg title_panel,cn_select;
    reg [5:0] cn_glyph;
    // Every selector below was already latched on the same frame start.
    wire [4:0] mode_title=album_l ? 5'd17 :
        (guard_l ? (motion_l ? 5'd16 : (recognition_l ? 5'd18 : 5'd15)) :
        ((object_l || (TRACK_UI_FEATURE && static_track_l)) ? 5'd13 : (motion_active_l ? 5'd14 :
        (mode_code<=12 ? mode_code : 5'd12))));
    wire center_hud=guard_l && !guard_paused_l && recognition_l && !motion_l && !range_card;
    // Reuse the guard geometry; its LOCKED/LOST banner remains guard-owned.
    wire standalone_track_card=track_card && !guard_l;
    wire aim_reticle=center_hud || standalone_track_card || (sad_l && sad_saved_l && sad_running_l && !guard_l && !album_l);
    always @*begin
        region=0;accent=0;geometry=0;text_enable=0;ink_color=24'hdcebf3;
        character=" ";dynamic_character=0;digit_override=0;digit_index=0;
        tx=0;ty=0;text_id=63;line_index=0;char_cell=0;
        title_panel=0;cn_select=0;cn_glyph=63;
        track_cn_select=0;track_glyph=31;
        range_cn_select=0;range_glyph=15;range_ascii=0;range_line=0;
        class_color=(id_l==1)?24'hff958b:24'h75baff;
        if(S_x>=16 && S_x<160 && S_y>=16 && S_y<48)begin
            region=1;tx=S_x-24;ty=S_y-16;text_enable=S_x>=24 && S_x<152;
            if(S_y<32)begin text_id=6'd30;ink_color=24'h65dcf0;end
            else begin
                text_id=6'd31;
            end
            accent=S_y==16 || S_x==16;
        end else if(SHOW_MODE_NAME && S_x>=IMG_WIDTH-216 && S_x<IMG_WIDTH-16 && S_y>=16 && S_y<60)begin
            region=1;tx=S_x-(IMG_WIDTH-208);ty=S_y-20;
            text_enable=S_x>=IMG_WIDTH-208 && S_x<IMG_WIDTH-24;
            title_panel=1;
            if(S_y<38)begin
                cn_select=text_enable && S_y>=20 && S_y<36;
                cn_glyph=F_mode_glyph(mode_title,tx[7:4]);
                if(INFO_FEATURE && TRACK_UI_FEATURE && sad_l && !album_l)begin
                    // Template assist title shares the existing synchronous UI ROM.
                    cn_select=cn_select && tx<96;
                    if(sad_saved_l && !guard_l)begin
                        case(tx[7:4])
                            0,1,2,3:begin
                                range_cn_select=cn_select;
                                range_glyph=5'd16+{3'd0,tx[5:4]}; // 辅助瞄准
                            end
                            4:cn_glyph=6'd6; // 模
                            5:cn_glyph=6'd7; // 式
                            default:cn_glyph=6'd63;
                        endcase
                    end else case(tx[7:4])
                        0:cn_glyph=6'd38; // 自
                        1:cn_glyph=6'd62; // 主 (unused mode-ROM slot)
                        2:begin track_cn_select=cn_select;track_glyph=5'd6;end
                        3:begin track_cn_select=cn_select;track_glyph=5'd7;end
                        4:begin
                            if(guard_l)cn_glyph=6'd48;
                            else begin track_cn_select=cn_select;track_glyph=5'd30;end
                        end
                        5:begin
                            if(guard_l)cn_glyph=6'd49;
                            else begin track_cn_select=cn_select;track_glyph=5'd16;end
                        end
                        default:cn_glyph=6'd63;
                    endcase
                end else if(range_card)begin
                    cn_select=cn_select && tx<96;
                    if(tx>=32 && tx<64)begin
                        range_cn_select=cn_select;range_glyph=tx[5:4]-2'd2;
                    end else begin
                        track_cn_select=cn_select;
                        case(tx[6:4])
                            0:track_glyph=5'd28;1:track_glyph=5'd29;
                            4:track_glyph=5'd2;5:track_glyph=5'd3;
                            default:track_glyph=5'd31;
                        endcase
                    end
                end else if(standalone_track_card)begin
                    cn_select=cn_select && tx<64;track_cn_select=cn_select;
                    track_glyph=F_track_glyph(7'd89,tx[6:4]);
                end
                text_enable=0;ink_color=24'hffffff;
            end else begin
                ty=S_y-38;text_enable=text_enable && S_y<54;
                text_id=album_l ? 7'd52 : ((GUARD_SESSION_FEATURE && guard_l) ?
                    (motion_l ? 7'd32 : (recognition_l ? 7'd88 : 7'd33)) :
                    (range_card ? 7'd99 : ((TRACK_UI_FEATURE && static_track_l) ? 7'd89 :
                    ((GUARD_SESSION_FEATURE && object_l) ? 7'd34 :
                    ((GUARD_SESSION_FEATURE && motion_active_l) ? 7'd35 : {2'b0,mode_code})))));
                if(INFO_FEATURE && sad_l && !album_l)text_id=guard_l?7'd90:7'd101;
                else if(!album_l && !guard_l && !object_l && !motion_active_l &&
                        !(TRACK_UI_FEATURE && static_track_l) && mode_code==30)text_id=7'd102;
                ink_color=24'h65dcf0;
            end
            accent=S_y==16 || S_x==IMG_WIDTH-17;
        end else if(range_card && S_x>=IMG_WIDTH-240 && S_x<IMG_WIDTH-16 && S_y>=72 && S_y<192)begin
            region=1;accent=S_y<74;tx=S_x-(IMG_WIDTH-224);
            if(S_y>=84 && S_y<100 && S_x>=IMG_WIDTH-224 && S_x<IMG_WIDTH-160)begin
                ty=S_y-84;cn_select=1;range_cn_select=1;range_glyph=F_range_glyph(1,tx[7:4]);
                ink_color=24'h8ba4b5;
            end else if(S_y>=110 && S_y<142 && S_x>=IMG_WIDTH-224 && S_x<IMG_WIDTH-144)begin
                // Exact 2x nearest-neighbour digits on the existing 8x16 font.
                tx=(S_x-(IMG_WIDTH-224))>>1;ty=(S_y-110)>>1;
                range_ascii=1;range_line=1;ink_color=range_valid_l ? 24'hffffff : 24'hffb36b;
            end else if(S_y>=124 && S_y<140 && S_x>=IMG_WIDTH-128 && S_x<IMG_WIDTH-112)begin
                tx=S_x-(IMG_WIDTH-128);ty=S_y-124;range_ascii=1;range_line=2;
                ink_color=24'h8ba4b5;
            end else if(S_y>=156 && S_y<172 && S_x>=IMG_WIDTH-224 && S_x<IMG_WIDTH-32)begin
                ty=S_y-156;ink_color=range_applied_l ? 24'h75baff : 24'hffb36b;
                if(tx<64)begin
                    cn_select=1;range_cn_select=1;
                    range_glyph=F_range_glyph(!range_valid_l ? 3'd2 : (range_applied_l ? 3'd4 : 3'd3),tx[7:4]);
                end else if(tx>=72)begin tx=tx-72;range_ascii=1;range_line=3;end
            end
        end else if(INFO_FEATURE && !album_l && (sad_l || guard_l || object_l || motion_active_l || track_card) &&
            S_x>=16 && S_x<240 && S_y>=64 && S_y<(track_card ? (guard_l ? 240 : 224) : 176))begin
            region=1;tx=S_x-24;ty=S_y-68;line_index=ty[7:4];
            text_enable=S_x>=24 && S_x<224 && S_y>=68 && S_y<(track_card ? (guard_l ? 228 : 212) : 164);
            if(guard_l && guard_paused_l)begin
                // Paused editing is still a guard session, never a detector UI.
                case(line_index)
                    0:begin text_id=7'd86;ink_color=24'hffb36b;end
                    1:text_id=7'd87;
                    5:text_id=7'd69+{3'd0,photo_status_l};
                    default:text_enable=0;
                endcase
            end else if(!sad_l && ((guard_l && motion_l) || (!guard_l && motion_active_l && !object_l)))begin
                case(line_index)
                    0:begin text_id=motion_overflow_l ? 7'd55 : (motion_ready_l ?
                            (guard_l ? (intrusion_l ? 7'd40 : 7'd41) : 7'd54) :
                            (motion_rebuild_l ? 7'd62 : 7'd53));
                        ink_color=motion_overflow_l ? 24'hff958b : 24'h65dcf0;end
                    1:text_id=7'd56;
                    2:text_id=7'd47;
                    3:text_id=7'd57;
                    4:text_id=guard_l ? 7'd56 : 7'd58;
                    5:text_id=guard_l ? (7'd69+{3'd0,photo_status_l}) : 7'd59;
                    default:text_enable=0;
                endcase
                // Motion guard keeps its actual intrusion/dwell state visible.
                if(guard_l && line_index==1)text_id=7'd42;
            end else if(guard_l)begin
                case(line_index)
                    0:begin text_id=recognition_l ? (valid_l ? (locked_l ? 7'd37 : 7'd38) : 7'd39) :
                            (intrusion_l ? 7'd40 : 7'd41);
                        ink_color=recognition_l ? (locked_l ? 24'h8ae8b0 : 24'h65dcf0) :
                            (intrusion_l ? 24'hffb36b : 24'h65dcf0);end
                    1:text_id=recognition_l ? 7'd43 : 7'd42;
                    2:begin text_id=valid_l ? (sad_guard_ui ? 7'd101 : (id_l==1 ? 7'd44 : 7'd45)) : 7'd46;
                        ink_color=valid_l ? (sad_guard_ui ? 24'h65dcf0 : class_color) : 24'h8ba4b5;end
                    3:text_id=7'd47;
                    4:text_id=7'd48;
                    5:begin text_id=7'd69+{3'd0,photo_status_l};
                        if(photo_status_l==6 || photo_status_l>=11)ink_color=24'hff958b;end
                    default:text_enable=0;
                endcase
            end else begin
                case(line_index)
                    // One ordinary target panel for color and manual SAD.
                    // No guard/region rows belong to standalone autonomous aim.
                    0:begin text_id=(sad_l && !sad_running_l) ? 7'd100 :
                            (aim_target_live ? (centered_l ? 7'd60 : 7'd38) : 7'd39);
                        ink_color=sad_l ? (aim_target_live ? 24'hff0000 : 24'h0000ff) :
                            (centered_l ? 24'h8ae8b0 : 24'h65dcf0);end
                    1:begin text_id=sad_l ? 7'd101 : (valid_l ? (id_l==1 ? 7'd44 : 7'd45) : 7'd46);
                        ink_color=sad_l ? 24'h65dcf0 : (valid_l ? class_color : 24'h8ba4b5);end
                    2:text_id=7'd47;
                    3:text_id=7'd48;
                    4:text_id=7'd59;
                    5:text_id=7'd61;
                    default:text_enable=0;
                endcase
            end
            if(track_card && line_index>=6)begin
                text_enable=S_x>=24 && S_x<224 && S_y>=68 && S_y<(guard_l ? 228 : 212);
                case(line_index)
                    6:begin text_id=guard_l ? 7'd90 : 7'd89;ink_color=24'h65dcf0;end
                    7:begin text_id=sad_guard_ui ? 7'd101 : (track_selected_l ? 7'd92 : 7'd91);
                        ink_color=sad_guard_ui ? 24'h65dcf0 : (track_selected_l ? 24'h75baff : 24'hff958b);end
                    8:begin text_id=7'd93+{5'd0,track_speed_l};ink_color=24'hdcebf3;end
                    9:begin text_id=!track_outside_l ? 7'd96 : (track_steps_l>=10 ? 7'd98 : 7'd97);
                        // IN stays here; the complete OUT row moves with its bar.
                        text_enable=text_enable && guard_l && !track_exit_card;
                        ink_color=track_outside_l ? 24'hff958b : 24'h75baff;end
                    default:text_enable=0;
                endcase
            end
            accent=S_x==16 || S_y==64;
            if(!track_card && guard_l && !guard_paused_l && S_y>=168 && S_y<174 && S_x>=24 && S_x<216)begin
                geometry=1;ink_color=(sad_l && !sad_guard_ui) ? ((recognition_l || S_x<guard_fill_right) ? 24'hff0000 : 24'h0000ff) :
                    (recognition_l ? 24'h8ae8b0 : ((S_x<guard_fill_right) ? 24'hffb36b : 24'h294555));
            end
        end else if(guard_l && S_x>=16 && S_x<192 && S_y>=64 && S_y<160)begin
            region=1;tx=S_x-24;ty=S_y-64;line_index=ty[6:4];
            text_enable=S_x>=24 && S_x<184;
            case(line_index)
                0:begin
                    text_id=recognition_l ? (valid_l ? (locked_l ? 6'd37 : 6'd38) : 6'd39) :
                        (intrusion_l ? 6'd40 : 6'd41);
                    ink_color=recognition_l ? (locked_l ? 24'h8ae8b0 : 24'h65dcf0) :
                        (intrusion_l ? 24'hffb36b : 24'h65dcf0);
                end
                1:begin
                    text_id=6'd42;
                    if(recognition_l)text_id=6'd43;
                end
                2:begin text_id=valid_l ? (id_l==1 ? 6'd44 : 6'd45) : 6'd46;ink_color=valid_l?class_color:24'h8ba4b5;end
                3:text_id=6'd47;
                4:text_id=6'd48;
                default:begin
                    text_id=63;text_enable=0;
                    geometry=S_y>=149 && S_y<155 && S_x>=24 && S_x<184;
                    ink_color=recognition_l ? 24'h8ae8b0 : ((S_x<guard_fill_right) ? 24'hffb36b : 24'h294555);
                end
            endcase
            if(guard_paused_l)begin
                geometry=0;text_enable=text_enable && line_index<2;
                text_id=line_index==0 ? 7'd86 : 7'd87;
            end
            accent=S_x==16;
        end else if(center_hud && S_x>=576 && S_x<704 && S_y>=408 && S_y<428)begin
            region=1;tx=S_x-576;ty=S_y-410;text_enable=S_y>=410 && S_y<426;
            text_id=valid_l ? (locked_l ? 6'd49 : 6'd50) : 6'd51;
            ink_color=locked_l ? 24'h8ae8b0:24'h65dcf0;
            if(locked_l && !lock_show_l)text_enable=0;
        end else if(track_exit_card && S_x>=544 && S_x<736 && S_y>=612 && S_y<648)begin
            // Reuse the same row fonts and three-clock mix for the bottom card.
            // 64px Chinese + 8px gap + 96px ASCII are centered above 192px bar.
            region=1;ink_color=24'hff958b;text_id=7'd97;ty=S_y-616;
            if(S_y>=616 && S_y<632)begin
                if(S_x>=556 && S_x<620)begin
                    tx=S_x-556;cn_select=1;track_cn_select=1;
                    track_glyph=F_track_glyph(7'd97,tx[6:4]);
                end else if(S_x>=628 && S_x<724)begin
                    tx=S_x-628;text_enable=1;
                end
            end
            if(S_y>=640 && S_y<646)begin
                geometry=1;ink_color=S_x<track_fill_right ? 24'hff958b : 24'h294555;
            end
        end else if(INFO_FEATURE && !album_l && param_frames!=0 &&
            S_x>=472 && S_x<808 && S_y>=612 && S_y<680)begin
            region=1;accent=S_y==612;
            if(S_y>=620 && S_y<636)begin
                ty=S_y-620;
                if(S_x>=488 && S_x<552)begin
                    tx=S_x-488;cn_select=1;cn_glyph=F_parameter_glyph(param_kind_l,tx[5:4]);
                    ink_color=24'hffffff;
                end else if(S_x>=560 && S_x<792)begin
                    tx=S_x-560;text_enable=1;text_id=7'd64+{5'd0,param_kind_l};ink_color=24'h65dcf0;
                end
            end else if(S_y>=642 && S_y<658)begin
                ty=S_y-642;
                if(S_x>=488 && S_x<648)begin tx=S_x-488;text_enable=1;text_id=7'd68;end
                else if(S_x>=720 && S_x<768)begin tx=S_x-720;text_enable=1;text_id=7'd85;ink_color=24'h8ba4b5;end
            end
            if(S_y>=666 && S_y<670 && S_x>=512 && S_x<768)begin
                geometry=1;ink_color=S_x<512+{param_level_l,4'b0000} ? 24'h65dcf0 : 24'h3d505b;
            end
            if(S_x==640 && S_y>=664 && S_y<674)begin geometry=1;ink_color=24'hdcebf3;end
        end
        if(aim_reticle && (
            (S_y>=359 && S_y<362 && ((S_x>=629 && S_x<637)||(S_x>=644 && S_x<652))) ||
            (S_x>=639 && S_x<642 && ((S_y>=349 && S_y<357)||(S_y>=364 && S_y<372))) ||
            (((S_x>=560 && S_x<563)||(S_x>=718 && S_x<721)) &&
                ((S_y>=315 && S_y<331)||(S_y>=390 && S_y<406))) ||
            (((S_y>=315 && S_y<318)||(S_y>=403 && S_y<406)) &&
                ((S_x>=560 && S_x<576)||(S_x>=705 && S_x<721)))))begin
            geometry=1;ink_color=(center_hud && locked_l)?24'h8ae8b0:24'h65dcf0;
        end
        if(sad_l && !sad_guard_ui && !album_l && ((S_y==360 && S_x>=636 && S_x<=644) ||
            (S_x==640 && S_y>=356 && S_y<=364)))begin geometry=1;ink_color=24'hffffff;end
        // One 16px Chinese prefix, 8px gap, then the original 8px ASCII path.
        // Only the four new rows change. Titles and legacy labels keep layout.
        if(track_card && S_y>=164 && S_y<(guard_l ? 228 : 212) && S_x>=24 && S_x<224 &&
            !(track_exit_card && S_y>=212))begin
            if(S_x<track_english_start-12'd8)begin
                tx=S_x-24;cn_select=1;track_cn_select=1;text_enable=0;
                track_glyph=F_track_glyph(text_id,tx[6:4]);
            end else if(S_x>=track_english_start)begin
                tx=S_x-track_english_start;
                // Keep the right-hand STATIC TRACK/GUARD TRACK captions intact.
                if(text_id==89)text_enable=text_enable && tx<48;
                else if(text_id==90)text_enable=text_enable && tx<40;
            end else text_enable=0;
        end
        if(track_card && range_card && S_y>=164 && S_y<180 && S_x>=24 && S_x<224)begin
            // The new mode gets its own heading, not a false STATIC caption.
            track_cn_select=0;
            if(S_x<88)begin
                tx=S_x-24;cn_select=1;range_cn_select=1;text_enable=0;
                range_glyph=F_range_glyph(0,tx[7:4]);
            end else if(S_x>=96)begin
                tx=S_x-96;cn_select=0;text_enable=0;range_ascii=1;range_line=0;
            end else begin cn_select=0;text_enable=0;end
        end
        char_cell=tx[7:3];
        if(text_enable && char_cell<20)begin
            case(text_id)
                102:begin
                    // Low-gain AE is valid; never present it as AE WAIT.
                    // A short override avoids growing the full 2048-byte text ROM.
                    dynamic_character=1;
                    case(char_cell)
                        0:character="A";1:character="E";3:character="L";
                        4:character="O";5:character="W";7:character="G";
                        8:character="A";9:character="I";10:character="N";
                        default:character=" ";
                    endcase
                end
                96:if(sad_l && guard_l && !recognition_l)begin
                    dynamic_character=1;
                    if(sad_inside_l)begin
                        case(char_cell)0:character="I";1:character="N";default:character=" ";endcase
                    end else begin
                        case(char_cell)0:character="O";1:character="U";2:character="T";default:character=" ";endcase
                    end
                end
                97:begin
                    if(char_cell==4)begin character="0"+{5'd0,track_steps_l[3:1]};dynamic_character=1;end
                    if(char_cell==6)begin character=track_steps_l[0]?"5":"0";dynamic_character=1;end
                end
                31:if(char_cell>=4 && char_cell<=9)
                    begin character=8'h30+{4'd0,frame_bcd[23-(char_cell-4)*4-:4]};dynamic_character=1;end
                42:case(char_cell)
                    5:begin character="0"+{4'd0,elapsed_l[4:1]}/8'd10;dynamic_character=1;end
                    6:begin character="0"+{4'd0,elapsed_l[4:1]}%8'd10;dynamic_character=1;end
                    8:begin character=elapsed_l[0]?"5":"0";dynamic_character=1;end
                    12:begin character="0"+{4'd0,seconds_l}/8'd10;dynamic_character=1;end
                    13:begin character="0"+{4'd0,seconds_l}%8'd10;dynamic_character=1;end
                    default:begin end
                endcase
                47:if(valid_l)begin
                    case(char_cell)
                        3:begin digit_index=15;digit_override=1;end
                        4:begin digit_index=14;digit_override=1;end
                        5:begin digit_index=13;digit_override=1;end
                        6:begin digit_index=12;digit_override=1;end
                        11:begin digit_index=11;digit_override=1;end
                        12:begin digit_index=10;digit_override=1;end
                        13:begin digit_index=9;digit_override=1;end
                        14:begin digit_index=8;digit_override=1;end
                        default:begin end
                    endcase
                end
                48:if(valid_l)begin
                    if(char_cell==3)begin character=dx_neg_l?8'h2d:8'h2b;dynamic_character=1;end
                    if(char_cell==11)begin character=dy_neg_l?8'h2d:8'h2b;dynamic_character=1;end
                    case(char_cell)
                        4:begin digit_index=6;digit_override=1;end
                        5:begin digit_index=5;digit_override=1;end
                        6:begin digit_index=4;digit_override=1;end
                        12:begin digit_index=2;digit_override=1;end
                        13:begin digit_index=1;digit_override=1;end
                        14:begin digit_index=0;digit_override=1;end
                        default:begin end
                    endcase
                end
                56:if(char_cell==8)begin character=8'h30+{6'd0,motion_count_l};dynamic_character=1;end
                57:if(valid_l)begin
                    case(char_cell)
                        2:begin digit_index=7;digit_override=1;end
                        3:begin digit_index=6;digit_override=1;end
                        4:begin digit_index=5;digit_override=1;end
                        5:begin digit_index=4;digit_override=1;end
                        9:begin digit_index=3;digit_override=1;end
                        10:begin digit_index=2;digit_override=1;end
                        11:begin digit_index=1;digit_override=1;end
                        12:begin digit_index=0;digit_override=1;end
                        default:begin end
                    endcase
                end
                68:begin
                    if(char_cell==3)begin character=param_level_l>=10 ? "1" : "0";dynamic_character=1;end
                    if(char_cell==4)begin character="0"+(param_level_l>=10 ? param_level_l-5'd10 : param_level_l);dynamic_character=1;end
                    if(param_kind_l==3)begin
                        case(char_cell)
                            10:begin character="A";dynamic_character=1;end
                            11:begin character="G";dynamic_character=1;end
                            12:begin digit_index=2;digit_override=1;end
                            13:begin digit_index=1;digit_override=1;end
                            14:begin digit_index=0;digit_override=1;end
                            15:begin character=" ";dynamic_character=1;end
                            default:begin end
                        endcase
                    end else begin
                        case(char_cell)
                            10:begin digit_index=3;digit_override=1;end
                            12:begin digit_index=2;digit_override=1;end
                            13:begin digit_index=1;digit_override=1;end
                            14:begin digit_index=0;digit_override=1;end
                            default:begin end
                        endcase
                    end
                end
                default:begin end
            endcase
        end
        if(digit_override)begin
            character=8'h30+{4'd0,digit_nibble};dynamic_character=1;
        end
        if(range_ascii)begin
            dynamic_character=1;
            case(range_line)
                0:character=F_range_ascii(0,char_cell);
                1:character=range_valid_l ? 8'h30+{4'd0,range_bcd_l[19-char_cell*4-:4]} : 8'h2d;
                // The shared font is uppercase ASCII; MM denotes millimetres.
                2:character="M";
                3:begin
                    if(range_applied_l)begin
                        case(char_cell)
                            0:character="A";1:character="P";2:character="P";3:character="L";
                            4:character="I";5:character="E";6:character="D";default:character=" ";
                        endcase
                    end else character=F_range_ascii(range_valid_l ? 2'd3 : 2'd2,char_cell);
                end
            endcase
        end
    end
    reg title_q,title_d2,cn_select_q,cn_select_d2;
    reg [5:0] cn_glyph_q;
    reg [3:0] cn_col_q,cn_col_d2;
    wire [15:0] cn_font_bits;
    reg track_cn_q,track_cn_d2;
    reg [4:0] track_glyph_q;
    reg [3:0] row_q;
    wire [15:0] track_range_font_bits;
    reg range_cn_q,range_cn_d2;
    reg [4:0] range_glyph_q;
    // Select the UI bank before the existing synchronous font-read stage.
    // Range retains priority; both banks share row_q and the same read edge.
    wire [9:0] track_range_address=range_cn_q ?
        {1'b1,range_glyph_q,row_q} : {1'b0,track_glyph_q,row_q};
    wire [15:0] selected_cn_bits=(range_cn_d2 || track_cn_d2) ? track_range_font_bits : cn_font_bits;
    wire cn_pixel=selected_cn_bits[15-cn_col_d2];
    generate if(TRACK_UI_FEATURE)begin:g_tracking_font
        hud_track_range_font_sync font(.clk(I_clk),.address(track_range_address),.bits(track_range_font_bits));
    end else begin:g_no_tracking_font
        assign track_range_font_bits=16'd0;
    end endgenerate
    wire [23:0] panel_rgb=F_panel_rgb(rgb_d2);
    reg [7:0] dynamic_char_q;
    reg dynamic_select_q,fixed_valid_q;
    wire [7:0] char_q=dynamic_select_q ? dynamic_char_q : (fixed_valid_q ? text_rom_q : 8'h20);
    reg [2:0] col_q;
    hud_mode_font_sync mode_font(.clk(I_clk),.glyph(cn_glyph_q),.row(row_q),.bits(cn_font_bits));
    reg region_q,region_d2,accent_q,accent_d2,geometry_q,geometry_d2,lat_select_d2;
    reg [2:0] font_column_d2;
    wire ink_d2=geometry_d2 || (!lat_select_d2 && (cn_select_d2 ? cn_pixel : shared_pixel));
    reg [23:0] color_q,color_d2;
    wire [7:0] font_bits;
    hud_font_dual_sync shared_font(.clk(I_clk),.character(lat_request?lat_char:char_q),
        .row(lat_request?lat_row:row_q),.bits(font_bits),
        .character_b(photo_font_character),.row_b(photo_font_row),.bits_b(photo_font_bits));
    assign shared_pixel=font_bits[7-font_column_d2];
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            title_q<=0;title_d2<=0;cn_select_q<=0;cn_select_d2<=0;
            logo_window<=0;
            cn_glyph_q<=63;cn_col_q<=0;cn_col_d2<=0;
            track_cn_q<=0;track_cn_d2<=0;track_glyph_q<=31;
            range_cn_q<=0;range_cn_d2<=0;range_glyph_q<=15;
            dynamic_char_q<=32;dynamic_select_q<=0;fixed_valid_q<=0;row_q<=0;col_q<=0;region_q<=0;region_d2<=0;accent_q<=0;accent_d2<=0;
            geometry_q<=0;geometry_d2<=0;lat_select_d2<=0;font_column_d2<=0;color_q<=0;color_d2<=0;vs_pipe<=0;hs_pipe<=0;de_pipe<=0;
            rgb_q<=0;rgb_d2<=0;O_hdmi_vsync<=0;O_hdmi_hsync<=0;O_hdmi_de<=0;O_hdmi_data<=0;
        end else begin
            title_q<=title_panel && I_video_de;title_d2<=title_q;
            logo_window<={logo_window[0],logo_request};
            cn_select_q<=cn_select && I_video_de;cn_select_d2<=cn_select_q;
            cn_glyph_q<=cn_glyph;cn_col_q<=tx[3:0];cn_col_d2<=cn_col_q;
            track_cn_q<=track_cn_select && I_video_de;track_cn_d2<=track_cn_q;track_glyph_q<=track_glyph;
            range_cn_q<=range_cn_select && I_video_de;range_cn_d2<=range_cn_q;range_glyph_q<=range_glyph;
            dynamic_char_q<=character;dynamic_select_q<=dynamic_character;
            fixed_valid_q<=text_enable && char_cell<20 && text_id<=(INFO_FEATURE ? 101 : (TRACK_UI_FEATURE ? 99 : 88));
            row_q<=ty[3:0];col_q<=tx[2:0];
            region_q<=region && I_video_de;region_d2<=region_q;
            accent_q<=accent && I_video_de;accent_d2<=accent_q;
            geometry_q<=geometry && I_video_de;
            geometry_d2<=geometry_q;lat_select_d2<=lat_request;
            font_column_d2<=lat_request?lat_col[2:0]:col_q;
            color_q<=ink_color;color_d2<=color_q;
            vs_pipe<={vs_pipe[1:0],I_video_vsync};hs_pipe<={hs_pipe[1:0],I_video_hsync};de_pipe<={de_pipe[1:0],I_video_de};
            rgb_q<=I_video_rd_data;rgb_d2<=rgb_q;
            O_hdmi_vsync<=vs_pipe[1];O_hdmi_hsync<=hs_pipe[1];O_hdmi_de<=de_pipe[1];
            if(DEBUG_MODE == 1) begin
                if(de_pipe[1]) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(de_pipe[1]) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(de_pipe[1]) begin
                    if(S_x < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(photo_ink && de_pipe[1])O_hdmi_data<=photo_error?24'hff958b:24'hdcebf3;
            else if(photo_region && de_pipe[1])O_hdmi_data<=panel_rgb;
            else if(album_l && !title_d2)O_hdmi_data<=rgb_d2;
            else if(de_pipe[1] && ink_d2)O_hdmi_data<=color_d2;
            else if(de_pipe[1] && accent_d2)O_hdmi_data<=24'h65dcf0;
            else if(de_pipe[1] && lat_ink && lat_region)O_hdmi_data<=24'hdcebf3;
            else if(de_pipe[1] && (region_d2 || lat_region))
                O_hdmi_data<=panel_rgb;
            else if(de_pipe[1] && logo_window[1] && logo_pixel[24])O_hdmi_data<=logo_pixel[23:0];
            else O_hdmi_data<=rgb_d2;
        end
    end
endmodule

// Desired-distance UI observer, never measured range or physical control.
// Fresh low/high pairs in either order; no mixed old/new publication.
// Five BCD digits are computed serially, outside the pixel path (16 clocks).
module range_ui_control(
    input wire clk,rst_n,command_valid,
    input wire [15:0] command,
    output reg active,distance_valid,applied,
    output reg [19:0] distance_bcd
);
    reg [7:0] low_byte,high_byte;
    reg low_pending,high_pending,busy,apply_pending;
    reg [4:0] steps;
    reg [35:0] work;
    reg [35:0] adjusted;
    integer k;
    wire low_write=command_valid && command[15:8]==8'h2e;
    wire high_write=command_valid && command[15:8]==8'h2f;
    wire pair_complete=(low_write && high_pending)||(high_write && low_pending);
    wire [15:0] pair_value=low_write ? {high_byte,command[7:0]} : {command[7:0],low_byte};
    wire [35:0] shifted={adjusted[34:0],1'b0};
    always @*begin
        adjusted=work;
        for(k=0;k<5;k=k+1)
            if(work[16+k*4+:4]>=5)adjusted[16+k*4+:4]=work[16+k*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active<=0;distance_valid<=0;applied<=0;distance_bcd<=0;
            low_byte<=0;high_byte<=0;low_pending<=0;high_pending<=0;
            busy<=0;apply_pending<=0;steps<=0;work<=0;
        end else begin
            if(busy)begin
                work<=shifted;steps<=steps-1'b1;
                if(steps==1)begin
                    distance_bcd<=shifted[35:16];distance_valid<=1;busy<=0;
                    if(apply_pending)applied<=active;
                    apply_pending<=0;
                end
            end
            if(low_write || high_write)begin
                applied<=0;apply_pending<=0;
                if(low_write)begin low_byte<=command[7:0];low_pending<=1;end
                else begin high_byte<=command[7:0];high_pending<=1;end
                if(pair_complete)begin
                    low_pending<=0;high_pending<=0;work<={20'd0,pair_value};steps<=16;busy<=1;
                end
            end
            // Tracking modes are exclusive; keep the last complete distance.
            if(command_valid && command==16'h2c03)begin
                active<=0;applied<=0;apply_pending<=0;low_pending<=0;high_pending<=0;
            end
            if(command_valid && command[15:8]==8'h2d)begin
                case(command[7:0])
                    0:begin active<=0;applied<=0;apply_pending<=0;low_pending<=0;high_pending<=0;end
                    1:begin active<=1;if(!active)begin applied<=0;apply_pending<=0;end end
                    2:if(active && !low_pending && !high_pending)begin
                        if(busy && steps!=1)apply_pending<=1;
                        else if(distance_valid || busy)applied<=1;
                    end
                    3:begin applied<=0;apply_pending<=0;end
                    default:begin end
                endcase
            end
        end
    end
endmodule

// Ordered UI state; static_track also owns the top's automatic recognition.
// 30 01 ALWAYS resets both the half-second counter and its tick remainder.
// A full five seconds saturates; ONLY top's 30 00 -> 0E02 restores guard.
module tracking_ui_control #(
    parameter integer HALF_SECOND_CYCLES=37500000
)(
    input wire clk,rst_n,command_valid,
    input wire [15:0] command,
    input wire guard_tracking,album,
    output reg static_track,selected_green,
    output reg [1:0] speed,
    output reg outside,
    output reg [3:0] elapsed_half
);
    localparam integer TW=(HALF_SECOND_CYCLES>1)?$clog2(HALF_SECOND_CYCLES):1;
    reg [TW-1:0] ticks;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            static_track<=0;selected_green<=0;speed<=1;
            outside<=0;elapsed_half<=0;ticks<=0;
        end else begin
            if(!guard_tracking || album)begin outside<=0;elapsed_half<=0;ticks<=0;end
            else if(outside && elapsed_half<10)begin
                if(ticks==HALF_SECOND_CYCLES-1)begin
                    ticks<=0;elapsed_half<=elapsed_half+1'b1;
                end else ticks<=ticks+1'b1;
            end
            if(command_valid)begin
                case(command)
                    16'h2c03:static_track<=1;
                    16'h2c04:static_track<=0;
                    16'h2d01:static_track<=0;
                    16'h2b01:selected_green<=0;
                    16'h2b02:selected_green<=1;
                    16'h2c00:speed<=0;
                    16'h2c01:speed<=1;
                    16'h2c02:speed<=2;
                    default:begin end
                endcase
                if(guard_tracking && !album && command[15:8]==8'h30 && command[7:0]<=2)begin
                    outside<=command[7:0]==1;elapsed_half<=0;ticks<=0;
                end
            end
        end
    end
endmodule

// 64x64 transparent logo, offline resized from the original image above.
// 4096x5 index ROM targets one ERAM20K; the 32-entry palette is logic.
// Index 0 is transparent. Two clock edges address -> pixel, no reset on RAM.
// Generated by tests/logo_small_20261018/run.py; no external memory file.
module anlogic_logo_small_rom (
    input wire I_clk,
    input wire [11:0] I_addr,
    output reg [24:0] O_pixel
);
    function [319:0] F_row;
        input [5:0] row;
        begin case(row)
            6'd0: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd1: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd2: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd3: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd4: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd5: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd6: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd7: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd8: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd9: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd10: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd11: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd12: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd13: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd14: F_row=320'h00000000000000000000000000002076b5ad6b5ad6b5ad6b5ad6b5ad6b5ad6b5ad6b5ad6b5ac8c00;
            6'd15: F_row=320'h00000000000000000000000000066007bffffffffffffffffffffffffffffffffffffffffffc0000;
            6'd16: F_row=320'h0000000000000000000000000056e600000000000000000000000000000000000000000000000000;
            6'd17: F_row=320'h000000000000000000000000055ef500000000000000000000000000000000000000000000000000;
            6'd18: F_row=320'h0000000000000000000000000bdef708068421084210842108421084210842108421084210100000;
            6'd19: F_row=320'h0000000000000000000000001bdef79803effffffffffffffffffffffffffffffffffffff0000000;
            6'd20: F_row=320'h0000000000000000000000015bdef7ba8036b5ad6b5ad6b5ad6b5ad6b5ad6b5ad6b5ad6b40000000;
            6'd21: F_row=320'h0000000000000000000000157bdef7bd400000000000000000000000000000000000000000000000;
            6'd22: F_row=320'h00000000000000000000002f7bdef7bdc40000000000000000000000000000000000000000000000;
            6'd23: F_row=320'h00000000000000000000006f7bdef7bde800f3bdef7bdef7bdef7bdef7bdef7bdef7bdc000000000;
            6'd24: F_row=320'h00000000000000000000056f7bdef7bdeeb0135ad6b5ad6b5ad6b5ad6b5ad6b5ad6b5a0000000000;
            6'd25: F_row=320'h0000000000000000000055ef7bdef7bdef6000000000000000000000000000000000000000000000;
            6'd26: F_row=320'h00000000000000000000bdef7bdef7bdef7100000000000000000000000000000000000000000000;
            6'd27: F_row=320'h00000000000000000001bdef7bdef7bdef7a0004294a5294a5294a5294a5294a5294600000000000;
            6'd28: F_row=320'h00000000000000000015bdef7bdef7bdef7bbc07fffffffffffffffffffffffffffc000000000000;
            6'd29: F_row=320'h00000000000000000157bdef7bdef7bdef7bd8006318c6318c6318c6318c6318c630000000000000;
            6'd30: F_row=320'h000000000000000002f7bdef7bdef7bdef7bdcc00000000000000000000000000000000000000000;
            6'd31: F_row=320'h000000000000000006f7bdef7bd297bdef7bde800000000000000000000000000000000000000000;
            6'd32: F_row=320'h000000000000000056f7bdef7b0436bdef7bdef301fffffffffffffffffffffff000000000000000;
            6'd33: F_row=320'h00000000000000055ef7bdef79800bbdef7bdef7003def7bdef7bdef7bdef7bda000000000000000;
            6'd34: F_row=320'h000000000000000bdef7bdef700000bdef7bdef73000000000000000000000000000000000000000;
            6'd35: F_row=320'h000000000000002bdef7bdef4000009def7bdef7a800000000000000000000000000000000000000;
            6'd36: F_row=320'h000000000000015bdef7bdee100000052f7bdef7bcc09def7bdef7bdef7bdec00000000000000000;
            6'd37: F_row=320'h000000000000157bdef7bde600000001af7bdef7bdc00ffffffffffffffffe400000000000000000;
            6'd38: F_row=320'h0000000000002f7bdef7bdc0000000002d7bdef7bdcc000000000000000000000000000000000000;
            6'd39: F_row=320'h000000000000af7bdef7bd4000000000177bdef7bdea000000000000000000000000000000000000;
            6'd40: F_row=320'h0000000000056f7bdef7b84000000000013bdef7bdef30046318c6318c6300000000000000000000;
            6'd41: F_row=320'h00000000005def7bdef7980000000000001bdef7bdef7003fffffffffff900000000000000000000;
            6'd42: F_row=320'h0000000000bdef7bdef7000000000000000a5ef7bdef75818d6b5ad6b5a100000000000000000000;
            6'd43: F_row=320'h0000000002bdef7bdef500000000000000035ef7bdef7a8000000000000000000000000000000000;
            6'd44: F_row=320'h0000000016bdef7bdeeb5294a5294a0000002ef7bdef7bd000000000000000000000000000000000;
            6'd45: F_row=320'h0000000177bdef7bdef7bdef7bdef710000002f7bdef7bdc00d6b5ad600000000000000000000000;
            6'd46: F_row=320'h00000002f7bdef7bdef7bdef7bdef7b040000277bdef7bdd60c7bdef040000000000000000000000;
            6'd47: F_row=320'h0000000af7bdef7bdef7bdef7bdef7bcc0000037bdef7bdec0000000000000000000000000000000;
            6'd48: F_row=320'h00000056f7bdef7bdef7bdef7bdef7bdc0000006bdef7bdef4000000000000000000000000000000;
            6'd49: F_row=320'h000005def7bdef7bdef7bdef7bdef7bdcc000000bdef7bdef7000630000000000000000000000000;
            6'd50: F_row=320'h00000bdef7bdef7bdef7bdef7bdef7bdee2000005def7bdef7883010000000000000000000000000;
            6'd51: F_row=320'h0000194a5294a5294a5294a5294a5294a4b000000465294a52800200000000000000000000000000;
            6'd52: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd53: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd54: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd55: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd56: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd57: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd58: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd59: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd60: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd61: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd62: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            6'd63: F_row=320'h00000000000000000000000000000000000000000000000000000000000000000000000000000000;
            default: F_row=320'd0;
        endcase end
    endfunction
    function [24:0] F_palette;
        input [4:0] index;
        begin case(index)
            5'd0: F_palette=25'h0000000;
            5'd1: F_palette=25'h1e0d8db;
            5'd2: F_palette=25'h1ceb4ba;
            5'd3: F_palette=25'h1f89598;
            5'd4: F_palette=25'h1f88a8d;
            5'd5: F_palette=25'h1f78a8c;
            5'd6: F_palette=25'h1878f9e;
            5'd7: F_palette=25'h1f88286;
            5'd8: F_palette=25'h1f47579;
            5'd9: F_palette=25'h1fa6f73;
            5'd10: F_palette=25'h17f8797;
            5'd11: F_palette=25'h16c7689;
            5'd12: F_palette=25'h1f96b70;
            5'd13: F_palette=25'h1f5646a;
            5'd14: F_palette=25'h1f95a60;
            5'd15: F_palette=25'h15b667d;
            5'd16: F_palette=25'h15c657a;
            5'd17: F_palette=25'h15b657a;
            5'd18: F_palette=25'h15b6579;
            5'd19: F_palette=25'h144526c;
            5'd20: F_palette=25'h1283857;
            5'd21: F_palette=25'h11f3051;
            5'd22: F_palette=25'h11d2e4f;
            5'd23: F_palette=25'h11c2d4e;
            5'd24: F_palette=25'h1f1242c;
            5'd25: F_palette=25'h1f11e26;
            5'd26: F_palette=25'h1f01e26;
            5'd27: F_palette=25'h1f11d25;
            5'd28: F_palette=25'h1f11c25;
            5'd29: F_palette=25'h1f01c25;
            5'd30: F_palette=25'h1ee1c24;
            5'd31: F_palette=25'h1ed1c24;
            default: F_palette=25'd0;
        endcase end
    endfunction
    (* rom_style="bram", ram_style="bram" *) reg [4:0] index_rom [0:4095];
    reg [4:0] index_q;
    integer row_init,col_init;
    initial begin
        for(row_init=0;row_init<64;row_init=row_init+1)
            for(col_init=0;col_init<64;col_init=col_init+1)
                index_rom[row_init*64+col_init]=F_row(row_init) >> ((63-col_init)*5);
    end
    always @(posedge I_clk) begin
        index_q<=index_rom[I_addr];
        O_pixel<=F_palette(index_q);
    end
endmodule

// Mirrors the existing requested/active coefficient SOF contract. This is
// read-only: no output returns to the RGB or RAW arithmetic. Startup/same-value
// transfers do not pop a bar. A simultaneous config applies on the NEXT SOF.
module hud_level_commit(
    input clk,rst_n,manual_enable,frame_start,config_valid,
    input [4:0] config_level,
    output reg commit,output reg [4:0] level
);
    reg [4:0] requested,active;
    reg pending;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin requested<=8;active<=8;pending<=0;commit<=0;level<=8;end
        else begin
            commit<=0;
            if(frame_start && manual_enable)begin
                active<=requested;pending<=0;
                if(pending && requested!=active)begin commit<=1;level<=requested;end
            end
            if(config_valid && config_level<=16 && manual_enable)begin requested<=config_level;pending<=1;end
            if(!manual_enable)pending<=0;
        end
    end
endmodule

// Camera-domain manual AG observer. ae_set's submitted AG must match the
// accepted manual request, and the I2C transfer must go busy then finish.
// No initial/same-value, AUTO, canceled, or failed transaction reports success.
module hud_camera_commit(
    input clk,rst_n,auto_enable,config_valid,input [4:0] config_level,
    input [15:0] config_ag,submitted_ag,
    input ae_request,cam_done,ae_done,iic_error,
    output reg commit,output reg [4:0] level
);
    reg auto_q,pending,inflight,saw_busy,flight_manual;
    reg [4:0] pending_level,flight_level;
    reg [15:0] pending_ag,flight_ag,last_ag;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin auto_q<=0;pending<=0;inflight<=0;saw_busy<=0;
            pending_level<=8;flight_level<=8;pending_ag<=80;flight_ag<=80;last_ag<=80;
            flight_manual<=0;commit<=0;level<=8;end
        else begin
            auto_q<=auto_enable;commit<=0;
            if(inflight)begin
                if(!ae_done)saw_busy<=1;
                if(iic_error || !cam_done)begin inflight<=0;saw_busy<=0;end
                else if(saw_busy && ae_done)begin
                    inflight<=0;saw_busy<=0;
                    last_ag<=flight_ag;
                    if(flight_manual && flight_ag!=last_ag)begin commit<=1;level<=flight_level;end
                end
            end
            if(ae_request)begin
                flight_ag<=submitted_ag;flight_level<=pending_level;inflight<=1;saw_busy<=0;
                flight_manual<=pending && submitted_ag==pending_ag && !auto_enable && !auto_q;
                if(pending && submitted_ag==pending_ag)pending<=0;
            end
            if(config_valid && config_level<=16 && !auto_enable && !auto_q)begin
                pending<=1;pending_level<=config_level;pending_ag<=config_ag;
            end
            if(auto_enable || auto_q || iic_error)begin pending<=0;flight_manual<=0;commit<=0;end
            if(iic_error)begin inflight<=0;saw_busy<=0;end
        end
    end
endmodule

// Bundled-data toggle mailbox. Payload is held until the synchronized ACK;
// latest UI event is coalesced while busy. No business config can be dropped.
// Both resets derive from the common board reset, with domain-local release.
module hud_event_cdc(
    input src_clk,src_rst_n,src_event,input [6:0] src_record,
    input dst_clk,dst_rst_n,
    output reg dst_event,output reg [6:0] dst_record
);
    reg request,acknowledge,queued;
    reg [6:0] holding,latest,captured;
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,request_sync;
    reg capture_pending;
    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin request<=0;queued<=0;holding<=0;latest<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(src_event)begin latest<=src_record;queued<=1;end
            if(ack_sync[1]==request && (queued || src_event))begin
                holding<=src_event ? src_record : latest;request<=!request;queued<=0;
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n)begin
        if(!dst_rst_n)begin request_sync<=0;acknowledge<=0;capture_pending<=0;captured<=0;dst_record<=0;dst_event<=0;end
        else begin
            request_sync<={request_sync[0],request};dst_event<=0;
            if(!capture_pending && request_sync[1]!=acknowledge)begin captured<=holding;capture_pending<=1;end
            else if(capture_pending)begin
                dst_record<=captured;dst_event<=1;acknowledge<=request_sync[1];capture_pending<=0;
            end
        end
    end
endmodule

// Display-only center stability/freshness; parameters allow bounded simulation.
module hud_target_state #(
    parameter integer STABLE_CYCLES=15000000,FRESH_CYCLES=7500000,FLASH_CYCLES=37500000,
    parameter integer EXTENDED_METRICS=0
)(
    input clk,rst_n,enable,recognition,input [7:0] epoch,
    input update,valid,overflow,input [15:0] id,x,y,
    output wire out_valid,output reg locked,output wire lock_visible,
    output wire [15:0] out_id,output wire [63:0] digits,
    output wire dx_negative,dy_negative,
    input metric_mode,input [11:0] metric_w,metric_h,output wire out_centered,
    input sad_mode,output wire [15:0] out_x,out_y
);
    reg live,centered;
    reg [15:0] live_id;
    // Only accepted transactions may complete the number conversion.
    // Rejected full-width inputs still clear ready/busy on the original edge.
    reg [10:0] live_x,number_x;
    reg [9:0] live_y,number_y;
    reg [9:0] number_id_code;
    wire [15:0] number_id={number_id_code[9]?8'h39:(number_id_code[8]?8'h38:8'h00),number_id_code[7:0]};
    reg [7:0] epoch_q;
    reg [22:0] age;
    reg [23:0] stable;
    reg [25:0] flash_time;
    reg [2:0] flashes;
    reg [47:0] binary_work;
    reg [15:0] bcd_work;
    // Partial conversion is hidden by number_ready until the original commit.
    reg [63:0] number_digits;
    reg [5:0] step;
    reg busy,number_ready,sign_x,sign_y,number_sign_x,number_sign_y;
    wire accepted=valid && ((EXTENDED_METRICS && sad_mode) ? (id[15:8]==8'h38 || id[15:8]==8'h39) : (id==1 || id==2)) && x<1280 && y<720;
    // Inclusive center-valid bounds match the fixed static tracking aim frame.
    localparam [15:0] CENTER_VALID_X_MIN=16'd560, CENTER_VALID_X_MAX=16'd720;
    localparam [15:0] CENTER_VALID_Y_MIN=16'd315, CENTER_VALID_Y_MAX=16'd405;
    wire in_center=x>=CENTER_VALID_X_MIN && x<=CENTER_VALID_X_MAX &&
        y>=CENTER_VALID_Y_MIN && y<=CENTER_VALID_Y_MAX;
    // Only accepted x<1280/y<720 transactions consume these magnitudes.
    // Signed differences fit 12/11 bits; legal magnitudes fit 10/9 bits.
    // Rejected full-width coordinates still follow the original cancel path.
    wire signed [11:0] center_dx=$signed({1'b0,x[10:0]})-12'sd640;
    wire signed [10:0] center_dy=$signed({1'b0,y[9:0]})-11'sd360;
    wire [9:0] dx_magnitude=center_dx[11] ? (~center_dx[9:0]+10'd1) : center_dx[9:0];
    wire [8:0] dy_magnitude=center_dy[10] ? (~center_dy[8:0]+9'd1) : center_dy[8:0];
    wire [11:0] dx={2'b00,dx_magnitude};
    wire [11:0] dy={3'b000,dy_magnitude};
    function [15:0] bcd_shift;
        input [15:0] b;input bit_in;
        reg [15:0] a;integer j;
        begin a=b;for(j=0;j<4;j=j+1)if(a[j*4+:4]>=5)a[j*4+:4]=a[j*4+:4]+4'd3;
            bcd_shift={a[14:0],bit_in};end
    endfunction
    wire [15:0] bcd_next=bcd_shift(bcd_work,binary_work[47]);
    assign out_valid=enable && live && age<FRESH_CYCLES && !overflow && number_ready &&
        number_id==live_id && number_x==live_x && number_y==live_y;
    assign out_id=number_id;assign digits=number_digits;
    assign out_x=number_x;assign out_y=number_y;
    assign dx_negative=number_sign_x;assign dy_negative=number_sign_y;
    assign out_centered=out_valid && centered;
    assign lock_visible=locked && (flashes>=6 || !flashes[0]);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            live<=0;centered<=0;live_id<=0;live_x<=0;live_y<=0;epoch_q<=0;age<=FRESH_CYCLES;
            stable<=0;locked<=0;flash_time<=0;flashes<=0;busy<=0;step<=0;
            binary_work<=0;bcd_work<=0;number_digits<=0;number_ready<=0;
            number_id_code<=0;number_x<=0;number_y<=0;sign_x<=0;sign_y<=0;number_sign_x<=0;number_sign_y<=0;
        end else begin
            epoch_q<=epoch;
            if(age<FRESH_CYCLES)age<=age+1'b1;
            if(recognition && live && centered && age<FRESH_CYCLES)begin
                if(stable<STABLE_CYCLES)stable<=stable+1'b1;
                if(stable>=STABLE_CYCLES-1)locked<=1;
            end else begin stable<=0;locked<=0;end
            if(locked && flashes<6)begin
                if(flash_time==FLASH_CYCLES-1)begin flash_time<=0;flashes<=flashes+1'b1;end
                else flash_time<=flash_time+1'b1;
            end
            if(!locked)begin flashes<=0;flash_time<=0;end
            if(busy)begin
                binary_work<={binary_work[46:0],1'b0};
                bcd_work<=bcd_next;step<=step+1'b1;
                if(step==11 || step==23 || step==35 || step==47)begin
                    number_digits<={number_digits[47:0],bcd_next};bcd_work<=0;
                    if(step==47)begin
                        number_ready<=1;busy<=0;
                        number_id_code<={live_id[15:8]==8'h39,live_id[15:8]==8'h38,live_id[7:0]};number_x<=live_x;number_y<=live_y;
                        number_sign_x<=sign_x;number_sign_y<=sign_y;
                    end
                end
            end
            if(update)begin
                age<=0;live<=accepted;centered<=accepted && in_center;
                live_id<=id;live_x<=x[10:0];live_y<=y[9:0];
                if(!accepted || !in_center || id!=live_id)begin stable<=0;locked<=0;end
                if(accepted)begin
                    binary_work<={x[11:0],y[11:0],
                        (EXTENDED_METRICS && metric_mode) ? metric_w : dx,
                        (EXTENDED_METRICS && metric_mode) ? metric_h : dy};
                    bcd_work<=0;number_digits<=0;step<=0;busy<=1;
                    sign_x<=x<640;sign_y<=y<360;number_ready<=0;
                end else begin busy<=0;number_ready<=0;end
            end
            if(!enable || overflow || (epoch!=epoch_q && !(EXTENDED_METRICS && sad_mode)) || (age>=FRESH_CYCLES && !update))begin
                live<=0;centered<=0;stable<=0;locked<=0;flashes<=0;flash_time<=0;
                if(!enable || overflow || (epoch!=epoch_q && !(EXTENDED_METRICS && sad_mode)))begin age<=FRESH_CYCLES;number_ready<=0;busy<=0;end
            end
        end
    end
endmodule

// Two-stage glyph pipeline, consumed by hdmi_mixer's existing output register.
// 20 characters per row, 24-pixel right/bottom margins. No video delay added.
module latency_osd #(
    parameter integer WIDTH=1280, HEIGHT=720, PIXEL_HZ=75000000,
    parameter integer EXTERNAL_FONT=0,FONT_PIXEL_DELAYED=0
)(
    input wire clk, rst_n, frame_start, de,
    input wire [11:0] x, y,
    input wire [3:0] proc_mode, row_enable,
    input wire [15:0] age_bcd,
    input wire [13:0] age_ticks,
    input wire age_valid,
    input wire [15:0] detect_bcd,
    input wire detect_valid,
    output reg region_d2, output wire ink_d2,
    output wire [7:0] font_char,
    output wire [3:0] font_row,font_col,
    output wire font_request,
    input wire external_font_pixel
);
    localparam integer LEFT=WIDTH-24-160, TOP=HEIGHT-24-64;
    function [15:0] proc_ns_bcd;
        input integer clocks;
        reg [63:0] tenths;
        reg [3:0] d3,d2,d1,d0;
        begin
            // Called only by localparams: compile-time 0.1 ns rounding.
            tenths=(64'd10000000000*clocks+PIXEL_HZ/2)/PIXEL_HZ;
            d3=tenths/1000;d2=(tenths/100)%10;d1=(tenths/10)%10;d0=tenths%10;
            proc_ns_bcd={d3,d2,d1,d0};
        end
    endfunction
    localparam [15:0] PROC_1_NS=proc_ns_bcd(1), PROC_3_NS=proc_ns_bcd(3), PROC_5_NS=proc_ns_bcd(5);
    localparam [15:0] PROC_6_NS=proc_ns_bcd(6);
    wire [15:0] average_bcd, maximum_bcd;
    wire average_valid, maximum_valid;
    video_latency_average average(
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.mode(proc_mode),
        .sample_ticks(age_ticks),.sample_valid(age_valid),
        .result_bcd(average_bcd),.result_valid(average_valid),
        .maximum_bcd(maximum_bcd),.maximum_valid(maximum_valid));
    reg [15:0] proc_bcd, frame_bcd, max_frame_bcd, detect_frame_bcd;
    reg [3:0] display_mode;
    reg frame_valid, max_frame_valid, detect_frame_valid;
    wire [11:0] rx=x-LEFT, ry=y-TOP;
    wire region=(x>=LEFT)&&(x<WIDTH-24)&&(y>=TOP)&&(y<HEIGHT-24);
    wire [1:0] text_line=ry[5:4];
    wire glyph=1'b1;
    wire [3:0] font_y=ry[3:0];
    wire [15:0] video_value=(text_line==1) ? frame_bcd : max_frame_bcd;
    wire video_valid=(text_line==1) ? frame_valid : max_frame_valid;
    reg [7:0] character, char_d1;
    reg [3:0] row_d1,col_d1;
    reg region_d1,glyph_d1,glyph_d2,ink_registered;
    reg [3:0] display_enable;
    wire font_pixel;
    assign font_char=char_d1;assign font_row=row_d1;assign font_col=col_d1;
    assign font_request=region_d1 && glyph_d1;
    // Delayed external row bits already belong to stage two. The standalone
    // default retains its original two registered glyph stages.
    assign ink_d2=(EXTERNAL_FONT && FONT_PIXEL_DELAYED) ?
        (glyph_d2 && external_font_pixel) : ink_registered;
    generate if(EXTERNAL_FONT)begin : g_external_font
        assign font_pixel=external_font_pixel;
    end else begin : g_local_font
        wire [7:0] bits;
        hud_font font(char_d1,row_d1,bits);
        assign font_pixel=bits[7-col_d1[2:0]];
    end endgenerate
    always @* begin
        character=8'h20;
        case(text_line)
            0:case(rx[7:3])
                0:character="P";1:character="R";2:character="O";3:character="C";4:character=":";
                6:character=8'h30+{4'd0,proc_bcd[15:12]};
                7:character=8'h30+{4'd0,proc_bcd[11:8]};
                8:character=8'h30+{4'd0,proc_bcd[7:4]};9:character=".";
                10:character=8'h30+{4'd0,proc_bcd[3:0]};12:character="N";13:character="S";
                default:character=8'h20;
            endcase
            1,2:case(rx[7:3])
                0:character="V";1:character="I";2:character="D";3:character="E";4:character="O";
                6:character=(text_line==1) ? "A" : "M";
                7:character=(text_line==1) ? "V" : "A";
                8:character=(text_line==1) ? "G" : "X";9:character=":";
                11:character=video_valid ? 8'h30+{4'd0,video_value[15:12]} : "-";
                12:character=video_valid ? 8'h30+{4'd0,video_value[11:8]} : "-";
                13:character=video_valid ? 8'h30+{4'd0,video_value[7:4]} : "-";14:character=".";
                15:character=video_valid ? 8'h30+{4'd0,video_value[3:0]} : "-";
                17:character="M";18:character="S";default:character=8'h20;
            endcase
            3:case(rx[7:3])
                0:character="D";1:character="E";2:character="T";3:character="E";4:character="C";5:character="T";
                7:character="A";8:character="V";9:character="G";10:character=":";
                12:character=detect_frame_valid ? 8'h30+{4'd0,detect_frame_bcd[15:12]} : "-";
                13:character=detect_frame_valid ? 8'h30+{4'd0,detect_frame_bcd[11:8]} : "-";
                14:character=detect_frame_valid ? 8'h30+{4'd0,detect_frame_bcd[7:4]} : "-";15:character=".";
                16:character=detect_frame_valid ? 8'h30+{4'd0,detect_frame_bcd[3:0]} : "-";
                18:character="M";19:character="S";default:character=8'h20;
            endcase
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            proc_bcd<=PROC_1_NS;frame_bcd<=0;max_frame_bcd<=0;detect_frame_bcd<=0;
            frame_valid<=0;max_frame_valid<=0;detect_frame_valid<=0;display_mode<=0;
            char_d1<=8'h20;row_d1<=0;col_d1<=0;
            region_d1<=0;region_d2<=0;glyph_d1<=0;glyph_d2<=0;ink_registered<=0;display_enable<=4'h0;
        end else begin
            if(frame_start) begin
                display_enable<=row_enable;
                proc_bcd<=(proc_mode==0 || proc_mode>11) ? PROC_1_NS :
                         ((proc_mode==11) ? PROC_6_NS :
                         ((proc_mode>=3 && proc_mode<=6) ? PROC_5_NS : PROC_3_NS));
                display_mode<=proc_mode;
                frame_valid<=average_valid && age_valid && (proc_mode==display_mode);
                max_frame_valid<=maximum_valid && age_valid && (proc_mode==display_mode);
                detect_frame_valid<=detect_valid;
                if(average_valid)frame_bcd<=average_bcd;
                if(maximum_valid)max_frame_bcd<=maximum_bcd;
                if(detect_valid)detect_frame_bcd<=detect_bcd;
            end
            char_d1<=character;row_d1<=font_y;col_d1<={1'b0,rx[2:0]};
            region_d1<=region && de && display_enable[text_line];glyph_d1<=glyph && display_enable[text_line];region_d2<=region_d1;
            glyph_d2<=glyph_d1;ink_registered<=glyph_d1 && font_pixel;
        end
    end
endmodule

// Display statistics only. Raw same-frame timestamps and video are untouched.
// 32-frame moving mean and Q8 EMA. Only statistic arithmetic is serialized;
// history sampling and peak publication retain the video-frame time base.
module video_latency_average(
 input wire clk,rst_n,frame_start,input wire[3:0]mode,
 input wire[13:0]sample_ticks,input wire sample_valid,
 output reg[15:0]result_bcd,output reg result_valid,
 output reg[15:0]maximum_bcd,output reg maximum_valid
);
 reg[3:0]mode_q;
 (* ram_style="bram" *) reg[13:0]history[0:31];
 reg[4:0]pointer,refresh;
 reg[5:0]count;reg[18:0]sum;reg[21:0]smooth;
 reg[13:0]binary_shift;reg[15:0]bcd_work;reg[3:0]steps;
 reg converter_max;
 reg[2:0]math_state;
 localparam [2:0] M_IDLE=0,M_SUBTRACT_OLDEST=1,M_DIFFERENCE=2,M_EMA=3,M_ROUND=4;
 reg[13:0]oldest_sample;
 reg[14:0]ema_step;
 reg ema_correction,initial_mean,publish_pending;
 // Real frame pulses are separated by a complete video frame. Suppress a
 // malformed new frame before the five-clock statistic transaction finishes.
 wire invalid_frame=frame_start&&((mode!=mode_q)||!sample_valid||math_state!=M_IDLE);
 wire history_write=rst_n&&frame_start&&!invalid_frame;
 reg[13:0]history_pointer_q,history_scan_q,history_zero;
 reg history_wrote;
 wire[13:0]history_oldest=history_wrote ? history_scan_q : history_pointer_q;
 wire publish=frame_start&&sample_valid&&mode==mode_q&&
  count>=31&&(count==31||refresh==29);
 wire average_start=(math_state==M_ROUND)&&publish_pending;
 // One explicit carry chain serves sum, difference, EMA and rounding.
 // For d=smooth-mean: smooth-trunc(d/256) equals the old
 // smooth+trunc((mean-smooth)/256), including negative fractional steps.
 reg[22:0]alu_a,alu_b;
 reg alu_subtract,alu_carry;
 always @*begin
  alu_a={4'b0,sum};alu_b={9'b0,sample_ticks};alu_subtract=0;alu_carry=0;
  case(math_state)
   M_SUBTRACT_OLDEST:begin alu_b={9'b0,oldest_sample};alu_subtract=1;alu_carry=1;end
   M_DIFFERENCE:begin alu_a={1'b0,smooth};alu_b={1'b0,sum,3'b0};alu_subtract=1;alu_carry=1;end
   M_EMA:begin alu_a={1'b0,smooth};alu_b={{8{ema_step[14]}},ema_step};alu_subtract=1;alu_carry=!ema_correction;end
   M_ROUND:begin alu_a={1'b0,smooth};alu_b=23'd128;end
   default:begin end
  endcase
 end
 wire[22:0]alu_result=alu_a+(alu_b^{23{alu_subtract}})+{{22{1'b0}},alu_carry};
 reg[5:0]max_scan_left;reg[4:0]max_index;reg[13:0]max_value;
 wire[13:0]max_read=(max_scan_left==32)?history_zero:history_scan_q;
 wire[13:0]max_next=(max_read>max_value)?max_read:max_value;
 wire max_converting=converter_max&&(steps!=0);
 wire cancel_max=frame_start&&(max_scan_left!=0||max_converting);
 wire[4:0]history_scan_address=history_write ? pointer+5'd1 :
  ((max_scan_left!=0)?max_index+5'd1:5'd0);
 // Same two RAM ports, write sampling, prefetch and collision forwarding.
 always @(posedge clk)begin
  history_wrote<=history_write;
  if(history_write)begin
   history[pointer]<=sample_ticks;
   if(pointer==0)history_zero<=sample_ticks;
  end else history_pointer_q<=history[pointer];
  history_scan_q<=history[history_scan_address];
 end
 reg[15:0]adjusted;integer d;
 always @*begin
  adjusted=bcd_work;
  for(d=0;d<4;d=d+1)if(bcd_work[d*4+:4]>=5)adjusted[d*4+:4]=bcd_work[d*4+:4]+4'd3;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   mode_q<=0;pointer<=0;refresh<=0;count<=0;sum<=0;smooth<=0;
   math_state<=M_IDLE;oldest_sample<=0;ema_step<=0;ema_correction<=0;initial_mean<=0;publish_pending<=0;
  end else if(invalid_frame)begin
   mode_q<=mode;pointer<=0;refresh<=0;count<=0;sum<=0;smooth<=0;
   math_state<=M_IDLE;publish_pending<=0;
  end else if(frame_start)begin
   pointer<=pointer+1'b1;sum<=alu_result[18:0];
   oldest_sample<=(count==32)?history_oldest:14'd0;
   initial_mean<=(count==31);publish_pending<=publish;
   math_state<=M_SUBTRACT_OLDEST;
   if(count<32)count<=count+1'b1;
   if(count>=31)begin if(count==31||refresh==29)refresh<=0;else refresh<=refresh+1'b1;end
  end else begin
   case(math_state)
    M_SUBTRACT_OLDEST:begin
     sum<=alu_result[18:0];
     if(initial_mean)smooth<={alu_result[18:0],3'b0};
     if(count==32)math_state<=M_DIFFERENCE;else math_state<=M_IDLE;
    end
    M_DIFFERENCE:begin
     ema_step<=alu_result[22:8];ema_correction<=alu_result[22]&&(|alu_result[7:0]);math_state<=M_EMA;
    end
    M_EMA:begin smooth<=alu_result[21:0];math_state<=publish_pending?M_ROUND:M_IDLE;end
    M_ROUND:begin math_state<=M_IDLE;publish_pending<=0;end
    default:begin end
   endcase
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin max_scan_left<=0;max_index<=0;max_value<=0;end
  else if(invalid_frame)max_scan_left<=0;
  else if(publish)begin max_scan_left<=32;max_index<=0;max_value<=0;end
  else if(cancel_max)max_scan_left<=0;
  else if(max_scan_left!=0)begin max_value<=max_next;max_index<=max_index+1'b1;max_scan_left<=max_scan_left-1'b1;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   binary_shift<=0;bcd_work<=0;steps<=0;converter_max<=0;
   result_bcd<=0;result_valid<=0;maximum_bcd<=0;maximum_valid<=0;
  end else if(invalid_frame)begin steps<=0;result_valid<=0;maximum_valid<=0;end
  else begin
   if(cancel_max&&!publish)maximum_valid<=0;
   if(average_start)begin binary_shift<=alu_result[21:8];bcd_work<=0;steps<=14;converter_max<=0;end
   else if(frame_start)begin if(max_converting)steps<=0;end
   else if(max_scan_left==1)begin binary_shift<=max_next;bcd_work<=0;steps<=14;converter_max<=1;end
   else if(steps!=0)begin
    bcd_work<={adjusted[14:0],binary_shift[13]};binary_shift<={binary_shift[12:0],1'b0};steps<=steps-1'b1;
    if(steps==1)begin
     if(converter_max)begin maximum_bcd<={adjusted[14:0],binary_shift[13]};maximum_valid<=1;end
     else begin result_bcd<={adjusted[14:0],binary_shift[13]};result_valid<=1;end
    end
   end
  end
 end
endmodule



// Both detectors and this observer use the HDMI clock. No video-path registers.
module detection_latency_monitor #(
    parameter integer H_ACTIVE=1280, V_ACTIVE=720, PIXEL_HZ=75000000, AVG_LOG2=5
)(
    input wire clk,rst_n,
    input wire [1:0] mode, // 0 off, 1 motion, 2 colour
    input wire measure_ready,frame_start,frame_de,result_update,result_good,
    output wire [15:0] average_bcd,
    output wire average_valid,
    output reg sample_update,sample_valid,
    output reg [13:0] sample_ticks
);
    localparam integer FRAME_PIXELS=H_ACTIVE*V_ACTIVE;
    localparam integer TICK_CLOCKS=PIXEL_HZ/10000;
    localparam integer DIV_WIDTH=(TICK_CLOCKS<2) ? 1 : $clog2(TICK_CLOCKS);
    reg [1:0] mode_q;
    reg pending,frame_good;
    reg [20:0] pixels;
    reg [DIV_WIDTH-1:0] divider;
    reg [13:0] elapsed;
    wire enabled=measure_ready && mode!=0;
    wire [21:0] next_pixels={1'b0,pixels}+(frame_de ? 22'd1 : 22'd0);
    wire carry=(divider==TICK_CLOCKS-1);
    wire [13:0] next_elapsed=elapsed+(carry ? 14'd1 : 14'd0);
    detection_latency_average #(.AVG_LOG2(AVG_LOG2)) average(
        .clk(clk),.rst_n(rst_n),.enabled(enabled),.owner(mode),
        .sample_update(sample_update),.sample_valid(sample_valid),.sample_ticks(sample_ticks),
        .result_bcd(average_bcd),.result_valid(average_valid));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mode_q<=0;pending<=0;frame_good<=0;pixels<=0;divider<=0;elapsed<=0;
            sample_update<=0;sample_valid<=0;sample_ticks<=0;
        end else begin
            sample_update<=0;
            if(!enabled || mode!=mode_q) begin
                mode_q<=mode;pending<=0;frame_good<=0;pixels<=0;divider<=0;elapsed<=0;
                sample_valid<=0;
            end else if(frame_start) begin
                // Never pair an old/late result with a newer frame start.
                if(pending || result_update) begin sample_update<=1;sample_valid<=0;end
                pending<=1;frame_good<=frame_de;pixels<=frame_de ? 21'd1 : 21'd0;
                divider<=0;elapsed<=0;
            end else if(pending) begin
                if(frame_de) begin
                    if(pixels<FRAME_PIXELS)pixels<=pixels+21'd1;
                    else frame_good<=0;
                end
                if(carry) begin
                    divider<=0;
                    if(elapsed<10000)elapsed<=next_elapsed;
                    if(next_elapsed>9999)frame_good<=0;
                end else divider<=divider+1'b1;
                if(result_update) begin
                    pending<=0;sample_update<=1;sample_ticks<=next_elapsed;
                    sample_valid<=frame_good && result_good && next_pixels==FRAME_PIXELS && next_elapsed<=9999;
                end
            end else if(result_update) begin
                sample_update<=1;sample_valid<=0; // no matching SOF, including first blanking
            end
        end
    end
endmodule

// Non-overlapping groups of 32 valid completed detections, rounded to 0.1 ms.
// Unlike VIDEO AVG, no EMA or frame-history RAM is needed for this statistic.
module detection_latency_average #(parameter integer AVG_LOG2=5)(
    input wire clk,rst_n,enabled,
    input wire [1:0] owner,
    input wire sample_update,sample_valid,
    input wire [13:0] sample_ticks,
    output reg [15:0] result_bcd,
    output reg result_valid
);
    reg [1:0] owner_q;
    reg [AVG_LOG2-1:0] count;
    reg [13+AVG_LOG2:0] sum;
    wire [13+AVG_LOG2:0] next_sum=sum+sample_ticks;
    wire [14+AVG_LOG2:0] rounded={1'b0,next_sum}+(1 << (AVG_LOG2-1));
    wire good_sample=sample_valid && sample_ticks<=9999;
    reg [13:0] binary_shift;
    reg [15:0] bcd_work,adjusted;
    reg [3:0] steps;
    integer digit;
    always @* begin
        adjusted=bcd_work;
        for(digit=0;digit<4;digit=digit+1)
            if(bcd_work[digit*4 +: 4]>=5)
                adjusted[digit*4 +: 4]=bcd_work[digit*4 +: 4]+4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            owner_q<=0;count<=0;sum<=0;binary_shift<=0;bcd_work<=0;steps<=0;
            result_bcd<=0;result_valid<=0;
        end else if(!enabled || owner==0 || owner!=owner_q || (sample_update && !good_sample)) begin
            owner_q<=owner;count<=0;sum<=0;steps<=0;result_valid<=0;
        end else begin
            if(sample_update) begin
                if(&count) begin
                    count<=0;sum<=0;binary_shift<=rounded[AVG_LOG2 +: 14];
                    bcd_work<=0;steps<=14;
                end else begin count<=count+1'b1;sum<=next_sum;end
            end
            if(steps!=0 && !(sample_update && (&count))) begin
                bcd_work<={adjusted[14:0],binary_shift[13]};
                binary_shift<={binary_shift[12:0],1'b0};steps<=steps-1'b1;
                if(steps==1) begin result_bcd<={adjusted[14:0],binary_shift[13]};result_valid<=1;end
            end
        end
    end
endmodule

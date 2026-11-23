`include "fpga_b_example_config.vh"



// Default: follow the existing target register with the C core's hold branch.
// The repeating quintic trajectory requires an explicit TEST_MODE opt-in.
module GM6020_id2_model_ctrl #(
    parameter integer CLK_HZ=50000000,
    parameter integer COMMAND_REVERSE=0,
    parameter integer CLOCKWISE_COUNT_INCREASE=1,
    parameter integer FEEDBACK_TIMEOUT_MS=10,
    parameter integer TEST_MODE=0,
    parameter integer AUTO_START=0,
    // Disable in production instances with no test_start input. This removes
    // quintic powers/polynomial hardware rather than running it with phase=0.
    parameter integer ENABLE_TEST_TRAJECTORY=1,

    parameter signed [31:0] MODEL_INV_K_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_MODEL_INV_K_Q16_1,
    parameter signed [31:0] MODEL_KP_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_MODEL_KP_Q16_1,
    parameter signed [31:0] MODEL_KI_DT_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_MODEL_KI_DT_Q16_1,
    parameter signed [31:0] MODEL_TAU_Q24=`FPGA_B_GM6020_ID2_MODEL_CTRL_MODEL_TAU_Q24_1,
    // Defaults preserve the legacy/manual core. The top supplies distinct
    // visual tracking gains and filters for each identified motor.
    parameter signed [31:0] NORMAL_KP_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_NORMAL_KP_Q16_1,
    parameter signed [31:0] NORMAL_KI_DT_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_NORMAL_KI_DT_Q16_1,
    parameter signed [31:0] FAST_KP_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_FAST_KP_Q16_1,
    parameter signed [31:0] FAST_KI_DT_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_FAST_KI_DT_Q16_1,
    parameter signed [31:0] MAX_SPEED_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_MAX_SPEED_Q16_1,
    parameter signed [31:0] TRACKING_STABLE_KP_Q16=MODEL_KP_Q16,
    parameter signed [31:0] TRACKING_STABLE_KI_DT_Q16=MODEL_KI_DT_Q16,
    parameter signed [31:0] FAST_MAX_SPEED_Q16=MAX_SPEED_Q16,
    parameter signed [31:0] FAST_COMMAND_LIMIT_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_FAST_COMMAND_LIMIT_Q16_1,
    parameter integer FAST_OVERSPEED_RPM=`FPGA_B_GM6020_ID2_MODEL_CTRL_FAST_OVERSPEED_RPM_1,
    parameter signed [31:0] TRACKING_ENCODER_ALPHA_Q16=`FPGA_B_GM6020_ID2_MODEL_CTRL_TRACKING_ENCODER_ALPHA_Q16_1,
    parameter integer TRACKING_SPEED_FILTER_SHIFT=`FPGA_B_GM6020_ID2_MODEL_CTRL_TRACKING_SPEED_FILTER_SHIFT_1,
    parameter integer HOLD_LEAK_ENABLE=`FPGA_B_GM6020_ID2_MODEL_CTRL_HOLD_LEAK_ENABLE_1,
    parameter integer ENABLE_POSITION_LIMITS=0,
    // Arrival reporting only; the drive/hold control deadband stays unchanged.
    parameter integer ARRIVAL_TOLERANCE_COUNTS=`FPGA_B_GM6020_ID2_MODEL_CTRL_ARRIVAL_TOLERANCE_COUNTS_1,

    // 1 => equal new output/history; 2 => 1/4 new output; 0 bypasses.
    parameter integer FAST_OUTPUT_FILTER_SHIFT=`FPGA_B_GM6020_ID2_MODEL_CTRL_FAST_OUTPUT_FILTER_SHIFT_1
)(
    input wire clk,rst_n,enable,feedback_valid,
    input wire [12:0] angle,
    input wire signed [15:0] speed_rpm,
    input wire [7:0] temperature,
    input wire [12:0] target_angle_register,
    input wire test_start,test_stop,
    // Absolute multi-turn target. Velocity is counts/s Q16 and is an offset
    // to the unchanged 8/s position correction, as in ID2_CoreTrack.
    input wire tracking_enable,
    input wire [1:0] tracking_mode,
    input wire signed [31:0] tracking_target_counts, tracking_velocity_q16,
    input wire position_limit_enable,
    input wire signed [31:0] position_min_counts,position_max_counts,
    output wire signed [15:0] command,
    output reg command_valid,active,fault,test_running,
    output reg signed [31:0] position_counts,target_counts,reference_counts,
    output reg signed [31:0] speed_setpoint_q16,
    output reg [31:0] completed_segments,
    output wire feedback_ready,
    // Arrival belongs to the angle/speed control sample, not the UART or
    // camera parser. Qualify the sample against the live streamed target.
    output wire at_target
);
    localparam integer TRAJECTORY_ENABLED=TEST_MODE || ENABLE_TEST_TRAJECTORY;
    localparam integer TICKS=CLK_HZ/1000;
    localparam integer TW=(TICKS>1)?$clog2(TICKS):1;
    localparam integer TIMEOUT=(CLK_HZ/1000)*FEEDBACK_TIMEOUT_MS;
    localparam signed [31:0] INV_K=MODEL_INV_K_Q16, KP=MODEL_KP_Q16, KI_DT=MODEL_KI_DT_Q16;
    localparam signed [31:0] TAU_Q24=MODEL_TAU_Q24, LEAK=`FPGA_B_GM6020_ID2_MODEL_CTRL_LEAK_1, R_STEP=`FPGA_B_GM6020_ID2_MODEL_CTRL_R_STEP_1;
    localparam signed [31:0] V_LIMIT=MAX_SPEED_Q16, I_LIMIT=`FPGA_B_GM6020_ID2_MODEL_CTRL_I_LIMIT_1, U_LIMIT=`FPGA_B_GM6020_ID2_MODEL_CTRL_U_LIMIT_1;
    localparam signed [31:0] HOLD_BAND=`FPGA_B_GM6020_ID2_MODEL_CTRL_HOLD_BAND_1;
    localparam signed [32:0] ARRIVAL_LIMIT=ARRIVAL_TOLERANCE_COUNTS;
    localparam [31:0] ARRIVAL_BAND_Q16=ARRIVAL_TOLERANCE_COUNTS*65536;
    localparam signed [31:0] STEP_COUNTS=CLOCKWISE_COUNT_INCREASE?4096:-4096;
    localparam [5:0] IDLE=0,Q_WAIT=1,Q_STORE=2,R2_WAIT=3,R2_STORE=4,
        R3_WAIT=5,R3_STORE=6,R4_WAIT=7,R4_STORE=8,R5_WAIT=9,R5_STORE=10,
        POLY=11,SCALE=12,ERROR=13,FILTER=14,DESIRED=15,
        LEAK_WAIT=16,LEAK_STORE=17,TAU_WAIT=18,TAU_STORE=19,
        FF_WAIT=20,FF_STORE=21,P_WAIT=22,P_STORE=23,I_WAIT=24,I_STORE=25,OUT=26,ENC_WAIT=27,ENC_STORE=28,BLEND=29,GAIN_WAIT=30,GAIN_STORE=31,FAST_OUTPUT=32;
    reg [TW-1:0] tick_count;
    wire control_tick=(tick_count==TICKS-1);
    reg [31:0] feedback_age;
    reg [12:0] last_angle;
    reg signed [15:0] latest_speed;
    reg [7:0] latest_temperature;
    reg has_feedback;
    reg [5:0] seen_frames;
    wire stale=has_feedback && !feedback_valid && feedback_age>=TIMEOUT-1;
    assign feedback_ready=has_feedback && feedback_age<TIMEOUT && !fault;
    reg [5:0] state;
    reg initialized,auto_started,start_pending,stop_pending,filter_initialized;
    reg tracking_was_applied;
    reg signed [31:0] work_kp,work_ki_dt,last_kp,work_speed_limit;
    reg work_gain_changed;
    // Unconnected legacy simulation ports and invalid values use stable tuning.
    function [1:0] select_mode;
        input enabled;
        input [1:0] mode;
        begin
            select_mode=0;
            if(enabled)case(mode)
                2'd1:select_mode=1;
                2'd2:select_mode=2;
                default:select_mode=0;
            endcase
        end
    endfunction
    wire [1:0] requested_mode=select_mode(tracking_enable,tracking_mode);
    wire signed [31:0] requested_kp=!tracking_enable?MODEL_KP_Q16:
        (requested_mode==1?NORMAL_KP_Q16:(requested_mode==2?FAST_KP_Q16:TRACKING_STABLE_KP_Q16));
    wire signed [31:0] requested_ki_dt=!tracking_enable?MODEL_KI_DT_Q16:
        (requested_mode==1?NORMAL_KI_DT_Q16:(requested_mode==2?FAST_KI_DT_Q16:TRACKING_STABLE_KI_DT_Q16));
    wire signed [31:0] requested_speed_limit=requested_mode==2?FAST_MAX_SPEED_Q16:MAX_SPEED_Q16;
    reg fast_speed_guard;
    wire signed [31:0] speed_fault_limit=(fast_speed_guard || requested_mode==2)?FAST_OVERSPEED_RPM:60;
    wire speed_violation=latest_speed>speed_fault_limit || latest_speed< -speed_fault_limit;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)fast_speed_guard<=0;
        else if(!enable || fault)fast_speed_guard<=0;
        else if(requested_mode==2)fast_speed_guard<=1;
        else if(latest_speed<=60 && latest_speed>=-60)fast_speed_guard<=0;
    end
    reg [12:0] applied_target;
    reg [10:0] phase_ms;
    reg signed [31:0] base_counts,hold_counts;
    reg signed [31:0] mult_x,mult_y;
    reg signed [63:0] product;
    reg signed [31:0] r,r2,r3,r4,r5;
    reg signed [31:0] f_norm,v_norm,a_norm;
    reg signed [31:0] ref_inc_q16,ref_speed_q16,ref_accel_q16;
    reg signed [31:0] work_pos,work_base,work_speed;
    reg work_profile,work_boundary,work_tracking,encoder_speed_valid;
    reg signed [31:0] encoder_last_position,encoder_speed_q16,work_velocity_q16;
    reg signed [31:0] error_q16,filtered_speed_q16,desired_q16,speed_error_q16;
    reg signed [31:0] integral_q16,work_integral_q16,i_candidate_q16,ff_q16,p_q16;
    reg settled_sample;
    reg signed [15:0] command_raw;
    reg work_fast_output;
    reg signed [31:0] work_command_limit;
    // Keep fractional command precision, before motor polarity reversal.
    reg signed [31:0] output_filter_q16,output_filter_input_q16;
    reg work_limits;
    reg signed [31:0] work_min,work_max;
    wire live_limits=ENABLE_POSITION_LIMITS && position_limit_enable &&
        tracking_enable && enable && feedback_ready && position_min_counts<=position_max_counts;
    wire signed [31:0] effective_tracking_target=!live_limits?tracking_target_counts:
        (tracking_target_counts<position_min_counts?position_min_counts:
         (tracking_target_counts>position_max_counts?position_max_counts:tracking_target_counts));
    wire drive_outward=COMMAND_REVERSE ?
        ((position_counts>=position_max_counts && command_raw<0) ||
         (position_counts<=position_min_counts && command_raw>0)) :
        ((position_counts>=position_max_counts && command_raw>0) ||
         (position_counts<=position_min_counts && command_raw<0));

    // braking/recovery torque remains available, including reversed polarity.
    wire signed [15:0] mode_command=requested_mode==2?command_raw:
        (command_raw>6000?16'sd6000:(command_raw< -6000?-16'sd6000:command_raw));
    assign command=(live_limits && drive_outward)?16'sd0:mode_command;
    // Use the published reference for the arrival distance. Qualify it with
    // the live effective target separately, keeping the region/target mux out
    // of this subtractor and the return timer's long combinational path.
    wire signed [32:0] live_position_error=
        $signed({reference_counts[31],reference_counts})-
        $signed({position_counts[31],position_counts});
    assign at_target=enable && feedback_ready && active && tracking_enable &&
        !test_running && settled_sample && target_counts==reference_counts &&
        reference_counts==effective_tracking_target &&
        live_position_error>= -ARRIVAL_LIMIT && live_position_error<=ARRIVAL_LIMIT &&
        latest_speed>= -16'sd1 && latest_speed<=16'sd1;

    function signed [31:0] wrap_delta;
        input [12:0] wanted,actual;
        reg signed [31:0] d;
        begin
            d=$signed({1'b0,wanted})-$signed({1'b0,actual});
            if(d>4096) d=d-8192;
            else if(d< -4096) d=d+8192;
            wrap_delta=d;
        end
    endfunction
    function signed [31:0] target_delta;
        input [12:0] wanted,actual;
        reg signed [31:0] d;
        begin
            d=wrap_delta(wanted,actual);
            if(d==4096 || d== -4096) d=STEP_COUNTS;
            target_delta=d;
        end
    endfunction
    function signed [31:0] clip;
        input signed [63:0] v;
        input signed [31:0] limit;
        begin
            if(v>limit) clip=limit;
            else if(v< -$signed(limit)) clip=-limit;
            else clip=v[31:0];
        end
    endfunction
    function [31:0] abs32;
        input signed [31:0] v;
        begin abs32=v<0?-v:v;end
    endfunction
    // Exact fixed-coefficient products. Widen before shifting; leave the
    // shared registered variable multiplier and every control state unchanged.
    function signed [63:0] times6;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin v=value;times6=(v<<<2)+(v<<<1);end
    endfunction
    function signed [63:0] times10;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin v=value;times10=(v<<<3)+(v<<<1);end
    endfunction
    function signed [63:0] times15;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin v=value;times15=(v<<<4)-v;end
    endfunction
    function signed [63:0] times480000;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin
            v=value;
            times480000=(((v<<<10)-(v<<<8))+((v<<<12)+(v<<<14)))+((v<<<19)-(v<<<16));
        end
    endfunction
    function signed [15:0] rounded_command;
        input signed [31:0] v;
        reg signed [31:0] n;
        begin
            n=v>=0?(v+32768)>>>16:-(((-v)+32768)>>>16);
            rounded_command=COMMAND_REVERSE?-n[15:0]:n[15:0];
        end
    endfunction

    wire signed [31:0] fresh_position=has_feedback?
        position_counts+wrap_delta(angle,last_angle):32'sd0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tick_count<=0;feedback_age<=0;last_angle<=0;latest_speed<=0;
            latest_temperature<=0;has_feedback<=0;seen_frames<=0;position_counts<=0;
        end else if(!enable) begin
            tick_count<=0;feedback_age<=0;has_feedback<=0;seen_frames<=0;position_counts<=0;
        end else begin
            tick_count<=control_tick?0:tick_count+1'b1;
            if(feedback_valid) begin
                position_counts<=fresh_position;last_angle<=angle;
                latest_speed<=speed_rpm;latest_temperature<=temperature;
                has_feedback<=1;feedback_age<=0;
                if(seen_frames<63) seen_frames<=seen_frames+1'b1;
            end else if(has_feedback && feedback_age<TIMEOUT) feedback_age<=feedback_age+1'b1;
        end
    end
    reg [1:0] multiply_phase;
    reg signed [31:0] partial_low,partial_high;
    wire multiplication_wait=state==Q_WAIT || state==R2_WAIT || state==R3_WAIT || state==R4_WAIT || state==R5_WAIT || state==LEAK_WAIT || state==TAU_WAIT || state==FF_WAIT || state==P_WAIT || state==I_WAIT || state==ENC_WAIT || state==GAIN_WAIT;
    wire signed [16:0] low_x={mult_x[15],mult_x[15:0]};
    wire signed [16:0] low_y={mult_y[15],mult_y[15:0]};
    wire signed [16:0] high_x=$signed({mult_x[31],mult_x[31:16]})+$signed({16'd0,mult_x[15]});
    wire signed [16:0] high_y=$signed({mult_y[31],mult_y[31:16]})+$signed({16'd0,mult_y[15]});
    wire multiply_fast=high_x==0 || high_y==0;
    wire signed [16:0] full_low=high_y==0?low_x:low_y;
    wire signed [16:0] full_high=high_y==0?high_x:high_y;
    wire signed [16:0] small_value=high_y==0?low_y:low_x;
    wire signed [16:0] multiply_a=multiply_fast?(multiply_phase==0?full_low:full_high):
        (multiply_phase==0?low_x:(multiply_phase==1?high_x:low_x-high_x));
    wire signed [16:0] multiply_b=multiply_fast?small_value:
        (multiply_phase==0?low_y:(multiply_phase==1?high_y:low_y-high_y));
    wire signed [33:0] multiply_result=multiply_a*multiply_b;
    wire signed [33:0] cross_sum={{2{partial_low[31]}},partial_low}+
        {{2{partial_high[31]}},partial_high}-multiply_result;
    wire signed [32:0] cross_value=multiply_fast?{multiply_result[31],multiply_result[31:0]}:cross_sum[32:0];
    wire signed [32:0] middle_sum=cross_value+$signed({{17{partial_low[31]}},partial_low[31:16]});
    wire [31:0] high_sum=(multiply_fast?32'd0:partial_high)+{{15{middle_sum[32]}},middle_sum[32:16]};
    wire multiply_done=multiply_phase==(multiply_fast?2'd1:2'd2);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin multiply_phase<=0;partial_low<=0;partial_high<=0;product<=0;end
        else if(multiplication_wait)begin
            multiply_phase<=multiply_done?2'd0:multiply_phase+1'b1;
            if(multiply_phase==0)partial_low<=multiply_result[31:0];
            else if(multiply_done)product<={high_sum,middle_sum[15:0],partial_low[15:0]};
            else partial_high<=multiply_result[31:0];
        end else multiply_phase<=0;
    end

    always @(posedge clk or negedge rst_n) begin: controller
        reg signed [31:0] pos,base,hold,speed,phase,new_r,power,n,filt,u;
        reg profile,boundary;
        reg signed [63:0] wide,poly_f,poly_v,poly_a,unsaturated;
        reg signed [47:0] ref_wide,position_wide,error_wide;
        reg signed [32:0] distance_to_bound;
        reg signed [63:0] boundary_speed;
        reg block_drive;
        if(!rst_n) begin
            command_raw<=0;command_valid<=0;active<=0;fault<=0;test_running<=0;settled_sample<=0;
            work_command_limit<=`FPGA_B_GM6020_ID2_MODEL_CTRL_U_LIMIT_2;
            work_fast_output<=0;output_filter_q16<=0;output_filter_input_q16<=0;
            work_limits<=0;work_min<=0;work_max<=0;
            target_counts<=0;reference_counts<=0;speed_setpoint_q16<=0;completed_segments<=0;
            state<=IDLE;initialized<=0;auto_started<=0;start_pending<=0;stop_pending<=0;
            tracking_was_applied<=0;
            work_kp<=MODEL_KP_Q16;work_ki_dt<=MODEL_KI_DT_Q16;last_kp<=MODEL_KP_Q16;work_gain_changed<=0;
            work_speed_limit<=MAX_SPEED_Q16;
            filter_initialized<=0;applied_target<=0;phase_ms<=0;base_counts<=0;hold_counts<=0;
            mult_x<=0;mult_y<=0;r<=0;r2<=0;r3<=0;r4<=0;r5<=0;
            f_norm<=0;v_norm<=0;a_norm<=0;ref_inc_q16<=0;ref_speed_q16<=0;ref_accel_q16<=0;
            work_pos<=0;work_base<=0;work_speed<=0;work_profile<=0;work_boundary<=0;work_tracking<=0;encoder_speed_valid<=0;
            encoder_last_position<=0;encoder_speed_q16<=0;work_velocity_q16<=0;
            error_q16<=0;filtered_speed_q16<=0;desired_q16<=0;speed_error_q16<=0;
            integral_q16<=0;work_integral_q16<=0;i_candidate_q16<=0;ff_q16<=0;p_q16<=0;
        end else begin
            command_valid<=0;
            if(TRAJECTORY_ENABLED && test_start) start_pending<=1;
            if(TRAJECTORY_ENABLED && test_stop) begin stop_pending<=1;start_pending<=0;auto_started<=1;end
            if(fault) begin
                command_raw<=0;active<=0;test_running<=0;state<=IDLE;settled_sample<=0;
                output_filter_q16<=0;output_filter_input_q16<=0;work_fast_output<=0;
            end
            else if(!enable) begin
                // Loss of a previously live CAN channel is latched; reset to recover.
                if(has_feedback) fault<=1;
                command_raw<=0;active<=0;test_running<=0;state<=IDLE;initialized<=0;
                output_filter_q16<=0;output_filter_input_q16<=0;work_fast_output<=0;
                tracking_was_applied<=0;
                last_kp<=MODEL_KP_Q16;work_gain_changed<=0;
                filter_initialized<=0;integral_q16<=0;encoder_speed_valid<=0;settled_sample<=0;
            end else if(stale || (has_feedback &&
                (latest_temperature>=80 || speed_violation))) begin
                fault<=1;command_raw<=0;active<=0;test_running<=0;state<=IDLE;integral_q16<=0;settled_sample<=0;
                output_filter_q16<=0;output_filter_input_q16<=0;work_fast_output<=0;
            end else case(state)
                IDLE: if(control_tick && has_feedback) begin
                    tracking_was_applied<=tracking_enable;
                    work_kp<=requested_kp;work_ki_dt<=requested_ki_dt;
                    work_speed_limit<=requested_speed_limit;
                    work_command_limit<=requested_mode==2?FAST_COMMAND_LIMIT_Q16:U_LIMIT;
                    work_fast_output<=requested_mode==2 && !live_limits;
                    work_gain_changed<=tracking_enable && tracking_was_applied && requested_kp!=last_kp;
                    pos=feedback_valid?fresh_position:position_counts;
                    speed=feedback_valid?$signed(speed_rpm):$signed(latest_speed);
                    base=base_counts;hold=hold_counts;phase=phase_ms;
                    profile=TRAJECTORY_ENABLED?test_running:1'b0;boundary=0;
                    if(!initialized) begin
                        initialized<=1;applied_target<=target_angle_register;
                        hold=TEST_MODE?pos:pos+target_delta(target_angle_register,feedback_valid?angle:last_angle);
                        hold_counts<=hold;base=hold;base_counts<=hold;integral_q16<=0;
                    end
                    if(tracking_enable) begin
                        // Streamed reference changes retain the speed PI and filters.
                        profile=0;test_running<=0;start_pending<=0;stop_pending<=0;
                        hold=effective_tracking_target;
                        hold_counts<=hold;
                        base=hold;base_counts<=hold;applied_target<=target_angle_register;
                    end else if(stop_pending) begin
                        stop_pending<=0;start_pending<=0;profile=0;
                        hold=pos;hold_counts<=pos;base=pos;base_counts<=pos;
                        integral_q16<=0;test_running<=0;
                    end else if(start_pending || (TEST_MODE && AUTO_START && !auto_started && seen_frames>=20)) begin
                        start_pending<=0;auto_started<=1;profile=1;test_running<=1;
                        base=pos;base_counts<=pos;phase=0;integral_q16<=0;completed_segments<=0;
                    end else if(TEST_MODE==0 && !profile &&
                        (target_angle_register!=applied_target || tracking_was_applied)) begin
                        // A streamed reference can differ from the cached angle
                        // register. Reapply manual position on the mode edge even
                        // when that register's numeric value has not changed.
                        hold=pos+target_delta(target_angle_register,feedback_valid?angle:last_angle);
                        hold_counts<=hold;base=hold;base_counts<=hold;
                        applied_target<=target_angle_register;integral_q16<=0;
                    end
                    if(profile) begin
                        if(phase>=2000) begin
                            base=base+STEP_COUNTS;base_counts<=base;phase=0;boundary=1;
                            completed_segments<=completed_segments+1'b1;
                        end
                        phase_ms<=phase+1;target_counts<=base+STEP_COUNTS;
                    end else begin phase=0;base=hold;target_counts<=hold;end
                    // Every profile uses the same live-reference position/PI law.
                    work_pos<=pos;work_base<=base;work_speed<=speed;
                    work_profile<=profile;work_boundary<=boundary;work_tracking<=tracking_enable;
                    work_limits<=live_limits;work_min<=position_min_counts;work_max<=position_max_counts;
                    work_velocity_q16<=tracking_velocity_q16;
                    if(TRAJECTORY_ENABLED)begin
                        mult_x<=phase;mult_y<=R_STEP;state<=Q_WAIT;
                    end else begin
                        ref_inc_q16<=0;ref_accel_q16<=0;
                        ref_speed_q16<=tracking_enable?(times15(tracking_velocity_q16)>>>11):0;
                        state<=ERROR;
                    end
                end
                Q_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=Q_STORE;
                Q_STORE:if(TRAJECTORY_ENABLED)begin new_r=product>>>16;r<=new_r;mult_x<=new_r;mult_y<=new_r;state<=R2_WAIT;end
                R2_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R2_STORE;
                R2_STORE:if(TRAJECTORY_ENABLED)begin power=product>>>24;r2<=power;mult_x<=power;mult_y<=r;state<=R3_WAIT;end
                R3_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R3_STORE;
                R3_STORE:if(TRAJECTORY_ENABLED)begin power=product>>>24;r3<=power;mult_x<=power;mult_y<=r;state<=R4_WAIT;end
                R4_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R4_STORE;
                R4_STORE:if(TRAJECTORY_ENABLED)begin power=product>>>24;r4<=power;mult_x<=power;mult_y<=r;state<=R5_WAIT;end
                R5_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R5_STORE;
                R5_STORE:if(TRAJECTORY_ENABLED)begin r5<=product>>>24;state<=POLY;end
                POLY:if(TRAJECTORY_ENABLED)begin
                    poly_f=times10(r3)-times15(r4)+times6(r5);
                    poly_v=(times15(r2)<<<1)-(times15(r3)<<<2)+(times15(r4)<<<1);
                    poly_a=(times15(r)<<<2)-((times15(r2)<<<3)+(times15(r2)<<<2))+(times15(r3)<<<3);
                    f_norm<=poly_f[31:0];v_norm<=poly_v[31:0];a_norm<=poly_a[31:0];state<=SCALE;
                end
                SCALE:if(TRAJECTORY_ENABLED)begin
                    wide=times15(v_norm);
                    ref_speed_q16<=work_tracking?(times15(work_velocity_q16)>>>11):!work_profile?0:(CLOCKWISE_COUNT_INCREASE?(wide>>>8):-(wide>>>8));
                    wide=times15(a_norm);
                    ref_accel_q16<=!work_profile?0:(CLOCKWISE_COUNT_INCREASE?(wide>>>9):-(wide>>>9));
                    ref_inc_q16<=!work_profile?0:(CLOCKWISE_COUNT_INCREASE?(f_norm<<<4):-(f_norm<<<4));
                    state<=ERROR;
                end
                ERROR:begin
                    ref_wide=$signed({work_base,16'b0})+$signed(ref_inc_q16);
                    position_wide=$signed({work_pos,16'b0});error_wide=ref_wide-position_wide;
                    error_q16<=clip({{16{error_wide[47]}},error_wide},work_tracking?32'sh7fffffff:32'sd67108864);
                    reference_counts<=ref_wide>>>16;state<=FILTER;
                end
                FILTER:begin
                    if(work_tracking && encoder_speed_valid) begin

                        // default is 20ms; top selects 10ms for the faster Y plant.
                        wide=times480000(work_pos-encoder_last_position);
                        mult_x<=wide-encoder_speed_q16;mult_y<=TRACKING_ENCODER_ALPHA_Q16;
                        state<=ENC_WAIT;
                    end else begin
                        encoder_speed_q16<=work_speed<<<16;
                        encoder_speed_valid<=work_tracking;
                        encoder_last_position<=work_pos;state<=BLEND;
                    end
                end
                ENC_WAIT:if(multiply_done)state<=ENC_STORE;
                ENC_STORE:begin
                    encoder_speed_q16<=encoder_speed_q16+(product>>>16);
                    encoder_last_position<=work_pos;state<=BLEND;
                end
                BLEND:begin
                    speed=work_speed<<<16;
                    if(work_tracking) begin
                        if(work_speed==0) speed=encoder_speed_q16;
                        else if(work_speed==1 || work_speed== -1) speed=(speed+encoder_speed_q16)>>>1;
                    end
                    filt=filter_initialized?filtered_speed_q16+
                        ((speed-filtered_speed_q16)>>>(work_tracking?TRACKING_SPEED_FILTER_SHIFT:2)):speed;
                    filtered_speed_q16<=filt;filter_initialized<=1;state<=DESIRED;
                end
                DESIRED:begin
                    wide=times15(error_q16);
                    if(work_tracking) begin
                        // Use the full integer multi-turn distance before saturation.
                        // No target travel or target-minus-position angle clamp.
                        wide=$signed(work_base);
                        wide=wide-$signed(work_pos);
                        wide=(wide<<<12)-(wide<<<8);
                        n=clip($signed(ref_speed_q16)+wide,work_speed_limit);
                    end else n=clip($signed(ref_speed_q16)+(wide>>>8),V_LIMIT);
                    if(work_limits) begin
                        // Bound the total speed request by the remaining
                        // angular distance using the existing 8/s correction.

                        distance_to_bound=$signed({work_max[31],work_max})-$signed({work_pos[31],work_pos});
                        boundary_speed={{31{distance_to_bound[32]}},distance_to_bound};
                        boundary_speed=(boundary_speed<<<12)-(boundary_speed<<<8);
                        if($signed(n)>boundary_speed) n=clip(boundary_speed,work_speed_limit);
                        distance_to_bound=$signed({work_min[31],work_min})-$signed({work_pos[31],work_pos});
                        boundary_speed={{31{distance_to_bound[32]}},distance_to_bound};
                        boundary_speed=(boundary_speed<<<12)-(boundary_speed<<<8);
                        if($signed(n)<boundary_speed) n=clip(boundary_speed,work_speed_limit);
                    end
                    if(HOLD_LEAK_ENABLE && (!work_profile || work_boundary) && abs32(ref_speed_q16)<655 && abs32(error_q16)<=HOLD_BAND && abs32(filtered_speed_q16)<=65536) begin
                        n=0;mult_x<=integral_q16;mult_y<=LEAK;state<=LEAK_WAIT;
                    end else begin
                        work_integral_q16<=integral_q16;
                        if(TRAJECTORY_ENABLED)begin
                            mult_x<=ref_accel_q16;mult_y<=TAU_Q24;state<=TAU_WAIT;
                        end else begin mult_x<=n;mult_y<=INV_K;state<=FF_WAIT;end
                    end
                    desired_q16<=n;speed_setpoint_q16<=n;
                    speed_error_q16<=n-filtered_speed_q16;
                end
                LEAK_WAIT:if(multiply_done)state<=LEAK_STORE;
                LEAK_STORE:begin
                    work_integral_q16<=product>>>16;
                    if(TRAJECTORY_ENABLED)begin mult_x<=ref_accel_q16;mult_y<=TAU_Q24;state<=TAU_WAIT;end
                    else begin mult_x<=desired_q16;mult_y<=INV_K;state<=FF_WAIT;end
                end
                TAU_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=TAU_STORE;
                TAU_STORE:if(TRAJECTORY_ENABLED)begin mult_x<=desired_q16+(product>>>24);mult_y<=INV_K;state<=FF_WAIT;end
                FF_WAIT:if(multiply_done)state<=FF_STORE;
                FF_STORE:begin ff_q16<=product>>>16;mult_x<=speed_error_q16;mult_y<=work_kp;state<=P_WAIT;end
                P_WAIT:if(multiply_done)state<=P_STORE;
                P_STORE:begin
                    p_q16<=product>>>16;
                    mult_x<=speed_error_q16;
                    if(work_gain_changed)begin mult_y<=last_kp-work_kp;state<=GAIN_WAIT;end
                    else begin mult_y<=work_ki_dt;state<=I_WAIT;end
                end
                GAIN_WAIT:if(multiply_done)state<=GAIN_STORE;
                GAIN_STORE:begin
                    // Preserve P+I across a gain switch at the current error.
                    // Integral and voltage limits retain their existing bounds.
                    work_integral_q16<=clip($signed(work_integral_q16)+(product>>>16),I_LIMIT);
                    mult_x<=speed_error_q16;mult_y<=work_ki_dt;state<=I_WAIT;
                end
                I_WAIT:if(multiply_done)state<=I_STORE;
                I_STORE:begin i_candidate_q16<=clip($signed(work_integral_q16)+(product>>>16),I_LIMIT);state<=OUT;end
                OUT:begin
                    last_kp<=work_kp;
                    settled_sample<=work_tracking && !work_profile &&
                        abs32(ref_speed_q16)<655 && abs32(error_q16)<=ARRIVAL_BAND_Q16 &&
                        abs32(filtered_speed_q16)<=65536;
                    unsaturated=$signed(ff_q16)+$signed(p_q16)+$signed(i_candidate_q16);
                    u=clip(unsaturated,requested_mode==2?work_command_limit:U_LIMIT);
                    block_drive=live_limits &&
                        ((position_counts>=position_max_counts && u>0) ||
                         (position_counts<=position_min_counts && u<0));
                    if(block_drive) begin u=0;integral_q16<=0;end
                    else if(work_boundary) integral_q16<=0;
                    else if(unsaturated==u || (unsaturated>u && speed_error_q16<0) || (unsaturated<u && speed_error_q16>0)) integral_q16<=i_candidate_q16;
                    else integral_q16<=work_integral_q16;
                    if(FAST_OUTPUT_FILTER_SHIFT>0 && work_fast_output && requested_mode==2 && !live_limits)begin
                        // Separate register stage avoids extending the PI sum/
                        // saturation path. Only fast output gains one clock.
                        output_filter_input_q16<=u;state<=FAST_OUTPUT;
                    end else begin
                        // Bypass modes seed the history with their actual output,
                        // so entering fast mode never resumes an old filter tail.
                        output_filter_q16<=u;
                        command_raw<=rounded_command(u);command_valid<=1;active<=1;state<=IDLE;
                    end
                end
                FAST_OUTPUT:begin
                    if(requested_mode==2 && !live_limits)begin
                        wide=$signed(output_filter_input_q16);
                        wide=(wide-$signed(output_filter_q16))>>>FAST_OUTPUT_FILTER_SHIFT;
                        filt=$signed(output_filter_q16)+wide;
                    end else filt=output_filter_input_q16;
                    filt=clip($signed(filt),requested_mode==2?work_command_limit:U_LIMIT);
                    // Recheck live bounds if region limiting was enabled after
                    // OUT. Boundary and fault/disable actions bypass the tail.
                    block_drive=live_limits &&
                        ((position_counts>=position_max_counts && filt>0) ||
                         (position_counts<=position_min_counts && filt<0));
                    if(block_drive)begin filt=0;integral_q16<=0;end
                    output_filter_q16<=filt;
                    command_raw<=rounded_command(filt);command_valid<=1;active<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(TICKS<64 || FEEDBACK_TIMEOUT_MS<1) $fatal(1,"ID2 controller clock/timeout invalid");
    initial if(FAST_OUTPUT_FILTER_SHIFT<0 || FAST_OUTPUT_FILTER_SHIFT>8) $fatal(1,"Fast output filter shift must be 0..8");
`endif
endmodule


// Two independent motor contexts share one controller FSM, multiplier,
// add/subtract, saturation and filter datapath. Feedback unwrapping, timeout,
// live angle limits and output gating remain independent and run every clock.
module GM6020_dual_model_ctrl #(
    parameter integer CLK_HZ=50000000,
    parameter integer COMMAND_REVERSE_A=0,
    parameter integer CLOCKWISE_COUNT_INCREASE_A=1,
    parameter integer FEEDBACK_TIMEOUT_MS_A=10,
    parameter integer TEST_MODE_A=0,
    parameter integer AUTO_START_A=0,
    parameter integer ENABLE_TEST_TRAJECTORY_A=1,
    parameter signed [31:0] MODEL_INV_K_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_INV_K_Q16_A_1,
    parameter signed [31:0] MODEL_KP_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_KP_Q16_A_1,
    parameter signed [31:0] MODEL_KI_DT_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_KI_DT_Q16_A_1,
    parameter signed [31:0] MODEL_TAU_Q24_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_TAU_Q24_A_1,
    parameter signed [31:0] NORMAL_KP_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_NORMAL_KP_Q16_A_1,
    parameter signed [31:0] NORMAL_KI_DT_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_NORMAL_KI_DT_Q16_A_1,
    parameter signed [31:0] FAST_KP_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_KP_Q16_A_1,
    parameter signed [31:0] FAST_KI_DT_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_KI_DT_Q16_A_1,
    parameter signed [31:0] MAX_SPEED_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MAX_SPEED_Q16_A_1,
    parameter signed [31:0] TRACKING_STABLE_KP_Q16_A=MODEL_KP_Q16_A,
    parameter signed [31:0] TRACKING_STABLE_KI_DT_Q16_A=MODEL_KI_DT_Q16_A,
    parameter signed [31:0] FAST_MAX_SPEED_Q16_A=MAX_SPEED_Q16_A,
    parameter signed [31:0] FAST_COMMAND_LIMIT_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_COMMAND_LIMIT_Q16_A_1,
    parameter integer FAST_OVERSPEED_RPM_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_OVERSPEED_RPM_A_1,
    parameter signed [31:0] TRACKING_ENCODER_ALPHA_Q16_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_TRACKING_ENCODER_ALPHA_Q16_A_1,
    parameter integer TRACKING_SPEED_FILTER_SHIFT_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_TRACKING_SPEED_FILTER_SHIFT_A_1,
    parameter integer HOLD_LEAK_ENABLE_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_HOLD_LEAK_ENABLE_A_1,
    parameter integer ENABLE_POSITION_LIMITS_A=0,
    parameter integer ARRIVAL_TOLERANCE_COUNTS_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_ARRIVAL_TOLERANCE_COUNTS_A_1,
    parameter integer FAST_OUTPUT_FILTER_SHIFT_A=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_OUTPUT_FILTER_SHIFT_A_1,
    parameter integer COMMAND_REVERSE_B=0,
    parameter integer CLOCKWISE_COUNT_INCREASE_B=1,
    parameter integer FEEDBACK_TIMEOUT_MS_B=10,
    parameter integer TEST_MODE_B=0,
    parameter integer AUTO_START_B=0,
    parameter integer ENABLE_TEST_TRAJECTORY_B=1,
    parameter signed [31:0] MODEL_INV_K_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_INV_K_Q16_B_1,
    parameter signed [31:0] MODEL_KP_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_KP_Q16_B_1,
    parameter signed [31:0] MODEL_KI_DT_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_KI_DT_Q16_B_1,
    parameter signed [31:0] MODEL_TAU_Q24_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MODEL_TAU_Q24_B_1,
    parameter signed [31:0] NORMAL_KP_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_NORMAL_KP_Q16_B_1,
    parameter signed [31:0] NORMAL_KI_DT_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_NORMAL_KI_DT_Q16_B_1,
    parameter signed [31:0] FAST_KP_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_KP_Q16_B_1,
    parameter signed [31:0] FAST_KI_DT_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_KI_DT_Q16_B_1,
    parameter signed [31:0] MAX_SPEED_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_MAX_SPEED_Q16_B_1,
    parameter signed [31:0] TRACKING_STABLE_KP_Q16_B=MODEL_KP_Q16_B,
    parameter signed [31:0] TRACKING_STABLE_KI_DT_Q16_B=MODEL_KI_DT_Q16_B,
    parameter signed [31:0] FAST_MAX_SPEED_Q16_B=MAX_SPEED_Q16_B,
    parameter signed [31:0] FAST_COMMAND_LIMIT_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_COMMAND_LIMIT_Q16_B_1,
    parameter integer FAST_OVERSPEED_RPM_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_OVERSPEED_RPM_B_1,
    parameter signed [31:0] TRACKING_ENCODER_ALPHA_Q16_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_TRACKING_ENCODER_ALPHA_Q16_B_1,
    parameter integer TRACKING_SPEED_FILTER_SHIFT_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_TRACKING_SPEED_FILTER_SHIFT_B_1,
    parameter integer HOLD_LEAK_ENABLE_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_HOLD_LEAK_ENABLE_B_1,
    parameter integer ENABLE_POSITION_LIMITS_B=0,
    parameter integer ARRIVAL_TOLERANCE_COUNTS_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_ARRIVAL_TOLERANCE_COUNTS_B_1,
    parameter integer FAST_OUTPUT_FILTER_SHIFT_B=`FPGA_B_GM6020_DUAL_MODEL_CTRL_FAST_OUTPUT_FILTER_SHIFT_B_1
)(
    input wire clk,rst_n,
    input wire [1:0] enable_bus,
    input wire [1:0] feedback_valid_bus,
    input wire [25:0] angle_bus,
    input wire [31:0] speed_rpm_bus,
    input wire [15:0] temperature_bus,
    input wire [25:0] target_angle_register_bus,
    input wire [1:0] test_start_bus,
    input wire [1:0] test_stop_bus,
    input wire [1:0] tracking_enable_bus,
    input wire [3:0] tracking_mode_bus,
    input wire [63:0] tracking_target_counts_bus,
    input wire [63:0] tracking_velocity_q16_bus,
    input wire [1:0] position_limit_enable_bus,
    input wire [63:0] position_min_counts_bus,
    input wire [63:0] position_max_counts_bus,
    output wire [31:0] command_bus,
    output wire [1:0] command_valid_bus,
    output wire [1:0] active_bus,
    output wire [1:0] fault_bus,
    output wire [1:0] test_running_bus,
    output wire [63:0] position_counts_bus,
    output wire [63:0] target_counts_bus,
    output wire [63:0] reference_counts_bus,
    output wire [63:0] speed_setpoint_q16_bus,
    output wire [63:0] completed_segments_bus,
    output wire [1:0] feedback_ready_bus,
    output wire [1:0] at_target_bus
);
    reg lane;
    integer k;
    reg [1:0] pending;
    wire [0:0] enable=enable_bus[1*lane+:1];
    reg [0:0] sample_enable [0:1];
    wire [0:0] feedback_valid=feedback_valid_bus[1*lane+:1];
    wire [12:0] angle=angle_bus[13*lane+:13];
    wire signed [15:0] speed_rpm=speed_rpm_bus[16*lane+:16];
    wire [7:0] temperature=temperature_bus[8*lane+:8];
    wire [12:0] target_angle_register=target_angle_register_bus[13*lane+:13];
    reg [12:0] sample_target_angle_register [0:1];
    wire [0:0] test_start=test_start_bus[1*lane+:1];
    wire [0:0] test_stop=test_stop_bus[1*lane+:1];
    wire [0:0] tracking_enable=tracking_enable_bus[1*lane+:1];
    reg [0:0] sample_tracking_enable [0:1];
    wire [1:0] tracking_mode=tracking_mode_bus[2*lane+:2];
    reg [1:0] sample_tracking_mode [0:1];
    wire signed [31:0] tracking_target_counts=tracking_target_counts_bus[32*lane+:32];
    reg signed [31:0] sample_tracking_target_counts [0:1];
    wire signed [31:0] tracking_velocity_q16=tracking_velocity_q16_bus[32*lane+:32];
    reg signed [31:0] sample_tracking_velocity_q16 [0:1];
    wire [0:0] position_limit_enable=position_limit_enable_bus[1*lane+:1];
    reg [0:0] sample_position_limit_enable [0:1];
    wire signed [31:0] position_min_counts=position_min_counts_bus[32*lane+:32];
    reg signed [31:0] sample_position_min_counts [0:1];
    wire signed [31:0] position_max_counts=position_max_counts_bus[32*lane+:32];
    reg signed [31:0] sample_position_max_counts [0:1];
    wire [31:0] COMMAND_REVERSE=lane?COMMAND_REVERSE_B:COMMAND_REVERSE_A;
    wire [31:0] CLOCKWISE_COUNT_INCREASE=lane?CLOCKWISE_COUNT_INCREASE_B:CLOCKWISE_COUNT_INCREASE_A;
    wire [31:0] FEEDBACK_TIMEOUT_MS=lane?FEEDBACK_TIMEOUT_MS_B:FEEDBACK_TIMEOUT_MS_A;
    wire [31:0] TEST_MODE=lane?TEST_MODE_B:TEST_MODE_A;
    wire [31:0] AUTO_START=lane?AUTO_START_B:AUTO_START_A;
    wire [31:0] ENABLE_TEST_TRAJECTORY=lane?ENABLE_TEST_TRAJECTORY_B:ENABLE_TEST_TRAJECTORY_A;
    wire signed [31:0] MODEL_INV_K_Q16=lane?MODEL_INV_K_Q16_B:MODEL_INV_K_Q16_A;
    wire signed [31:0] MODEL_KP_Q16=lane?MODEL_KP_Q16_B:MODEL_KP_Q16_A;
    wire signed [31:0] MODEL_KI_DT_Q16=lane?MODEL_KI_DT_Q16_B:MODEL_KI_DT_Q16_A;
    wire signed [31:0] MODEL_TAU_Q24=lane?MODEL_TAU_Q24_B:MODEL_TAU_Q24_A;
    wire signed [31:0] NORMAL_KP_Q16=lane?NORMAL_KP_Q16_B:NORMAL_KP_Q16_A;
    wire signed [31:0] NORMAL_KI_DT_Q16=lane?NORMAL_KI_DT_Q16_B:NORMAL_KI_DT_Q16_A;
    wire signed [31:0] FAST_KP_Q16=lane?FAST_KP_Q16_B:FAST_KP_Q16_A;
    wire signed [31:0] FAST_KI_DT_Q16=lane?FAST_KI_DT_Q16_B:FAST_KI_DT_Q16_A;
    wire signed [31:0] MAX_SPEED_Q16=lane?MAX_SPEED_Q16_B:MAX_SPEED_Q16_A;
    wire signed [31:0] TRACKING_STABLE_KP_Q16=lane?TRACKING_STABLE_KP_Q16_B:TRACKING_STABLE_KP_Q16_A;
    wire signed [31:0] TRACKING_STABLE_KI_DT_Q16=lane?TRACKING_STABLE_KI_DT_Q16_B:TRACKING_STABLE_KI_DT_Q16_A;
    wire signed [31:0] FAST_MAX_SPEED_Q16=lane?FAST_MAX_SPEED_Q16_B:FAST_MAX_SPEED_Q16_A;
    wire signed [31:0] FAST_OVERSPEED_RPM=lane?FAST_OVERSPEED_RPM_B:FAST_OVERSPEED_RPM_A;
    wire signed [31:0] FAST_COMMAND_LIMIT_Q16=lane?FAST_COMMAND_LIMIT_Q16_B:FAST_COMMAND_LIMIT_Q16_A;
    wire signed [31:0] TRACKING_ENCODER_ALPHA_Q16=lane?TRACKING_ENCODER_ALPHA_Q16_B:TRACKING_ENCODER_ALPHA_Q16_A;
    wire [31:0] TRACKING_SPEED_FILTER_SHIFT=lane?TRACKING_SPEED_FILTER_SHIFT_B:TRACKING_SPEED_FILTER_SHIFT_A;
    wire [31:0] HOLD_LEAK_ENABLE=lane?HOLD_LEAK_ENABLE_B:HOLD_LEAK_ENABLE_A;
    wire [31:0] ENABLE_POSITION_LIMITS=lane?ENABLE_POSITION_LIMITS_B:ENABLE_POSITION_LIMITS_A;
    wire [31:0] ARRIVAL_TOLERANCE_COUNTS=lane?ARRIVAL_TOLERANCE_COUNTS_B:ARRIVAL_TOLERANCE_COUNTS_A;
    wire [31:0] FAST_OUTPUT_FILTER_SHIFT=lane?FAST_OUTPUT_FILTER_SHIFT_B:FAST_OUTPUT_FILTER_SHIFT_A;
    reg signed [31:0] sample_position [0:1],sample_speed [0:1];
    reg [12:0] sample_actual_angle [0:1];
    reg [5:0] sample_seen_frames [0:1];
    reg sample_ready [0:1],sample_start_pending [0:1],sample_stop_pending [0:1],sample_auto_started [0:1];
    wire [1:0] stale,feedback_ready;
    wire signed [31:0] fresh_position [0:1];
    reg [0:0] command_valid [0:1];
    reg [0:0] active [0:1];
    reg [0:0] fault [0:1];
    reg [0:0] test_running [0:1];
    reg signed [31:0] target_counts [0:1];
    reg signed [31:0] reference_counts [0:1];
    reg signed [31:0] speed_setpoint_q16 [0:1];
    reg [31:0] completed_segments [0:1];
    reg signed [31:0] position_counts [0:1];
    wire TRAJECTORY_ENABLED=TEST_MODE || ENABLE_TEST_TRAJECTORY;
    localparam integer TICKS=CLK_HZ/1000;
    localparam integer TW=(TICKS>1)?$clog2(TICKS):1;
    wire signed [31:0] INV_K=MODEL_INV_K_Q16, KP=MODEL_KP_Q16, KI_DT=MODEL_KI_DT_Q16;
    wire signed [31:0] TAU_Q24=MODEL_TAU_Q24, LEAK=`FPGA_B_GM6020_DUAL_MODEL_CTRL_LEAK_1, R_STEP=`FPGA_B_GM6020_DUAL_MODEL_CTRL_R_STEP_1;
    wire signed [31:0] V_LIMIT=MAX_SPEED_Q16, I_LIMIT=`FPGA_B_GM6020_DUAL_MODEL_CTRL_I_LIMIT_1, U_LIMIT=`FPGA_B_GM6020_DUAL_MODEL_CTRL_U_LIMIT_1;
    localparam signed [31:0] HOLD_BAND=`FPGA_B_GM6020_DUAL_MODEL_CTRL_HOLD_BAND_1;
    wire signed [32:0] ARRIVAL_LIMIT=ARRIVAL_TOLERANCE_COUNTS;
    wire [31:0] ARRIVAL_BAND_Q16=ARRIVAL_TOLERANCE_COUNTS*65536;
    wire signed [31:0] STEP_COUNTS=CLOCKWISE_COUNT_INCREASE?4096:-4096;
    localparam [5:0] IDLE=0,Q_WAIT=1,Q_STORE=2,R2_WAIT=3,R2_STORE=4,
        R3_WAIT=5,R3_STORE=6,R4_WAIT=7,R4_STORE=8,R5_WAIT=9,R5_STORE=10,
        POLY=11,SCALE=12,ERROR=13,FILTER=14,DESIRED=15,
        LEAK_WAIT=16,LEAK_STORE=17,TAU_WAIT=18,TAU_STORE=19,
        FF_WAIT=20,FF_STORE=21,P_WAIT=22,P_STORE=23,I_WAIT=24,I_STORE=25,OUT=26,ENC_WAIT=27,ENC_STORE=28,BLEND=29,GAIN_WAIT=30,GAIN_STORE=31,FAST_OUTPUT=32,JOB_START=33;
    reg [TW-1:0] tick_count [0:1];
    reg [31:0] feedback_age [0:1];
    reg [12:0] last_angle [0:1];
    reg signed [15:0] latest_speed [0:1];
    reg [7:0] latest_temperature [0:1];
    reg has_feedback [0:1];
    reg [5:0] seen_frames [0:1];
    reg [5:0] state;
    reg initialized [0:1];
    reg auto_started [0:1];
    reg start_pending [0:1];
    reg stop_pending [0:1];
    reg filter_initialized [0:1];
    reg tracking_was_applied [0:1];
    reg signed [31:0] work_kp;
    reg signed [31:0] work_ki_dt;
    reg signed [31:0] last_kp [0:1];
    reg signed [31:0] work_speed_limit;
    reg work_gain_changed;
    // Unconnected legacy simulation ports and invalid values use stable tuning.
    function [1:0] select_mode;
        input enabled;
        input [1:0] mode;
        begin
            select_mode=0;
            if(enabled)case(mode)
                2'd1:select_mode=1;
                2'd2:select_mode=2;
                default:select_mode=0;
            endcase
        end
    endfunction
    wire [1:0] requested_mode=select_mode(tracking_enable,tracking_mode);
    wire signed [31:0] requested_kp=!tracking_enable?MODEL_KP_Q16:
        (requested_mode==1?NORMAL_KP_Q16:(requested_mode==2?FAST_KP_Q16:TRACKING_STABLE_KP_Q16));
    wire signed [31:0] requested_ki_dt=!tracking_enable?MODEL_KI_DT_Q16:
        (requested_mode==1?NORMAL_KI_DT_Q16:(requested_mode==2?FAST_KI_DT_Q16:TRACKING_STABLE_KI_DT_Q16));
    wire signed [31:0] requested_speed_limit=requested_mode==2?FAST_MAX_SPEED_Q16:MAX_SPEED_Q16;
    wire [1:0] sample_mode=select_mode(sample_tracking_enable[lane],sample_tracking_mode[lane]);
    wire signed [31:0] sample_kp=!sample_tracking_enable[lane]?MODEL_KP_Q16:
        (sample_mode==1?NORMAL_KP_Q16:(sample_mode==2?FAST_KP_Q16:TRACKING_STABLE_KP_Q16));
    wire signed [31:0] sample_ki=!sample_tracking_enable[lane]?MODEL_KI_DT_Q16:
        (sample_mode==1?NORMAL_KI_DT_Q16:(sample_mode==2?FAST_KI_DT_Q16:TRACKING_STABLE_KI_DT_Q16));
    wire signed [31:0] sample_limit=sample_mode==2?FAST_MAX_SPEED_Q16:MAX_SPEED_Q16;
    wire sample_limits=ENABLE_POSITION_LIMITS && sample_position_limit_enable[lane] && sample_tracking_enable[lane] &&
        sample_enable[lane] && sample_ready[lane] && sample_position_min_counts[lane]<=sample_position_max_counts[lane];
    wire signed [31:0] sample_effective_target=!sample_limits?sample_tracking_target_counts[lane]:
        (sample_tracking_target_counts[lane]<sample_position_min_counts[lane]?sample_position_min_counts[lane]:
         (sample_tracking_target_counts[lane]>sample_position_max_counts[lane]?sample_position_max_counts[lane]:sample_tracking_target_counts[lane]));
    reg [12:0] applied_target [0:1];
    reg [10:0] phase_ms [0:1];
    reg signed [31:0] base_counts [0:1];
    reg signed [31:0] hold_counts [0:1];
    reg signed [31:0] mult_x;
    reg signed [31:0] mult_y;
    reg signed [63:0] product;
    reg signed [31:0] r;
    reg signed [31:0] r2;
    reg signed [31:0] r3;
    reg signed [31:0] r4;
    reg signed [31:0] r5;
    reg signed [31:0] f_norm;
    reg signed [31:0] v_norm;
    reg signed [31:0] a_norm;
    reg signed [31:0] ref_inc_q16;
    reg signed [31:0] ref_speed_q16;
    reg signed [31:0] ref_accel_q16;
    reg signed [31:0] work_pos;
    reg signed [31:0] work_base;
    reg signed [31:0] work_speed;
    reg work_profile;
    reg work_boundary;
    reg work_tracking;
    reg encoder_speed_valid [0:1];
    reg signed [31:0] encoder_last_position [0:1];
    reg signed [31:0] encoder_speed_q16 [0:1];
    reg signed [31:0] work_velocity_q16;
    reg signed [31:0] error_q16;
    reg signed [31:0] filtered_speed_q16 [0:1];
    reg signed [31:0] desired_q16;
    reg signed [31:0] speed_error_q16;
    reg signed [31:0] integral_q16 [0:1];
    reg signed [31:0] work_integral_q16;
    reg signed [31:0] i_candidate_q16;
    reg signed [31:0] ff_q16;
    reg signed [31:0] p_q16;
    reg settled_sample [0:1];
    reg signed [15:0] command_raw [0:1];
    reg work_fast_output;
    reg signed [31:0] work_command_limit;
    // Keep fractional command precision, before motor polarity reversal.
    reg signed [31:0] output_filter_q16 [0:1];
    reg signed [31:0] output_filter_input_q16;
    reg work_limits;
    reg signed [31:0] work_min;
    reg signed [31:0] work_max;
    wire live_limits=ENABLE_POSITION_LIMITS && position_limit_enable &&
        tracking_enable && enable && feedback_ready && position_min_counts<=position_max_counts;
    wire signed [31:0] effective_tracking_target=!live_limits?tracking_target_counts:
        (tracking_target_counts<position_min_counts?position_min_counts:
         (tracking_target_counts>position_max_counts?position_max_counts:tracking_target_counts));
    function signed [31:0] wrap_delta;
        input [12:0] wanted,actual;
        reg signed [31:0] d;
        begin
            d=$signed({1'b0,wanted})-$signed({1'b0,actual});
            if(d>4096) d=d-8192;
            else if(d< -4096) d=d+8192;
            wrap_delta=d;
        end
    endfunction
    function signed [31:0] target_delta;
        input [12:0] wanted,actual;
        reg signed [31:0] d;
        begin
            d=wrap_delta(wanted,actual);
            if(d==4096 || d== -4096) d=STEP_COUNTS;
            target_delta=d;
        end
    endfunction
    function signed [31:0] clip;
        input signed [63:0] v;
        input signed [31:0] limit;
        begin
            if(v>limit) clip=limit;
            else if(v< -$signed(limit)) clip=-limit;
            else clip=v[31:0];
        end
    endfunction
    function [31:0] abs32;
        input signed [31:0] v;
        begin abs32=v<0?-v:v;end
    endfunction
    // Exact fixed-coefficient products. Widen before shifting; leave the
    // shared registered variable multiplier and every control state unchanged.
    function signed [63:0] times6;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin v=value;times6=(v<<<2)+(v<<<1);end
    endfunction
    function signed [63:0] times10;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin v=value;times10=(v<<<3)+(v<<<1);end
    endfunction
    function signed [63:0] times15;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin v=value;times15=(v<<<4)-v;end
    endfunction
    function signed [63:0] times480000;
        input signed [31:0] value;
        reg signed [63:0] v;
        begin
            v=value;
            times480000=(((v<<<10)-(v<<<8))+((v<<<12)+(v<<<14)))+((v<<<19)-(v<<<16));
        end
    endfunction
    function signed [15:0] rounded_command;
        input signed [31:0] v;
        reg signed [31:0] n;
        begin
            n=v>=0?(v+32768)>>>16:-(((-v)+32768)>>>16);
            rounded_command=COMMAND_REVERSE?-n[15:0]:n[15:0];
        end
    endfunction

    wire [1:0] speed_violation;
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:axis
        localparam integer TIMEOUT=(CLK_HZ/1000)*(g?FEEDBACK_TIMEOUT_MS_B:FEEDBACK_TIMEOUT_MS_A);
        localparam integer LIMITS=g?ENABLE_POSITION_LIMITS_B:ENABLE_POSITION_LIMITS_A;
        localparam integer REVERSE=g?COMMAND_REVERSE_B:COMMAND_REVERSE_A;
        localparam signed [32:0] ARRIVAL=g?ARRIVAL_TOLERANCE_COUNTS_B:ARRIVAL_TOLERANCE_COUNTS_A;
        reg fast_speed_guard;
        wire fast_selected=tracking_enable_bus[g] && tracking_mode_bus[2*g+:2]==2;
        wire signed [31:0] high_limit=g?FAST_OVERSPEED_RPM_B:FAST_OVERSPEED_RPM_A;
        wire signed [31:0] speed_fault_limit=(fast_speed_guard || fast_selected)?high_limit:60;
        assign speed_violation[g]=latest_speed[g]>speed_fault_limit || latest_speed[g]< -speed_fault_limit;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)fast_speed_guard<=0;
            else if(!enable_bus[g] || fault[g])fast_speed_guard<=0;
            else if(fast_selected)fast_speed_guard<=1;
            else if(latest_speed[g]<=60 && latest_speed[g]>=-60)fast_speed_guard<=0;
        end
        wire enabled=enable_bus[g];
        wire feedback=feedback_valid_bus[g];
        wire [12:0] actual_angle=angle_bus[13*g+:13];
        wire signed [15:0] rpm=speed_rpm_bus[16*g+:16];
        wire signed [31:0] minimum=position_min_counts_bus[32*g+:32];
        wire signed [31:0] maximum=position_max_counts_bus[32*g+:32];
        wire signed [31:0] requested=tracking_target_counts_bus[32*g+:32];
        wire limits=LIMITS && position_limit_enable_bus[g] && tracking_enable_bus[g] &&
            enabled && feedback_ready[g] && minimum<=maximum;
        wire signed [31:0] effective=!limits?requested:(requested<minimum?minimum:(requested>maximum?maximum:requested));
        wire outward=REVERSE?
            ((position_counts[g]>=maximum && command_raw[g]<0)||(position_counts[g]<=minimum && command_raw[g]>0)):
            ((position_counts[g]>=maximum && command_raw[g]>0)||(position_counts[g]<=minimum && command_raw[g]<0));
        wire signed [32:0] arrival_error=$signed({reference_counts[g][31],reference_counts[g]})-
                                                $signed({position_counts[g][31],position_counts[g]});
        wire signed [15:0] mode_command=fast_selected?command_raw[g]:
            (command_raw[g]>6000?16'sd6000:(command_raw[g]< -6000?-16'sd6000:command_raw[g]));
        assign command_bus[16*g+:16]=(limits && outward)?16'sd0:mode_command;
        assign feedback_ready[g]=has_feedback[g] && feedback_age[g]<TIMEOUT && !fault[g];
        assign feedback_ready_bus[g]=feedback_ready[g];
        assign stale[g]=has_feedback[g] && !feedback && feedback_age[g]>=TIMEOUT-1;
        assign fresh_position[g]=has_feedback[g]?position_counts[g]+wrap_delta(actual_angle,last_angle[g]):32'sd0;
        assign at_target_bus[g]=enabled && feedback_ready[g] && active[g] && tracking_enable_bus[g] &&
            !test_running[g] && settled_sample[g] && target_counts[g]==reference_counts[g] &&
            reference_counts[g]==effective && arrival_error>=-ARRIVAL && arrival_error<=ARRIVAL &&
            latest_speed[g]>=-16'sd1 && latest_speed[g]<=16'sd1;
        assign command_valid_bus[1*g+:1]=command_valid[g];
        assign active_bus[1*g+:1]=active[g];
        assign fault_bus[1*g+:1]=fault[g];
        assign test_running_bus[1*g+:1]=test_running[g];
        assign position_counts_bus[32*g+:32]=position_counts[g];
        assign target_counts_bus[32*g+:32]=target_counts[g];
        assign reference_counts_bus[32*g+:32]=reference_counts[g];
        assign speed_setpoint_q16_bus[32*g+:32]=speed_setpoint_q16[g];
        assign completed_segments_bus[32*g+:32]=completed_segments[g];
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin
                tick_count[g]<=0;feedback_age[g]<=0;last_angle[g]<=0;latest_speed[g]<=0;
                latest_temperature[g]<=0;has_feedback[g]<=0;seen_frames[g]<=0;position_counts[g]<=0;
            end else if(!enabled)begin
                tick_count[g]<=0;feedback_age[g]<=0;has_feedback[g]<=0;seen_frames[g]<=0;position_counts[g]<=0;
            end else begin
                tick_count[g]<=tick_count[g]==TICKS-1?0:tick_count[g]+1'b1;
                if(feedback)begin
                    position_counts[g]<=fresh_position[g];last_angle[g]<=actual_angle;
                    latest_speed[g]<=rpm;latest_temperature[g]<=temperature_bus[8*g+:8];
                    has_feedback[g]<=1;feedback_age[g]<=0;
                    if(seen_frames[g]<63)seen_frames[g]<=seen_frames[g]+1'b1;
                end else if(has_feedback[g] && feedback_age[g]<TIMEOUT)feedback_age[g]<=feedback_age[g]+1'b1;
            end
        end
    end endgenerate

    reg [1:0] multiply_phase;
    reg signed [31:0] partial_low;
    reg signed [31:0] partial_high;
    wire multiplication_wait=state==Q_WAIT || state==R2_WAIT || state==R3_WAIT || state==R4_WAIT || state==R5_WAIT || state==LEAK_WAIT || state==TAU_WAIT || state==FF_WAIT || state==P_WAIT || state==I_WAIT || state==ENC_WAIT || state==GAIN_WAIT;
    wire signed [16:0] low_x={mult_x[15],mult_x[15:0]};
    wire signed [16:0] low_y={mult_y[15],mult_y[15:0]};
    wire signed [16:0] high_x=$signed({mult_x[31],mult_x[31:16]})+$signed({16'd0,mult_x[15]});
    wire signed [16:0] high_y=$signed({mult_y[31],mult_y[31:16]})+$signed({16'd0,mult_y[15]});
    wire multiply_fast=high_x==0 || high_y==0;
    wire signed [16:0] full_low=high_y==0?low_x:low_y;
    wire signed [16:0] full_high=high_y==0?high_x:high_y;
    wire signed [16:0] small_value=high_y==0?low_y:low_x;
    wire signed [16:0] multiply_a=multiply_fast?(multiply_phase==0?full_low:full_high):
        (multiply_phase==0?low_x:(multiply_phase==1?high_x:low_x-high_x));
    wire signed [16:0] multiply_b=multiply_fast?small_value:
        (multiply_phase==0?low_y:(multiply_phase==1?high_y:low_y-high_y));
    wire signed [33:0] multiply_result=multiply_a*multiply_b;
    wire signed [33:0] cross_sum={{2{partial_low[31]}},partial_low}+
        {{2{partial_high[31]}},partial_high}-multiply_result;
    wire signed [32:0] cross_value=multiply_fast?{multiply_result[31],multiply_result[31:0]}:cross_sum[32:0];
    wire signed [32:0] middle_sum=cross_value+$signed({{17{partial_low[31]}},partial_low[31:16]});
    wire [31:0] high_sum=(multiply_fast?32'd0:partial_high)+{{15{middle_sum[32]}},middle_sum[32:16]};
    wire multiply_done=multiply_phase==(multiply_fast?2'd1:2'd2);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin multiply_phase<=0;partial_low<=0;partial_high<=0;product<=0;end
        else if(multiplication_wait)begin
            multiply_phase<=multiply_done?2'd0:multiply_phase+1'b1;
            if(multiply_phase==0)partial_low<=multiply_result[31:0];
            else if(multiply_done)product<={high_sum,middle_sum[15:0],partial_low[15:0]};
            else partial_high<=multiply_result[31:0];
        end else multiply_phase<=0;
    end

    always @(posedge clk or negedge rst_n) begin: controller
        reg signed [31:0] pos,base,hold,speed,phase,new_r,power,n,filt,u;
        reg profile,boundary;
        reg signed [63:0] wide,poly_f,poly_v,poly_a,unsaturated;
        reg signed [47:0] ref_wide,position_wide,error_wide;
        reg signed [32:0] distance_to_bound;
        reg signed [63:0] boundary_speed;
        reg block_drive;
        if(!rst_n) begin
            lane<=0;pending<=0;
            for(k=0;k<2;k=k+1)begin
            command_raw[k]<=0;command_valid[k]<=0;active[k]<=0;fault[k]<=0;test_running[k]<=0;settled_sample[k]<=0;
            work_command_limit<=`FPGA_B_GM6020_DUAL_MODEL_CTRL_U_LIMIT_2;
            work_fast_output<=0;output_filter_q16[k]<=0;output_filter_input_q16<=0;
            work_limits<=0;work_min<=0;work_max<=0;
            target_counts[k]<=0;reference_counts[k]<=0;speed_setpoint_q16[k]<=0;completed_segments[k]<=0;
            state<=IDLE;initialized[k]<=0;auto_started[k]<=0;start_pending[k]<=0;stop_pending[k]<=0;
            tracking_was_applied[k]<=0;
            // Async reset values must be constants, never a mux selected by
            // lane. JOB_START loads this job's real axis/profile parameters.
            work_kp<=MODEL_KP_Q16_A;work_ki_dt<=MODEL_KI_DT_Q16_A;last_kp[k]<=k?MODEL_KP_Q16_B:MODEL_KP_Q16_A;work_gain_changed<=0;
            work_speed_limit<=MAX_SPEED_Q16_A;
            filter_initialized[k]<=0;applied_target[k]<=0;phase_ms[k]<=0;base_counts[k]<=0;hold_counts[k]<=0;
            mult_x<=0;mult_y<=0;r<=0;r2<=0;r3<=0;r4<=0;r5<=0;
            f_norm<=0;v_norm<=0;a_norm<=0;ref_inc_q16<=0;ref_speed_q16<=0;ref_accel_q16<=0;
            work_pos<=0;work_base<=0;work_speed<=0;work_profile<=0;work_boundary<=0;work_tracking<=0;encoder_speed_valid[k]<=0;
            encoder_last_position[k]<=0;encoder_speed_q16[k]<=0;work_velocity_q16<=0;
            error_q16<=0;filtered_speed_q16[k]<=0;desired_q16<=0;speed_error_q16<=0;
            integral_q16[k]<=0;work_integral_q16<=0;i_candidate_q16<=0;ff_q16<=0;p_q16<=0;
            sample_enable[k]<=0;

            sample_target_angle_register[k]<=0;

            sample_tracking_enable[k]<=0;
            sample_tracking_mode[k]<=0;
            sample_tracking_target_counts[k]<=0;
            sample_tracking_velocity_q16[k]<=0;
            sample_position_limit_enable[k]<=0;
            sample_position_min_counts[k]<=0;
            sample_position_max_counts[k]<=0;
            sample_ready[k]<=0;sample_start_pending[k]<=0;sample_stop_pending[k]<=0;sample_auto_started[k]<=0;
            sample_position[k]<=0;sample_speed[k]<=0;sample_actual_angle[k]<=0;sample_seen_frames[k]<=0;
            end
        end else begin
            for(k=0;k<2;k=k+1)begin
            command_valid[k]<=0;
            if((k?(TEST_MODE_B||ENABLE_TEST_TRAJECTORY_B):(TEST_MODE_A||ENABLE_TEST_TRAJECTORY_A)) && test_start_bus[k]) start_pending[k]<=1;
            if((k?(TEST_MODE_B||ENABLE_TEST_TRAJECTORY_B):(TEST_MODE_A||ENABLE_TEST_TRAJECTORY_A)) && test_stop_bus[k]) begin stop_pending[k]<=1;start_pending[k]<=0;auto_started[k]<=1;end
                if(tick_count[k]==TICKS-1 && has_feedback[k] && enable_bus[k] && !fault[k] && !stale[k])begin
                    pending[k]<=1;
                    sample_position[k]<=feedback_valid_bus[k]?fresh_position[k]:position_counts[k];
                    sample_speed[k]<=feedback_valid_bus[k]?$signed(speed_rpm_bus[16*k+:16]):$signed(latest_speed[k]);
                    sample_actual_angle[k]<=feedback_valid_bus[k]?angle_bus[13*k+:13]:last_angle[k];
                    sample_seen_frames[k]<=seen_frames[k];
                    sample_ready[k]<=feedback_ready[k];
                    sample_start_pending[k]<=start_pending[k];sample_stop_pending[k]<=stop_pending[k];
                    sample_auto_started[k]<=auto_started[k];
                    // Consume only events present on the sampling edge. New
                    // test pulses arriving while queued belong to the next job.
                    if(tracking_enable_bus[k] || stop_pending[k])begin start_pending[k]<=0;stop_pending[k]<=0;end
                    else if(start_pending[k] || ((k?TEST_MODE_B:TEST_MODE_A) && (k?AUTO_START_B:AUTO_START_A) && !auto_started[k] && seen_frames[k]>=20))start_pending[k]<=0;
                    sample_enable[k]<=enable_bus[1*k+:1];

                    sample_target_angle_register[k]<=target_angle_register_bus[13*k+:13];

                    sample_tracking_enable[k]<=tracking_enable_bus[1*k+:1];
                    sample_tracking_mode[k]<=tracking_mode_bus[2*k+:2];
                    sample_tracking_target_counts[k]<=tracking_target_counts_bus[32*k+:32];
                    sample_tracking_velocity_q16[k]<=tracking_velocity_q16_bus[32*k+:32];
                    sample_position_limit_enable[k]<=position_limit_enable_bus[1*k+:1];
                    sample_position_min_counts[k]<=position_min_counts_bus[32*k+:32];
                    sample_position_max_counts[k]<=position_max_counts_bus[32*k+:32];
                end
            if(fault[k]) begin
                command_raw[k]<=0;active[k]<=0;test_running[k]<=0;settled_sample[k]<=0;
                output_filter_q16[k]<=0;
            end
            else if(!enable_bus[k]) begin
                // Loss of a previously live CAN channel is latched; reset to recover.
                if(has_feedback[k]) fault[k]<=1;
                command_raw[k]<=0;active[k]<=0;test_running[k]<=0;initialized[k]<=0;
                output_filter_q16[k]<=0;
                tracking_was_applied[k]<=0;
                last_kp[k]<=k?MODEL_KP_Q16_B:MODEL_KP_Q16_A;
                filter_initialized[k]<=0;integral_q16[k]<=0;encoder_speed_valid[k]<=0;settled_sample[k]<=0;
            end else if(stale[k] || (has_feedback[k] &&
                (latest_temperature[k]>=80 || speed_violation[k]))) begin
                fault[k]<=1;command_raw[k]<=0;active[k]<=0;test_running[k]<=0;integral_q16[k]<=0;settled_sample[k]<=0;
                output_filter_q16[k]<=0;
            end
                if(fault[k] || !enable_bus[k] || stale[k])pending[k]<=0;
            end
            if(state!=IDLE && (fault[lane] || !enable || stale[lane] ||
                (has_feedback[lane] && (latest_temperature[lane]>=80 || speed_violation[lane]))))state<=IDLE;
            else case(state)
                IDLE:begin
                    if(pending[0])begin lane<=0;pending[0]<=0;state<=JOB_START;end
                    else if(pending[1])begin lane<=1;pending[1]<=0;state<=JOB_START;end
                end
                JOB_START:begin
                    tracking_was_applied[lane]<=sample_tracking_enable[lane];
                    work_kp<=sample_kp;work_ki_dt<=sample_ki;
                    work_speed_limit<=sample_limit;
                    work_command_limit<=sample_mode==2?FAST_COMMAND_LIMIT_Q16:U_LIMIT;
                    work_fast_output<=sample_mode==2 && !sample_limits;
                    work_gain_changed<=sample_tracking_enable[lane] && tracking_was_applied[lane] && sample_kp!=last_kp[lane];
                    pos=sample_position[lane];
                    speed=sample_speed[lane];
                    base=base_counts[lane];hold=hold_counts[lane];phase=phase_ms[lane];
                    profile=TRAJECTORY_ENABLED?test_running[lane]:1'b0;boundary=0;
                    if(!initialized[lane]) begin
                        initialized[lane]<=1;applied_target[lane]<=sample_target_angle_register[lane];
                        hold=TEST_MODE?pos:pos+target_delta(sample_target_angle_register[lane],sample_actual_angle[lane]);
                        hold_counts[lane]<=hold;base=hold;base_counts[lane]<=hold;integral_q16[lane]<=0;
                    end
                    if(sample_tracking_enable[lane]) begin
                        // Streamed reference changes retain the speed PI and filters.
                        profile=0;test_running[lane]<=0;
                        hold=sample_effective_target;
                        hold_counts[lane]<=hold;
                        base=hold;base_counts[lane]<=hold;applied_target[lane]<=sample_target_angle_register[lane];
                    end else if(sample_stop_pending[lane]) begin
                        profile=0;
                        hold=pos;hold_counts[lane]<=pos;base=pos;base_counts[lane]<=pos;
                        integral_q16[lane]<=0;test_running[lane]<=0;
                    end else if(sample_start_pending[lane] || (TEST_MODE && AUTO_START && !sample_auto_started[lane] && sample_seen_frames[lane]>=20)) begin
                        auto_started[lane]<=1;profile=1;test_running[lane]<=1;
                        base=pos;base_counts[lane]<=pos;phase=0;integral_q16[lane]<=0;completed_segments[lane]<=0;
                    end else if(TEST_MODE==0 && !profile &&
                        (sample_target_angle_register[lane]!=applied_target[lane] || tracking_was_applied[lane])) begin
                        // A streamed reference can differ from the cached angle
                        // register. Reapply manual position on the mode edge even
                        // when that register's numeric value has not changed.
                        hold=pos+target_delta(sample_target_angle_register[lane],sample_actual_angle[lane]);
                        hold_counts[lane]<=hold;base=hold;base_counts[lane]<=hold;
                        applied_target[lane]<=sample_target_angle_register[lane];integral_q16[lane]<=0;
                    end
                    if(profile) begin
                        if(phase>=2000) begin
                            base=base+STEP_COUNTS;base_counts[lane]<=base;phase=0;boundary=1;
                            completed_segments[lane]<=completed_segments[lane]+1'b1;
                        end
                        phase_ms[lane]<=phase+1;target_counts[lane]<=base+STEP_COUNTS;
                    end else begin phase=0;base=hold;target_counts[lane]<=hold;end
                    // Every profile uses the same live-reference position/PI law.
                    work_pos<=pos;work_base<=base;work_speed<=speed;
                    work_profile<=profile;work_boundary<=boundary;work_tracking<=sample_tracking_enable[lane];
                    work_limits<=sample_limits;work_min<=sample_position_min_counts[lane];work_max<=sample_position_max_counts[lane];
                    work_velocity_q16<=sample_tracking_velocity_q16[lane];
                    if(TRAJECTORY_ENABLED)begin
                        mult_x<=phase;mult_y<=R_STEP;state<=Q_WAIT;
                    end else begin
                        ref_inc_q16<=0;ref_accel_q16<=0;
                        ref_speed_q16<=sample_tracking_enable[lane]?(times15(sample_tracking_velocity_q16[lane])>>>11):0;
                        state<=ERROR;
                    end
                end
                Q_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=Q_STORE;
                Q_STORE:if(TRAJECTORY_ENABLED)begin new_r=product>>>16;r<=new_r;mult_x<=new_r;mult_y<=new_r;state<=R2_WAIT;end
                R2_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R2_STORE;
                R2_STORE:if(TRAJECTORY_ENABLED)begin power=product>>>24;r2<=power;mult_x<=power;mult_y<=r;state<=R3_WAIT;end
                R3_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R3_STORE;
                R3_STORE:if(TRAJECTORY_ENABLED)begin power=product>>>24;r3<=power;mult_x<=power;mult_y<=r;state<=R4_WAIT;end
                R4_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R4_STORE;
                R4_STORE:if(TRAJECTORY_ENABLED)begin power=product>>>24;r4<=power;mult_x<=power;mult_y<=r;state<=R5_WAIT;end
                R5_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=R5_STORE;
                R5_STORE:if(TRAJECTORY_ENABLED)begin r5<=product>>>24;state<=POLY;end
                POLY:if(TRAJECTORY_ENABLED)begin
                    poly_f=times10(r3)-times15(r4)+times6(r5);
                    poly_v=(times15(r2)<<<1)-(times15(r3)<<<2)+(times15(r4)<<<1);
                    poly_a=(times15(r)<<<2)-((times15(r2)<<<3)+(times15(r2)<<<2))+(times15(r3)<<<3);
                    f_norm<=poly_f[31:0];v_norm<=poly_v[31:0];a_norm<=poly_a[31:0];state<=SCALE;
                end
                SCALE:if(TRAJECTORY_ENABLED)begin
                    wide=times15(v_norm);
                    ref_speed_q16<=work_tracking?(times15(work_velocity_q16)>>>11):!work_profile?0:(CLOCKWISE_COUNT_INCREASE?(wide>>>8):-(wide>>>8));
                    wide=times15(a_norm);
                    ref_accel_q16<=!work_profile?0:(CLOCKWISE_COUNT_INCREASE?(wide>>>9):-(wide>>>9));
                    ref_inc_q16<=!work_profile?0:(CLOCKWISE_COUNT_INCREASE?(f_norm<<<4):-(f_norm<<<4));
                    state<=ERROR;
                end
                ERROR:begin
                    ref_wide=$signed({work_base,16'b0})+$signed(ref_inc_q16);
                    position_wide=$signed({work_pos,16'b0});error_wide=ref_wide-position_wide;
                    error_q16<=clip({{16{error_wide[47]}},error_wide},work_tracking?32'sh7fffffff:32'sd67108864);
                    reference_counts[lane]<=ref_wide>>>16;state<=FILTER;
                end
                FILTER:begin
                    if(work_tracking && encoder_speed_valid[lane]) begin

                        // default is 20ms; top selects 10ms for the faster Y plant.
                        wide=times480000(work_pos-encoder_last_position[lane]);
                        mult_x<=wide-encoder_speed_q16[lane];mult_y<=TRACKING_ENCODER_ALPHA_Q16;
                        state<=ENC_WAIT;
                    end else begin
                        encoder_speed_q16[lane]<=work_speed<<<16;
                        encoder_speed_valid[lane]<=work_tracking;
                        encoder_last_position[lane]<=work_pos;state<=BLEND;
                    end
                end
                ENC_WAIT:if(multiply_done)state<=ENC_STORE;
                ENC_STORE:begin
                    encoder_speed_q16[lane]<=encoder_speed_q16[lane]+(product>>>16);
                    encoder_last_position[lane]<=work_pos;state<=BLEND;
                end
                BLEND:begin
                    speed=work_speed<<<16;
                    if(work_tracking) begin
                        if(work_speed==0) speed=encoder_speed_q16[lane];
                        else if(work_speed==1 || work_speed== -1) speed=(speed+encoder_speed_q16[lane])>>>1;
                    end
                    filt=filter_initialized[lane]?filtered_speed_q16[lane]+
                        ((speed-filtered_speed_q16[lane])>>>(work_tracking?TRACKING_SPEED_FILTER_SHIFT:2)):speed;
                    filtered_speed_q16[lane]<=filt;filter_initialized[lane]<=1;state<=DESIRED;
                end
                DESIRED:begin
                    wide=times15(error_q16);
                    if(work_tracking) begin
                        // Use the full integer multi-turn distance before saturation.
                        // No target travel or target-minus-position angle clamp.
                        wide=$signed(work_base);
                        wide=wide-$signed(work_pos);
                        wide=(wide<<<12)-(wide<<<8);
                        n=clip($signed(ref_speed_q16)+wide,work_speed_limit);
                    end else n=clip($signed(ref_speed_q16)+(wide>>>8),V_LIMIT);
                    if(work_limits) begin
                        // Bound the total speed request by the remaining
                        // angular distance using the existing 8/s correction.

                        distance_to_bound=$signed({work_max[31],work_max})-$signed({work_pos[31],work_pos});
                        boundary_speed={{31{distance_to_bound[32]}},distance_to_bound};
                        boundary_speed=(boundary_speed<<<12)-(boundary_speed<<<8);
                        if($signed(n)>boundary_speed) n=clip(boundary_speed,work_speed_limit);
                        distance_to_bound=$signed({work_min[31],work_min})-$signed({work_pos[31],work_pos});
                        boundary_speed={{31{distance_to_bound[32]}},distance_to_bound};
                        boundary_speed=(boundary_speed<<<12)-(boundary_speed<<<8);
                        if($signed(n)<boundary_speed) n=clip(boundary_speed,work_speed_limit);
                    end
                    if(HOLD_LEAK_ENABLE && (!work_profile || work_boundary) && abs32(ref_speed_q16)<655 && abs32(error_q16)<=HOLD_BAND && abs32(filtered_speed_q16[lane])<=65536) begin
                        n=0;mult_x<=integral_q16[lane];mult_y<=LEAK;state<=LEAK_WAIT;
                    end else begin
                        work_integral_q16<=integral_q16[lane];
                        if(TRAJECTORY_ENABLED)begin
                            mult_x<=ref_accel_q16;mult_y<=TAU_Q24;state<=TAU_WAIT;
                        end else begin mult_x<=n;mult_y<=INV_K;state<=FF_WAIT;end
                    end
                    desired_q16<=n;speed_setpoint_q16[lane]<=n;
                    speed_error_q16<=n-filtered_speed_q16[lane];
                end
                LEAK_WAIT:if(multiply_done)state<=LEAK_STORE;
                LEAK_STORE:begin
                    work_integral_q16<=product>>>16;
                    if(TRAJECTORY_ENABLED)begin mult_x<=ref_accel_q16;mult_y<=TAU_Q24;state<=TAU_WAIT;end
                    else begin mult_x<=desired_q16;mult_y<=INV_K;state<=FF_WAIT;end
                end
                TAU_WAIT:if(TRAJECTORY_ENABLED && multiply_done)state<=TAU_STORE;
                TAU_STORE:if(TRAJECTORY_ENABLED)begin mult_x<=desired_q16+(product>>>24);mult_y<=INV_K;state<=FF_WAIT;end
                FF_WAIT:if(multiply_done)state<=FF_STORE;
                FF_STORE:begin ff_q16<=product>>>16;mult_x<=speed_error_q16;mult_y<=work_kp;state<=P_WAIT;end
                P_WAIT:if(multiply_done)state<=P_STORE;
                P_STORE:begin
                    p_q16<=product>>>16;
                    mult_x<=speed_error_q16;
                    if(work_gain_changed)begin mult_y<=last_kp[lane]-work_kp;state<=GAIN_WAIT;end
                    else begin mult_y<=work_ki_dt;state<=I_WAIT;end
                end
                GAIN_WAIT:if(multiply_done)state<=GAIN_STORE;
                GAIN_STORE:begin
                    // Preserve P+I across a gain switch at the current error.
                    // Integral and voltage limits retain their existing bounds.
                    work_integral_q16<=clip($signed(work_integral_q16)+(product>>>16),I_LIMIT);
                    mult_x<=speed_error_q16;mult_y<=work_ki_dt;state<=I_WAIT;
                end
                I_WAIT:if(multiply_done)state<=I_STORE;
                I_STORE:begin i_candidate_q16<=clip($signed(work_integral_q16)+(product>>>16),I_LIMIT);state<=OUT;end
                OUT:begin
                    last_kp[lane]<=work_kp;
                    settled_sample[lane]<=work_tracking && !work_profile &&
                        abs32(ref_speed_q16)<655 && abs32(error_q16)<=ARRIVAL_BAND_Q16 &&
                        abs32(filtered_speed_q16[lane])<=65536;
                    unsaturated=$signed(ff_q16)+$signed(p_q16)+$signed(i_candidate_q16);
                    u=clip(unsaturated,requested_mode==2?work_command_limit:U_LIMIT);
                    block_drive=live_limits &&
                        ((position_counts[lane]>=position_max_counts && u>0) ||
                         (position_counts[lane]<=position_min_counts && u<0));
                    if(block_drive) begin u=0;integral_q16[lane]<=0;end
                    else if(work_boundary) integral_q16[lane]<=0;
                    else if(unsaturated==u || (unsaturated>u && speed_error_q16<0) || (unsaturated<u && speed_error_q16>0)) integral_q16[lane]<=i_candidate_q16;
                    else integral_q16[lane]<=work_integral_q16;
                    if(FAST_OUTPUT_FILTER_SHIFT>0 && work_fast_output && requested_mode==2 && !live_limits)begin
                        // Separate register stage avoids extending the PI sum/
                        // saturation path. Only fast output gains one clock.
                        output_filter_input_q16<=u;state<=FAST_OUTPUT;
                    end else begin
                        // Bypass modes seed the history with their actual output,
                        // so entering fast mode never resumes an old filter tail.
                        output_filter_q16[lane]<=u;
                        command_raw[lane]<=rounded_command(u);command_valid[lane]<=1;active[lane]<=1;state<=IDLE;
                    end
                end
                FAST_OUTPUT:begin
                    if(requested_mode==2 && !live_limits)begin
                        wide=$signed(output_filter_input_q16);
                        wide=(wide-$signed(output_filter_q16[lane]))>>>FAST_OUTPUT_FILTER_SHIFT;
                        filt=$signed(output_filter_q16[lane])+wide;
                    end else filt=output_filter_input_q16;
                    filt=clip($signed(filt),requested_mode==2?work_command_limit:U_LIMIT);
                    // Recheck live bounds if region limiting was enabled after
                    // OUT. Boundary and fault[lane]/disable actions bypass the tail.
                    block_drive=live_limits &&
                        ((position_counts[lane]>=position_max_counts && filt>0) ||
                         (position_counts[lane]<=position_min_counts && filt<0));
                    if(block_drive)begin filt=0;integral_q16[lane]<=0;end
                    output_filter_q16[lane]<=filt;
                    command_raw[lane]<=rounded_command(filt);command_valid[lane]<=1;active[lane]<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(TICKS<256 || FEEDBACK_TIMEOUT_MS_A<1 || FEEDBACK_TIMEOUT_MS_B<1)
        $fatal(1,"Shared gimbal clock/timeout invalid");
    initial if(FAST_OUTPUT_FILTER_SHIFT_A<0 || FAST_OUTPUT_FILTER_SHIFT_A>8 || FAST_OUTPUT_FILTER_SHIFT_B<0 || FAST_OUTPUT_FILTER_SHIFT_B>8)
        $fatal(1,"Fast output filter shift must be 0..8");
    always @(posedge clk)if(rst_n)begin
        if(pending[0] && tick_count[0]==TICKS-1 && enable_bus[0] && !fault[0])$fatal(1,"Gimbal A sample overrun");
        if(pending[1] && tick_count[1]==TICKS-1 && enable_bus[1] && !fault[1])$fatal(1,"Gimbal B sample overrun");
    end
`endif
endmodule

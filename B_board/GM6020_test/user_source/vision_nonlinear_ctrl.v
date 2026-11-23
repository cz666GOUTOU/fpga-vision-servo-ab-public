`include "fpga_b_example_config.vh"

// Q16 pixels/counts/s; multi-turn absolute goals use 48 bits (32 integer).

module vision_nonlinear_ctrl #(
    parameter integer CLK_HZ=50000000,
    parameter integer DELAY_MS=23, UPDATE_MS=10, ACQUIRE_MS=80,
    parameter integer RX_TIMEOUT_MS=100, DEADBAND_PIXELS=2,

    // Bounded from the LAST GOOD record, never from an invalid frame.
    parameter integer INVALID_GRACE_MS=300
)(
    input wire clk,rst_n,enable,manual_override,
    input wire [1:0] tracking_mode,
    input wire result_update,target_valid,comm_timeout,clear_history,source_change,
    input wire [15:0] center_x,center_y,setpoint_x,setpoint_y,
    input wire feedback_ready1,feedback_ready2,
    input wire signed [31:0] position1,position2,
    output reg command_valid,hold,tracking,busy,
    output reg signed [31:0] target1,target2,velocity1_q16,velocity2_q16,
    output reg signed [31:0] predicted_x_q16,predicted_y_q16,
    output reg signed [31:0] error_x_q16,error_y_q16,
    output reg [3:0] hold_reason
);
    localparam integer MS_TICKS=CLK_HZ/1000;
    localparam integer CW=MS_TICKS>1?$clog2(MS_TICKS):1;
    localparam signed [31:0] RATE=`FPGA_B_VISION_NONLINEAR_CTRL_RATE_1, ACCEL_STEP=`FPGA_B_VISION_NONLINEAR_CTRL_ACCEL_STEP_1;
    localparam signed [31:0] INTEGRAL_MAX=`FPGA_B_VISION_NONLINEAR_CTRL_INTEGRAL_MAX_1, RESET_GOAL=`FPGA_B_VISION_NONLINEAR_CTRL_RESET_GOAL_1;
    localparam signed [31:0] NOISE_SPEED=`FPGA_B_VISION_NONLINEAR_CTRL_NOISE_SPEED_1;
    localparam IDLE=0,PREDICT=1,MAP_WAIT=2,DET_A=3,DET_B=4,
        DET_C=5,NUM_X_A=6,NUM_X_B=7,NUM_X_C=8,
        NUM_Y_A=9,NUM_Y_B=10,NUM_Y_C=11,
        DIV_X=12,DIV_X_WAIT=13,DIV_Y=14,DIV_Y_WAIT=15,
        MAP_CURRENT=16,MAP_GOAL=17,MAP_RAW_GOAL=18,
        STEP=19,OBSERVE=20,OBS_ACCEL=21,VELOCITY_GATE=22,
        COMMAND=23,WANTED=24,SLEW=25,PUBLISH=26,MUL_WAIT=27,
        FALLBACK_X=28,FALLBACK_Y1=29,FALLBACK_Y2=30,
        OBS_PREDICT=31,OBS_CORRECT=32,OBS_INTEGRAL=33,ACCEL_STORE=34,
        GATE_COEFF=35,GATE_STORE=36,LEAD_STORE=37,WANTED_STORE=38;
    reg [5:0] state,next_state,map_return;
    reg [CW-1:0] tick_count;
    wire millisecond=tick_count==MS_TICKS-1;
    reg [31:0] now_ms,rx_ms,last_packet_ms,valid_since,last_update;
    reg [1:0] work_mode;
    reg signed [31:0] work_rate,work_accel_step,work_rate_y,work_accel_step_y;
    reg [15:0] rx_x,rx_y;
    reg frame_valid,stored_frame_valid,acquiring,centered,goal_valid;
    wire incoming_frame_valid=target_valid && !comm_timeout && center_x<1280 && center_y<720 &&
        (center_x!=0 || center_y!=0);
    // A synchronous-read simple dual-port RAM replaces three asynchronous
    // indexed arrays. It stores the same two positions and timestamp.
    (* ram_style="bram" *) reg [95:0] history[0:127];
    reg [95:0] history_read;
    reg [127:0] history_valid;
    wire [31:0] capture_ms=rx_ms-DELAY_MS;
    wire [6:0] history_slot=capture_ms[6:0];
    wire [31:0] arriving_capture_ms=now_ms-DELAY_MS;
    // Prefetch only the timestamp that will actually be latched into rx_ms.
    // Invalid frames keep both the coordinate and its historical encoder pose.
    wire [6:0] history_read_slot=result_update && incoming_frame_valid?arriving_capture_ms[6:0]:history_slot;
    always @(posedge clk)begin
        if(rst_n && millisecond)history[now_ms[6:0]]<={now_ms,position1,position2};
        history_read<=history[history_read_slot];
    end
    // Keep the matched encoder pose with the last good camera record. The
    // 128ms history ring can wrap during the 300ms invalid-frame grace.
    // A new valid record invalidates this cache; the matched RAM read can
    // bypass it immediately, including arrivals on a millisecond boundary.
    wire motors_ok=feedback_ready1 && feedback_ready2;
    reg [63:0] cached_capture_positions;
    reg cached_capture_valid;
    wire capture_from_ram_valid=stored_frame_valid && history_valid[history_slot] &&
        history_read[95:64]==capture_ms;
    wire capture_pose_valid=capture_from_ram_valid || cached_capture_valid;
    wire [63:0] capture_positions=capture_from_ram_valid?history_read[63:0]:cached_capture_positions;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin cached_capture_positions<=0;cached_capture_valid<=0;end
        else if(!motors_ok || source_change || (result_update && incoming_frame_valid))
            cached_capture_valid<=0;
        else if(capture_from_ram_valid)begin
            cached_capture_positions<=history_read[63:0];cached_capture_valid<=1;
        end
    end
    wire recent_good_frame=INVALID_GRACE_MS>0 && tracking && stored_frame_valid &&
        now_ms-rx_ms<=INVALID_GRACE_MS;
    // Packet silence and continuous invalid coordinates have separate timers.
    // Invalid packets keep the link alive, but never renew the good-record age.
    wire record_ok=(frame_valid || recent_good_frame) && !comm_timeout && now_ms-last_packet_ms<=RX_TIMEOUT_MS &&
        setpoint_x<1280 && setpoint_y<720;
    wire effective_valid=enable && motors_ok && record_ok && !manual_override;
    reg map_start;
    reg signed [31:0] map_x,map_y;
    wire map_done,map_busy;
    wire signed [31:0] mq1,mq2,mj11,mj12,mj21,mj22;
    vision_geometry_map geometry(.clk(clk),.rst_n(rst_n),.start(map_start),
        .x_q16(map_x),.y_q16(map_y),.busy(map_busy),.done(map_done),
        .q1(mq1),.q2(mq2),.j11(mj11),.j12(mj12),.j21(mj21),.j22(mj22));
    reg div_start;
    reg [63:0] numerator;
    reg [31:0] denominator;
    wire div_done,div_busy;
    wire [63:0] quotient;
    vision_u64_div32 division(.clk(clk),.rst_n(rst_n),.start(div_start),
        .numerator(numerator),.denominator(denominator),
        .busy(div_busy),.done(div_done),.quotient(quotient));
    reg signed [31:0] mx,my;
    reg signed [63:0] product,saved_product,numerator_x,numerator_y;
    wire signed [31:0] product_q16=product[47:16];
    // Exact signed-digit 32x32 with one 17x17 DSP lane. Small signed
    // operands complete in two clocks; full-width pairs take three.
    reg [1:0] multiply_phase;
    reg signed [31:0] partial_low,partial_high;
    wire multiplication_wait=state==MUL_WAIT;
    wire signed [16:0] low_x={mx[15],mx[15:0]};
    wire signed [16:0] low_y={my[15],my[15:0]};
    wire signed [16:0] high_x=$signed({mx[31],mx[31:16]})+$signed({16'd0,mx[15]});
    wire signed [16:0] high_y=$signed({my[31],my[31:16]})+$signed({16'd0,my[15]});
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

    reg [1:0] prediction_iteration;
    reg signed [31:0] px,py,wanted_q1,wanted_q2,raw_q1,raw_q2,det;
    reg signed [31:0] e1,e2,j11,j12,j21,j22;
    reg signed [31:0] work_p[0:1],current_q[0:1],goal_q[0:1],raw_goal_q[0:1];
    reg signed [31:0] integral[0:1],velocity[0:1];
    reg signed [47:0] observed_goal[0:1],goal[0:1],angle_command[0:1];
    reg signed [31:0] observed_velocity[0:1],observed_accel[0:1];
    reg signed [31:0] previous_velocity,fv,fa,wanted_velocity,work_velocity;
    reg signed [31:0] ex,ey,dt_ms,observer_error;
    reg signed [31:0] work_sx,work_sy;
    reg axis,raw_centered,observer_reset;
    reg signed [31:0] out_target[0:1],out_velocity[0:1];
    reg signed [47:0] observer_measured,observer_prediction;
    reg signed [63:0] wanted_base;
    function signed [31:0] clip;
        input signed [63:0] n;
        input signed [31:0] limit;
        begin clip=n>limit?limit:(n< -$signed(limit)?-$signed(limit):n[31:0]);end
    endfunction
    function [47:0] abs48;
        input signed [47:0] n;
        begin abs48=n<0?-n:n;end
    endfunction
    function signed [31:0] round_count;
        input signed [47:0] n;
        begin round_count=n>=0?(n+48'sd32768)>>>16:-((-n+48'sd32768)>>>16);end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin tick_count<=0;now_ms<=0;rx_ms<=0;last_packet_ms<=0;rx_x<=0;rx_y<=0;frame_valid<=0;stored_frame_valid<=0;
            history_valid<=0;
        end else begin
            tick_count<=millisecond?0:tick_count+1'b1;
            if(millisecond) begin
                now_ms<=now_ms+1'b1;
                history_valid[now_ms[6:0]]<=motors_ok;
            end
            // A source change cannot borrow another target's cached record.
            // A simultaneous valid record belongs to the new source below.
            if(source_change)begin frame_valid<=0;stored_frame_valid<=0;end
            if(result_update) begin
                last_packet_ms<=now_ms;
                frame_valid<=incoming_frame_valid;
                if(incoming_frame_valid)begin
                    rx_x<=center_x;rx_y<=center_y;rx_ms<=now_ms;
                    stored_frame_valid<=1;
                end
            end
            if(!motors_ok) history_valid<=0;
        end
    end
    always @(posedge clk or negedge rst_n) begin: control
        reg signed [47:0] measured,delta_goal,predicted_goal,full_goal;
        reg signed [63:0] wide,n,acceleration_step;
        reg signed [31:0] d,updated_velocity,gate,command_count;
        if(!rst_n) begin
            state<=IDLE;next_state<=IDLE;map_return<=IDLE;map_start<=0;div_start<=0;
            map_x<=0;map_y<=0;mx<=0;my<=0;saved_product<=0;numerator_x<=0;numerator_y<=0;
            numerator<=0;denominator<=1;prediction_iteration<=0;wanted_q1<=0;wanted_q2<=0;
            px<=0;py<=0;raw_q1<=0;raw_q2<=0;det<=0;e1<=0;e2<=0;j11<=0;j12<=0;j21<=0;j22<=0;
            command_valid<=0;hold<=0;tracking<=0;busy<=0;hold_reason<=1;
            target1<=0;target2<=0;velocity1_q16<=0;velocity2_q16<=0;
            predicted_x_q16<=0;predicted_y_q16<=0;error_x_q16<=0;error_y_q16<=0;
            valid_since<=0;last_update<=0;acquiring<=0;centered<=0;goal_valid<=0;
            work_mode<=0;work_rate<=RATE;work_accel_step<=ACCEL_STEP;
            work_rate_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_1;work_accel_step_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_2;
            axis<=0;ex<=0;ey<=0;dt_ms<=UPDATE_MS;work_sx<=0;work_sy<=0;
            previous_velocity<=0;observer_error<=0;fv<=0;fa<=0;wanted_velocity<=0;work_velocity<=0;raw_centered<=0;observer_reset<=1;
            work_p[0]<=0;work_p[1]<=0;current_q[0]<=0;current_q[1]<=0;
            goal_q[0]<=0;goal_q[1]<=0;raw_goal_q[0]<=0;raw_goal_q[1]<=0;
            integral[0]<=0;integral[1]<=0;velocity[0]<=0;velocity[1]<=0;
            observed_goal[0]<=0;observed_goal[1]<=0;observed_velocity[0]<=0;observed_velocity[1]<=0;
            observed_accel[0]<=0;observed_accel[1]<=0;goal[0]<=0;goal[1]<=0;
            angle_command[0]<=0;angle_command[1]<=0;out_target[0]<=0;out_target[1]<=0;
            out_velocity[0]<=0;out_velocity[1]<=0;
            observer_measured<=0;observer_prediction<=0;wanted_base<=0;
        end else begin
            command_valid<=0;map_start<=0;div_start<=0;
            // A key event cancels visual work and allows the original key target.
            if(manual_override) begin
                tracking<=0;acquiring<=0;centered<=0;goal_valid<=0;
                integral[0]<=0;integral[1]<=0;velocity[0]<=0;velocity[1]<=0;
                // Manual/region preparation can move both motors while visual
                // control is suspended. Publish that pose as the idle reference
                // so resuming cannot replay a reset-zero or old visual target.
                target1<=position1;target2<=position2;
                velocity1_q16<=0;velocity2_q16<=0;hold<=1;
                state<=IDLE;busy<=0;hold_reason<=1;
            end else if(!effective_valid) begin
                if(tracking) begin
                    command_valid<=1;hold<=1;target1<=position1;target2<=position2;
                    velocity1_q16<=0;velocity2_q16<=0;
                end
                tracking<=0;acquiring<=0;centered<=0;goal_valid<=0;
                integral[0]<=0;integral[1]<=0;velocity[0]<=0;velocity[1]<=0;
                state<=IDLE;busy<=0;
                hold_reason<=!enable?1:(!record_ok?2:3);
            end else if(clear_history) begin
                // Moving setpoints preserve the motion observer and acquisition.
                integral[0]<=0;integral[1]<=0;centered<=0;
                if(source_change) begin goal_valid<=0;state<=IDLE;busy<=0;end
            end else case(state)
                IDLE:if(millisecond && !map_busy && !div_busy) begin
                    if(!capture_pose_valid) begin
                        if(tracking) begin command_valid<=1;hold<=1;target1<=position1;target2<=position2;velocity1_q16<=0;velocity2_q16<=0;end
                        tracking<=0;acquiring<=0;goal_valid<=0;velocity[0]<=0;velocity[1]<=0;
                        integral[0]<=0;integral[1]<=0;hold_reason<=4;
                    end else if(!acquiring && !tracking) begin valid_since<=now_ms;acquiring<=1;hold_reason<=4;end
                    else if(!tracking && now_ms-valid_since<ACQUIRE_MS) hold_reason<=4;
                    else if(!tracking || now_ms-last_update>=UPDATE_MS) begin
                        tracking<=1;hold_reason<=0;busy<=1;hold<=0;
                        // Fast uses the normal algorithm with doubled rate/acceleration.
                        // Acquisition, observer and reference publication are identical.
                        case(tracking_mode)
                            2'd1:begin
                                work_mode<=1;work_rate<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_3;work_accel_step<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_4;
                                work_rate_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_5;work_accel_step_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_6;
                            end
                            2'd2:begin
                                work_mode<=2;work_rate<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_7;work_accel_step<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_8;
                                work_rate_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_9;work_accel_step_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_10;
                            end
                            default:begin
                                work_mode<=0;work_rate<=RATE;work_accel_step<=ACCEL_STEP;
                                work_rate_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_11;work_accel_step_y<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_12;
                            end
                        endcase
                        dt_ms<=(!tracking)?UPDATE_MS:(now_ms-last_update>40?40:now_ms-last_update);
                        last_update<=now_ms;
                        work_p[0]<=position1;work_p[1]<=position2;
                        work_sx<=$signed({setpoint_x,16'b0});work_sy<=$signed({setpoint_y,16'b0});
                        px<=$signed({rx_x,16'b0});py<=$signed({rx_y,16'b0});
                        map_x<=$signed({rx_x,16'b0});map_y<=$signed({rx_y,16'b0});
                        wanted_q1<=(position1-$signed(capture_positions[63:32]))<<<16;
                        wanted_q2<=(position2-$signed(capture_positions[31:0]))<<<16;
                        prediction_iteration<=0;map_start<=1;map_return<=PREDICT;state<=MAP_WAIT;
                    end
                end
                MAP_WAIT:if(map_done) state<=map_return;
                MUL_WAIT:if(multiply_done)state<=next_state;
                PREDICT:begin
                    if(prediction_iteration==0) begin wanted_q1<=wanted_q1+mq1;wanted_q2<=wanted_q2+mq2;raw_q1<=mq1;raw_q2<=mq2;end
                    e1<=(prediction_iteration==0?wanted_q1+mq1:wanted_q1)-mq1;
                    e2<=(prediction_iteration==0?wanted_q2+mq2:wanted_q2)-mq2;
                    j11<=mj11;j12<=mj12;j21<=mj21;j22<=mj22;
                    mx<=mj11;my<=mj22;state<=MUL_WAIT;next_state<=DET_A;
                end
                DET_A:begin saved_product<=product;mx<=j12;my<=j21;state<=MUL_WAIT;next_state<=DET_B;end
                DET_B:begin det<=(saved_product-product)>>>16;state<=DET_C;end
                DET_C:begin
                    if(det<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_13 || det>=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_14) begin
                        mx<=wanted_q1-raw_q1;my<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_15;state<=MUL_WAIT;next_state<=FALLBACK_X;
                    end else begin mx<=j22;my<=e1;state<=MUL_WAIT;next_state<=NUM_X_A;end
                end
                FALLBACK_X:begin
                    px<=px+product_q16;
                    mx<=wanted_q1-raw_q1;my<=5447;state<=MUL_WAIT;next_state<=FALLBACK_Y1;
                end
                FALLBACK_Y1:begin
                    py<=py+product_q16;
                    mx<=wanted_q2-raw_q2;my<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_16;state<=MUL_WAIT;next_state<=FALLBACK_Y2;
                end
                FALLBACK_Y2:begin py<=py+product_q16;state<=MAP_CURRENT;end
                NUM_X_A:begin saved_product<=product;mx<=j12;my<=e2;state<=MUL_WAIT;next_state<=NUM_X_B;end
                NUM_X_B:begin numerator_x<=saved_product-product;mx<=j11;my<=e2;state<=MUL_WAIT;next_state<=NUM_Y_A;end
                NUM_Y_A:begin saved_product<=product;mx<=j21;my<=e1;state<=MUL_WAIT;next_state<=NUM_Y_B;end
                NUM_Y_B:begin numerator_y<=saved_product-product;state<=DIV_X;end
                DIV_X:begin numerator<=numerator_x<0?-numerator_x:numerator_x;denominator<=det;div_start<=1;state<=DIV_X_WAIT;end
                DIV_X_WAIT:if(div_done) begin px<=px+(numerator_x<0?-$signed(quotient[31:0]):$signed(quotient[31:0]));state<=DIV_Y;end
                DIV_Y:begin numerator<=numerator_y<0?-numerator_y:numerator_y;denominator<=det;div_start<=1;state<=DIV_Y_WAIT;end
                DIV_Y_WAIT:if(div_done) begin
                    py<=py+(numerator_y<0?-$signed(quotient[31:0]):$signed(quotient[31:0]));
                    if(prediction_iteration==1) state<=MAP_CURRENT;
                    else begin prediction_iteration<=1;map_x<=px;map_y<=py+(numerator_y<0?-$signed(quotient[31:0]):$signed(quotient[31:0]));map_start<=1;map_return<=PREDICT;state<=MAP_WAIT;end
                end
                MAP_CURRENT:begin
                    if(px< -32'sd268435456 || px>32'sd268435456 || py< -32'sd268435456 || py>32'sd268435456) begin
                        // Preserve the C core's projected-coordinate validity bound.
                        // It rejects impossible encoder/history jumps, not angles.
                        command_valid<=1;hold<=1;target1<=work_p[0];target2<=work_p[1];
                        velocity1_q16<=0;velocity2_q16<=0;tracking<=0;acquiring<=0;
                        centered<=0;goal_valid<=0;integral[0]<=0;integral[1]<=0;
                        velocity[0]<=0;velocity[1]<=0;hold_reason<=2;busy<=0;state<=IDLE;
                    end else begin
                        ex<=work_sx-px;ey<=work_sy-py;
                        error_x_q16<=work_sx-px;error_y_q16<=work_sy-py;
                        predicted_x_q16<=px;predicted_y_q16<=py;
                        map_x<=px;map_y<=py;map_start<=1;map_return<=MAP_GOAL;state<=MAP_WAIT;
                    end
                end
                MAP_GOAL:begin
                    current_q[0]<=mq1;current_q[1]<=mq2;
                    raw_centered<=abs48(ex)<=DEADBAND_PIXELS*65536 && abs48(ey)<=DEADBAND_PIXELS*65536;
                    map_x<=abs48(ex)<=DEADBAND_PIXELS*65536?px:work_sx;
                    map_y<=abs48(ey)<=DEADBAND_PIXELS*65536?py:work_sy;
                    map_start<=1;map_return<=MAP_RAW_GOAL;state<=MAP_WAIT;
                end
                MAP_RAW_GOAL:begin
                    goal_q[0]<=mq1;goal_q[1]<=mq2;
                    map_x<=work_sx;map_y<=work_sy;map_start<=1;map_return<=STEP;state<=MAP_WAIT;
                end
                STEP:begin
                    raw_goal_q[0]<=mq1;raw_goal_q[1]<=mq2;
                    measured=$signed({work_p[0],16'b0})+$signed(mq1)-$signed(current_q[0]);
                    full_goal=$signed({work_p[1],16'b0})+$signed(mq2)-$signed(current_q[1]);
                    // Only acquisition/source changes initialize both axes.
                    observer_reset<=!goal_valid;
                    if(raw_centered && abs48(velocity[0])<`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_17 && abs48(velocity[1])<`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_18) begin
                        if(!centered) begin command_valid<=1;hold<=1;target1<=work_p[0];target2<=work_p[1];velocity1_q16<=0;velocity2_q16<=0;end
                        centered<=1;goal_valid<=0;velocity[0]<=0;velocity[1]<=0;busy<=0;state<=IDLE;
                    end else begin centered<=0;axis<=0;state<=OBSERVE;end
                end
                OBSERVE:begin
                    // Absolute angle is kept wide; only small observer errors narrow.
                    measured=$signed({work_p[axis],16'b0})+$signed(raw_goal_q[axis])-$signed(current_q[axis]);
                    observer_measured<=measured;
                    previous_velocity<=observed_velocity[axis];
                    if(observer_reset) begin
                        observed_goal[axis]<=measured;observed_velocity[axis]<=0;observed_accel[axis]<=0;
                        previous_velocity<=0;observer_error<=0;
                        mx<=goal_q[axis]-current_q[axis];my<=131;
                        state<=MUL_WAIT;next_state<=OBS_INTEGRAL;
                    end else begin
                        mx<=observed_velocity[axis];my<=655;
                        state<=MUL_WAIT;next_state<=OBS_PREDICT;
                    end
                    d=goal_q[axis]-current_q[axis];
                    goal[axis]<=$signed({work_p[axis],16'b0})+$signed(d);
                end
                OBS_PREDICT:begin
                    predicted_goal=observed_goal[axis]+$signed(product_q16);
                    delta_goal=observer_measured-predicted_goal;observer_error<=delta_goal;
                    observer_prediction<=predicted_goal;
                    // Compare this axis with its motion prediction. Continuous
                    // movement on X must not clear the Y velocity estimate.
                    if(abs48(delta_goal)>RESET_GOAL) begin
                        observed_goal[axis]<=observer_measured;
                        observed_velocity[axis]<=0;observed_accel[axis]<=0;
                        previous_velocity<=0;observer_error<=0;
                        mx<=goal_q[axis]-current_q[axis];my<=131;
                        state<=MUL_WAIT;next_state<=OBS_INTEGRAL;
                    end else begin
                        observed_velocity[axis]<=clip($signed(observed_velocity[axis])+($signed(delta_goal)<<<2),axis?work_rate_y:work_rate);
                        mx<=delta_goal;my<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_19;state<=MUL_WAIT;next_state<=OBS_CORRECT;
                    end
                end
                OBS_CORRECT:begin
                    observed_goal[axis]<=observer_prediction+$signed(product_q16);
                    mx<=goal_q[axis]-current_q[axis];my<=131;
                    state<=MUL_WAIT;next_state<=OBS_INTEGRAL;
                end
                OBS_INTEGRAL:begin
                    if(abs48(ex)<25*65536 && abs48(ey)<25*65536)
                        integral[axis]<=clip($signed(integral[axis])+$signed(product_q16),INTEGRAL_MAX);
                    else integral[axis]<=0;
                    state<=OBS_ACCEL;
                end
                OBS_ACCEL:begin
                    d=observed_velocity[axis]-previous_velocity;
                    d=(d<<<6)+(d<<<5)+(d<<<2); // Exact 32-bit d*100, including wrap.
                    mx<=d-observed_accel[axis];my<=9362;state<=MUL_WAIT;next_state<=ACCEL_STORE;
                end
                ACCEL_STORE:begin
                    observed_accel[axis]<=observed_accel[axis]+product_q16;
                    state<=VELOCITY_GATE;
                end
                VELOCITY_GATE:begin
                    d=observed_velocity[axis];
                    if(abs48(d)<=NOISE_SPEED)begin fv<=0;state<=COMMAND;end
                    else if(abs48(d)>=2*NOISE_SPEED)begin fv<=d;state<=COMMAND;end
                    else begin
                        mx<=abs48(d)-NOISE_SPEED;my<=`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_20;
                        state<=MUL_WAIT;next_state<=GATE_COEFF;
                    end
                end
                GATE_COEFF:begin
                    mx<=observed_velocity[axis];my<=product>>>24;
                    state<=MUL_WAIT;next_state<=GATE_STORE;
                end
                GATE_STORE:begin fv<=product_q16;state<=COMMAND;end
                COMMAND:begin
                    // Reduced position lead: X=26.50ms, Y=17.50ms.
                    mx<=fv;my<=axis?1147:1737;state<=MUL_WAIT;next_state<=LEAD_STORE;
                    fa<=fv!=0?clip(observed_accel[axis],`FPGA_B_VISION_NONLINEAR_CTRL_OBSERVER_TUNING_21):0;
                end
                LEAD_STORE:begin
                    angle_command[axis]<=goal[axis]+$signed(integral[axis])+$signed(product_q16);
                    state<=WANTED;
                end
                WANTED:begin
                    delta_goal=angle_command[axis]-$signed({work_p[axis],16'b0});
                    // Position rates X/Y: stable 16/20, normal 16/24,
                    // fast24/30 (normal X1.5/Y1.25). Constant shifts avoid a new DSP.
                    wide=$signed(delta_goal);
                    if(axis)begin
                        if(work_mode==0)wide=(wide<<<4)+(wide<<<2);
                        else if(work_mode==1)wide=(wide<<<4)+(wide<<<3);
                        else wide=(wide<<<5)-(wide<<<1);
                    end else begin
                        if(work_mode==2)wide=(wide<<<4)+(wide<<<3);
                        else wide=wide<<<4;
                    end
                    // Damp X target-motion feedforward without changing the motor PI.
                    wanted_base<=wide+(axis?$signed(fv):($signed(fv)>>>1));
                    mx<=fa;my<=axis?786:1966;state<=MUL_WAIT;next_state<=WANTED_STORE;
                    out_target[axis]<=round_count(angle_command[axis]);
                end
                WANTED_STORE:begin
                    wanted_velocity<=clip(wanted_base+$signed(product_q16),axis?work_rate_y:work_rate);
                    state<=SLEW;
                end
                SLEW:begin
                    acceleration_step=axis?work_accel_step_y:work_accel_step;
                    updated_velocity=velocity[axis]+clip($signed(wanted_velocity)-$signed(velocity[axis]),acceleration_step);
                    velocity[axis]<=updated_velocity;work_velocity<=updated_velocity;
                    // The motor adds 8*(target-actual) counts/s. The speed offset
                    // cancels that term so total requested speed follows the ramp.
                    n=($signed({{32{out_target[axis][31]}},out_target[axis]})-$signed({{32{work_p[axis][31]}},work_p[axis]}))<<<19;
                    out_velocity[axis]<=clip($signed(updated_velocity)-n,32'sh7fffffff);
                    if(axis) state<=PUBLISH;
                    else begin axis<=1;state<=OBSERVE;end
                end
                PUBLISH:begin
                    // A newer valid frame does not cancel this captured two-axis
                    // result. Invalid frames and source/key changes abort above.
                    if(now_ms-last_update<UPDATE_MS && dt_ms==UPDATE_MS) begin
                        target1<=out_target[0];target2<=out_target[1];
                        velocity1_q16<=out_velocity[0];velocity2_q16<=out_velocity[1];
                        command_valid<=1;hold<=0;goal_valid<=1;
                    end
                    busy<=0;state<=IDLE;
                end
                default:begin busy<=0;state<=IDLE;end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial if(MS_TICKS<512 || UPDATE_MS!=10 || DELAY_MS>=128 || RX_TIMEOUT_MS<1 || INVALID_GRACE_MS<0) $fatal(1,"Unsupported visual timing parameters");
`endif
endmodule

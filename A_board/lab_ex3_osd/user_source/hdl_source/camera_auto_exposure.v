`timescale 1ns/1ps
// Entry-relative, bidirectional FPGA digital gain. No automatic sensor writes.
// RAW sums are PRE gain: compare sum*gain against the saved entry reference.
// Monotone residual walk reuses a 13-bit limb ALU; exact nearest-rank/deadband.
// No pixel-path changes, runtime multipliers, or new memories.
module camera_auto_exposure #(
    parameter integer FRAME_PIXELS = 921600,
    parameter [9:0] DARK_MIN_MEAN = 10'd0,
    parameter [9:0] RECOVER_MIN_MEAN = 10'd0,
    parameter integer CONFIRM_SAMPLES = 2,
    parameter [2:0] SETTLE_FRAMES = 3
)(
    input wire I_clk, input wire I_rst_n, input wire I_auto_enable,
    input wire [15:0] I_seed_ae, input wire [15:0] I_seed_ag,
    input wire I_cam_cfg_done, input wire I_ae_cfg_done, input wire I_ae_req,
    input wire [15:0] I_submitted_ae, input wire [15:0] I_submitted_ag,
    input wire I_iic_error,
    input wire I_stat_toggle_async, input wire [31:0] I_stat_sum_async,
    input wire I_stat_valid_async, input wire [4:0] I_stat_gain_async,
    input wire [7:0] I_stat_epoch_async, input wire I_dgain_ack_async,
    output reg O_stat_request, output reg [2:0] O_stat_skip,
    output reg O_dgain_request, output reg [4:0] O_dgain,
    output reg [7:0] O_dgain_epoch,
    output reg O_targets_valid, output reg [15:0] O_ae, output reg [15:0] O_ag,
    output reg [31:0] O_target_sum, output reg O_target_valid
);
    // Production floor parameters are zero; the reference remains entry-relative.
    localparam [3:0] ST_OFF=0, ST_SETTLE=1, ST_SAMPLE=2, ST_CAPTURE=3,
        ST_MULT=4, ST_DIFF=5, ST_SAVE_ERROR=6, ST_STEP=7,
        ST_TEST=8, ST_PICK=9, ST_RESTORE=10, ST_ABS=11,
        ST_IMPROVE=12, ST_DEADBAND=13, ST_DECIDE=14, ST_DIGITAL=15;
    localparam [7:0] CONFIRM_LAST=CONFIRM_SAMPLES-1;
    reg [3:0] state;
    reg enable_d,baseline_needed,search_down;
    reg [2:0] ready_count,next_skip,base_steps;
    reg [4:0] saved_gain,current_gain,scan_gain,pending_gain;
    reg [7:0] epoch,confirm_count;
    reg [31:0] sample_sum;
    reg [6:0] base_coefficient;
    reg [37:0] target_product,current_error;
    reg [38:0] residual;
    reg [1:0] edge_shift;
    (* ASYNC_REG="TRUE" *) reg [1:0] stat_sync,dgain_sync;
    wire mailboxes_idle=(stat_sync[1]==O_stat_request) &&
                        (dgain_sync[1]==O_dgain_request);
    function [6:0] coefficient;
        input [4:0] gain;
        begin
            if(gain<8) coefficient=7'd16+{1'b0,gain,1'b0};
            else if(gain<=16) coefficient={gain,2'b00};
            else if(gain<=28) coefficient={2'b00,gain}-7'd13;
            else coefficient=7'd32;
        end
    endfunction
    function [4:0] adjacent;
        input [4:0] gain;input down;
        begin
            if(down)adjacent=(gain==0)?5'd28:gain-5'd1;
            else adjacent=(gain==28)?5'd0:gain+5'd1;
        end
    endfunction
    wire [4:0] proposed_gain=adjacent(current_gain,search_down);
    wire [4:0] previous_gain=adjacent(scan_gain,!search_down);
    // A coefficient interval is 1, 2 or 4 in Q4. Save the traversed interval
    // for crossing/tie selection, rather than recomputing it at the new rank.
    wire [1:0] next_shift=search_down ?
        ((scan_gain>=17 || scan_gain==0)?2'd0:scan_gain<=8?2'd1:2'd2) :
        (scan_gain>=17?2'd0:scan_gain<8?2'd1:2'd2);
    wire [1:0] step_shift=(state==ST_STEP)?next_shift:edge_shift;
    wire [38:0] interval_sum={7'd0,sample_sum}<<step_shift;
    // Three little-endian 13-bit limbs reuse the existing residual register.
    // Preserve the old low-to-high shift boundary before overwriting each limb.
    // All state side effects commit only with limb 2; cancellation wins every cycle.
    reg [1:0] alu_part;
    reg alu_carry,shift_bit,lower_zero;
    wire alu_state=(state==ST_MULT || state==ST_DIFF || state==ST_SAVE_ERROR ||
        state==ST_STEP || state==ST_PICK || state==ST_RESTORE || state==ST_ABS ||
        state==ST_IMPROVE || state==ST_DEADBAND);
    reg [12:0] residual_word,sample_word,interval_word,target_word,error_word,deadband_word;
    always @* begin
        case(alu_part)
            0:begin residual_word=residual[12:0];sample_word=sample_sum[12:0];
                interval_word=interval_sum[12:0];target_word=target_product[12:0];
                error_word=current_error[12:0];deadband_word=target_product[18:6];end
            1:begin residual_word=residual[25:13];sample_word=sample_sum[25:13];
                interval_word=interval_sum[25:13];target_word=target_product[25:13];
                error_word=current_error[25:13];deadband_word=target_product[31:19];end
            default:begin residual_word=residual[38:26];sample_word={7'd0,sample_sum[31:26]};
                interval_word=interval_sum[38:26];target_word={1'b0,target_product[37:26]};
                error_word={1'b0,current_error[37:26]};deadband_word={7'd0,target_product[37:32]};end
        endcase
    end
    reg [12:0] alu_a,alu_b;
    reg alu_sub;
    always @* begin
        alu_a=residual_word;alu_b=0;alu_sub=0;
        case(state)
            ST_MULT:begin alu_a={residual_word[11:0],alu_part==0 ? 1'b0 : shift_bit};
                alu_b=base_coefficient[6] ? sample_word : 13'd0;end
            ST_DIFF:begin alu_b=target_word;alu_sub=1;end
            ST_SAVE_ERROR,ST_ABS:if(residual[38])begin
                alu_a=0;alu_b=residual_word;alu_sub=1;end
            ST_STEP:begin alu_b=interval_word;alu_sub=search_down;end
            ST_PICK:begin alu_a={residual_word[11:0],alu_part==0 ? 1'b0 : shift_bit};
                alu_b=interval_word;alu_sub=!search_down;end
            ST_RESTORE:begin alu_b=interval_word;alu_sub=!search_down;end
            ST_IMPROVE:begin alu_a=error_word;alu_b=residual_word;alu_sub=1;end
            ST_DEADBAND:begin alu_b=deadband_word;alu_sub=1;end
            default:begin end
        endcase
    end
    wire [13:0] word_result={1'b0,alu_a}+{1'b0,(alu_b^{13{alu_sub}})}+
        {13'd0,(alu_part==0 ? alu_sub : alu_carry)};
    // ST_PICK leaves residual intact. Accumulate zero separately for its tie rule.
    wire restore_previous=search_down ?
        (word_result[12] || (lower_zero && word_result[12:0]==0 && previous_gain==current_gain)) :
        !word_result[12];
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=ST_OFF;enable_d<=0;baseline_needed<=1;search_down<=0;
            alu_part<=0;alu_carry<=0;shift_bit<=0;lower_zero<=1;
            ready_count<=0;next_skip<=0;base_steps<=0;edge_shift<=0;
            saved_gain<=8;current_gain<=8;scan_gain<=8;pending_gain<=8;
            epoch<=0;confirm_count<=0;sample_sum<=0;base_coefficient<=0;
            target_product<=0;current_error<=0;residual<=0;
            stat_sync<=0;dgain_sync<=0;O_stat_request<=0;O_stat_skip<=0;
            O_dgain_request<=0;O_dgain<=8;O_dgain_epoch<=0;
            O_targets_valid<=0;O_ae<=1991;O_ag<=112;O_target_sum<=0;O_target_valid<=0;
        end else begin
            stat_sync<={stat_sync[0],I_stat_toggle_async};
            dgain_sync<={dgain_sync[0],I_dgain_ack_async};
            enable_d<=I_auto_enable;O_targets_valid<=0;
            if(!I_auto_enable)begin
                alu_part<=0;alu_carry<=0;shift_bit<=0;lower_zero<=1;
                state<=ST_OFF;O_target_valid<=0;baseline_needed<=1;
                ready_count<=0;confirm_count<=0;
            end else if(!enable_d)begin
                alu_part<=0;alu_carry<=0;shift_bit<=0;lower_zero<=1;
                O_ae<=I_seed_ae;O_ag<=I_seed_ag;
                O_target_valid<=0;baseline_needed<=1;ready_count<=0;confirm_count<=0;
                next_skip<=SETTLE_FRAMES;state<=ST_SETTLE;
            end else begin
                if(alu_state)begin
                    alu_carry<=word_result[13];shift_bit<=residual_word[12];
                    lower_zero<=(alu_part==0 ? 1'b1 : lower_zero) && (word_result[12:0]==0);
                    alu_part<=(alu_part==2) ? 2'd0 : alu_part+2'd1;
                    if(state==ST_SAVE_ERROR)begin
                        case(alu_part)
                            0:current_error[12:0]<=word_result[12:0];
                            1:current_error[25:13]<=word_result[12:0];
                            default:current_error[37:26]<=word_result[11:0];
                        endcase
                    end else if(state!=ST_PICK)begin
                        case(alu_part)
                            0:residual[12:0]<=word_result[12:0];
                            1:residual[25:13]<=word_result[12:0];
                            default:residual[38:26]<=word_result[12:0];
                        endcase
                    end
                end else alu_part<=0;
                if(!alu_state || alu_part==2)case(state)
                ST_SETTLE:if(mailboxes_idle)begin
                    if(ready_count==3)begin
                        O_stat_skip<=next_skip;O_stat_request<=~O_stat_request;
                        ready_count<=0;state<=ST_SAMPLE;
                    end else ready_count<=ready_count+3'd1;
                end else ready_count<=0;
                ST_SAMPLE:if(stat_sync[1]==O_stat_request)state<=ST_CAPTURE;
                ST_CAPTURE:begin
                    next_skip<=0;state<=ST_SETTLE;
                    if(!I_stat_valid_async || I_stat_gain_async>16)begin
                        confirm_count<=0;
                        if(baseline_needed)next_skip<=SETTLE_FRAMES;
                    end else if(baseline_needed)begin
                        epoch<=I_stat_epoch_async;
                        saved_gain<=I_stat_gain_async;current_gain<=I_stat_gain_async;
                        sample_sum<=I_stat_sum_async;O_target_sum<=I_stat_sum_async;
                        residual<=0;base_coefficient<=coefficient(I_stat_gain_async);
                        base_steps<=7;confirm_count<=0;state<=ST_MULT;
                    end else if(I_stat_epoch_async!=epoch)begin
                        baseline_needed<=1;O_target_valid<=0;
                        next_skip<=SETTLE_FRAMES;confirm_count<=0;
                    end else if(I_stat_gain_async!=saved_gain)confirm_count<=0;
                    else begin
                        sample_sum<=I_stat_sum_async;residual<=0;
                        base_coefficient<=coefficient(current_gain);base_steps<=7;
                        scan_gain<=current_gain;state<=ST_MULT;
                    end
                end
                ST_MULT:begin
                    
                    base_coefficient<={base_coefficient[5:0],1'b0};
                    base_steps<=base_steps-3'd1;
                    if(base_steps==1)begin
                        if(baseline_needed)begin
                            target_product<={word_result[11:0],residual[25:0]};baseline_needed<=0;
                            O_target_valid<=1;state<=ST_SETTLE;
                        end else state<=ST_DIFF;
                    end
                end
                ST_DIFF:begin state<=ST_SAVE_ERROR;end
                ST_SAVE_ERROR:begin
                    search_down<=!residual[38];
                    if(residual==0 || (!residual[38] && current_gain==17) ||
                       (residual[38] && current_gain==16))begin
                        confirm_count<=0;state<=ST_SETTLE;
                    end else state<=ST_STEP;
                end
                ST_STEP:begin
                    edge_shift<=next_shift;
                    scan_gain<=adjacent(scan_gain,search_down);state<=ST_TEST;
                end
                ST_TEST:begin
                    if(residual==0)state<=ST_ABS;
                    else if(residual[38]==search_down)state<=ST_PICK;
                    else if((search_down && scan_gain==17) ||
                            (!search_down && scan_gain==16))state<=ST_ABS;
                    else state<=ST_STEP;
                end
                ST_PICK:state<=restore_previous?ST_RESTORE:ST_ABS;
                ST_RESTORE:begin
                    scan_gain<=previous_gain;state<=ST_ABS;
                end
                ST_ABS:begin state<=ST_IMPROVE;end
                ST_IMPROVE:begin state<=ST_DEADBAND;end
                ST_DEADBAND:begin state<=ST_DECIDE;end
                ST_DECIDE:begin
                    state<=ST_SETTLE;
                    if(!residual[38] && residual!=0 && scan_gain!=current_gain)begin
                        if(CONFIRM_SAMPLES==1 ||
                           (pending_gain==proposed_gain && confirm_count>=CONFIRM_LAST))begin
                            confirm_count<=0;O_dgain<=proposed_gain;O_dgain_epoch<=epoch;
                            O_dgain_request<=~O_dgain_request;
                            current_gain<=proposed_gain;state<=ST_DIGITAL;
                        end else begin
                            pending_gain<=proposed_gain;
                            confirm_count<=(pending_gain==proposed_gain)?confirm_count+8'd1:8'd1;
                        end
                    end else confirm_count<=0;
                end
                ST_DIGITAL:if(dgain_sync[1]==O_dgain_request)begin next_skip<=0;state<=ST_SETTLE;end
                default:state<=ST_SETTLE;
            endcase
            end
        end
    end
endmodule

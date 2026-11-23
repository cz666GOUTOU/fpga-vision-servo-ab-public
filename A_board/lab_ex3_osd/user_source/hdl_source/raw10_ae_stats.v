`timescale 1ns/1ps
// Requested complete pre-digital-gain RAW frame; no pixel-path registers.
// I_gain_active carries the saved manual restore tag, stable for this session.
// Request metadata and response payload remain held until acknowledgement.
module raw10_ae_stats #(parameter integer FRAME_PIXELS = 921600)(
    input wire I_clk, input wire I_rst_n, input wire I_auto_enable,
    input wire I_request_async, input wire [2:0] I_skip_async,
    input wire [4:0] I_gain_active, input wire [7:0] I_epoch,
    input wire I_tvalid, input wire I_tuser, input wire [39:0] I_tdata,
    output reg [31:0] O_frame_sum, output reg O_frame_toggle,
    output reg O_frame_valid, output reg [4:0] O_frame_gain,
    output reg [7:0] O_frame_epoch
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync;
    reg pending, collecting, frame_bad;
    reg [2:0] skip;
    reg [31:0] frame_sum;
    reg [20:0] frame_count;
    reg [4:0] frame_gain;
    reg [7:0] frame_epoch;
    wire [11:0] p0 = {2'b0,I_tdata[39:30]};
    wire [11:0] p1 = {2'b0,I_tdata[29:20]};
    wire [11:0] p2 = {2'b0,I_tdata[19:10]};
    wire [11:0] p3 = {2'b0,I_tdata[9:0]};
    wire [11:0] beat_sum = p0+p1+p2+p3;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            request_sync<=0; pending<=0; collecting<=0; frame_bad<=0;
            skip<=0; frame_sum<=0; frame_count<=0; frame_gain<=0; frame_epoch<=0;
            O_frame_sum<=0; O_frame_toggle<=0; O_frame_valid<=0;
            O_frame_gain<=0; O_frame_epoch<=0;
        end else begin
            request_sync<={request_sync[0],I_request_async};
            if(!pending && (request_sync[1] != O_frame_toggle)) begin
                pending<=1; collecting<=0; skip<=I_skip_async;
            end else if(pending) begin
                if(collecting && !(I_tvalid && I_tuser) && I_gain_active != frame_gain)
                    frame_bad<=1;
                if(!I_auto_enable || (collecting && frame_epoch != I_epoch)) begin
                    // Drain cancellation so an old response cannot stall re-entry.
                    O_frame_toggle<=request_sync[1]; O_frame_valid<=0;
                    pending<=0; collecting<=0;
                end else if(I_tvalid) begin
                    if(I_tuser) begin
                        if(collecting && !frame_bad && frame_count == FRAME_PIXELS) begin
                            O_frame_sum<=frame_sum; O_frame_gain<=frame_gain;
                            O_frame_epoch<=frame_epoch; O_frame_valid<=1;
                            O_frame_toggle<=request_sync[1]; pending<=0; collecting<=0;
                        end else if(skip != 0) skip<=skip-3'd1;
                        else begin
                            // Reject partial/oversized frames; restart at a qualified SOF.
                            collecting<=1; frame_bad<=0;
                            frame_sum<=beat_sum; frame_count<=21'd4;
                            frame_gain<=I_gain_active; frame_epoch<=I_epoch;
                        end
                    end else if(collecting) begin
                        if(frame_count >= FRAME_PIXELS) frame_bad<=1;
                        else begin
                            frame_sum<=frame_sum+beat_sum;
                            frame_count<=frame_count+21'd4;
                        end
                    end
                end
            end
        end
    end
endmodule

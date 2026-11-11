// CSI-domain UART base selection, and frame-acknowledged AUTO commands.
// Manual tags 0..16 remain 1..4x; AUTO-only 17..28 adds 0.25..0.9375x.
// Tags cross the same frame-boundary/epoch mailbox; startup level 8 is 2x.
module raw10_auto_gain (
    input wire I_clk,I_rst_n,
    input wire I_config_valid, input wire [4:0] I_config_gain,
    input wire I_auto_enable,I_tuser,I_tvalid,
    input wire I_cmd_toggle_async,
    input wire [4:0] I_cmd_gain_async, input wire [7:0] I_cmd_epoch_async,
    output wire [4:0] O_gain_sel, output reg [4:0] O_gain_active,
    output wire [4:0] O_gain_saved,
    output reg [7:0] O_epoch, output reg O_cmd_ack
);
    reg auto_d;
    reg [4:0] gain_req,gain_saved;
    (* ASYNC_REG="TRUE" *) reg [1:0] cmd_sync;
    reg pending,armed;
    reg [4:0] cmd_gain;
    reg [7:0] cmd_epoch;
    wire apply_cmd=pending && armed && I_auto_enable && auto_d &&
                   cmd_epoch==O_epoch && I_tuser && I_tvalid;
    assign O_gain_sel=gain_req;
    assign O_gain_saved=gain_saved;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            auto_d<=0;gain_req<=8;gain_saved<=8;O_epoch<=0;O_gain_active<=8;
        end else begin
            auto_d<=I_auto_enable;
            if(I_tuser) O_gain_active<=O_gain_sel;
            if(I_auto_enable && !auto_d) begin gain_saved<=gain_req;O_epoch<=O_epoch+8'd1;end
            else if(!I_auto_enable && auto_d) gain_req<=gain_saved;
            else if(I_auto_enable) begin
                if(pending && !armed && cmd_epoch==O_epoch && cmd_gain<=28) gain_req<=cmd_gain;
            end else if(I_config_valid && I_config_gain<=16) gain_req<=I_config_gain;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            cmd_sync<=0;pending<=0;armed<=0;cmd_gain<=0;cmd_epoch<=0;O_cmd_ack<=0;
        end else begin
            cmd_sync<={cmd_sync[0],I_cmd_toggle_async};
            if(!pending && cmd_sync[1]!=O_cmd_ack) begin
                cmd_gain<=I_cmd_gain_async;cmd_epoch<=I_cmd_epoch_async;pending<=1;armed<=0;
            end else if(pending) begin
                if(!I_auto_enable || cmd_epoch!=O_epoch || cmd_gain>28 || apply_cmd) begin
                    O_cmd_ack<=cmd_sync[1];pending<=0;armed<=0;
                end else if(auto_d && !armed) armed<=1;
            end
        end
    end
endmodule

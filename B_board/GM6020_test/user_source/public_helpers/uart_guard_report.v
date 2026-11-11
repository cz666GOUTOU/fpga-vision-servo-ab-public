// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module uart_guard_report #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst_n,home_request,status_enable,status_valid,
    input wire [7:0] status_data,
    output wire tx,
    output reg busy
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer BW=BIT_TICKS>1?$clog2(BIT_TICKS):1;
    reg [BW-1:0] ticks;
    reg [9:0] shift;
    reg [3:0] bit_index;
    reg second_byte,home_pending,status_pending;
    reg [7:0] payload,pending_status;
    assign tx=busy?shift[0]:1'b1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;ticks<=0;shift<=10'h3ff;bit_index<=0;second_byte<=0;
            home_pending<=0;status_pending<=0;payload<=0;pending_status<=0;
        end else begin
            if(home_request && busy) home_pending<=1;
            if(!status_enable) status_pending<=0;
            else if(status_valid)begin status_pending<=1;pending_status<=status_data;end
            if(!busy) begin
                if(home_request || home_pending) begin
                    busy<=1;ticks<=0;shift<={1'b1,8'h30,1'b0};
                    bit_index<=0;second_byte<=0;payload<=8'h00;home_pending<=0;
                end else if(status_enable && (status_valid || status_pending)) begin
                    busy<=1;ticks<=0;shift<={1'b1,8'h30,1'b0};
                    bit_index<=0;second_byte<=0;
                    payload<=status_valid?status_data:pending_status;status_pending<=0;
                end
            end else if(ticks==BIT_TICKS-1) begin
                ticks<=0;
                if(bit_index==9) begin
                    if(!second_byte) begin shift<={1'b1,payload,1'b0};bit_index<=0;second_byte<=1;end
                    else begin busy<=0;shift<=10'h3ff;end
                end else begin shift<={1'b1,shift[9:1]};bit_index<=bit_index+1'b1;end
            end else ticks<=ticks+1'b1;
        end
    end
`ifndef SYNTHESIS
    initial if(BAUD<1 || BIT_TICKS<2) $fatal(1,"UART report clock/baud invalid");
`endif
endmodule

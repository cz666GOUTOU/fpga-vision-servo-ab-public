// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module uart_home_report #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst_n,request,
    output wire tx,busy
);
    uart_guard_report #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) report(
        .clk(clk),.rst_n(rst_n),.home_request(request),
        .status_enable(1'b0),.status_valid(1'b0),.status_data(8'd0),.tx(tx),.busy(busy));
endmodule

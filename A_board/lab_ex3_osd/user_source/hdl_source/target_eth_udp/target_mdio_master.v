// Clause 22, 32-bit preamble, <=2.5 MHz MDC, read turnaround ACK checked.
module target_mdio_master #(
    parameter integer HALF_PERIOD=10
)(
    input clk, input reset_n, input start, input read_op,
    input [4:0] phy_addr, reg_addr, input [15:0] write_data,
    output reg busy, output reg done, output reg error,
    output reg [15:0] read_data, output reg mdc, inout mdio
);
    reg [63:0] frame;
    reg [6:0] bit_index;
    reg [31:0] divider;
    reg is_read;
    wire drive=busy && !(is_read && bit_index>=46);
    assign mdio=drive ? frame[63-bit_index] : 1'bz;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            frame<=0; bit_index<=0; divider<=0; is_read<=0;
            busy<=0; done<=0; error<=0; read_data<=0; mdc<=0;
        end else begin
            done<=0;
            if(!busy) begin
                mdc<=0; divider<=0;
                if(start) begin
                    frame<={32'hffffffff,2'b01,(read_op ? 2'b10 : 2'b01),
                            phy_addr,reg_addr,2'b10,write_data};
                    bit_index<=0; is_read<=read_op; busy<=1; error<=0; read_data<=0;
                end
            end else if(divider==HALF_PERIOD-1) begin
                divider<=0; mdc<=!mdc;
                if(!mdc) begin
                    if(is_read && bit_index==47 && mdio!==1'b0) error<=1;
                    if(is_read && bit_index>=48) read_data<={read_data[14:0],mdio};
                end else if(bit_index==63) begin busy<=0; done<=1; end
                else bit_index<=bit_index+1'b1;
            end else divider<=divider+1'b1;
        end
    end
endmodule

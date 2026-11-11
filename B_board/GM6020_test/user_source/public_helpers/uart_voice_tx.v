// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module uart_voice_tx #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst_n,valid,
    input wire [7:0] payload,
    output wire ready,tx,
    output reg busy,
    output wire frame_done
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer TW=BIT_TICKS>1?$clog2(BIT_TICKS):1;
    reg [TW-1:0] ticks;
    reg [9:0] shift;
    reg [3:0] bit_index;
    reg [2:0] byte_index;
    reg [7:0] message;
    assign ready=!busy;
    assign tx=busy?shift[0]:1'b1;
    // Assert during the final stop-bit clock, sampled when busy drops.
    assign frame_done=busy && ticks==BIT_TICKS-1 && bit_index==9 && byte_index==4;
    function [7:0] frame_byte;
        input [2:0] index;
        input [7:0] code;
        begin case(index)
            0,4:frame_byte=8'haa;
            1,3:frame_byte=8'h55;
            2:frame_byte=code;
            default:frame_byte=8'hff;
        endcase end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            busy<=0;ticks<=0;shift<=10'h3ff;bit_index<=0;byte_index<=0;message<=0;
        end else if(!busy)begin
            if(valid)begin
                busy<=1;ticks<=0;shift<={1'b1,8'haa,1'b0};
                bit_index<=0;byte_index<=0;message<=payload;
            end
        end else if(ticks==BIT_TICKS-1)begin
            ticks<=0;
            if(bit_index==9)begin
                if(byte_index==4)begin busy<=0;shift<=10'h3ff;end
                else begin
                    byte_index<=byte_index+1'b1;bit_index<=0;
                    shift<={1'b1,frame_byte(byte_index+1'b1,message),1'b0};
                end
            end else begin shift<={1'b1,shift[9:1]};bit_index<=bit_index+1'b1;end
        end else ticks<=ticks+1'b1;
    end
`ifndef SYNTHESIS
    initial if(BAUD<1 || BIT_TICKS<2)$fatal(1,"Speech UART clock/baud invalid");
`endif
endmodule

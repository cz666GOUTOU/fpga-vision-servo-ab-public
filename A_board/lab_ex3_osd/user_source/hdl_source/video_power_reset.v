// Configuration-time register initialization is supported by TD SWUG106,
// DFF initialization section. Verify initialization mapping in implementation.
module video_power_reset #(
    parameter integer START_CYCLES=50000,
    parameter integer LOCK_CYCLES=1024
)(input clk, input pll_locked, output pll_reset, output reset_n);
    localparam integer SW=(START_CYCLES<2)?1:$clog2(START_CYCLES+1);
    localparam integer LW=(LOCK_CYCLES<2)?1:$clog2(LOCK_CYCLES+1);
    reg [SW-1:0] startup=0;
    reg [LW-1:0] stable=0;
    (* ASYNC_REG="TRUE" *) reg [1:0] lock_sync=0;
    assign pll_reset=(startup<START_CYCLES);
    wire qualified=!pll_reset && pll_locked;
    assign reset_n=qualified && (stable==LOCK_CYCLES);
    always @(posedge clk)
        if(startup<START_CYCLES) startup<=startup+1'b1;
    always @(posedge clk or negedge qualified) begin
        if(!qualified) begin lock_sync<=0;stable<=0;end
        else begin
            lock_sync<={lock_sync[0],1'b1};
            if(!lock_sync[1]) stable<=0;
            else if(stable<LOCK_CYCLES) stable<=stable+1'b1;
        end
    end
endmodule

// Asynchronous assertion, synchronous release. rst_n must reset BOTH FIFO sides.
module target_reset_sync(input clk, input rst_n, output reset_n);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_ff;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) sync_ff <= 2'b00;
        else sync_ff <= {sync_ff[0], 1'b1};
    assign reset_n = sync_ff[1];
endmodule

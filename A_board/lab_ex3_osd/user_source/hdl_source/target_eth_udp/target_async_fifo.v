// Small distributed-memory FIFO. ADDR_BITS >= 2; both resets share a source.
// Gray buses require physical skew/max-delay constraints when integrated.
module target_async_fifo #(
    parameter WIDTH = 114, parameter ADDR_BITS = 4,
    parameter RAM_STYLE = "auto"
)(
    input wr_clk, input wr_reset_n, input wr_en,
    input [WIDTH-1:0] wr_data, output reg full,
    input rd_clk, input rd_reset_n, input rd_en,
    output [WIDTH-1:0] rd_data, output reg empty
);
    // Select DRAM only for shallow result queues; packet FIFOs retain AUTO.
    // The asynchronous read and all Gray-pointer/reset logic stay unchanged.
    (* ram_style = RAM_STYLE *) reg [WIDTH-1:0] mem [0:(1<<ADDR_BITS)-1];
    reg [ADDR_BITS:0] wr_bin, wr_gray, rd_bin, rd_gray;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_BITS:0] rq1, rq2, wq1, wq2;
    wire [ADDR_BITS:0] wn = wr_bin + {{ADDR_BITS{1'b0}}, (wr_en && !full)};
    wire [ADDR_BITS:0] rn = rd_bin + {{ADDR_BITS{1'b0}}, (rd_en && !empty)};
    wire [ADDR_BITS:0] wg = (wn >> 1) ^ wn;
    wire [ADDR_BITS:0] rg = (rn >> 1) ^ rn;
    assign rd_data = mem[rd_bin[ADDR_BITS-1:0]];
    always @(posedge wr_clk or negedge wr_reset_n) begin
        if (!wr_reset_n) begin
            wr_bin <= 0; wr_gray <= 0; full <= 0; rq1 <= 0; rq2 <= 0;
        end else begin
            rq1 <= rd_gray; rq2 <= rq1;
            if (wr_en && !full) mem[wr_bin[ADDR_BITS-1:0]] <= wr_data;
            wr_bin <= wn; wr_gray <= wg;
            full <= (wg == {~rq2[ADDR_BITS:ADDR_BITS-1], rq2[ADDR_BITS-2:0]});
        end
    end
    always @(posedge rd_clk or negedge rd_reset_n) begin
        if (!rd_reset_n) begin
            rd_bin <= 0; rd_gray <= 0; empty <= 1; wq1 <= 0; wq2 <= 0;
        end else begin
            wq1 <= wr_gray; wq2 <= wq1;
            rd_bin <= rn; rd_gray <= rg; empty <= (rg == wq2);
        end
    end
endmodule

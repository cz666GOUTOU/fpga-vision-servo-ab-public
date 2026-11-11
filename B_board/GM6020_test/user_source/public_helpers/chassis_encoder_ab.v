// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module chassis_encoder_ab #(
    parameter integer FILTER_CYCLES=0
)(
    input wire clk,rst_n,a,b,
    output reg signed [31:0] count,
    output reg step_valid,step_positive,invalid_transition
);
    (* async_reg="true" *) reg [1:0] ab_meta,ab_sync;
    wire [1:0] qualified_ab;
    generate if(FILTER_CYCLES>1)begin:input_filter
        localparam integer FW=$clog2(FILTER_CYCLES);
        reg [FW-1:0] stable_a,stable_b;
        reg [1:0] filtered;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin stable_a<=0;stable_b<=0;filtered<=0;end
            else begin
                if(ab_sync[1]==filtered[1])stable_a<=0;
                else if(stable_a==FILTER_CYCLES-1)begin filtered[1]<=ab_sync[1];stable_a<=0;end
                else stable_a<=stable_a+1'b1;
                if(ab_sync[0]==filtered[0])stable_b<=0;
                else if(stable_b==FILTER_CYCLES-1)begin filtered[0]<=ab_sync[0];stable_b<=0;end
                else stable_b<=stable_b+1'b1;
            end
        end
        assign qualified_ab=filtered;
    end else begin:unfiltered
        assign qualified_ab=ab_sync;
    end endgenerate
    localparam integer WARM_CYCLES=FILTER_CYCLES>1?FILTER_CYCLES+4:4;
    localparam integer WW=$clog2(WARM_CYCLES+1);
    reg [1:0] previous;
    reg [WW-1:0] warmup;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin ab_meta<=0;ab_sync<=0;end
        else begin ab_meta<={a,b};ab_sync<=ab_meta;end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            previous<=0;warmup<=0;count<=0;step_valid<=0;step_positive<=0;invalid_transition<=0;
        end else begin
            step_valid<=0;invalid_transition<=0;
            previous<=qualified_ab;
            if(warmup<WARM_CYCLES)warmup<=warmup+1'b1;
            else case({previous,qualified_ab})
                4'b0010,4'b1011,4'b1101,4'b0100:begin count<=count+32'sd1;step_valid<=1;step_positive<=1;end
                4'b0001,4'b0111,4'b1110,4'b1000:begin count<=count-32'sd1;step_valid<=1;step_positive<=0;end
                4'b0011,4'b1100,4'b0110,4'b1001:invalid_transition<=1;
                default:begin end
            endcase
        end
    end
endmodule

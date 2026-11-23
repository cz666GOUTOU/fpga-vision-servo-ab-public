// Iterative unsigned division: 64 cycles, no combinational divider chain.
module vision_u64_div32(
    input wire clk,rst_n,start,
    input wire [63:0] numerator,
    input wire [31:0] denominator,
    output reg busy,done,
    output reg [63:0] quotient
);
    reg [63:0] shifting;
    reg [31:0] remainder;
    reg [31:0] divisor;
    reg [6:0] remaining;
    always @(posedge clk or negedge rst_n) begin: division
        reg [32:0] trial;
        reg [33:0] difference;
        if(!rst_n) begin busy<=0;done<=0;quotient<=0;shifting<=0;remainder<=0;divisor<=0;remaining<=0;end
        else begin
            done<=0;
            if(start && !busy) begin
                shifting<=numerator;remainder<=0;divisor<=denominator;
                remaining<=64;busy<=1;
            end else if(busy) begin
                trial={remainder,shifting[63]};
                difference={1'b0,trial}-{2'b0,divisor};
                if(!difference[33]) begin remainder<=difference[31:0];shifting<={shifting[62:0],1'b1};end
                else begin remainder<=trial[31:0];shifting<={shifting[62:0],1'b0};end
                remaining<=remaining-1'b1;
                if(remaining==1) begin quotient<={shifting[62:0],!difference[33]};done<=1;busy<=0;end
            end
        end
    end
endmodule

// Four RGB888 pixels per beat. Serial levels 0..16 = 0.5..2x, startup 1x.
// DATA/VALID/USER/LAST retain one clock boundary, with four pixels every clock.
module rgb_contrast (
    input wire I_clk,I_rst_n,I_config_valid, input wire [4:0] I_level,
    input wire [95:0] I_tdata, input wire I_tvalid,I_tuser,I_tlast,
    output reg [95:0] O_tdata, output reg O_tvalid,O_tuser,O_tlast
);
    reg [4:0] requested_level,active_level;
    wire [4:0] pixel_level=I_tuser?requested_level:active_level;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin requested_level<=5'd8;active_level<=5'd8;end
        else begin
            if(I_config_valid && I_level<=16) requested_level<=I_level;
            // A simultaneous configuration applies at the NEXT frame start.
            if(I_tuser) active_level<=requested_level;
        end
    end

    // q=floor(m*(8+index)/8), m=value[6:0]. Low levels use q/2;
    // high levels use q. Subtracting 128 from an input with bit7=0
    // contributes an exact integer offset, so no rounding bit is lost.
    wire [7:0] negative_offset=pixel_level[3]?
        (8'd0-{1'b0,pixel_level[2:0],4'b0}):
        (8'd64-{2'b00,pixel_level[2:0],3'b0});
    reg [7:0] offset_q;
    reg high_q,double_q;
    reg [11:0] upper_q;
    reg output_initialized;
    wire [95:0] table_values;
    integer channel;
    integer tag;
    // RAM and associated data tags have no reset. The existing output reset
    // is implemented by output_initialized, including the first release edge.
    always @(posedge I_clk) begin
        offset_q<=negative_offset;
        high_q<=pixel_level[3];
        double_q<=pixel_level[4];
        for(tag=0;tag<12;tag=tag+1)
            upper_q[tag]<=I_tdata[tag*8+7];
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            output_initialized<=1'b0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end else begin
            output_initialized<=1'b1;
            O_tvalid<=I_tvalid;O_tuser<=I_tuser;O_tlast<=I_tlast;
        end
    end

    genvar pair;
    generate for(pair=0;pair<6;pair=pair+1) begin: g_lut_pair
        rgb_contrast_lut_pair table_pair (
            .clk(I_clk),
            .address_a({pixel_level[2:0],I_tdata[pair*16+:7]}),
            .address_b({pixel_level[2:0],I_tdata[pair*16+8+:7]}),
            .value_a(table_values[pair*16+:8]),
            .value_b(table_values[pair*16+8+:8])
        );
    end endgenerate

    function [7:0] finish_contrast;
        input [7:0] q;
        input upper,high_level,double_level;
        input [7:0] low_offset;
        reg [7:0] increment;
        reg signed [9:0] result,offset;
        begin
            if(double_level) begin
                // Level16 uses ROM index0, hence q=value[6:0].
                // clamp(2*value-128) is exact, including 64 and 192.
                if(upper==q[6]) finish_contrast={8{upper}};
                else finish_contrast={upper,q[5:0],1'b0};
            end else begin
                increment=high_level?q:{1'b0,q[7:1]};
                offset=upper?10'sd128:$signed({{2{low_offset[7]}},low_offset});
                result=$signed({2'b00,increment})+offset;
                if(result[9]) finish_contrast=8'd0;
                else if(result[8]) finish_contrast=8'd255;
                else finish_contrast=result[7:0];
            end
        end
    endfunction
    // The synchronous table read reuses the old output clock boundary.
    // Only the small offset/clamp remains after the ROM; no extra video beat.
    always @* begin
        O_tdata=96'd0;
        if(output_initialized)
            for(channel=0;channel<12;channel=channel+1)
                O_tdata[channel*8+:8]=finish_contrast(
                    table_values[channel*8+:8],upper_q[channel],high_q,double_q,offset_q);
    end
endmodule

// One physical dual-read ROM per two independent channels. Initialization is
// compile-time constant; there is no runtime multiplier or external mem file.
module rgb_contrast_lut_pair (
    input wire clk,
    input wire [9:0] address_a,address_b,
    output reg [7:0] value_a,value_b
);
    (* ram_style="bram" *) reg [7:0] values[0:1023];
    integer entry;
    initial begin
        for(entry=0;entry<1024;entry=entry+1)
            values[entry]=((entry%128)*(8+entry/128))>>3;
    end
    always @(posedge clk) value_a<=values[address_a];
    always @(posedge clk) value_b<=values[address_b];
endmodule

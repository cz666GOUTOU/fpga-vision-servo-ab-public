// Manual 0..16 is unchanged. AUTO-only 17..28 adds 0.25..0.9375x.
// Reuse the same two ROMs; attenuation is a shift BEFORE saturation.
// DATA/VALID/USER/LAST retain one clock boundary and four pixels per beat.
module raw10_dgain (
    input wire I_clk, I_rst_n, input wire [4:0] I_gain_sel,
    input wire I_tuser, I_tlast, I_tvalid, input wire [39:0] I_tdata,
    output reg O_tuser, O_tlast, O_tvalid, output reg [39:0] O_tdata
);
    reg [4:0] gain_sel_active;
    wire [4:0] gain_sel_use=I_tuser?I_gain_sel:gain_sel_active;
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) gain_sel_active<=5'd8;
        else if(I_tuser) gain_sel_active<=I_gain_sel;

    // p=256*u+m; q=floor(m*(8+index)/4). Two dual-read ROMs
    // reuse the original output register boundary. Illegal ranks retain 2x.
    wire dim_gain=gain_sel_use>=17 && gain_sel_use<=28;
    wire [4:0] dim_rank=gain_sel_use-5'd17;
    wire [2:0] fraction_index=dim_gain ?
        (gain_sel_use<21 ? {dim_rank[1:0],1'b0} : dim_rank[2:0]-3'd4) :
        (gain_sel_use[4]?3'd0:gain_sel_use[2:0]);
    wire [39:0] table_values;
    reg [23:0] upper_q;
    reg [1:0] shift_q;
    reg double_q,output_initialized;
    function [5:0] upper_product;
        input [4:0] address;
        begin case(address)
            5'd0:upper_product=6'd0;
            5'd1:upper_product=6'd8;
            5'd2:upper_product=6'd16;
            5'd3:upper_product=6'd24;
            5'd4:upper_product=6'd0;
            5'd5:upper_product=6'd9;
            5'd6:upper_product=6'd18;
            5'd7:upper_product=6'd27;
            5'd8:upper_product=6'd0;
            5'd9:upper_product=6'd10;
            5'd10:upper_product=6'd20;
            5'd11:upper_product=6'd30;
            5'd12:upper_product=6'd0;
            5'd13:upper_product=6'd11;
            5'd14:upper_product=6'd22;
            5'd15:upper_product=6'd33;
            5'd16:upper_product=6'd0;
            5'd17:upper_product=6'd12;
            5'd18:upper_product=6'd24;
            5'd19:upper_product=6'd36;
            5'd20:upper_product=6'd0;
            5'd21:upper_product=6'd13;
            5'd22:upper_product=6'd26;
            5'd23:upper_product=6'd39;
            5'd24:upper_product=6'd0;
            5'd25:upper_product=6'd14;
            5'd26:upper_product=6'd28;
            5'd27:upper_product=6'd42;
            5'd28:upper_product=6'd0;
            5'd29:upper_product=6'd15;
            5'd30:upper_product=6'd30;
            5'd31:upper_product=6'd45;
            default:upper_product=6'bxxxxxx;
        endcase end
    endfunction
    integer tag;
    always @(posedge I_clk) begin
        shift_q<=dim_gain ? (gain_sel_use<21 ? 2'd3 : 2'd2) :
            (gain_sel_use<8 ? 2'd1 : 2'd0);
        double_q<=gain_sel_use==16;
        for(tag=0;tag<4;tag=tag+1)
            upper_q[tag*6+:6]<=upper_product({fraction_index,I_tdata[tag*10+8+:2]});
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin output_initialized<=0;O_tuser<=0;O_tlast<=0;O_tvalid<=0;end
        else begin output_initialized<=1;O_tuser<=I_tuser;O_tlast<=I_tlast;O_tvalid<=I_tvalid;end
    end
    genvar pair;
    generate for(pair=0;pair<2;pair=pair+1) begin:g_lut_pair
        raw10_dgain_lut_pair table_pair(
            .clk(I_clk),.address_a({fraction_index,I_tdata[pair*20+:8]}),
            .address_b({fraction_index,I_tdata[pair*20+10+:8]}),
            .value_a(table_values[pair*20+:10]),.value_b(table_values[pair*20+10+:10]));
    end endgenerate
    function [9:0] finish_gain;
        input [9:0] q;input [5:0] upper;input [1:0] attenuation;input double_gain;
        reg [11:0] total,result;
        begin
            total={2'b00,q}+{upper,6'b000000};
            result=double_gain?{total[10:0],1'b0}:
                (total>>attenuation);
            finish_gain=(|result[11:10])?10'h3ff:result[9:0];
        end
    endfunction
    integer channel;
    always @* begin
        O_tdata=40'd0;
        if(output_initialized)
            for(channel=0;channel<4;channel=channel+1)
                O_tdata[channel*10+:10]=finish_gain(table_values[channel*10+:10],
                    upper_q[channel*6+:6],shift_q,double_q);
    end
endmodule

// Compile-time initialization only; no runtime multiplier or external asset.
module raw10_dgain_lut_pair (
    input wire clk,input wire [10:0] address_a,address_b,
    output reg [9:0] value_a,value_b
);
    (* ram_style="bram" *) reg [9:0] values[0:2047];
    integer entry;
    initial for(entry=0;entry<2048;entry=entry+1)
        values[entry]=((entry%256)*(8+entry/256))>>2;
    always @(posedge clk) value_a<=values[address_a];
    always @(posedge clk) value_b<=values[address_b];
endmodule

// GMII includes preamble/SFD/FCS; 125 MHz, full duplex, fixed 24-byte UDP payload.
// tx_done is in tx_clk; overflow and result_ready are in result_clk.
module target_udp_tx_core #(
    parameter [47:0] SRC_MAC = 48'h020000000001,
    parameter [47:0] DST_MAC = 48'h020000000002,
    parameter [31:0] SRC_IP = 32'hc0a80a01,
    parameter [31:0] DST_IP = 32'hc0a80a02,
    parameter [15:0] SRC_PORT = 16'd5000, DST_PORT = 16'd5000,
    parameter FIFO_ADDR_BITS = 4
)(
    input rst_n, input result_clk, input tx_clk, input link_ready,
    input result_update, input target_valid, input distance_valid, input region_valid,
    input [15:0] target_id, center_x, center_y, input [31:0] distance,
    output result_ready, output result_link_ready, output reg overflow, output reg [31:0] dropped_results,
    output reg [7:0] gmii_txd, output reg gmii_tx_en,
    output gmii_tx_er, output reg tx_done
);
    wire rr, tr;
    target_reset_sync r0(result_clk, rst_n, rr);
    target_reset_sync r1(tx_clk, rst_n, tr);
    (* ASYNC_REG = "TRUE" *) reg [1:0] lr, lt;
    reg [31:0] sequence_number;
    wire full, empty;
    wire [114:0] record;
    reg [2:0] state;
    wire pop = !empty && (state == 0 || !lt[1]);
    assign result_ready = rr && lr[1] && !full;
    assign result_link_ready = rr && lr[1]; // same-domain link status, independent of FIFO fullness
    assign gmii_tx_er = 1'b0;
    always @(posedge result_clk or negedge rr) begin
        if (!rr) begin
            lr <= 0; sequence_number <= 0; overflow <= 0; dropped_results <= 0;
        end else begin
            lr <= {lr[0],link_ready}; overflow <= 0;
            if (result_update) begin
                sequence_number <= sequence_number + 1'b1;
                if (!result_ready) begin
                    overflow <= 1; dropped_results <= dropped_results + 1'b1;
                end
            end
        end
    end
    target_async_fifo #(.WIDTH(115), .ADDR_BITS(FIFO_ADDR_BITS)) q (
        .wr_clk(result_clk), .wr_reset_n(rr), .wr_en(result_update && result_ready),
        .wr_data({region_valid, sequence_number, distance_valid, target_valid, target_id,
                  center_x, center_y, distance}), .full(full),
        .rd_clk(tx_clk), .rd_reset_n(tr), .rd_en(pop), .rd_data(record), .empty(empty)
    );
    function [31:0] crc_byte;
        input [31:0] c; input [7:0] d;
        integer k; reg [31:0] v;
        begin
            v = c;
            for (k=0;k<8;k=k+1)
                if (v[0]^d[k]) v=(v>>1)^32'hedb88320; else v=v>>1;
            crc_byte=v;
        end
    endfunction
    function [15:0] checksum;
        input [31:0] sum;
        reg [31:0] s;
        begin s=(sum & 32'hffff)+(sum>>16); s=(s & 32'hffff)+(s>>16);
            checksum=~s[15:0]; end
    endfunction
    localparam [31:0] IP_SUM = 32'h4500 + 32'd52 + 32'h4000 + 32'h4011 +
        {16'b0,SRC_IP[31:16]} + {16'b0,SRC_IP[15:0]} +
        {16'b0,DST_IP[31:16]} + {16'b0,DST_IP[15:0]};
    localparam [15:0] IP_CSUM = checksum(IP_SUM);
    // Compile-time CRC through the invariant 40-byte Ethernet/IP/UDP prefix.
    localparam [319:0] CRC_PREFIX={DST_MAC,SRC_MAC,16'h0800,
        8'h45,8'h00,16'd52,16'd0,16'h4000,8'd64,8'd17,IP_CSUM,
        SRC_IP,DST_IP,SRC_PORT,DST_PORT,16'd32};
    function [31:0] prefix_crc;
        input [319:0] prefix;
        integer n;reg [31:0] v;
        begin
            v=32'hffffffff;
            for(n=0;n<40;n=n+1) v=crc_byte(v,prefix[319-n*8 -:8]);
            prefix_crc=v;
        end
    endfunction
    localparam [31:0] CRC_SEED=prefix_crc(CRC_PREFIX);
    localparam [20:0] UDP_BASE_SUM={5'd0,SRC_IP[31:16]}+{5'd0,SRC_IP[15:0]}+
        {5'd0,DST_IP[31:16]}+{5'd0,DST_IP[15:0]}+21'h11+21'd32+
        {5'd0,SRC_PORT}+{5'd0,DST_PORT}+21'd32;
    reg [191:0] payload;
    reg [20:0] udp_sum;
    reg [31:0] crc;
    reg [15:0] udp_csum;
    reg [7:0] byte_q;
    reg [2:0] crc_bit;
    reg [16:0] udp_fold_q;
    reg [6:0] index;
    reg [3:0] ifg_count;
    function [7:0] frame_byte;
        input [6:0] n;
        begin
            frame_byte=0;
            if (n<6) frame_byte=DST_MAC[47-n*8 -: 8];
            else if(n<12) frame_byte=SRC_MAC[47-(n-6)*8 -: 8];
            else if(n>=42 && n<66) frame_byte=payload[191-(n-42)*8 -: 8];
            else case(n)
                12:frame_byte=8'h08; 13:frame_byte=0;
                14:frame_byte=8'h45; 15:frame_byte=0;
                16:frame_byte=0; 17:frame_byte=8'd52;
                18,19:frame_byte=0;
                20:frame_byte=8'h40; 21:frame_byte=0;
                22:frame_byte=8'd64; 23:frame_byte=8'd17;
                24:frame_byte=IP_CSUM[15:8]; 25:frame_byte=IP_CSUM[7:0];
                26:frame_byte=SRC_IP[31:24]; 27:frame_byte=SRC_IP[23:16];
                28:frame_byte=SRC_IP[15:8]; 29:frame_byte=SRC_IP[7:0];
                30:frame_byte=DST_IP[31:24]; 31:frame_byte=DST_IP[23:16];
                32:frame_byte=DST_IP[15:8]; 33:frame_byte=DST_IP[7:0];
                34:frame_byte=SRC_PORT[15:8]; 35:frame_byte=SRC_PORT[7:0];
                36:frame_byte=DST_PORT[15:8]; 37:frame_byte=DST_PORT[7:0];
                38:frame_byte=0; 39:frame_byte=8'd32;
                40:frame_byte=udp_csum[15:8]; 41:frame_byte=udp_csum[7:0];
                default:frame_byte=0;
            endcase
        end
    endfunction
    // One byte selector serves UDP prep, CRC prep and GMII.
    wire [6:0] byte_index=(state==2) ? (index-7'd8) : index;
    wire [7:0] body_byte=frame_byte(byte_index);
    wire [20:0] next_sum=udp_sum+{5'd0,byte_q,body_byte};
    wire [15:0] folded_sum=udp_fold_q[15:0]+{15'd0,udp_fold_q[16]};
    always @(posedge tx_clk or negedge tr) begin
        if (!tr) begin
            lt<=0;state<=0;payload<=0;udp_sum<=0;udp_csum<=0;
            crc<=32'hffffffff;index<=0;ifg_count<=0;
            byte_q<=0;crc_bit<=0;udp_fold_q<=0;
            gmii_txd<=0;gmii_tx_en<=0;tx_done<=0;
        end else begin
            lt<={lt[0],link_ready};gmii_tx_en<=0;gmii_txd<=0;tx_done<=0;
            if(!lt[1]) begin state<=0;crc<=32'hffffffff;end
            else case(state)
                0:if(!empty) begin
                    payload<={16'ha55a,8'h01,5'b0,record[114],record[81:80],record[113:82],
                              record[79:32],16'b0,record[31:0],32'b0};
                    udp_sum<=UDP_BASE_SUM;index<=42;state<=1;
                end
                1:begin
                    byte_q<=body_byte;
                    if(index[0]) udp_sum<=next_sum;
                    if(index==65)state<=5;else index<=index+1'b1;
                end
                5:begin
                    udp_fold_q<={1'b0,udp_sum[15:0]}+{12'b0,udp_sum[20:16]};state<=6;
                end
                6:begin
                    udp_csum<=(folded_sum==16'hffff)?16'hffff:~folded_sum;
                    crc<=CRC_SEED;index<=40;state<=4;
                end
                4:begin byte_q<=body_byte;crc_bit<=0;state<=7;end
                7:begin
                    if(crc[0]^byte_q[0])crc<=(crc>>1)^32'hedb88320;
                    else crc<=crc>>1;
                    byte_q<=byte_q>>1;
                    if(crc_bit==7)begin
                        if(index==65)begin index<=0;state<=2;end
                        else begin index<=index+1'b1;state<=4;end
                    end else crc_bit<=crc_bit+1'b1;
                end
                2:begin
                    gmii_tx_en<=1;
                    if(index<7)gmii_txd<=8'h55;
                    else if(index==7)gmii_txd<=8'hd5;
                    else if(index<74)gmii_txd<=body_byte;
                    else begin gmii_txd<=~crc[7:0];crc<=crc>>8;end
                    if(index==77)begin state<=3;ifg_count<=0;tx_done<=1;end
                    else index<=index+1'b1;
                end
                3:if(ifg_count==11)state<=0;else ifg_count<=ifg_count+1'b1;
            endcase
        end
    end
endmodule

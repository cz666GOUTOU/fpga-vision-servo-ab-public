// Fixed peer, untagged Ethernet, IPv4 IHL=5, unfragmented UDP, 24 payload bytes.
// Rejects UDP checksum=0. gmii_rxd includes preamble/SFD/FCS.
// All result outputs and counters are in app_clk, except bad_frames/rx_overflow.
module target_udp_rx_core #(
    parameter [47:0] SRC_MAC=48'h020000000001, DST_MAC=48'h020000000002,
    parameter [31:0] SRC_IP=32'hc0a80a01, DST_IP=32'hc0a80a02,
    parameter [15:0] SRC_PORT=16'd5000, DST_PORT=16'd5000,
    parameter FIFO_ADDR_BITS=4,
    parameter integer TIMEOUT_CYCLES=7500000
)(
    input rst_n, input rx_clk, input app_clk, input link_ready,
    input [7:0] gmii_rxd, input gmii_rx_dv, input gmii_rx_er,
    output reg result_update, output reg target_valid, output reg distance_valid,
    // flags[1] keeps its legacy name: center-window status, not range validity.
    // flags[2] is independent scene-wide guard presence, even without valid XY.
    output reg guard_inside,
    output reg [15:0] target_id, center_x, center_y,
    output reg [31:0] distance, result_sequence,
    output reg comm_timeout, output reg [31:0] received_results,
    output reg [31:0] stale_results, output reg [31:0] missing_results,
    output reg [31:0] bad_frames, output reg rx_overflow,
    output reg debug_data_seen, output reg debug_frame_seen
);
    wire rr, ar;
    target_reset_sync r0(rx_clk,rst_n,rr);
    target_reset_sync r1(app_clk,rst_n,ar);
    (* ASYNC_REG = "TRUE" *) reg [1:0] lr, la;
    reg [1:0] state;
    reg [3:0] pre_count;
    reg [7:0] count;
    reg bad;
    reg [7:0] packet [0:65];
    reg [31:0] crc, ip_sum, udp_sum;
    reg [7:0] high_byte;
    reg commit;
    reg [114:0] commit_data;
    wire full, empty;
    wire [114:0] record;
    function [31:0] crc_byte;
        input [31:0] c; input [7:0] d;
        integer k; reg [31:0] v;
        begin v=c; for(k=0;k<8;k=k+1)
            if(v[0]^d[k]) v=(v>>1)^32'hedb88320; else v=v>>1;
            crc_byte=v; end
    endfunction
    function [15:0] folded;
        input [31:0] sum; reg [31:0] s;
        begin s=(sum & 32'hffff)+(sum>>16); s=(s & 32'hffff)+(s>>16);
            folded=s[15:0]; end
    endfunction
    localparam [31:0] PSEUDO_SUM={16'b0,SRC_IP[31:16]}+{16'b0,SRC_IP[15:0]}+
        {16'b0,DST_IP[31:16]}+{16'b0,DST_IP[15:0]}+32'd17+32'd32;
    wire packet_ok = !bad && count==70 && crc==32'hdebb20e3 &&
        {packet[0],packet[1],packet[2],packet[3],packet[4],packet[5]}==DST_MAC &&
        {packet[6],packet[7],packet[8],packet[9],packet[10],packet[11]}==SRC_MAC &&
        {packet[12],packet[13]}==16'h0800 && packet[14]==8'h45 &&
        {packet[16],packet[17]}==16'd52 && (packet[20] & 8'hbf)==0 &&
        packet[21]==0 && packet[22]!=0 && packet[23]==17 &&
        {packet[26],packet[27],packet[28],packet[29]}==SRC_IP &&
        {packet[30],packet[31],packet[32],packet[33]}==DST_IP &&
        folded(ip_sum)==16'hffff &&
        {packet[34],packet[35]}==SRC_PORT && {packet[36],packet[37]}==DST_PORT &&
        {packet[38],packet[39]}==16'd32 && {packet[40],packet[41]}!=0 &&
        folded(udp_sum)==16'hffff && {packet[42],packet[43]}==16'ha55a &&
        packet[44]==1 && packet[45][7:3]==0 &&
        {packet[56],packet[57],packet[62],packet[63],packet[64],packet[65]}==48'b0;
    target_async_fifo #(.WIDTH(115),.ADDR_BITS(FIFO_ADDR_BITS)) q (
        .wr_clk(rx_clk),.wr_reset_n(rr),.wr_en(commit),.wr_data(commit_data),.full(full),
        .rd_clk(app_clk),.rd_reset_n(ar),.rd_en(!empty),.rd_data(record),.empty(empty)
    );
    always @(posedge rx_clk or negedge rr) begin
        if(!rr) begin
            lr<=0; state<=0; pre_count<=0; count<=0; bad<=0;
            crc<=32'hffffffff; ip_sum<=0; udp_sum<=PSEUDO_SUM; high_byte<=0;
            commit<=0; commit_data<=0; bad_frames<=0; rx_overflow<=0;
            debug_data_seen<=0; debug_frame_seen<=0;
        end else begin
            lr<={lr[0],link_ready}; commit<=0; rx_overflow<=0;
            if(lr[1] && gmii_rx_dv) debug_data_seen<=1;
            if(!lr[1]) begin state<=0; pre_count<=0; end
            else case(state)
                0: begin
                    if(!gmii_rx_dv) pre_count<=0;
                    else if(gmii_rx_er) begin state<=3; pre_count<=0; end
                    else if(gmii_rxd==8'h55 && pre_count<7) pre_count<=pre_count+1'b1;
                    else if(gmii_rxd==8'hd5 && pre_count==7) begin
                        state<=1; count<=0; bad<=0; pre_count<=0;
                        crc<=32'hffffffff; ip_sum<=0; udp_sum<=PSEUDO_SUM;
                    end else begin state<=3; pre_count<=0; end
                end
                1: begin
                    if(gmii_rx_dv) begin
                        if(count<66) packet[count]<=gmii_rxd;
                        if(count<71) count<=count+1'b1; else bad<=1;
                        if(count>=70 || gmii_rx_er) bad<=1;
                        crc<=crc_byte(crc,gmii_rxd);
                        if(!count[0]) high_byte<=gmii_rxd;
                        else begin
                            if(count>=15 && count<=33)
                                ip_sum<=ip_sum+{16'b0,high_byte,gmii_rxd};
                            if(count>=35 && count<=65)
                                udp_sum<=udp_sum+{16'b0,high_byte,gmii_rxd};
                        end
                    end else state<=2;
                end
                2: begin
                    state<=0;
                    // Expected 70-byte frame after SFD, independent of IP/UDP filters.
                    if(!bad && count==70 && crc==32'hdebb20e3)
                        debug_frame_seen<=1;
                    if(packet_ok) begin
                        if(!full) begin
                            commit<=1;
                            // Append bit2 above the existing114-bit layout so
                            // sequence/ID/XY/range bit positions stay unchanged.
                            commit_data<={packet[45][2],packet[46],packet[47],packet[48],packet[49],
                                packet[45][1:0],packet[50],packet[51],packet[52],packet[53],
                                packet[54],packet[55],packet[58],packet[59],packet[60],packet[61]};
                        end else rx_overflow<=1;
                    end else bad_frames<=bad_frames+1'b1;
                end
                3: if(!gmii_rx_dv) begin state<=0; bad_frames<=bad_frames+1'b1; end
            endcase
        end
    end
    reg have_sequence;
    reg [31:0] timeout_count;
    wire [31:0] seq_delta=record[113:82]-result_sequence;
    // Serial-number arithmetic accepts differences 1..2^31-1, including wrap.
    wire fresh=!have_sequence || (seq_delta!=0 && !seq_delta[31]);
    always @(posedge app_clk or negedge ar) begin
        if(!ar) begin
            la<=0; result_update<=0; target_valid<=0; distance_valid<=0; guard_inside<=0;
            target_id<=0; center_x<=0; center_y<=0; distance<=0; result_sequence<=0;
            comm_timeout<=1; timeout_count<=0; have_sequence<=0;
            received_results<=0; stale_results<=0; missing_results<=0;
        end else begin
            la<={la[0],link_ready}; result_update<=0;
            if(!la[1]) begin
                comm_timeout<=1; timeout_count<=0; have_sequence<=0;
                target_valid<=0; distance_valid<=0; guard_inside<=0;
            end else if(!empty && fresh) begin
                result_sequence<=record[113:82];
                distance_valid<=record[81]; target_valid<=record[80];
                guard_inside<=record[114];
                target_id<=record[79:64]; center_x<=record[63:48];
                center_y<=record[47:32]; distance<=record[31:0];
                result_update<=1; received_results<=received_results+1'b1;
                if(have_sequence) missing_results<=missing_results+seq_delta-1'b1;
                have_sequence<=1; comm_timeout<=0; timeout_count<=0;
            end else begin
                if(!empty) stale_results<=stale_results+1'b1;
                if(timeout_count>=TIMEOUT_CYCLES-1) begin
                    comm_timeout<=1; have_sequence<=0; target_valid<=0; distance_valid<=0; guard_inside<=0;
                end else timeout_count<=timeout_count+1'b1;
            end
        end
    end
endmodule

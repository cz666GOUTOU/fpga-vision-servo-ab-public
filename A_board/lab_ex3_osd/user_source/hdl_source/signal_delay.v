/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2025/01 
version:     :   
@Description :   
*****************************************************************/
module signal_delay #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    parameter DATA_WIDTH = 96,
    parameter DELAY_CYCLE = 50
) (
    input                        I_clk,
    input                        I_rst_n,
    input                        I_tuser,  //synthesis keep 
    input  wire                  I_valid,  //synthesis keep 
    input  wire [DATA_WIDTH-1:0] I_data,   //synthesis keep 
    output wire                  O_valid,  //synthesis keep 
    output wire [DATA_WIDTH-1:0] O_data ,  //synthesis keep 
    output wire                  O_tuser   //synthesis keep 
);

    wire        rd_en;  //synthesis keep 

    // Exact 720p bounds are enforced by the original wrap transitions.
    localparam integer COMPACT_COUNTS=(IMG_WIDTH==1280 && IMG_HEIGHT==720);
    localparam integer H_COUNT_BITS=COMPACT_COUNTS ? 9 : 14;
    localparam integer V_COUNT_BITS=COMPACT_COUNTS ? 10 : 14;
    localparam integer RD_COUNT_BITS=COMPACT_COUNTS ? 9 : 14;
    localparam integer ADDR_COUNT_BITS=COMPACT_COUNTS ? 9 : 11;
    wire [10:0] addra;  //synthesis keep
    reg [ADDR_COUNT_BITS-1:0] addrb;  //synthesis keep
    reg [H_COUNT_BITS-1:0] h_cnt;
    reg [V_COUNT_BITS-1:0] v_cnt;
    reg [RD_COUNT_BITS-1:0] rd_cnt;
    
    reg  [DATA_WIDTH-1:0] I_data_r;
    reg         rd_valid,I_valid_r;

    localparam IMG_WIDTH_4x = (IMG_WIDTH >> 2);
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n ) begin
            I_valid_r <= 0;
            I_data_r  <= 0;
        end
        else begin
            I_valid_r <= I_valid;
            I_data_r  <= I_data;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end
        else begin
            h_cnt <= I_valid_r ? ((h_cnt == IMG_WIDTH_4x-1) ? 0 : h_cnt + 1) : h_cnt;
            v_cnt <= I_valid_r &&(h_cnt == IMG_WIDTH_4x-1) ? ((v_cnt == IMG_HEIGHT - 1) ? 0 : v_cnt + 1) : v_cnt;
        end
    end
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            rd_valid <= 0;
        end
        else if(h_cnt == DELAY_CYCLE - 3)begin
            rd_valid <= 1;
        end
        else if(rd_cnt == IMG_WIDTH_4x - 1) 
            rd_valid <= 0;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            rd_cnt <= 0;
        end
        else if(rd_cnt == IMG_WIDTH_4x )
            rd_cnt <= 0;
        else if(rd_valid)begin
            rd_cnt <= rd_cnt + 1;
        end
    end

    generate if(COMPACT_COUNTS) begin: g_shared_write_address
        // Same reset, enable and terminal value as the former write counter.
        assign addra=h_cnt;
    end else begin: g_legacy_write_address
        reg [10:0] address;
        assign addra=address;
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) address<=0;
            else if(I_valid_r)
                address<=(address==IMG_WIDTH_4x-1) ? 11'd0 : address+1'b1;
        end
    end endgenerate

  
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n || I_tuser) begin
        addrb <= 0;
      end else begin
        addrb <= rd_valid ? (addrb == IMG_WIDTH_4x - 1) ? 'b0 : addrb + 1'b1 : addrb;
      end
    end
    
    reg rd_valid_d;
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
        rd_valid_d <= 0;
      end else begin
        rd_valid_d <= rd_valid;
      end
    end
    assign O_valid = rd_valid_d;
    assign O_tuser = (v_cnt == 0) && (rd_cnt == 1);

    // Only 320 words are addressed in the current 720P design (480 at the
    // default 1920 width). Keep the original line scheduling and read edge;
    // five <=20-bit banks replace the oversized 2048x96 generated memory.
    genvar bank;
    generate if(DATA_WIDTH==96 && IMG_WIDTH_4x>=1 && IMG_WIDTH_4x<=512) begin: g_compact
        for(bank=0;bank<5;bank=bank+1) begin: g_bank
            localparam BANK_WIDTH=(bank==4)?16:20;
            (* ram_style="bram" *) reg [BANK_WIDTH-1:0] words[0:511];
            reg [BANK_WIDTH-1:0] read_word;
            // Same-clock read-before-write, no reset or memory clearing.
            always @(posedge I_clk) begin
                if(I_valid_r) words[addra[8:0]]<=I_data_r[bank*20+:BANK_WIDTH];
                read_word<=words[addrb[8:0]];
            end
            assign O_data[bank*20+:BANK_WIDTH]=read_word;
        end
    end else begin: g_legacy
    blk_mem_gen_awb_delay_signal blk_mem_gen_awb_delay_signal_d (
      .clka (I_clk   ),  // input wire clka
      .wea  (I_valid_r),  // input wire [0 : 0] wea
      .addra(addra   ),  // input wire [10 : 0] addra
      .dia  (I_data_r ),  // input wire [95 : 0] dina
      .clkb (I_clk   ),  // input wire clkb
      .addrb(addrb   ),  // input wire [10 : 0] addrb
      .dob  (O_data  )   // output wire [95 : 0] doutb
    );
    end endgenerate


endmodule

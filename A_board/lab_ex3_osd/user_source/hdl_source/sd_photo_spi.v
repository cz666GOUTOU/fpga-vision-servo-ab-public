// SPI sector transport adapted to the official example's CMD17/CMD24 layer.
// SDHC/SDXC only: CMD58 CCS check, CSD v2 capacity, CRC16 and finite timeout.
// Does not create a filesystem or write without an explicit sector request.
module photo_spi_byte #(parameter integer LOW_HALF=125,FAST_HALF=2)(
    input wire clk,rst_n,start,fast, input wire [7:0] tx,
    input wire miso, output reg sclk,mosi,busy,done,output reg [7:0] rx,
    output wire rx_sample
);
    reg [7:0] shift;
    reg [2:0] bitno;
    reg [7:0] wait_count;
    wire [7:0] half_period=fast ? FAST_HALF : LOW_HALF;
    // Same pre-edge event that samples MISO into rx; no added register.
    assign rx_sample=busy && wait_count==0 && !sclk;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin shift<=0;bitno<=7;wait_count<=0;sclk<=0;mosi<=1;busy<=0;done<=0;rx<=0;end
        else begin
            done<=0;
            if(start && !busy)begin busy<=1;shift<=tx;bitno<=7;rx<=0;mosi<=tx[7];sclk<=0;wait_count<=half_period-1'b1;end
            else if(busy)begin
                if(wait_count!=0)wait_count<=wait_count-1'b1;
                else begin
                    wait_count<=half_period-1'b1;sclk<=!sclk;
                    if(!sclk)rx<={rx[6:0],miso};
                    else if(bitno==0)begin busy<=0;done<=1;mosi<=1;end
                    else begin bitno<=bitno-1'b1;shift<={shift[6:0],1'b1};mosi<=shift[6];end
                end
            end
        end
    end
endmodule

module sd_photo_spi #(parameter integer LOW_HALF=125,FAST_HALF=2,TIMEOUT_CYCLES=100000000)(
    input wire clk,rst_n,request,write,
    input wire [31:0] lba,
    output reg ready,busy,done,error,
    output reg [31:0] sector_count,
    output reg [8:0] buffer_index,
    input wire [7:0] buffer_read,
    output reg buffer_we,
    output reg [8:0] buffer_waddr,
    output reg [7:0] buffer_write,
    output reg ncs,
    output wire sclk,mosi,input wire miso
);
    localparam BOOT=0,CMD=1,RESPONSE=2,AFTER=3,EXT=4,TOKEN=5,READ=6,
        RCRC0=7,RCRC1=8,WTOKEN=9,WDATA=10,WCRC0=11,WCRC1=12,WRESP=13,
        WBUSY=14,RELEASE=15,IDLE=16,FAILED=17,PREP=18;
    reg [4:0] state;
    reg [3:0] phase;
    // Commands are selected bytewise; saved_lba already owns the request.
    reg [7:0] command_byte;
    reg [2:0] command_index;
    reg [8:0] count;
    reg [7:0] r1;
    reg [7:0] echo_previous;
    reg card_ccs;
    reg [1:0] csd_structure;
    reg [21:0] csd_size;
    reg [15:0] crc,received_crc;
    reg [26:0] timeout;
    reg fast,waiting,start,prefetch;
    reg [31:0] saved_lba;
    reg [7:0] tx;
    wire byte_busy,byte_done,rx_sample;
    wire [7:0] rx;
    photo_spi_byte #(.LOW_HALF(LOW_HALF),.FAST_HALF(FAST_HALF)) bytes(
        .clk(clk),.rst_n(rst_n),.start(start),.fast(fast),.tx(tx),.miso(miso),
        .sclk(sclk),.mosi(mosi),.busy(byte_busy),.done(byte_done),.rx(rx),.rx_sample(rx_sample));
    always @*begin
        command_byte=8'hff;
        case(command_index)
            0:case(phase)
                0:command_byte=8'h40;1:command_byte=8'h48;
                2:command_byte=8'h77;3:command_byte=8'h69;
                4:command_byte=8'h7a;5:command_byte=8'h49;
                6:command_byte=8'h51;7:command_byte=8'h58;
                default:command_byte=8'hff;
            endcase
            1,2,3,4:begin
                command_byte=8'd0;
                if(phase==6 || phase==7)begin
                    case(command_index)
                        1:command_byte=saved_lba[31:24];
                        2:command_byte=saved_lba[23:16];
                        3:command_byte=saved_lba[15:8];
                        default:command_byte=saved_lba[7:0];
                    endcase
                end else if(phase==1)begin
                    if(command_index==3)command_byte=8'h01;
                    else if(command_index==4)command_byte=8'haa;
                end else if(phase==3 && command_index==1)command_byte=8'h40;
            end
            5:command_byte=(phase==0)?8'h95:(phase==1)?8'h87:8'h01;
            default:command_byte=8'hff;
        endcase
    end
    wire transfer_state=state==BOOT || state==CMD || state==RESPONSE || state==EXT ||
        state==TOKEN || state==READ || state==RCRC0 || state==RCRC1 || state==WTOKEN ||
        state==WDATA || state==WCRC0 || state==WCRC1 || state==WRESP || state==WBUSY || state==RELEASE;
    wire [31:0] v2_sectors=({10'd0,csd_size}+32'd1)<<10;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=BOOT;phase<=0;command_index<=0;count<=0;
            r1<=0;echo_previous<=0;card_ccs<=0;csd_structure<=0;csd_size<=0;crc<=0;received_crc<=0;timeout<=0;
            fast<=0;waiting<=0;start<=0;prefetch<=0;tx<=8'hff;
            ready<=0;busy<=1;done<=0;error<=0;sector_count<=0;ncs<=1;
            buffer_index<=0;buffer_we<=0;buffer_waddr<=0;buffer_write<=0;saved_lba<=0;
        end else begin
            start<=0;done<=0;buffer_we<=0;prefetch<=byte_done;
            if(state==IDLE)timeout<=0;
            else if(timeout<TIMEOUT_CYCLES)timeout<=timeout+1'b1;
            // buffer_index changes on byte_done. Allow the synchronous RAM
            // one full clock to fetch the next 128-bit word before latching TX.
            if(transfer_state && !waiting && !byte_busy && !prefetch)begin
                waiting<=1;start<=1;
                case(state)
                    CMD:tx<=command_byte;
                    WTOKEN:tx<=8'hfe;
                    WDATA:tx<=buffer_read;
                    default:tx<=8'hff;
                endcase
            end
            if(byte_done)waiting<=0;
            // CCITT, MSB first. All eight samples retire before byte_done.
            // READ excludes token, response and received CRC bytes.
            if(state==READ && rx_sample)
                crc<={crc[14:0],1'b0} ^ (16'h1021 & {16{crc[15]^miso}});
            case(state)
                BOOT:if(byte_done)begin
                    if(count==9)begin count<=0;phase<=0;state<=PREP;end else count<=count+1'b1;
                end
                PREP:begin
                    ncs<=0;command_index<=0;state<=CMD;
                end
                CMD:if(byte_done)begin
                    if(command_index==5)state<=RESPONSE;else command_index<=command_index+1'b1;
                end
                RESPONSE:if(byte_done && !rx[7])begin r1<=rx;state<=AFTER;end
                AFTER:case(phase)
                    0:if(r1==1)begin phase<=1;state<=PREP;end else state<=FAILED;
                    1:if(r1==1)begin count<=0;echo_previous<=0;card_ccs<=0;state<=EXT;end else state<=FAILED;
                    2:if(r1<=1)begin phase<=3;state<=PREP;end else state<=FAILED;
                    3:if(r1==0)begin phase<=4;state<=PREP;end
                      else if(r1==1)begin phase<=2;state<=PREP;end else state<=FAILED;
                    4:if(r1==0)begin count<=0;echo_previous<=0;card_ccs<=0;state<=EXT;end else state<=FAILED;
                    5,6:if(r1==0)begin state<=TOKEN;crc<=0;count<=0;end else state<=FAILED;
                    7:if(r1==0)begin state<=WTOKEN;buffer_index<=0;count<=0;end else state<=FAILED;
                endcase
                EXT:if(byte_done)begin
                    if(phase==1)echo_previous<=rx;
                    else if(count==0)card_ccs<=rx[6];
                    if(count==3)begin
                        if(phase==1)begin
                            if({echo_previous,rx}!=16'h01aa)state<=FAILED;
                            else begin phase<=2;state<=PREP;end
                        end else begin
                            // CCS=0 is byte-addressed SDSC, deliberately unsupported.
                            if(!card_ccs)state<=FAILED;
                            else begin fast<=1;phase<=5;state<=PREP;end
                        end
                    end else count<=count+1'b1;
                end
                TOKEN:if(byte_done && rx!=8'hff)begin if(rx==8'hfe)state<=READ;else state<=FAILED;end
                READ:if(byte_done)begin
                    if(phase==5)begin
                        // Keep only CSD_STRUCTURE and C_SIZE, not a 128-bit shifter.
                        case(count)
                            0:csd_structure<=rx[7:6];
                            7:csd_size[21:16]<=rx[5:0];
                            8:csd_size[15:8]<=rx;
                            9:csd_size[7:0]<=rx;
                        endcase
                    end
                    else begin buffer_we<=1;buffer_waddr<=count[8:0];buffer_write<=rx;end
                    if(phase==5 ? count==9'd15 : count==9'd511)state<=RCRC0;else count<=count+1'b1;
                end
                RCRC0:if(byte_done)begin received_crc[15:8]<=rx;state<=RCRC1;end
                RCRC1:if(byte_done)begin
                    if({received_crc[15:8],rx}!=crc)state<=FAILED;
                    else if(phase==5)begin
                        // 2^32 sectors cannot be represented by this 32-bit count.
                        if(csd_structure!=2'd1 || csd_size==22'h3fffff)state<=FAILED;
                        else begin
                            sector_count<=v2_sectors;
                            ready<=1;state<=RELEASE;
                        end
                    end else state<=RELEASE;
                end
                WTOKEN:if(byte_done)state<=WDATA;
                WDATA:if(byte_done)begin
                    if(count==511)state<=WCRC0;
                    else begin count<=count+1'b1;buffer_index<=buffer_index+1'b1;end
                end
                WCRC0:if(byte_done)state<=WCRC1;
                WCRC1:if(byte_done)state<=WRESP;
                WRESP:if(byte_done && rx!=8'hff)begin if(rx[4:0]==5'b00101)state<=WBUSY;else state<=FAILED;end
                WBUSY:if(byte_done && rx==8'hff)state<=RELEASE;
                RELEASE:begin ncs<=1;if(byte_done)begin busy<=0;done<=phase==6 || phase==7;state<=IDLE;end end
                IDLE:if(request)begin
                    error<=0;
                    if(!ready || lba>=sector_count)begin error<=1;done<=1;end
                    else begin saved_lba<=lba;phase<=write ? 7 : 6;busy<=1;state<=PREP;end
                end
                // A timeout can occur at any bit phase. Finish the active
                // byte before releasing CS, so CS never changes on a rising
                // SCLK edge. Normal transactions and byte timing are unchanged.
                FAILED:if(!byte_busy && !start)begin ncs<=1;busy<=0;error<=1;done<=1;state<=IDLE;end
                default:state<=FAILED;
            endcase
            if(state!=IDLE && state!=FAILED && timeout>=TIMEOUT_CYCLES)state<=FAILED;
        end
    end
endmodule

// One dual-clock sector RAM. DDR owns it while idle; SPI owns it between
// request and response. The RAM contents cross domains only while held.
module photo_sector_bridge(
    input wire clk,rst_n,sys_clk,sys_rst_n,
    input wire request,write,input wire [31:0] lba,
    input wire ram_we,input wire [4:0] ram_addr,input wire [127:0] ram_wdata,
    output wire [127:0] ram_rdata,
    output reg done,error,output wire ready,
    output wire [31:0] sectors,
    output wire sd_cs,sd_clk,sd_mosi,input wire sd_miso
);
    wire spi_request;
    wire [32:0] spi_command;
    wire mailbox_busy;
    wire transport_ready,transport_busy,transport_done,transport_error;
    wire [31:0] transport_sectors;
    wire [8:0] index,waddr;
    wire we;
    wire [7:0] wbyte;
    wire [127:0] sys_word;
    // Stream bits directly into the seven physical banks. Bank 6 is the
    // leading 8 bits; banks 5..0 are six 20-bit slices. A 24-bit accumulator
    // replaces the old 120-bit shift chain; sector byte order is unchanged.
    reg [23:0] pack_acc;
    reg [2:0] pack_bank;
    reg [4:0] pack_count; // valid bits: 0,4,8,12,16
    reg [4:0] pack_addr;
    wire [7:0] sys_byte=sys_word >> ((15-index[3:0])*8);
    reg [6:0] bank_we;
    reg [127:0] bank_dib;
    wire first_byte=we && (waddr[3:0]==4'd0);
    wire pack_byte=we && (waddr[3:0]!=4'd0);
    wire [23:0] append_16={pack_acc[15:0],wbyte};
    wire [19:0] append_12={pack_acc[11:0],wbyte};
    wire any_bank_write=|bank_we;
    wire [4:0] sys_ram_addr=any_bank_write ? pack_addr : index[8:4];
    always @* begin
        bank_we=7'b0; bank_dib=128'b0;
        if(first_byte) begin
            bank_we[6]=1'b1; bank_dib[120 +: 8]=wbyte;
        end else if(pack_byte && pack_count==5'd16) begin
            case(pack_bank)
                3'd5:begin bank_we[5]=1'b1; bank_dib[100 +: 20]=append_16[23:4]; end
                5'd4:begin bank_we[4]=1'b1; bank_dib[80  +: 20]=append_16[23:4]; end
                3'd3:begin bank_we[3]=1'b1; bank_dib[60  +: 20]=append_16[23:4]; end
                3'd2:begin bank_we[2]=1'b1; bank_dib[40  +: 20]=append_16[23:4]; end
                3'd1:begin bank_we[1]=1'b1; bank_dib[20  +: 20]=append_16[23:4]; end
                3'd0:begin bank_we[0]=1'b1; bank_dib[0   +: 20]=append_16[23:4]; end
                default:begin end
            endcase
        end else if(pack_byte && pack_count==5'd12) begin
            case(pack_bank)
                3'd5:begin bank_we[5]=1'b1; bank_dib[100 +: 20]=append_12; end
                5'd4:begin bank_we[4]=1'b1; bank_dib[80  +: 20]=append_12; end
                3'd3:begin bank_we[3]=1'b1; bank_dib[60  +: 20]=append_12; end
                3'd2:begin bank_we[2]=1'b1; bank_dib[40  +: 20]=append_12; end
                3'd1:begin bank_we[1]=1'b1; bank_dib[20  +: 20]=append_12; end
                3'd0:begin bank_we[0]=1'b1; bank_dib[0   +: 20]=append_12; end
                default:begin end
            endcase
        end
    end
    photo_sector_eram sector_ram(
        .clka(clk),.wea(ram_we),.addra(ram_addr),.dia(ram_wdata),.doa(ram_rdata),
        .clkb(sys_clk),.web(bank_we),.addrb(sys_ram_addr),
        .dib(bank_dib),.dob(sys_word));
    always @(posedge sys_clk or negedge sys_rst_n)begin
        if(!sys_rst_n) begin pack_acc<=0; pack_bank<=3'd5; pack_count<=0; pack_addr<=0; end
        else if(first_byte) begin
            pack_acc<=0; pack_bank<=3'd5; pack_count<=0; pack_addr<=waddr[8:4];
        end else if(pack_byte) begin
            case(pack_count)
                5'd8: begin pack_acc<={8'd0,pack_acc[7:0],wbyte}; pack_count<=5'd16; end
                5'd16: begin pack_acc<={20'd0,append_16[3:0]}; pack_count<=5'd4; if(pack_bank!=0)pack_bank<=pack_bank-1'b1; end
                5'd4: begin pack_acc<={12'd0,pack_acc[3:0],wbyte}; pack_count<=5'd12; end
                5'd12: begin pack_acc<=0; pack_count<=0; if(pack_bank!=0)pack_bank<=pack_bank-1'b1; end
                default: begin pack_acc<={16'd0,wbyte}; pack_count<=5'd8; end
            endcase
        end
    end
    photo_mailbox #(.WIDTH(33)) commands(.src_clk(clk),.src_rst_n(rst_n),
        .src_send(request),.src_data({write,lba}),.src_busy(mailbox_busy),
        .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_valid(spi_request),.dst_data(spi_command));
    sd_photo_spi transport(.clk(sys_clk),.rst_n(sys_rst_n),.request(spi_request),
        .write(spi_command[32]),.lba(spi_command[31:0]),.ready(transport_ready),
        .busy(transport_busy),.done(transport_done),.error(transport_error),
        .sector_count(transport_sectors),.buffer_index(index),
        .buffer_read(sys_byte),
        .buffer_we(we),.buffer_waddr(waddr),.buffer_write(wbyte),
        .ncs(sd_cs),.sclk(sd_clk),.mosi(sd_mosi),.miso(sd_miso));
    wire result_valid;
    wire [32:0] result_data;
    wire result_busy;
    reg reported;
    photo_sector_result_mailbox responses(.src_clk(sys_clk),.src_rst_n(sys_rst_n),
        // CSD CRC is valid before RELEASE finishes its final byte. Advertise
        // initial readiness only when IDLE can actually accept a command.
        .src_send(transport_done || (transport_ready && !transport_busy && !reported)),
        .src_data({transport_error,transport_sectors}),.src_busy(result_busy),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_valid(result_valid),.dst_data(result_data));
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n)reported<=0;
        else if(transport_ready && !transport_busy && !result_busy)reported<=1;
    reg ready_reg;
    reg [31:0] sectors_reg;
    reg operation_pending;
    assign ready=ready_reg;
    assign sectors=sectors_reg;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin done<=0;error<=0;ready_reg<=0;sectors_reg<=0;operation_pending<=0;end
        else begin
            done<=0;
            if(request)operation_pending<=1;
            if(result_valid)begin
                sectors_reg<=result_data[31:0];ready_reg<=result_data[31:0]!=0;
                error<=result_data[32];
                if(operation_pending)begin done<=1;operation_pending<=0;end
            end
        end
    end
endmodule

// Private result mailbox. Card capacity is a registered constant from a
// completed CSD read until the same sys reset clears both transport and sender.
// Reuse that stable register instead of duplicating its 32-bit payload at source.
// Error still needs its own capture; it may change at the next transaction.
// Destination capture, two-flop synchronizers, ACK and valid timing are unchanged.
module photo_sector_result_mailbox(
    input wire src_clk,src_rst_n,src_send,
    input wire [32:0] src_data,
    output wire src_busy,
    input wire dst_clk,dst_rst_n,
    output reg dst_valid,
    output reg [32:0] dst_data
);
    reg request,ack,held_error,pending;
    (* ASYNC_REG="TRUE" *) reg [1:0] req_sync,ack_sync;
    wire [32:0] held={held_error,src_data[31:0]};
    assign src_busy=request!=ack_sync[1];
    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin request<=0;held_error<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(src_send && !src_busy)begin held_error<=src_data[32];request<=!request;end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n)begin
        if(!dst_rst_n)begin req_sync<=0;ack<=0;pending<=0;dst_valid<=0;dst_data<=0;end
        else begin
            req_sync<={req_sync[0],request};dst_valid<=0;
            if(!pending && req_sync[1]!=ack)begin dst_data<=held;pending<=1;end
            else if(pending)begin ack<=req_sync[1];dst_valid<=1;pending<=0;end
        end
    end
endmodule

// PH1P true dual-port ERAM exposes at most 20 bits per physical port.
// Six 20-bit banks plus one 8-bit bank hold the unchanged 128 x 32 sector.
// NOREG means one synchronous memory read, not a combinational read.
// No RAM reset/initialization, clock gating, or extra payload register.
// Ownership in photo_sector_bridge excludes simultaneous cross-port writes;
// cross-port read-during-write values are never consumed by the non-owner.
module photo_sector_eram(
    input wire clka,wea,input wire [4:0] addra,input wire [127:0] dia,
    output wire [127:0] doa,
    input wire clkb,input wire [6:0] web,input wire [4:0] addrb,input wire [127:0] dib,
    output wire [127:0] dob
);
    genvar bank;
    generate for(bank=0;bank<7;bank=bank+1)begin:banks
        localparam integer BANK_WIDTH=(bank==6) ? 8 : 20;
        PH1P_LOGIC_ERAM #(
            .DATA_WIDTH_A(BANK_WIDTH),.DATA_WIDTH_B(BANK_WIDTH),
            .ADDR_WIDTH_A(5),.ADDR_WIDTH_B(5),.DATA_DEPTH_A(32),.DATA_DEPTH_B(32),
            .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
            .IMPLEMENT("20K(FAST)"),.CLKMODE("ASYNC"),
            .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),.BYTE_ENABLE(0),
            .SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
            .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
            .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
            .INIT_FILE("NONE"),.FILL_ALL("NONE")
        ) ram(
            .clka(clka),.clkb(clkb),.cea(1'b1),.ceb(1'b1),.ocea(1'b0),.oceb(1'b0),
            .wea(wea),.web(web[bank]),.addra(addra),.addrb(addrb),
            .dia(dia[bank*20+:BANK_WIDTH]),.dib(dib[bank*20+:BANK_WIDTH]),
            .doa(doa[bank*20+:BANK_WIDTH]),.dob(dob[bank*20+:BANK_WIDTH]),
            .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
            .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
    end endgenerate
endmodule

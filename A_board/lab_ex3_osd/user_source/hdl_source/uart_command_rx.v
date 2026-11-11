// Two binary bytes [opcode,value], 115200 8N1 on the 50 MHz system clock.
module uart_command_rx #(
    parameter integer CLK_FREQ_HZ=50000000, BAUD_RATE=115200,
    parameter integer TIMEOUT_MS=10
)(
    input wire clk, rst_n, rx,
    output reg [7:0] opcode, value,
    output reg command_valid, command_error
);
    wire [7:0] byte_data;
    wire byte_valid, framing_error;
    uart_rx_8n1 #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) receiver(
        .clk(clk),.rst_n(rst_n),.rx(rx),.data(byte_data),
        .valid(byte_valid),.framing_error(framing_error));
    localparam integer TIMEOUT_TICKS=(CLK_FREQ_HZ/1000)*TIMEOUT_MS;
    localparam integer TW=(TIMEOUT_TICKS>1)?$clog2(TIMEOUT_TICKS):1;
    reg waiting_value;
    reg [7:0] saved_opcode;
    reg [TW-1:0] timeout_count;
    // The front end owns parameter ranges. Retain the complete opcode
    // whitelist and the original two-byte/framing/partial-packet handling.
    function legal_opcode;
        input [7:0] op;
        begin
            case(op)
                0,1,2,3,4,5,6,7,8,9,10,11,14,15,
                8'h21,8'h22,8'h23,8'h24,8'h25,8'h27,8'h28,
                8'h2b,8'h2c,8'h2d,8'h2e,8'h2f,8'h30,
                8'h32,8'h33,8'h34,8'h35,8'h36,8'h37,8'h38,8'h39:legal_opcode=1;
                default:legal_opcode=0;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            opcode<=0;value<=0;command_valid<=0;command_error<=0;
            waiting_value<=0;saved_opcode<=0;timeout_count<=0;
        end else begin
            command_valid<=0;command_error<=0;
            if(framing_error) begin
                waiting_value<=0;timeout_count<=0;command_error<=1;
            end else if(byte_valid) begin
                timeout_count<=0;
                if(!waiting_value) begin
                    // Consume both bytes even for an invalid opcode. Otherwise
                    // its value could be mistaken for the next valid opcode.
                    // legal_opcode's default=0 rejects unsupported opcode pairs.
                    saved_opcode<=byte_data;waiting_value<=1;
                end else begin
                    waiting_value<=0;
                    if(legal_opcode(saved_opcode)) begin
                        opcode<=saved_opcode;value<=byte_data;command_valid<=1;
                    end else command_error<=1;
                end
            end else if(waiting_value) begin
                if(timeout_count==TIMEOUT_TICKS-1) begin
                    waiting_value<=0;timeout_count<=0;command_error<=1;
                end else timeout_count<=timeout_count+1'b1;
            end else timeout_count<=0;
        end
    end
endmodule

// Ordered events, NOT a coalescing configuration mailbox. Keep these instance
// register names for the existing held-bus and first-stage CDC constraints.
module guard_command_source(
    input wire clk,rst_n,send,ack_async,
    input wire [15:0] command,
    output reg request,
    output reg [15:0] payload,
    output reg overflow
);
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync;
    (* ram_style="distributed" *) reg [15:0] queue[0:1];
    reg wr,rd;
    reg [1:0] count;
    wire pop=(request==ack_sync[1]) && count!=0;
    wire push=send && (count<2 || pop);
    always @(posedge clk)if(rst_n && push)queue[wr]<=command;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            request<=0;payload<=0;ack_sync<=0;wr<=0;rd<=0;count<=0;overflow<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_async};overflow<=send && !push;
            if(push)wr<=!wr;
            if(pop)begin payload<=queue[rd];rd<=!rd;request<=!request;end
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
endmodule

module uart_rx_8n1 #(
    parameter integer CLK_FREQ_HZ=50000000, BAUD_RATE=115200
)(
    input wire clk, rst_n, rx,
    output reg [7:0] data,
    output reg valid, framing_error
);
    localparam integer BIT_TICKS=(CLK_FREQ_HZ+BAUD_RATE/2)/BAUD_RATE;
    localparam integer CW=(BIT_TICKS>1)?$clog2(BIT_TICKS):1;
    localparam [1:0] IDLE=0, START=1, DATA=2, STOP=3;
    (* ASYNC_REG="TRUE" *) reg rx_meta, rx_sync;
    reg rx_previous;
    reg [1:0] state;
    reg [CW-1:0] countdown;
    reg [2:0] bit_index;
    reg [7:0] shift_data;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_meta<=1;rx_sync<=1;rx_previous<=1;state<=IDLE;
            countdown<=0;bit_index<=0;shift_data<=0;
            data<=0;valid<=0;framing_error<=0;
        end else begin
            rx_meta<=rx;rx_sync<=rx_meta;rx_previous<=rx_sync;
            valid<=0;framing_error<=0;
            case(state)
                IDLE: if(rx_previous && !rx_sync) begin
                    countdown<=BIT_TICKS/2-1;state<=START;
                end
                START: if(countdown!=0) countdown<=countdown-1'b1;
                       else if(!rx_sync) begin
                           countdown<=BIT_TICKS-1;bit_index<=0;state<=DATA;
                       end else state<=IDLE;
                DATA: if(countdown!=0) countdown<=countdown-1'b1;
                      else begin
                          shift_data[bit_index]<=rx_sync;countdown<=BIT_TICKS-1;
                          if(bit_index==7) state<=STOP;
                          else bit_index<=bit_index+1'b1;
                      end
                STOP: if(countdown!=0) countdown<=countdown-1'b1;
                      else begin
                          state<=IDLE;
                          if(rx_sync) begin data<=shift_data;valid<=1;end
                          else framing_error<=1;
                      end
                default: state<=IDLE;
            endcase
        end
    end
endmodule

// Source holds BOTH mask and configuration until destination acknowledges.
// Concurrent writes are coalesced per field; no frame-rate FIFO overflow.
module uart_config_source #(
    parameter integer WIDTH=1, MASK_WIDTH=1,
    parameter [WIDTH-1:0] INITIAL_VALUE=0
)(
    input wire clk, rst_n,
    input wire [WIDTH-1:0] configuration,
    input wire [MASK_WIDTH-1:0] update_mask,
    input wire ack_async,
    output reg request,
    output reg [WIDTH+MASK_WIDTH-1:0] payload
);
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync;
    reg [MASK_WIDTH-1:0] dirty;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ack_sync<=0;request<=0;payload<={{MASK_WIDTH{1'b0}},INITIAL_VALUE};
            dirty<={MASK_WIDTH{1'b1}};
        end else begin
            ack_sync<={ack_sync[0],ack_async};
            if(ack_sync[1]==request && |dirty) begin
                payload<={dirty,configuration};request<=~request;
                dirty<=update_mask;
            end else dirty<=dirty|update_mask;
        end
    end
endmodule

module uart_config_destination #(parameter integer WIDTH=1)(
    input wire clk, rst_n, request_async,
    input wire [WIDTH-1:0] payload_async,
    output reg ack, update,
    output reg [WIDTH-1:0] payload
);
    (* ASYNC_REG="TRUE" *) reg [1:0] request_sync;
    reg pending;
    reg [WIDTH-1:0] captured;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin request_sync<=0;pending<=0;captured<=0;ack<=0;update<=0;payload<=0;end
        else begin
            request_sync<={request_sync[0],request_async};update<=0;
            if(!pending && request_sync[1]!=ack) begin
                captured<=payload_async;pending<=1;
            end else if(pending) begin
                payload<=captured;update<=1;ack<=request_sync[1];pending<=0;
            end
        end
    end
endmodule

module uart_video_control #(
    parameter integer CLK_FREQ_HZ=50000000, BAUD_RATE=115200
)(
    input wire clk, rst_n, rx,
    input wire hdmi_ack, csi_ack, cam_ack,
    output wire hdmi_request, csi_request, cam_request,
    output wire [16:0] hdmi_payload,
    output wire [17:0] csi_payload,
    output wire [5:0] cam_payload,
    output wire command_valid, command_error,
    input wire guard_ack,
    output wire guard_request,
    output wire [15:0] guard_payload,
    output wire photo_command_valid,
    output wire [15:0] photo_command
);
    wire [7:0] opcode,value;
    wire rx_error,guard_overflow;
    assign command_error=rx_error || guard_overflow;
    // Entering either tracking mode requests the existing safe album exit.
    // The manual 0A switch remains independent of the mode-owned request.
    wire tracking_enter=command_valid &&
        ((opcode==8'h2c && value==3) || (opcode==8'h2d && value==1) || (opcode==8'h38 && value==1) || (opcode==8'h39 && value==1));
    assign photo_command_valid=(command_valid && (opcode==8'h27 || opcode==15)) || tracking_enter;
    assign photo_command=tracking_enter ? 16'h2700 : {opcode,value};
    uart_command_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) commands(
        .clk(clk),.rst_n(rst_n),.rx(rx),.opcode(opcode),.value(value),
        .command_valid(command_valid),.command_error(rx_error));
    // HDMI: object,motion,display[3:0],mode[3:0]. CSI: gain,contrast,saturation.
    reg [9:0] hdmi_config;
    reg [14:0] csi_config;
    reg [4:0] cam_config;
    reg [6:0] hdmi_mask;
    reg [2:0] csi_mask;
    reg cam_mask;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hdmi_config<=10'b00_0000_0000;csi_config<={5'd8,5'd8,5'd8};cam_config<=8;
            hdmi_mask<=0;csi_mask<=0;cam_mask<=0;
        end else begin
            hdmi_mask<=0;csi_mask<=0;cam_mask<=0;
            if(command_valid) case(opcode)
                0:begin hdmi_config[3:0]<=(value==8'h07 || value==8'h09)?4'd0:(value[3:0]-4'd1);hdmi_mask[0]<=1;end
                1:begin csi_config[4:0]<=value[4:0];csi_mask[0]<=1;end
                2:begin csi_config[9:5]<=value[4:0];csi_mask[1]<=1;end
                3:begin csi_config[14:10]<=value[4:0];csi_mask[2]<=1;end
                4:begin cam_config<=value[4:0];cam_mask<=1;end
                5:begin hdmi_config[4]<=value[0];hdmi_mask[1]<=1;end
                6:begin hdmi_config[6]<=value[0];hdmi_mask[3]<=1;end
                7:begin hdmi_config[7]<=value[0];hdmi_mask[4]<=1;end
                8:begin hdmi_config[5]<=value[0];hdmi_mask[2]<=1;end
                9:begin hdmi_config[8]<=value[0];hdmi_mask[5]<=1;end
                10:begin hdmi_config[9]<=value[0];hdmi_mask[6]<=1;end
                default:begin end
            endcase
        end
    end
    uart_config_source #(.WIDTH(10),.MASK_WIDTH(7),.INITIAL_VALUE(10'b00_0000_0000)) hdmi_source(
        .clk(clk),.rst_n(rst_n),.configuration(hdmi_config),.update_mask(hdmi_mask),
        .ack_async(hdmi_ack),.request(hdmi_request),.payload(hdmi_payload));
    uart_config_source #(.WIDTH(15),.MASK_WIDTH(3),.INITIAL_VALUE({5'd8,5'd8,5'd8})) csi_source(
        .clk(clk),.rst_n(rst_n),.configuration(csi_config),.update_mask(csi_mask),
        .ack_async(csi_ack),.request(csi_request),.payload(csi_payload));
    uart_config_source #(.WIDTH(5),.MASK_WIDTH(1),.INITIAL_VALUE(5'd8)) cam_source(
        .clk(clk),.rst_n(rst_n),.configuration(cam_config),.update_mask(cam_mask),
        .ack_async(cam_ack),.request(cam_request),.payload(cam_payload));
    wire guard_send=command_valid && (opcode==9 || opcode==10 || opcode==11 ||
        opcode==14 || opcode==8'h28 || (opcode>=8'h21 && opcode<=8'h25) ||
        opcode==8'h2b || opcode==8'h2c || opcode==8'h2d ||
        opcode==8'h2e || opcode==8'h2f || opcode==8'h30 ||
        (opcode>=8'h32 && opcode<=8'h39));
    guard_command_source guard_source(.clk(clk),.rst_n(rst_n),
        .send(guard_send),.command({opcode,value}),.ack_async(guard_ack),
        .request(guard_request),.payload(guard_payload),.overflow(guard_overflow));
endmodule

// Fixed-point editor in the continuous HDMI domain. Only commands and final
// results cross domains, using held-payload request/ack mailboxes.
module a38_local_control #(
    parameter integer TIMEOUT_CYCLES=15000000, GUARD_FEATURE=0
)(
    input wire clk,rst_n,frame_boundary,pause,
    input wire storage_clk,storage_rst_n,photo_busy,
    output wire storage_owner,storage_busy,
    output wire sd_request,sd_write,output wire [31:0] sd_lba,
    input wire sd_ready,sd_done,sd_error,input wire [31:0] sd_sectors,
    output wire ram_we,output wire [4:0] ram_addr,output wire [127:0] ram_wdata,input wire [127:0] ram_rdata,
    input wire command_valid,input wire [15:0] command,
    input wire csi_clk,csi_rst_n,
    input wire guard_parent,guard_block,guard_rearm,input wire [7:0] guard_epoch,
    input wire [15:0] source_frame_id,
    output reg guard_owned,guard_reset,
    output wire guard_update,output wire [52:0] guard_record,
    output wire [15:0] guard_photo_frame,
    input wire [95:0] rgb,input wire rgb_valid,rgb_user,rgb_last,
    output reg active,executing,
    output reg [10:0] cross_x,output reg [9:0] cross_y,
    output reg cross_active,cross_running,cross_live,
    output wire ui_update,ui_live,output wire [15:0] ui_id,ui_x,ui_y,
    output reg tx_update,tx_valid,output reg [15:0] tx_id,tx_x,tx_y
);
    reg [7:0] epoch;
    reg template_mode,template_recording,template_locked;
    reg [10:0] selected_x;
    reg [9:0] selected_y;
    reg dirty;
    reg guard_rearm_pending;
    reg [7:0] sent_guard_epoch;
    wire command_busy,config_received;
    wire [40:0] config_data;
    wire config_send=dirty && !command_busy && !guard_reset;
    photo_mailbox #(.WIDTH(41)) configuration_mail(
        .src_clk(clk),.src_rst_n(rst_n),.src_send(config_send),
        .src_data({template_mode,template_recording,GUARD_FEATURE && guard_owned ? guard_epoch : 8'd0,epoch,active,(executing || template_recording),selected_x,selected_y}),.src_busy(command_busy),
        .dst_clk(csi_clk),.dst_rst_n(csi_rst_n),.dst_valid(config_received),.dst_data(config_data));
    wire result_send,result_busy,result_received;
    wire [53:0] result_data,result_record;
    wire protocol_error,core_busy;
    wire template_request,template_load,template_received,template_manager_done,template_manager_error;
    wire template_request_busy,template_response_busy,template_reply;wire [0:0] template_request_data;
    wire [1:0] template_reply_data;
    wire io_req,io_ready,io_done,io_error;wire [1:0] io_op;wire [7:0] io_addr;wire [31:0] io_wdata,io_rdata;
    wire host_req,host_ready,host_ack,host_error;wire [1:0]host_op;wire [7:0]host_addr;wire [31:0]host_wdata,host_rdata;
    photo_mailbox #(.WIDTH(1)) template_commands(.src_clk(csi_clk),.src_rst_n(csi_rst_n),
        .src_send(template_request),.src_data(template_load),.src_busy(template_request_busy),
        .dst_clk(storage_clk),.dst_rst_n(storage_rst_n),.dst_valid(template_received),.dst_data(template_request_data));
    photo_mailbox #(.WIDTH(2)) template_responses(.src_clk(storage_clk),.src_rst_n(storage_rst_n),
        .src_send(template_manager_done),.src_data({template_manager_error,1'b1}),.src_busy(template_response_busy),
        .dst_clk(csi_clk),.dst_rst_n(csi_rst_n),.dst_valid(template_reply),.dst_data(template_reply_data));
    template_io_cdc template_words(.clk(storage_clk),.rst_n(storage_rst_n),.request(io_req),.op(io_op),.address(io_addr),.wdata(io_wdata),
        .ready(io_ready),.done(io_done),.error(io_error),.rdata(io_rdata),.core_clk(csi_clk),.core_rst_n(csi_rst_n),
        .core_ready(host_ready),.core_ack(host_ack),.core_error(host_error),.core_rdata(host_rdata),
        .core_req(host_req),.core_op(host_op),.core_address(host_addr),.core_wdata(host_wdata));
    template_sd_manager template_store(.clk(storage_clk),.rst_n(storage_rst_n),.request(template_received),.load(template_request_data[0]),
        .cancel(1'b0),.photo_busy(photo_busy),.busy(storage_busy),.storage_owner(storage_owner),.done(template_manager_done),.error(template_manager_error),
        .io_req(io_req),.io_op(io_op),.io_addr(io_addr),.io_wdata(io_wdata),.io_ready(io_ready),.io_done(io_done),.io_error(io_error),.io_rdata(io_rdata),
        .sd_request(sd_request),.sd_write(sd_write),.sd_lba(sd_lba),.sd_ready(sd_ready),.sd_done(sd_done),.sd_error(sd_error),.sd_sectors(sd_sectors),
        .ram_we(ram_we),.ram_addr(ram_addr),.ram_wdata(ram_wdata),.ram_rdata(ram_rdata));
    a38_sad16_capture camera(.clk(csi_clk),.rst_n(csi_rst_n),
        .config_update(config_received),.configuration(config_data),.source_frame_id(source_frame_id),
        .rgb(rgb),.valid(rgb_valid),.user(rgb_user),.last(rgb_last),
        .template_request(template_request),.template_load(template_load),.template_done(template_reply),.template_error(template_reply_data[1]),
        .host_req(host_req),.host_op(host_op),.host_addr(host_addr),.host_wdata(host_wdata),
        .host_ready(host_ready),.host_ack(host_ack),.host_error(host_error),.host_rdata(host_rdata),
        .result_update(result_send),.result(result_data),.protocol_error(protocol_error),.core_busy(core_busy));
    photo_mailbox #(.WIDTH(54)) result_mail(
        .src_clk(csi_clk),.src_rst_n(csi_rst_n),.src_send(result_send && !result_busy),
        .src_data(result_data),.src_busy(result_busy),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_valid(result_received),.dst_data(result_record));
    localparam integer TW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES):1;
    reg [TW-1:0] age;
    reg publish,live;
    assign ui_update=publish;assign ui_live=live;
    assign ui_id={template_mode?8'h39:8'h38,epoch};assign ui_x={5'd0,selected_x};assign ui_y={6'd0,selected_y};

    wire [7:0] op=command[15:8],value=command[7:0];
    wire accepted=result_received && result_record[29:22]==epoch && active && (executing || template_recording) &&
        (!GUARD_FEATURE || !guard_owned || result_record[53:46]==guard_epoch);
    // Do not publish a simultaneous cancelled/edited result to guard consumers.
    assign guard_update=GUARD_FEATURE && guard_owned && accepted && !guard_block &&
        !pause && !guard_reset && !command_valid && guard_parent &&
        !guard_rearm_pending && !guard_rearm;
    assign guard_record={1'b1,result_record[53:46],1'b0,result_record[21],21'd0,
        result_record[9:0],result_record[20:10]};
    assign guard_photo_frame=result_record[45:30];
    function [10:0] move_x;
        input [10:0] current;input [7:0] delta;
        reg signed [12:0] sum;
        begin
            sum=$signed({2'd0,current})+$signed({{5{delta[7]}},delta});
            if(sum<64)move_x=64;else if(sum>1216)move_x=1216;else move_x=sum[10:0];
        end
    endfunction
    function [9:0] move_y;
        input [9:0] current;input [7:0] delta;
        reg signed [12:0] sum;
        begin
            sum=$signed({3'd0,current})+$signed({{5{delta[7]}},delta});
            if(sum<64)move_y=64;else if(sum>656)move_y=656;else move_y=sum[9:0];
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            template_mode<=0;template_recording<=0;template_locked<=0;active<=0;executing<=0;guard_owned<=0;guard_reset<=0;epoch<=0;selected_x<=640;selected_y<=360;
            dirty<=1;age<=0;publish<=0;live<=0;guard_rearm_pending<=0;sent_guard_epoch<=0;
            tx_update<=0;tx_valid<=0;tx_id<=0;tx_x<=0;tx_y<=0;
            cross_x<=640;cross_y<=360;cross_active<=0;cross_running<=0;cross_live<=0;
        end else begin
            tx_update<=publish;publish<=0;guard_reset<=0;
            if(publish)begin
                tx_valid<=active && executing && live;
                tx_id<={8'h38,epoch};tx_x<={5'd0,selected_x};tx_y<={6'd0,selected_y};
            end
            // Refresh only the guard context through the existing atomic mailbox.
            // A return keeps selection epoch, running state and learned template.
            if(GUARD_FEATURE && guard_owned && sent_guard_epoch!=guard_epoch)dirty<=1;
            if(config_send)begin dirty<=0;sent_guard_epoch<=guard_epoch;end
            if(GUARD_FEATURE && guard_owned && guard_rearm)guard_rearm_pending<=1;
            if(frame_boundary && guard_rearm_pending)begin
                guard_reset<=1;guard_rearm_pending<=0;
            end
            if(frame_boundary)begin
                cross_x<=selected_x;cross_y<=selected_y;cross_active<=active && !pause && !(template_mode && executing && !live);cross_running<=executing;cross_live<=executing && live;
            end
            if(executing && (!template_mode || template_locked))begin
                if(age<TIMEOUT_CYCLES-1)age<=age+1'b1;
                else begin
                    executing<=0;live<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;age<=0;
                    if(GUARD_FEATURE && guard_owned)guard_reset<=1;
                end
            end else age<=0;
            if(accepted && template_recording)begin
                template_recording<=0;dirty<=1;epoch<=epoch+1'b1;live<=0;publish<=1;
            end else if(accepted)begin
                if(template_mode && result_record[21])template_locked<=1;
                if(result_record[21])age<=0;live<=result_record[21];publish<=1;
                if(result_record[21])begin selected_x<=result_record[20:10];selected_y<=result_record[9:0];end
            end
            // Commands have priority over an old result on the same edge.
            if(command_valid)begin
                if(op==8'h39)begin
                    if(value==0 || value==1)begin
                        if(GUARD_FEATURE && guard_owned)guard_reset<=1;
                        guard_owned<=0;guard_rearm_pending<=0;template_mode<=value==1;template_recording<=0;template_locked<=0;
                        active<=value==1;executing<=0;live<=0;selected_x<=640;selected_y<=360;epoch<=epoch+1'b1;dirty<=1;publish<=1;
                    end else if(active && template_mode && value==2 && !executing && !template_recording)begin
                        template_recording<=1;template_locked<=0;live<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;
                    end else if(active && template_mode && value==3 && !template_recording)begin
                        executing<=1;template_locked<=0;live<=0;age<=0;selected_x<=640;selected_y<=360;epoch<=epoch+1'b1;dirty<=1;publish<=1;
                    end
                end else if(op==8'h38)begin
                    template_mode<=0;template_recording<=0;template_locked<=0;
                    // Front-end contract: 38 values are 00/01/03/04.
                    guard_rearm_pending<=0;
                    if(GUARD_FEATURE && (guard_owned || (value==1 && guard_parent)))guard_reset<=1;
                    case(value)
                        0:begin guard_owned<=0;active<=0;executing<=0;live<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;end
                        1:begin guard_owned<=GUARD_FEATURE && guard_parent;active<=1;executing<=0;live<=0;selected_x<=640;selected_y<=360;epoch<=epoch+1'b1;dirty<=1;publish<=1;end
                        3:if(active)begin executing<=1;live<=0;age<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;end
                        4:if(active)begin executing<=0;live<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;end
                        default:begin end
                    endcase
                end else if(active && !executing && !template_recording && (op==8'h36 || op==8'h37))begin
                    if(GUARD_FEATURE && guard_owned)guard_reset<=1;
                    if(op==8'h36)selected_x<=move_x(selected_x,value);else selected_y<=move_y(selected_y,value);
                    epoch<=epoch+1'b1;dirty<=1;publish<=1;live<=0;
                end
            end
            if(GUARD_FEATURE && guard_owned && !guard_parent)begin
                active<=0;guard_owned<=0;executing<=0;live<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;guard_reset<=1;guard_rearm_pending<=0;
            end
            if((pause || (GUARD_FEATURE && guard_owned && guard_block)) && executing)begin executing<=0;live<=0;epoch<=epoch+1'b1;dirty<=1;publish<=1;guard_rearm_pending<=0;end
        end
    end
endmodule

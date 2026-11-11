// One photograph per class per guard epoch. Image and box carry one frame ID.
module guard_photo_trigger #(
    parameter integer POLYGON_FEATURE=0,
    parameter integer ALL_FEATURE=0, SAD_FEATURE=0
)(
    input wire clk,rst_n,session,triggered,paused,result_update,overflow,busy,
    input wire [7:0] epoch,
    input wire [52:0] guard_record,
    input wire [15:0] photo_record,
    input wire [8:0] xmin,xmax,
    input wire [7:0] ymin,ymax,
    output reg request,
    output reg [17:0] payload,
    output reg busy_event,
    input wire polygon_red_inside,polygon_green_inside,
    input wire motion_mode,selected_mode,source_reset,
    input wire [1:0] motion_photo_qualified,
    output wire motion_photo_taken
);
    reg [7:0] old_epoch;
    reg [1:0] taken;
    wire usable=guard_record[52] && guard_record[51:44]==epoch && !overflow;
    wire red=guard_record[42] && (POLYGON_FEATURE ? polygon_red_inside :
        (guard_record[10:0]>={xmin,2'b00} && guard_record[10:0]<={xmax,2'b11} &&
         guard_record[20:11]>={ymin,2'b00} && guard_record[20:11]<={ymax,2'b11}));
    wire green=guard_record[43] && (POLYGON_FEATURE ? polygon_green_inside :
        (guard_record[31:21]>={xmin,2'b00} && guard_record[31:21]<={xmax,2'b11} &&
         guard_record[41:32]>={ymin,2'b00} && guard_record[41:32]<={ymax,2'b11}));
    wire choose_red=red && !taken[0];
    wire motion_active=(ALL_FEATURE!=0) && motion_mode;
    assign motion_photo_taken=motion_active && taken[0];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin old_epoch<=0;taken<=0;request<=0;payload<=0;busy_event<=0;end
        else begin
            request<=0;busy_event<=0;old_epoch<=epoch;
            if(!session || paused || old_epoch!=epoch || (SAD_FEATURE && source_reset))taken<=0;
            else if(motion_active)begin
                if(result_update)begin
                    // One photograph for a continuous occupied interval,
                    // not one per class/track and not one on every frame.
                    if(!usable || (!red && !green))taken<=0;
                    else if(!taken[0] && |motion_photo_qualified)begin
                        if(busy)busy_event<=1;
                        else begin payload<={2'd3,photo_record};request<=1;taken<=2'b01;end
                    end
                end
            end else if(!triggered && result_update && usable && (choose_red || (green && !taken[1])))begin
                if(busy)busy_event<=1;
                else begin
                    // The entire associated frame is saved; only its ID and
                    // the triggering class must cross to the DDR controller.
                    payload<={(SAD_FEATURE && selected_mode) ? 2'd0 : (choose_red ? 2'd1 : 2'd2),photo_record};
                    request<=1;
                    taken<=taken | (choose_red ? 2'b01 : 2'b10);
                end
            end
        end
    end
endmodule

// Bundled-data mailbox: sender never modifies payload before acknowledgement.
module photo_mailbox #(parameter integer WIDTH=1)(
    input wire src_clk,src_rst_n,src_send,
    input wire [WIDTH-1:0] src_data,
    output wire src_busy,
    input wire dst_clk,dst_rst_n,
    output reg dst_valid,
    output reg [WIDTH-1:0] dst_data
);
    reg request,ack;
    reg [WIDTH-1:0] held;
    (* ASYNC_REG="TRUE" *) reg [1:0] req_sync,ack_sync;
    reg pending;
    assign src_busy=request!=ack_sync[1];
    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin request<=0;held<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(src_send && !src_busy)begin held<=src_data;request<=!request;end
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

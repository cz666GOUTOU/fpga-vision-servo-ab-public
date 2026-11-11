// The legacy video writer has one registered/skid word after READY. Reserve
// two idle cycles before issuing any photo request. Display requests are
// never back-pressured here; photo reads are issued only after video drains.
module photo_ddr_arbiter(
    input wire clk,rst_n,
    input wire video_wr,video_wr_busy,video_rd,video_rd_busy,
    input wire [24:0] video_wr_addr,video_rd_addr,
    input wire [127:0] video_wr_data,
    output wire video_ready,
    input wire photo_req,photo_write,photo_last,
    input wire [24:0] photo_addr,
    input wire [127:0] photo_data,
    output wire photo_ready,
    output wire photo_rvalid,video_rvalid,
    input wire user_ready,user_rvalid,
    input wire [127:0] user_rdata,
    output wire user_wr,user_rd,
    output wire [24:0] user_addr,
    output wire [127:0] user_wdata,
    output reg fault
);
    reg photo_owner,photo_end;
    reg [6:0] photo_pending;
    reg [9:0] video_pending;
    reg [1:0] quiet;
    wire can_start=quiet==3 && !video_wr_busy && !video_rd_busy &&
        !video_wr && !video_rd && video_pending==0;
    wire grant=photo_req && user_ready && !photo_end && (photo_owner || can_start);
    assign photo_ready=grant;
    // Once a photo read is outstanding, new video reads must wait. Video
    // writer still runs. Its output-ready is independent of photo response.
    assign video_ready=user_ready && !photo_owner;
    assign user_wr=video_wr || (grant && photo_write);
    assign user_rd=video_rd || (grant && !photo_write);
    assign user_addr=video_wr ? video_wr_addr : video_rd ? video_rd_addr : photo_addr;
    assign user_wdata=video_wr ? video_wr_data : photo_data;
    assign photo_rvalid=user_rvalid && photo_owner && photo_pending!=0;
    assign video_rvalid=user_rvalid && !photo_owner && video_pending!=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin photo_owner<=0;photo_end<=0;photo_pending<=0;video_pending<=0;quiet<=0;fault<=0;end
        else begin
            if(video_wr_busy || video_rd_busy || video_wr || video_rd)quiet<=0;
            else if(quiet!=3)quiet<=quiet+1'b1;
            if(grant)begin photo_owner<=1;if(photo_last)photo_end<=1;end
            case({grant && !photo_write,photo_rvalid})
                2'b10:photo_pending<=photo_pending+1'b1;
                2'b01:photo_pending<=photo_pending-1'b1;
                default:begin end
            endcase
            if(photo_owner && photo_end && photo_pending==0)begin photo_owner<=0;photo_end<=0;end
            case({video_rd,video_rvalid})
                2'b10:video_pending<=video_pending+1'b1;
                2'b01:video_pending<=video_pending-1'b1;
                default:begin end
            endcase
            if((video_rd && photo_owner) || (user_rvalid && !photo_owner && video_pending==0) ||
                (user_rvalid && photo_owner && photo_pending==0))fault<=1;
        end
    end
endmodule

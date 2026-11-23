// Pre-DDR observer, optionally shared with frame-tagged display overlays.
// RGB96 is four consecutive RGB888 pixels, first pixel in bits [95:72].
// USER may precede VALID; LAST qualifies the final four-pixel beat of a line.
// A full frame is published at its END, without waiting for HDMI or next SOF.
module color_control_detect #(
    parameter integer H_ACTIVE=1280, V_ACTIVE=720, GUARD_FEATURE=0, PHOTO_FEATURE=0,
    parameter integer SHARE_DISPLAY=0, CAMERA_HZ=103519668
)(
    input wire clk, rst_n, detect_en_async,
    input wire [95:0] rgb,
    input wire valid, user, last,
    output wire result_update, target_valid,
    output wire [15:0] target_id, center_x, center_y,
    output reg protocol_error,
    input wire [7:0] guard_epoch_async,
    output wire [52:0] guard_record,
    input wire [15:0] photo_frame_id,
    output wire [15:0] photo_record,
    output wire display_update,
    output wire [104:0] display_record
);
    localparam integer WORDS_PER_LINE=H_ACTIVE/4;
    (* ASYNC_REG="TRUE" *) reg [1:0] enable_sync;
    reg user_d, in_frame, frame_enabled, completed_good;
    reg [8:0] column;
    reg [9:0] row;
    reg [2:0] flush_count;
    reg finish_pending, observer_vs, observer_de;
    (* ASYNC_REG="TRUE" *) reg [7:0] guard_epoch_meta,guard_epoch_sync;
    reg [7:0] frame_epoch;
    wire start;
    reg [15:0] frame_id;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) frame_id<=0;
        else if(start && (PHOTO_FEATURE || SHARE_DISPLAY)) frame_id<=photo_frame_id;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin guard_epoch_meta<=0;guard_epoch_sync<=0;frame_epoch<=0;end
        else if(GUARD_FEATURE)begin
            // Gray epoch advances once per HDMI blanking commit, never by
            // a coalesced command count. Carry the SOF epoch with the frame.
            guard_epoch_meta<=guard_epoch_async;guard_epoch_sync<=guard_epoch_meta;
            if(start)frame_epoch<=guard_epoch_sync;
        end
    end
    reg [23:0] observer_rgb;
    wire new_user=user && !user_d;
    assign start=new_user && !in_frame && flush_count==0;
    wire early_user=new_user && in_frame;
    wire take=valid && (in_frame || start) && !early_user && flush_count==0;
    wire end_line=column==WORDS_PER_LINE-1;
    wire bad_last=take && (last!=end_line);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            enable_sync<=0; user_d<=0; in_frame<=0; frame_enabled<=0;
            completed_good<=0; column<=0; row<=0; flush_count<=0;
            finish_pending<=0; observer_vs<=0; observer_de<=0;
            observer_rgb<=0; protocol_error<=0;
        end else begin
            enable_sync<={enable_sync[0],detect_en_async};
            user_d<=user;
            observer_rgb<=rgb[95:72];
            observer_de<=take && !bad_last;
            // One register after the final payload, then one register to VS:
            // CCL sees the last line-end BEFORE seeing its frame boundary.
            observer_vs<=finish_pending;
            finish_pending<=0;
            if(flush_count!=0) flush_count<=flush_count-1'b1;
            if(new_user && flush_count!=0) protocol_error<=1;
            if(start) begin
                in_frame<=1; frame_enabled<=enable_sync[1];
                completed_good<=0; column<=0; row<=0;
            end
            if(take && !bad_last) begin
                if(end_line) begin
                    column<=0;
                    if(row==V_ACTIVE-1) begin
                        row<=0; in_frame<=0; completed_good<=1;
                        finish_pending<=1; flush_count<=7;
                    end else row<=row+1'b1;
                end else column<=column+1'b1;
            end
            if(early_user || bad_last) begin
                // Drop the interrupted/malformed frame; clear both CCLs.
                // An early SOF is also discarded; rearm at the next clean SOF.
                in_frame<=0; frame_enabled<=0; completed_good<=0;
                column<=0; row<=0; finish_pending<=1; flush_count<=7;
                protocol_error<=1;
            end
        end
    end

    wire core_update, core_valid;
    wire [15:0] core_id, core_x, core_y;
    wire [43:0] core_guard;
    wire [71:0] core_candidate;
    // One spatial engine supplies both consumers. Control confirmation and
    // result publication keep their original camera-frame timing.
    yanseshibie #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE),.PIXELS_PER_CLK(4),
        .SHARED_SPATIAL(SHARE_DISPLAY)) observer (
        .clk(clk),.rst_n(rst_n),.detect_en(frame_enabled),
        .pre_frame_vsync(observer_vs),.pre_frame_de(observer_de),.pre_rgb(observer_rgb),
        .square_valid(),.triangle_valid(),.result_update(core_update),
        .target_valid(core_valid),.target_id(core_id),.center_x(core_x),.center_y(core_y),
        .guard_targets(core_guard),.frame_candidate(core_candidate),
        .red_seen_frame(),.green_seen_frame(),
        .square_xmin(),.square_xmax(),.square_ymin(),.square_ymax(),
        .triangle_xmin(),.triangle_xmax(),.triangle_ymin(),.triangle_ymax());
    generate if(SHARE_DISPLAY) begin:g_display_record
        localparam integer TICK_CLOCKS=CAMERA_HZ/10000;
        localparam integer DIV_WIDTH=(TICK_CLOCKS<2)?1:$clog2(TICK_CLOCKS);
        reg measuring;
        reg [DIV_WIDTH-1:0] divider;
        reg [13:0] elapsed;
        wire first_pixel=take && !bad_last && column==0 && row==0;
        wire carry=divider==TICK_CLOCKS-1;
        wire [13:0] next_elapsed=elapsed+((measuring && carry)?14'd1:14'd0);
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin measuring<=0;divider<=0;elapsed<=0;end
            else begin
                if(start) begin measuring<=0;divider<=0;elapsed<=0;end
                if(first_pixel) begin measuring<=1;divider<=0;elapsed<=0;end
                else if(measuring) begin
                    if(carry) begin
                        divider<=0;
                        if(elapsed<10000)elapsed<=next_elapsed;
                    end else divider<=divider+1'b1;
                end
                if(core_update)measuring<=0;
            end
        end
        // EOF / latency-valid / 0.1ms ticks / frame-ID / complete / raw result.
        // An SOF invalidation also crosses, so interrupted frames cannot leave
        // an old cache entry alive across frame-ID wrap or a missing EOF.
        // Invalidate even an unexpected USER that the control parser rejects.
        // Its source frame ID has still advanced in video_in's tag stream.
        assign display_update=new_user || core_update;
        assign display_record=new_user ? {1'b0,1'b0,14'd0,photo_frame_id,1'b0,72'd0} :
            {1'b1,measuring && completed_good && frame_enabled && next_elapsed<=9999,
             next_elapsed,frame_id,completed_good,core_candidate};
    end else begin:g_no_display_record
        assign display_update=1'b0;
        assign display_record=105'd0;
    end endgenerate
    assign photo_record=PHOTO_FEATURE ? frame_id : 16'd0;
    assign result_update=core_update;
    assign target_valid=core_valid && completed_good && frame_enabled;
    assign target_id=target_valid ? core_id : 16'd0;
    assign center_x=target_valid ? core_x : 16'd0;
    assign center_y=target_valid ? core_y : 16'd0;
    assign guard_record=GUARD_FEATURE ? {completed_good && frame_enabled,frame_epoch,
        core_guard[43:42] & {2{completed_good && frame_enabled}},core_guard[41:0]} : 53'd0;
endmodule

// One small record per source frame; no pixels or frame buffers are copied.
// Display confirmation advances in DISPLAY order (including repeated frames).
// Coordinates commit at the VTC first-pixel request, two clocks before the
// corresponding video_out RGB reaches vision, and remain fixed for the frame.
module color_shared_display(
    input wire camera_clk,camera_rst_n,candidate_update,
    input wire [104:0] candidate_record,
    input wire ddr_clk,ddr_rst_n,read_start,write_start,
    input wire [1:0] read_slot,write_slot,
    input wire [63:0] slot_ids,
    input wire [3:0] slot_good,
    input wire pixel_clk,pixel_rst_n,vsync,first_pixel,enable,
    output reg [1:0] box_valid,seen,
    output reg [67:0] boxes,
    output reg result_update,
    output reg latency_update,latency_valid,
    output reg [13:0] latency_ticks,
    output reg overflow,
    output reg frame_matched,
    output reg [15:0] displayed_id,
    output wire source_frame_good
);
    wire full,empty;
    wire [104:0] record;
    target_async_fifo #(.WIDTH(105),.ADDR_BITS(2),.RAM_STYLE("dram")) candidates(
        .wr_clk(camera_clk),.wr_reset_n(camera_rst_n),.wr_en(candidate_update),
        .wr_data(candidate_record),.full(full),
        .rd_clk(pixel_clk),.rd_reset_n(pixel_rst_n),.rd_en(!empty),
        .rd_data(record),.empty(empty));
    always @(posedge camera_clk or negedge camera_rst_n)
        if(!camera_rst_n)overflow<=0;
        else if(candidate_update && full)overflow<=1;
    (* ASYNC_REG="TRUE" *) reg [1:0] overflow_sync;
    (* ram_style="dram" *) reg [88:0] cache [0:3];
    reg [3:0] cache_valid;
    wire [1:0] incoming_index=record[74:73];
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            overflow_sync<=0;cache_valid<=0;
            latency_update<=0;latency_valid<=0;latency_ticks<=0;
        end else begin
            overflow_sync<={overflow_sync[0],overflow};
            latency_update<=0;
            if(!empty) begin
                cache_valid[incoming_index]<=record[104] && record[72];
                latency_update<=record[104];
                latency_valid<=record[103] && !overflow_sync[1];
                latency_ticks<=record[102:89];
            end
            if(overflow_sync[1])cache_valid<=0;
        end
    end
    // Keep reset out of the data array so TD can infer a shallow DRAM.
    always @(posedge pixel_clk)
        if(pixel_rst_n && !empty)cache[incoming_index]<=record[88:0];

    reg vs_d,window_open;
    reg [15:0] display_epoch;
    wire prefetch=!vsync && vs_d;
    wire request_busy,request_valid;
    wire [15:0] request_epoch;
    photo_mailbox #(.WIDTH(16)) read_request(
        .src_clk(pixel_clk),.src_rst_n(pixel_rst_n),
        .src_send(prefetch && !request_busy),.src_data(display_epoch+16'd1),.src_busy(request_busy),
        .dst_clk(ddr_clk),.dst_rst_n(ddr_rst_n),.dst_valid(request_valid),.dst_data(request_epoch));

    // video_out snapshots read_slot at read_start. Capture that SAME event,
    // then answer the local display request after its held-data handshake.
    // The request arrives after video_out's three-register VS synchronizer.
    reg have_read,read_safe;
    reg [1:0] selected_slot;
    reg [15:0] selected_id;
    reg response_send;
    reg [32:0] response_data;
    wire response_busy,response_valid;
    wire [32:0] response;
    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if(!ddr_rst_n) begin
            have_read<=0;read_safe<=0;selected_slot<=0;selected_id<=0;
            response_send<=0;response_data<=0;
        end else begin
            response_send<=0;
            if(write_start && write_slot==selected_slot)read_safe<=0;
            if(read_start) begin
                have_read<=1;selected_slot<=read_slot;
                selected_id<=slot_ids[read_slot*16+:16];
                read_safe<=slot_good[read_slot] && !(write_start && write_slot==read_slot);
            end
            if(request_valid) begin
                have_read<=0;
                if(!response_busy) begin
                    response_send<=1;
                    response_data<={request_epoch,have_read && read_safe &&
                        !(write_start && write_slot==selected_slot),selected_id};
                end
            end
        end
    end
    photo_mailbox #(.WIDTH(33)) read_response(
        .src_clk(ddr_clk),.src_rst_n(ddr_rst_n),.src_send(response_send),
        .src_data(response_data),.src_busy(response_busy),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_valid(response_valid),.dst_data(response));
    (* ASYNC_REG="TRUE" *) reg [1:0] safe_sync;
    reg pending_valid,pending_good;
    reg displayed_good;
    // Source validity is independent of color candidates and their FIFO.
    // The existing bundled read-slot mailbox supplies the actual DDR ID.
    assign source_frame_good=displayed_good && safe_sync[1];
    reg [15:0] pending_id;
    wire [88:0] selected=cache[pending_id[1:0]];
    wire matched=pending_valid && pending_good && safe_sync[1] && !overflow_sync[1] &&
        cache_valid[pending_id[1:0]] && selected[88:73]==pending_id && selected[72];
    reg [1:0] red_confirm,red_miss,blue_confirm,blue_miss;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            vs_d<=0;window_open<=0;display_epoch<=0;safe_sync<=0;
            pending_valid<=0;pending_good<=0;pending_id<=0;
            box_valid<=0;boxes<=0;seen<=0;result_update<=0;
            red_confirm<=0;red_miss<=0;blue_confirm<=0;blue_miss<=0;frame_matched<=0;displayed_id<=0;displayed_good<=0;
        end else begin
            vs_d<=vsync;safe_sync<={safe_sync[0],read_safe};result_update<=0;
            if(prefetch) begin
                display_epoch<=display_epoch+1'b1;
                pending_valid<=0;window_open<=1;
            end
            if(response_valid && response[32:17]==display_epoch && window_open && !prefetch) begin
                pending_valid<=1;pending_good<=response[16];pending_id<=response[15:0];
            end
            if(first_pixel) begin
                window_open<=0;pending_valid<=0;
                frame_matched<=matched;displayed_id<=pending_id;
                displayed_good<=pending_valid && pending_good;
            end
            if(!enable) begin
                box_valid<=0;seen<=0;red_confirm<=0;red_miss<=0;blue_confirm<=0;blue_miss<=0;
            end else if(first_pixel) begin
                result_update<=1;
                if(!matched) begin
                    // Missing/late/overwritten metadata is not a shape miss:
                    // discard it, including temporal hold of a different frame.
                    box_valid<=0;seen<=0;red_confirm<=0;red_miss<=0;blue_confirm<=0;blue_miss<=0;
                end else begin
                    seen<=selected[71:70];
                    if(selected[68]) begin
                        red_miss<=0;
                        if(red_confirm<2)red_confirm<=red_confirm+1'b1;
                        if(red_confirm>=1)box_valid[0]<=1;
                        boxes[33:0]<=selected[33:0];
                    end else if(selected[70])begin
                        red_confirm<=0;red_miss<=2;box_valid[0]<=0;
                    end else if(red_miss>=2)begin
                        red_confirm<=0;box_valid[0]<=0;
                    end else begin
                        box_valid[0]<=0;red_miss<=red_miss+1'b1;
                    end
                    if(selected[69]) begin
                        blue_miss<=0;
                        if(blue_confirm<2)blue_confirm<=blue_confirm+1'b1;
                        if(blue_confirm>=1)box_valid[1]<=1;
                        boxes[67:34]<=selected[67:34];
                    end else if(selected[71])begin
                        blue_confirm<=0;blue_miss<=2;box_valid[1]<=0;
                    end else if(blue_miss>=2)begin
                        blue_confirm<=0;box_valid[1]<=0;
                    end else begin
                        box_valid[1]<=0;blue_miss<=blue_miss+1'b1;
                    end
                end
            end
        end
    end
endmodule

// Atomic result CDC: 49 bits normally, 102 bits with GUARD frame metadata.
// No image/frame buffer is added.
// Four slots are ample at one result/camera-frame and unconditional readout.
// Resets must originate from the same power reset (locally synchronized).
module color_control_result_cdc #(parameter integer GUARD_FEATURE=0, PHOTO_FEATURE=0)(
    input wire wr_clk, wr_rst_n, result_update, target_valid,
    input wire [15:0] target_id, center_x, center_y,
    input wire rd_clk, rd_rst_n,
    output reg out_update, out_valid,
    output reg [15:0] out_id, out_x, out_y,
    output reg overflow,
    input wire [52:0] guard_record,
    output reg [52:0] out_guard_record,
    input wire [15:0] photo_record,
    output reg [15:0] out_photo_record
);
    wire full, empty;
    localparam integer BASE_WIDTH=GUARD_FEATURE ? 102 : 49;
    localparam integer RECORD_WIDTH=BASE_WIDTH+(PHOTO_FEATURE ? 16 : 0);
    wire [RECORD_WIDTH-1:0] record;
    wire [BASE_WIDTH-1:0] base_record=GUARD_FEATURE ?
        {guard_record,target_valid,target_id,center_x,center_y} :
        {target_valid,target_id,center_x,center_y};
    wire [RECORD_WIDTH-1:0] extended_record=PHOTO_FEATURE ?
        {photo_record,base_record} : base_record;
    // Four records (at most 118 bits each) do not warrant four ERAMs.
    // Distributed RAM preserves the original fall-through read/CDC timing.
    target_async_fifo #(.WIDTH(RECORD_WIDTH),.ADDR_BITS(2),.RAM_STYLE("dram")) records (
        .wr_clk(wr_clk),.wr_reset_n(wr_rst_n),.wr_en(result_update),
        .wr_data(extended_record[RECORD_WIDTH-1:0]),.full(full),
        .rd_clk(rd_clk),.rd_reset_n(rd_rst_n),.rd_en(!empty),
        .rd_data(record),.empty(empty));
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) overflow<=0;
        else if(result_update && full) overflow<=1;
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            out_update<=0; out_valid<=0; out_id<=0; out_x<=0; out_y<=0;out_guard_record<=0;out_photo_record<=0;
        end else begin
            out_update<=!empty;
            if(!empty) begin
                out_valid<=record[48]; out_id<=record[47:32];
                out_x<=record[31:16]; out_y<=record[15:0];
                if(GUARD_FEATURE)out_guard_record<=record>>49;
                if(PHOTO_FEATURE)out_photo_record<=record>>BASE_WIDTH;
            end
        end
    end
endmodule

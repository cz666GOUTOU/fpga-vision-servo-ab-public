

module video_in #(parameter integer PHOTO_FEATURE=0, FRAME_WORDS=172800, PHOTO_FREEZE=0)(
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready,
    output wire        O_frame_write_start,
    output wire [1:0]  O_frame_write_slot,
    input wire [15:0] I_photo_frame_id,
    output reg [63:0] O_photo_slot_ids,
    output reg [3:0] O_photo_slot_good,
    input wire I_photo_pause,
    output wire O_photo_paused
);

    wire        S_fifo_rst;
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;
    reg [17:0] photo_words;
    reg [1:0] photo_slot;
    // Same DDR-clock request/acknowledge. Finish the registered write tail
    // before resetting the FIFO; keep it reset while camera frames are dropped.
    // Release only on a fresh SOF, never at an arbitrary pixel in a frame.
    wire photo_request=(PHOTO_FREEZE!=0) && I_photo_pause;
    reg photo_hold;
    reg [1:0] photo_recover;
    wire writer_idle=!S_ddr_wr_valid && !O_ddr_user_wr_en;
    wire photo_stop=photo_request || photo_hold;
    wire video_frame_start=S_frame_start && !photo_request &&
        (!photo_hold || writer_idle);
    assign O_photo_paused=(PHOTO_FREEZE!=0) && photo_hold && writer_idle;
    always @(posedge I_ddr_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin photo_hold<=0;photo_recover<=0;end
        else if(PHOTO_FREEZE!=0)begin
            if(photo_request)begin photo_hold<=1;photo_recover<=3;end
            else if(video_frame_start)begin
                photo_hold<=0;
                if(photo_recover!=0)photo_recover<=photo_recover-1'b1;
            end
        end
    end
    always @(posedge I_ddr_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin O_photo_slot_ids<=0;O_photo_slot_good<=0;photo_words<=0;photo_slot<=0;end
        else if(PHOTO_FEATURE)begin
            if(video_frame_start)begin
                photo_slot<=O_frame_write_slot;photo_words<=0;
                O_photo_slot_ids[O_frame_write_slot*16+:16]<=I_photo_frame_id;
                O_photo_slot_good[O_frame_write_slot]<=0;
            end else if(O_ddr_user_wr_en)begin
                if(photo_words<FRAME_WORDS)photo_words<=photo_words+1'b1;
                if(photo_words==FRAME_WORDS-1)O_photo_slot_good[photo_slot]<=1;
                else if(photo_words>=FRAME_WORDS)O_photo_slot_good[photo_slot]<=0;
            end
        end
    end

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    // Vendor FIFO asserts reset asynchronously and releases it through a
    // synchronizer in EACH clock domain. Do not alter the generated IP.
    assign S_fifo_rst = (S_camera_frame_start_extend_3d && !photo_stop) || O_photo_paused;

    // 以完整DDR写突发的占用标志仲裁，避免连续视频写入长期阻塞读通道。
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    // Keep one native combinational buffer per packer -> ERAM write-data bit.
    // Cover the whole bus: placement can move the shortest hold path to any bit.
    // No register stage: data/VALID/SOF cycles and pixel values stay unchanged.
    (* keep = "true" *) wire [127:0] S_fifo_wr_data_hold;
    genvar hold_bit;
    generate
        for (hold_bit = 0; hold_bit < 128; hold_bit = hold_bit + 1) begin : g_fifo_wr_data_hold
            PH1P_LOGIC_BUF u_hold_buf(
                .i ( I_camera_data[hold_bit]  ),
                .o ( S_fifo_wr_data_hold[hold_bit] )
            );
        end
    endgenerate
    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( I_camera_valid     ),
        .di         ( S_fifo_wr_data_hold ),
        .afull      (),
        .full_flag  (),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @ (posedge I_camera_clk) begin
    	if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk) begin
        S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
        S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
        S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;
    // Observe the pre-increment pointer used by the address register below.
    assign O_frame_write_start = video_frame_start;
    assign O_frame_write_slot = I_mipi_rx_error ? S_video_in_wp-2'd1 : S_video_in_wp;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(I_display_pause)
                S_video_in_wp <= S_video_in_wp;
            else if(video_frame_start)
                begin
                    if(I_mipi_rx_error)
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(I_display_pause)
                O_video_out_rp <= O_video_out_rp;
            else if(video_frame_start)
                begin
                    // An interrupted frame stays invalid. Retain the last
                    // complete display bank while that hole passes through
                    // the original two-frame read-pointer lag after resume.
                    if(photo_recover!=0 && !O_photo_slot_good[S_video_in_wp-2'd2])
                        O_video_out_rp<=O_video_out_rp;
                    else case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst) && !photo_stop)
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(video_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(video_frame_start && I_mipi_rx_error)
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
endmodule

// Passive frame-age telemetry. One tick is 0.1 ms at PIXEL_HZ.
// Start: RAW stream SOF before ISP. End: corresponding HDMI input SOF.
// Timestamp metadata follows the actual DDR address-bank selection, not a
// fixed number of frame periods. No image pixels pass through this module.
module video_latency_monitor #(
    parameter integer PIXEL_HZ = 75000000
)(
    input wire rst_n, pixel_clk, camera_clk, ddr_clk,
    input wire raw_sof, isp_sof,
    input wire write_start,
    input wire [1:0] write_slot,
    input wire read_start,
    input wire [1:0] read_slot,
    input wire hdmi_sof,
    output reg [15:0] age_bcd,
    output reg [13:0] age_ticks,
    output reg age_valid
);
    localparam integer TICK_CLOCKS = PIXEL_HZ / 10000;
    // Shared assertion clears every mailbox; release belongs to each domain.
    wire pixel_reset_n, camera_reset_n, ddr_reset_n;
    target_reset_sync pixel_reset(pixel_clk,rst_n,pixel_reset_n);
    target_reset_sync camera_reset(camera_clk,rst_n,camera_reset_n);
    target_reset_sync ddr_reset(ddr_clk,rst_n,ddr_reset_n);
    localparam integer DIV_WIDTH = TICK_CLOCKS<2 ? 1 : $clog2(TICK_CLOCKS);
    reg [DIV_WIDTH-1:0] divider;
    reg [23:0] ticks, ticks_gray;
    wire [23:0] next_ticks = ticks + 24'd1;
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin divider<=0; ticks<=0; ticks_gray<=0; end
        else if (divider == TICK_CLOCKS-1) begin
            divider<=0; ticks<=next_ticks;
            ticks_gray<=next_ticks ^ (next_ticks>>1);
        end else divider<=divider+1'b1;
    end
    function [23:0] gray_binary;
        input [23:0] value;
        integer n;
        begin
            gray_binary[23]=value[23];
            for(n=22;n>=0;n=n-1) gray_binary[n]=gray_binary[n+1]^value[n];
        end
    endfunction
    // Registered Gray timebase: only one bit changes at a tick boundary.
    (* ASYNC_REG = "TRUE" *) reg [23:0] time_c1, time_c2;
    reg [23:0] raw_stamp;
    reg raw_pending, stamp_sequence;
    reg [25:0] camera_mailbox; // sequence, valid, source time
    always @(posedge camera_clk or negedge camera_reset_n) begin
        if (!camera_reset_n) begin
            time_c1<=0; time_c2<=0; raw_stamp<=0; raw_pending<=0;
            camera_mailbox<=0; stamp_sequence<=0;
        end else begin
            time_c1<=ticks_gray; time_c2<=time_c1;
            if(raw_sof) begin
                raw_stamp<=gray_binary(time_c2); raw_pending<=1;
            end
            if(isp_sof) begin
                stamp_sequence<=~stamp_sequence;
                camera_mailbox<={~stamp_sequence, raw_pending|raw_sof,
                                  raw_sof ? gray_binary(time_c2) : raw_stamp};
                raw_pending<=0;
            end
        end
    end
    // Bundled-data CDC: mailbox is held from ISP SOF until the next frame.
    // write_start is the SAME ISP SOF synchronized by video_in. Delay its
    // consumption four DDR clocks, after the two mailbox settling registers.
    // Legal 720p frames are much longer than this settling interval.
    (* ASYNC_REG = "TRUE" *) reg [25:0] mail_d1, mail_d2;
    reg [3:0] write_pipe;
    reg [1:0] pending_slot;
    reg last_sequence;
    reg [23:0] bank_stamp [0:3];
    reg [3:0] bank_valid;
    reg [24:0] read_mailbox;
    reg read_toggle, read_safe;
    reg [1:0] selected_slot;
    integer k;
    always @(posedge ddr_clk or negedge ddr_reset_n) begin
        if(!ddr_reset_n) begin
            mail_d1<=0; mail_d2<=0; write_pipe<=0; pending_slot<=0;
            last_sequence<=0; bank_valid<=0; read_mailbox<=0;
            read_toggle<=0; read_safe<=0; selected_slot<=0;
            for(k=0;k<4;k=k+1) bank_stamp[k]<=0;
        end else begin
            mail_d1<=camera_mailbox; mail_d2<=mail_d1;
            write_pipe<={write_pipe[2:0],write_start};
            if(write_pipe[3]) begin
                bank_stamp[pending_slot]<=mail_d2[23:0];
                bank_valid[pending_slot]<=mail_d2[24] &&
                                           (mail_d2[25]!=last_sequence);
                last_sequence<=mail_d2[25];
            end
            if(write_start) begin
                pending_slot<=write_slot;
                bank_valid[write_slot]<=0;
                if(write_slot==selected_slot) read_safe<=0;
            end
            if(read_start) begin
                read_mailbox<={bank_valid[read_slot] &&
                    !(write_start && write_slot==read_slot),bank_stamp[read_slot]};
                selected_slot<=read_slot;
                read_safe<=bank_valid[read_slot] &&
                    !(write_start && write_slot==read_slot);
                read_toggle<=~read_toggle;
            end
        end
    end
    // read_start occurs at video_out's vertical blanking bank latch. The
    // bundled mailbox is stable before the three-stage toggle is consumed.
    (* ASYNC_REG = "TRUE" *) reg [24:0] read_p1, read_p2;
    (* ASYNC_REG = "TRUE" *) reg [2:0] toggle_pipe;
    (* ASYNC_REG = "TRUE" *) reg [1:0] safe_pipe;
    reg seen_toggle, frame_ready, selected_valid;
    reg [23:0] selected_stamp;
    wire [23:0] elapsed = ticks - selected_stamp;
    reg [13:0] binary_shift;
    reg [13:0] pending_ticks;
    reg [15:0] bcd_work;
    reg [3:0] steps;
    reg conversion_valid;
    reg [15:0] bcd_add3;
    integer digit;
    always @* begin
        bcd_add3=bcd_work;
        for(digit=0;digit<4;digit=digit+1)
            if(bcd_work[digit*4 +: 4]>=5)
                bcd_add3[digit*4 +: 4]=bcd_work[digit*4 +: 4]+4'd3;
    end
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            read_p1<=0; read_p2<=0; toggle_pipe<=0; safe_pipe<=0;
            seen_toggle<=0; frame_ready<=0; selected_valid<=0; selected_stamp<=0;
            age_bcd<=0; age_ticks<=0; age_valid<=0; binary_shift<=0; pending_ticks<=0; bcd_work<=0;
            steps<=0; conversion_valid<=0;
        end else begin
            read_p1<=read_mailbox; read_p2<=read_p1;
            toggle_pipe<={toggle_pipe[1:0],read_toggle};
            safe_pipe<={safe_pipe[0],read_safe};
            if(toggle_pipe[2]!=seen_toggle) begin
                seen_toggle<=toggle_pipe[2]; frame_ready<=1;
                selected_stamp<=read_p2[23:0]; selected_valid<=read_p2[24];
            end
            if(hdmi_sof) begin
                frame_ready<=0;
                bcd_work<=0; steps<=14;
                binary_shift<=elapsed[13:0];
                pending_ticks<=elapsed[13:0];
                conversion_valid<=frame_ready && selected_valid && safe_pipe[1] &&
                                  (elapsed<=24'd9999);
            end else if(steps!=0) begin
                bcd_work<={bcd_add3[14:0],binary_shift[13]};
                binary_shift<={binary_shift[12:0],1'b0};
                steps<=steps-1'b1;
                if(steps==1) begin
                    age_bcd<={bcd_add3[14:0],binary_shift[13]};
                    age_ticks<=pending_ticks;
                    age_valid<=conversion_valid;
                end
            end
        end
    end
endmodule


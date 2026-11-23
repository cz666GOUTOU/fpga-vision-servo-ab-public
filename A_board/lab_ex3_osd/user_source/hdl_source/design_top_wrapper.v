`include "fpga_motion_example_config.vh"


module design_top_wrapper #(
    parameter [9:0] AE_DARK_MIN_MEAN = 10'd0, // entry-relative pre-gain RAW thresholds
    parameter [9:0] AE_RECOVER_MIN_MEAN = 10'd0,
    parameter integer AE_CONFIRM_SAMPLES = 2,
    parameter [2:0] AE_SETTLE_FRAMES = 3'd3,
    parameter integer MOTION_GAIN_SETTLE_FRAMES = `FPGA_MOTION_TOP_GAIN_SETTLE
) (
    input wire        I_sys_clk,
    input wire        I_uart_rx, // binary command RX, 115200 8N1, V6
    output wire O_sd_cs,O_sd_clk,O_sd_mosi,
    input wire I_sd_miso,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    output wire [3:0] O_eth_txd,
    output wire       O_eth_tx_ctl, O_eth_tx_clk,
    output wire       O_phy_reset_n, O_eth_mdc,
    inout wire        IO_eth_mdio,
    output wire       O_led_circle,
    output wire       O_led_triangle,
    output wire       O_led_red_hit,
    output wire       O_led_green_hit,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	reg  [17:0] 	S_cam_power_cnt;
	reg         	S_cam_pwdnb;
	reg         	S_cam_i2c_ready;
	(* keep = "true" *) wire [15:0] S_cam_sensor_id;
	(* keep = "true" *) wire        S_cam_sensor_id_ok;
	(* keep = "true" *) wire        S_cam_i2c_error;
	localparam integer CAM_PWDNB_LOW_CYCLES = 23810;  // >= 1 ms at 23.809524 MHz
	localparam integer CAM_I2C_START_CYCLES = 142857; // release + >= 5 ms
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;
		
	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [4:0]		S_raw_gain_sel;
	wire [39:0]	S_raw_gain_data;
	wire			S_raw_gain_valid;
	wire			S_raw_gain_user;
	wire			S_raw_gain_last;
    // Mode-12 auto-exposure CDC and control signals.
    (* ASYNC_REG = "TRUE", keep = "true" *) reg auto_mode_meta_24m, auto_mode_sync_24m;
    reg auto_mode_meta_csi, auto_mode_sync_csi;
    wire S_auto_enable_24m = auto_mode_sync_24m;
    wire S_auto_enable_csi = auto_mode_sync_csi;
    wire [31:0] S_ae_stat_sum;
    wire S_ae_stat_toggle;
    wire [15:0] S_auto_ae, S_auto_ag, S_manual_seed_ae, S_manual_seed_ag;
    wire S_auto_targets_valid, S_auto_target_valid;
    wire S_ae_osd_active, S_ae_osd_ready, S_ae_osd_error;
    wire [4:0] S_ae_osd_gain;
    wire S_ae_stat_request, S_ae_stat_valid;
    wire [2:0] S_ae_stat_skip;
    wire [4:0] S_ae_stat_gain, S_raw_gain_active, S_raw_gain_saved, S_auto_dgain;
    wire [7:0] S_ae_stat_epoch, S_raw_gain_epoch, S_auto_dgain_epoch;
    wire S_auto_dgain_request, S_auto_dgain_ack;
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_latency_write_start, S_latency_read_start;
    wire [1:0]  S_latency_write_slot, S_latency_read_slot;
    wire [15:0] S_latency_bcd;
    wire [13:0] S_latency_ticks;
    wire        S_latency_valid;
    wire [15:0] S_detect_latency_bcd;
    wire S_detect_latency_valid, S_motion_result_update, S_motion_result_ready, S_motion_overflow;
    reg [2:0]   S_latency_hdmi_user;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    // video_out: synchronous FIFO read + registered RGB unpack = 2 clocks.
    // Keep the VTC read request unchanged; delay only the consumer qualifiers.
    reg [1:0] S_video_de_dly, S_video_vs_dly, S_video_hs_dly;
    reg [1:0] S_video_user_dly, S_video_last_dly;
    wire S_video_de_aligned = S_video_de_dly[1];
    wire S_video_vs_aligned = S_video_vs_dly[1];
    wire S_video_hs_aligned = S_video_hs_dly[1];
    wire S_video_user_aligned = S_video_user_dly[1];
    wire S_video_last_aligned = S_video_last_dly[1];

    wire        S_vision_vsync;
    wire        S_vision_href;
    wire        S_vision_de;
    wire[23:0]  S_vision_rgb;
    wire        S_vision_lv1;
    wire        S_vision_lv5;
    wire        S_vision_lv6;
    wire        S_vision_user_sel;
    wire        S_vision_last_sel;
    reg  [5:0]  S_vision_user_dly;
    reg  [5:0]  S_vision_last_dly;
    reg [3:0] S_proc_sel_pending, S_proc_sel_active;
    wire [3:0] S_proc_sel_effective;
    reg S_box_en_pending, S_box_en_active;
    reg S_object_en_pending, S_object_en_active;
    // Pending is the independent manual switch. Either mode may also own
    // recognition; their UI states already live in the HDMI clock domain.
    wire S_static_track_active,S_range_hold_active;
    reg [3:0] S_display_pending, S_display_active;
    wire S_uart_hdmi_req, S_uart_csi_req, S_uart_cam_req;
    wire S_uart_hdmi_ack, S_uart_csi_ack, S_uart_cam_ack;
    wire S_uart_hdmi_update, S_uart_csi_update, S_uart_cam_update;
    wire [16:0] S_uart_hdmi_source, S_uart_hdmi_data;
    wire [17:0] S_uart_csi_source, S_uart_csi_data;
    wire [5:0] S_uart_cam_source, S_uart_cam_data;
    wire [15:0] S_uart_camera_ag;
    wire        S_square_valid, S_triangle_valid, S_object_update;
    wire S_shared_update,S_shared_overflow;
    wire [104:0] S_shared_record;
    wire S_color_latency_update,S_color_latency_valid;
    wire [13:0] S_color_latency_ticks;
    wire S_motion_latency_update,S_motion_latency_valid;
    wire [13:0] S_motion_latency_ticks;
    wire [95:0] S_control_rgb;
    wire S_control_rgb_valid, S_control_rgb_user, S_control_rgb_last;
    wire S_control_update_csi, S_control_valid_csi;
    wire [15:0] S_control_id_csi, S_control_x_csi, S_control_y_csi;
    wire S_control_update, S_control_valid;
    wire [15:0] S_control_id, S_control_x, S_control_y;
    wire S_control_protocol_error, S_control_overflow;
    wire S_guard_req,S_guard_ack,S_guard_config_update;
    wire [15:0] S_guard_source,S_guard_command;
    wire [42:0] S_guard_config;
    wire S_guard_changed,S_guard_editing;
    wire S_guard_mode_request,S_guard_motion_mode;
    wire S_motion_guard_update,S_motion_frame_good;
    wire [15:0] S_motion_frame_id,S_motion_guard_photo;
    wire [52:0] S_motion_guard_record;
    wire [1:0] S_motion_result_fresh,S_motion_photo_qualified;
    wire S_motion_photo_taken;
    wire [3:0] S_guard_seconds;
    wire [2:0] S_guard_selected;
    wire [83:0] S_guard_preview,S_guard_active,S_guard_validate_points;
    wire [67:0] S_guard_active_grid,S_guard_validate_grid;
    // Editing/outline use physical pixels; keep the original low-cost 4px
    // geometry engine and its record format, validation and inside semantics.
    genvar guard_point;
    generate for(guard_point=0;guard_point<4;guard_point=guard_point+1)begin : g_guard_grid
        assign S_guard_active_grid[guard_point*17 +: 17]={
            S_guard_active[guard_point*21+12 +: 9],S_guard_active[guard_point*21+2 +: 8]};
        assign S_guard_validate_grid[guard_point*17 +: 17]={
            S_guard_validate_points[guard_point*21+12 +: 9],S_guard_validate_points[guard_point*21+2 +: 8]};
    end endgenerate
    wire S_guard_validate_request,S_guard_validate_ready,S_guard_validate_done,S_guard_validate_ok;
    wire S_guard_polygon_update,S_guard_polygon_overflow;
    wire [52:0] S_guard_polygon_record;
    wire [15:0] S_guard_polygon_photo;
    wire [1:0] S_guard_inside;
    wire S_guard_edit_pause=S_guard_editing || !S_guard_config[34];
    wire [52:0] S_guard_record_csi,S_guard_record;
    wire [7:0] S_guard_epoch;
    wire S_guard_session,S_guard_triggered,S_guard_view_recognition,S_guard_warning;
    wire S_guard_event,S_guard_wait,S_guard_cancel,S_guard_accepted;
    wire S_region_update,S_region_inside;
    wire [15:0] S_guard_id,S_guard_x,S_guard_y;
    wire [8:0] S_guard_xmin,S_guard_xmax;
    wire [7:0] S_guard_ymin,S_guard_ymax;
    wire S_photo_album;
    wire S_guard_hud_intrusion,S_guard_hud_blink;
    wire [3:0] S_guard_hud_seconds;
    wire [4:0] S_guard_hud_elapsed;
    wire S_a38_active,S_a38_running,S_a38_cross_active,S_a38_cross_running,S_a38_cross_live;
    wire S_a38_ui_update,S_a38_ui_live;wire [15:0] S_a38_ui_id,S_a38_ui_x,S_a38_ui_y;
    wire [10:0] S_a38_cross_x;wire [9:0] S_a38_cross_y;
    wire S_a38_update,S_a38_valid;wire [15:0] S_a38_id,S_a38_x,S_a38_y;
    reg S_a38_active_d,S_sad_guard_d;
    wire S_sad_guard_owned,S_sad_guard_reset,S_sad_guard_update;
    wire [52:0] S_sad_guard_record;wire [15:0] S_sad_guard_photo;
    wire S_sad_guard=S_sad_guard_owned && S_guard_session && !S_guard_motion_mode;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n)begin S_a38_active_d<=0;S_sad_guard_d<=0;end
        else begin S_a38_active_d<=S_a38_active;S_sad_guard_d<=S_sad_guard_owned;end
    wire S_guard_overlay=(!S_a38_active || S_sad_guard) && S_guard_session && !S_guard_view_recognition && !S_photo_album;
    wire S_recognition_run=!S_a38_active && (S_guard_session ? !S_guard_motion_mode : S_object_en_active) && !S_photo_album;
    wire S_object_display=S_recognition_run;
    wire S_motion_run=!S_a38_active && (S_guard_session ? S_guard_motion_mode : S_box_en_active) && !S_photo_album;
    wire S_control_send_valid = S_control_valid && !S_photo_album &&
        (S_guard_session ? (!S_guard_motion_mode && S_guard_triggered && !S_guard_wait && !S_guard_edit_pause) : S_object_en_active);
    wire S_photo_command_src_valid,S_photo_command_valid,S_photo_command_mail_busy;
    wire [15:0] S_photo_command_src,S_photo_command;
    wire [15:0] S_photo_record_csi,S_photo_record;
    reg [15:0] S_photo_frame_id;
    reg S_photo_user_d;
    wire [63:0] S_photo_slot_ids;
    wire [3:0] S_photo_slot_good;
    wire S_photo_trigger,S_photo_mail_busy,S_photo_capture,S_photo_busy_event;
    wire S_photo_busy_notice,S_photo_notice_mail_busy;
    wire [17:0] S_photo_capture_source,S_photo_capture_data;
    wire S_photo_store_busy,S_photo_store_album,S_photo_store_bank;
    wire [5:0] S_photo_store_index;
    wire [6:0] S_photo_store_count;
    wire S_photo_store_valid;
    wire S_photo_video_pause,S_photo_video_paused;
    wire [3:0] S_photo_store_status;
    (* ASYNC_REG="TRUE" *) reg [1:0] S_photo_busy_sync,S_photo_bank_ack_sync;
    wire S_photo_ddr_req,S_photo_ddr_write,S_photo_ddr_last,S_photo_ddr_ready,S_photo_ddr_rvalid;
    wire S_photo_video_ready,S_photo_video_rvalid,S_photo_arbiter_fault;
    wire [24:0] S_photo_ddr_addr;
    wire [127:0] S_photo_ddr_wdata;
    wire S_photo_sd_req,S_photo_sd_write,S_photo_sd_ready,S_photo_sd_done,S_photo_sd_error;
    wire [31:0] S_photo_sd_lba,S_photo_sd_sectors;
    wire S_photo_ram_we;
    wire [4:0] S_photo_ram_addr;
    wire [127:0] S_photo_ram_wdata,S_photo_ram_rdata;
    wire [19:0] S_photo_view_source={S_photo_store_album,S_photo_store_bank,S_photo_store_valid,S_photo_store_index,
        S_photo_store_count,
        (S_photo_arbiter_fault ? 4'he : S_photo_store_status)};
    reg [19:0] S_photo_view_sent,S_photo_view_pending,S_photo_view_active;
    wire [19:0] S_photo_view_received;
    wire S_photo_view_mail_busy,S_photo_view_valid;
    wire S_photo_view_send=(S_photo_view_source!=S_photo_view_sent) && !S_photo_view_mail_busy;
    assign S_photo_album=S_photo_view_active[19];
    wire S_photo_display_valid=S_photo_view_active[17];
    wire [24:0] S_photo_display_base=S_photo_view_active[18] ? 25'd30000000 : 25'd28000000;
    // Before the first complete load, keep the album black as the old zero
    // dimensions did. Thereafter every RGB888 pixel is part of the photo.
    wire [23:0] S_photo_video_rgb=(S_photo_album && !S_photo_display_valid) ? 24'd0 : S_video_rd_data;
    wire S_eth_clk,S_pll_reset,S_power_rst_n;
    wire S_cam_rst_n,S_csi_rst_n,S_ddr_rst_n,S_lp_rst_n;
    wire S_eth_ready,S_eth_result_link,S_eth_overflow,S_eth_done,S_eth_link,S_eth_error;
    wire [31:0] S_eth_dropped,S_eth_phy_id;
    wire        S_red_seen_frame, S_green_seen_frame;
    wire [8:0]  S_square_xmin, S_square_xmax, S_triangle_xmin, S_triangle_xmax;
    wire [7:0]  S_square_ymin, S_square_ymax, S_triangle_ymin, S_triangle_ymax;
    reg         S_hdmi_vsync_d;
    wire        S_frame_boundary;

    // 帧差检测输出：320x180 低分辨率域的包围盒四角坐标
    wire        S_zc_box_valid;
    wire [8:0]  S_zc_box_tl_x;
    wire [7:0]  S_zc_box_tl_y;
    wire [8:0]  S_zc_box_tr_x;
    wire [7:0]  S_zc_box_tr_y;
    wire [8:0]  S_zc_box_bl_x;
    wire [7:0]  S_zc_box_bl_y;
    wire [8:0]  S_zc_box_br_x;
    wire [7:0]  S_zc_box_br_y;
    wire [3:0]  S_zc_multi_valid;
    wire [35:0] S_zc_multi_xmin, S_zc_multi_xmax;
    wire [31:0] S_zc_multi_ymin, S_zc_multi_ymax;

    // 打框模块输出：叠加框后的 720p 视频流
    wire        S_dk_vsync;
    wire        S_dk_href;
    wire        S_dk_de;
    wire        S_dk_user;
    wire        S_dk_last;
    wire [23:0] S_dk_rgb;

    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;



    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    video_power_reset u_power_reset(.clk(I_sys_clk),.pll_locked(S_pll_lock),
        .pll_reset(S_pll_reset),.reset_n(S_power_rst_n));
    assign S_rst_n=S_power_rst_n;
    target_reset_sync u_hdmi_reset(S_hdmi_pixel_clk,S_power_rst_n,S_hdmi_rst_n);
    target_reset_sync u_cam_reset(S_24m_clk,S_power_rst_n,S_cam_rst_n);
    target_reset_sync u_csi_reset(S_csi_rx_clk,S_power_rst_n,S_csi_rst_n);
    target_reset_sync u_ddr_reset(S_ddr_clk,S_power_rst_n,S_ddr_rst_n);
    target_reset_sync u_lp_reset(S_100m_clk,S_power_rst_n,S_lp_rst_n);

    // Each mailbox holds its field mask and values through destination ACK.
    wire S_track_return;
    wire S_template_owner,S_template_busy,S_template_sd_req,S_template_sd_write,S_template_ram_we;
    wire [31:0] S_template_sd_lba;wire [4:0] S_template_ram_addr;wire [127:0] S_template_ram_wdata;
    wire S_sector_done,S_sector_error;
    a38_local_control #(.GUARD_FEATURE(1)) u_a38(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.frame_boundary(S_frame_boundary),.pause(S_photo_album),
        .command_valid(S_guard_config_update),.command(S_guard_command),
        .storage_clk(S_ddr_clk),.storage_rst_n(S_ddr_rst_n),.photo_busy(S_photo_store_busy),
        .storage_owner(S_template_owner),.storage_busy(S_template_busy),
        .sd_request(S_template_sd_req),.sd_write(S_template_sd_write),.sd_lba(S_template_sd_lba),
        .sd_ready(S_photo_sd_ready),.sd_done(S_sector_done && S_template_owner),.sd_error(S_sector_error),.sd_sectors(S_photo_sd_sectors),
        .ram_we(S_template_ram_we),.ram_addr(S_template_ram_addr),.ram_wdata(S_template_ram_wdata),.ram_rdata(S_photo_ram_rdata),
        .guard_parent(S_guard_config[34] && !S_guard_mode_request),
        .guard_block(S_guard_edit_pause || S_guard_changed),.guard_epoch(S_guard_epoch),
        .guard_rearm(S_sad_guard && S_track_return),
        .source_frame_id(S_photo_frame_id),.guard_owned(S_sad_guard_owned),.guard_reset(S_sad_guard_reset),
        .guard_update(S_sad_guard_update),.guard_record(S_sad_guard_record),.guard_photo_frame(S_sad_guard_photo),
        .csi_clk(S_csi_rx_clk),.csi_rst_n(S_csi_rst_n),
        .rgb(S_control_rgb),.rgb_valid(S_control_rgb_valid),.rgb_user(S_control_rgb_user),.rgb_last(S_control_rgb_last),
        .active(S_a38_active),.executing(S_a38_running),
        .cross_x(S_a38_cross_x),.cross_y(S_a38_cross_y),.cross_active(S_a38_cross_active),.cross_running(S_a38_cross_running),.cross_live(S_a38_cross_live),
        .ui_update(S_a38_ui_update),.ui_live(S_a38_ui_live),
        .ui_id(S_a38_ui_id),.ui_x(S_a38_ui_x),.ui_y(S_a38_ui_y),
        .tx_update(S_a38_update),.tx_valid(S_a38_valid),.tx_id(S_a38_id),.tx_x(S_a38_x),.tx_y(S_a38_y));
    uart_video_control u_command_uart(
        .clk(I_sys_clk),.rst_n(S_power_rst_n),.rx(I_uart_rx),
        .hdmi_ack(S_uart_hdmi_ack),.csi_ack(S_uart_csi_ack),.cam_ack(S_uart_cam_ack),
        .hdmi_request(S_uart_hdmi_req),.csi_request(S_uart_csi_req),.cam_request(S_uart_cam_req),
        .hdmi_payload(S_uart_hdmi_source),.csi_payload(S_uart_csi_source),.cam_payload(S_uart_cam_source),
        .command_valid(),.command_error(),.guard_ack(S_guard_ack),
        .guard_request(S_guard_req),.guard_payload(S_guard_source),
        .photo_command_valid(S_photo_command_src_valid),.photo_command(S_photo_command_src));
    uart_config_destination #(.WIDTH(16)) u_command_guard(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.request_async(S_guard_req),
        .payload_async(S_guard_source),.ack(S_guard_ack),
        .update(S_guard_config_update),.payload(S_guard_command));
    // TRACK UI DISPATCH BEGIN
    // Mode entry leaves the current guard session like ordinary recognition.
    // Other UI commands never enter the editor's illegal-opcode branch.
    wire S_track_enter=S_guard_config_update &&
        (S_guard_command==16'h2c03 || S_guard_command==16'h2d01 || S_guard_command==16'h3901);
    assign S_track_return=S_guard_config_update && S_guard_command==16'h3000 &&
        S_guard_session && S_guard_triggered && !S_guard_motion_mode &&
        !S_guard_edit_pause && !S_photo_album;
    wire S_guard_legacy_command=S_guard_command[15:8]==8'h09 ||
        S_guard_command[15:8]==8'h0a || S_guard_command[15:8]==8'h0b ||
        S_guard_command[15:8]==8'h0e || S_guard_command[15:8]==8'h28 ||
        (S_guard_command[15:8]>=8'h21 && S_guard_command[15:8]<=8'h25);
    wire S_guard_editor_update=S_guard_config_update && (S_guard_legacy_command || (S_track_return && !S_sad_guard) || S_track_enter);
    wire [15:0] S_guard_editor_command=S_track_enter ? 16'h0a01 :
        (S_track_return ? 16'h0e02 : S_guard_command);
    // TRACK UI DISPATCH END
    guard_roi_commands u_guard_editor(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.frame_boundary(S_frame_boundary),
        .command_valid(S_guard_editor_update),.opcode(S_guard_editor_command[15:8]),.value(S_guard_editor_command[7:0]),
        .configuration(S_guard_config),.changed(S_guard_changed),.qualify_seconds(S_guard_seconds),
        .motion_mode(S_guard_mode_request),
        .preview_points(S_guard_preview),.active_points(S_guard_active),.preview_selected(S_guard_selected),
        .editing(S_guard_editing),.validate_request(S_guard_validate_request),.validate_ready(S_guard_validate_ready),
        .validate_done(S_guard_validate_done),.validate_ok(S_guard_validate_ok),
        .validate_points(S_guard_validate_points),.error());
    guard_polygon_core u_guard_polygon(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.frame_boundary(S_frame_boundary),
        .run(S_guard_session && !S_guard_edit_pause && !S_photo_album),.active_points(S_guard_active_grid),
        .validate_points(S_guard_validate_grid),.validate_request(S_guard_validate_request),
        .validate_ready(S_guard_validate_ready),.validate_done(S_guard_validate_done),.validate_ok(S_guard_validate_ok),
        .result_update(S_sad_guard ? S_sad_guard_update : (S_guard_motion_mode ? S_motion_guard_update : S_control_update)),
        .record(S_sad_guard ? S_sad_guard_record : (S_guard_motion_mode ? S_motion_guard_record : S_guard_record)),
        .photo_record(S_sad_guard ? S_sad_guard_photo : (S_guard_motion_mode ? S_motion_guard_photo : S_photo_record)),
        .overflow_async(S_sad_guard ? 1'b0 : (S_guard_motion_mode ? S_motion_overflow : S_control_overflow)),
        .out_update(S_guard_polygon_update),.out_record(S_guard_polygon_record),
        .out_photo_record(S_guard_polygon_photo),.inside_flags(S_guard_inside),.overflow(S_guard_polygon_overflow));
    guard_mode_controller #(.PHOTO_FEATURE(1),.POLYGON_FEATURE(1),.ALL_FEATURE(1),.SAD_FEATURE(1)) u_guard(
        .mode_request(S_guard_mode_request),.motion_mode(S_guard_motion_mode),
        .motion_photo_taken(S_motion_photo_taken),.motion_photo_qualified(S_motion_photo_qualified),
        .hud_intrusion(S_guard_hud_intrusion),.hud_blink(S_guard_hud_blink),
        .hud_seconds(S_guard_hud_seconds),.hud_elapsed_half(S_guard_hud_elapsed),
        .source_reset(S_sad_guard_reset),.selected_mode(S_sad_guard),.selected_id(S_a38_ui_id),
        .photo_pause(S_photo_album),
        .edit_pause(S_guard_edit_pause),.qualify_seconds(S_guard_seconds),
        .polygon_red_inside(S_guard_inside[0]),.polygon_green_inside(S_guard_inside[1]),
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.frame_boundary(S_frame_boundary),
        .config_update(S_guard_changed),.configuration(S_guard_config),
        .result_update(S_guard_polygon_update),.record(S_guard_polygon_record),.overflow_async(S_guard_polygon_overflow),
        .event_accepted(S_guard_accepted),.session(S_guard_session),.triggered(S_guard_triggered),
        .view_recognition(S_guard_view_recognition),.warning_on(S_guard_warning),
        .xmin(S_guard_xmin),.xmax(S_guard_xmax),.ymin(S_guard_ymin),.ymax(S_guard_ymax),
        .epoch_gray(S_guard_epoch),.region_update(S_region_update),.region_inside(S_region_inside),
        .event_pulse(S_guard_event),.event_wait(S_guard_wait),
        .cancel_event(S_guard_cancel),.event_id(S_guard_id),.event_x(S_guard_x),.event_y(S_guard_y));
    uart_config_destination #(.WIDTH(17)) u_command_hdmi(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.request_async(S_uart_hdmi_req),
        .payload_async(S_uart_hdmi_source),.ack(S_uart_hdmi_ack),
        .update(S_uart_hdmi_update),.payload(S_uart_hdmi_data));
    uart_config_destination #(.WIDTH(18)) u_command_csi(
        .clk(S_csi_rx_clk),.rst_n(S_csi_rst_n),.request_async(S_uart_csi_req),
        .payload_async(S_uart_csi_source),.ack(S_uart_csi_ack),
        .update(S_uart_csi_update),.payload(S_uart_csi_data));
    uart_config_destination #(.WIDTH(6)) u_command_cam(
        .clk(S_24m_clk),.rst_n(S_cam_rst_n),.request_async(S_uart_cam_req),
        .payload_async(S_uart_cam_source),.ack(S_uart_cam_ack),
        .update(S_uart_cam_update),.payload(S_uart_cam_data));
    function [15:0] camera_ag_from_level;
        input [4:0] level;
        begin
            // SC500: 17 UART levels, valid AG16..89, midpoint AG=80 (4x).
            // Rounded linear spacing on each side; no new register latency.
            case(level)
                5'd0: camera_ag_from_level=16'd16;
                5'd1: camera_ag_from_level=16'd24;
                5'd2: camera_ag_from_level=16'd32;
                5'd3: camera_ag_from_level=16'd40;
                5'd4: camera_ag_from_level=16'd48;
                5'd5: camera_ag_from_level=16'd56;
                5'd6: camera_ag_from_level=16'd64;
                5'd7: camera_ag_from_level=16'd72;
                5'd8: camera_ag_from_level=16'd80;
                5'd9: camera_ag_from_level=16'd81;
                5'd10: camera_ag_from_level=16'd82;
                5'd11: camera_ag_from_level=16'd83;
                5'd12: camera_ag_from_level=16'd85;
                5'd13: camera_ag_from_level=16'd86;
                5'd14: camera_ag_from_level=16'd87;
                5'd15: camera_ag_from_level=16'd88;
                5'd16: camera_ag_from_level=16'd89;
                default: camera_ag_from_level=16'd80;
            endcase
        end
    endfunction
    assign S_uart_camera_ag=camera_ag_from_level(S_uart_cam_data[4:0]);

    // Serial rank 0..16; AUTO retains its original eight gradual targets.
    raw10_auto_gain u_raw10_auto_gain (
        .I_clk(S_csi_rx_clk), .I_rst_n(S_csi_rst_n),
        .I_config_valid(S_uart_csi_update && S_uart_csi_data[17]),
        .I_config_gain(S_uart_csi_data[14:10]),
        .I_auto_enable(S_auto_enable_csi), .I_tuser(S_axis_tuser), .I_tvalid(S_axis_tvalid),
        .I_cmd_toggle_async(S_auto_dgain_request), .I_cmd_gain_async(S_auto_dgain),
        .I_cmd_epoch_async(S_auto_dgain_epoch), .O_gain_sel(S_raw_gain_sel),
        .O_gain_active(S_raw_gain_active), .O_gain_saved(S_raw_gain_saved),
        .O_epoch(S_raw_gain_epoch), .O_cmd_ack(S_auto_dgain_ack)
    );

    // The mode is selected in the HDMI domain and used only as a stable enable.
    always @(posedge S_24m_clk or negedge S_cam_rst_n) begin
        if(!S_cam_rst_n) begin auto_mode_meta_24m<=1'b0; auto_mode_sync_24m<=1'b0; end
        else begin auto_mode_meta_24m <= (S_proc_sel_effective == 4'd12); auto_mode_sync_24m <= auto_mode_meta_24m; end
    end
    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n) begin auto_mode_meta_csi<=1'b0; auto_mode_sync_csi<=1'b0; end
        else begin auto_mode_meta_csi <= (S_proc_sel_effective == 4'd12); auto_mode_sync_csi <= auto_mode_meta_csi; end
    end

    // Serial mode, detector priority and row visibility commit at HDMI blanking.
    assign S_frame_boundary = S_hdmi_vsync & ~S_hdmi_vsync_d;
    assign S_proc_sel_effective = (S_a38_active | S_box_en_active | S_object_en_active | S_guard_session | S_photo_album) ? 4'd0 : S_proc_sel_active;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_proc_sel_pending<=0;S_proc_sel_active<=0;
            S_box_en_pending<=0;S_box_en_active<=0;
            S_object_en_pending<=0;S_object_en_active<=0;
            S_display_pending<=4'h0;S_display_active<=4'h0;
            S_hdmi_vsync_d<=0;
        end else begin
            S_hdmi_vsync_d<=S_hdmi_vsync;
            if(S_uart_hdmi_update) begin
                if(S_uart_hdmi_data[10]) S_proc_sel_pending<=S_uart_hdmi_data[3:0];
                if(S_uart_hdmi_data[11]) S_display_pending[0]<=S_uart_hdmi_data[4];
                if(S_uart_hdmi_data[12]) S_display_pending[1]<=S_uart_hdmi_data[5];
                if(S_uart_hdmi_data[13]) S_display_pending[2]<=S_uart_hdmi_data[6];
                if(S_uart_hdmi_data[14]) S_display_pending[3]<=S_uart_hdmi_data[7];
                if(S_uart_hdmi_data[15]) S_box_en_pending<=S_uart_hdmi_data[8];
                if(S_uart_hdmi_data[16]) S_object_en_pending<=S_uart_hdmi_data[9];
            end
            if(S_frame_boundary) begin
                S_proc_sel_active<=S_proc_sel_pending;
                S_box_en_active<=S_box_en_pending &&
                    !(S_object_en_pending || S_static_track_active || S_range_hold_active);
                S_object_en_active<=S_object_en_pending || S_static_track_active || S_range_hold_active;
                S_display_active<=S_display_pending;
            end
        end
    end

    // VTC request to vision output: 3/5/7 clocks, CARTOON 8 clocks.
    // Common video_out latency is 2; vision contributes 1/3/5 or CARTOON 6.
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_video_de_dly <= 2'b00;
            S_video_vs_dly <= 2'b00;
            S_video_hs_dly <= 2'b00;
            S_video_user_dly <= 2'b00;
            S_video_last_dly <= 2'b00;
        end else begin
            S_video_de_dly <= {S_video_de_dly[0], S_hdmi_de};
            S_video_vs_dly <= {S_video_vs_dly[0], S_hdmi_vsync};
            S_video_hs_dly <= {S_video_hs_dly[0], S_hdmi_hsync};
            S_video_user_dly <= {S_video_user_dly[0], S_hdmi_user};
            S_video_last_dly <= {S_video_last_dly[0], S_hdmi_last};
        end
    end
    assign S_vision_lv1 = (S_proc_sel_effective == 4'd0) ||
                          (S_proc_sel_effective >= 4'd12);
    assign S_vision_lv5 = (S_proc_sel_effective == 4'd3) ||
                          (S_proc_sel_effective == 4'd4) ||
                          (S_proc_sel_effective == 4'd5) ||
                          (S_proc_sel_effective == 4'd6);
    assign S_vision_lv6 = (S_proc_sel_effective == 4'd11);

    // user / last 必须与 vision 延时后的 de 对齐，否则 S_x 每行提前归零、逐行累积偏移
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_vision_user_dly <= 6'b000000;
            S_vision_last_dly <= 6'b000000;
        end
        else begin
            S_vision_user_dly <= {S_vision_user_dly[4:0], S_video_user_aligned};
            S_vision_last_dly <= {S_vision_last_dly[4:0], S_video_last_aligned};
        end
    end

    assign S_vision_user_sel = S_vision_lv6 ? S_vision_user_dly[5] :
                               S_vision_lv5 ? S_vision_user_dly[4] :
                               S_vision_lv1 ? S_vision_user_dly[0] :
                                              S_vision_user_dly[2];
    assign S_vision_last_sel = S_vision_lv6 ? S_vision_last_dly[5] :
                               S_vision_lv5 ? S_vision_last_dly[4] :
                               S_vision_lv1 ? S_vision_last_dly[0] :
                                              S_vision_last_dly[2];

    // FIFO read request stays on the original VTC DE, before the two-clock delay.
    assign S_hdmi_window_rd_en = S_hdmi_de;

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_cam_rst_n) begin
        if(!S_cam_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n) begin
        if(!S_csi_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_ddr_rst_n) begin
        if(!S_ddr_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),
        S_ddr_user_rd_valid,
        S_vo_ddr_rd_en,
        S_vi_ddr_wr_en
    };
	
	// SC500CS上电后先保持PWDNB/XSHUTDN为低，再释放并等待内部上电完成，
	// 避免PLL刚锁定就开始I2C初始化而造成寄存器偶发写入失败。
	always @(posedge S_24m_clk or negedge S_cam_rst_n) begin
		if (!S_cam_rst_n) begin
			S_cam_power_cnt <= 18'd0;
			S_cam_pwdnb <= 1'b0;
			S_cam_i2c_ready <= 1'b0;
		end else begin
			if (S_cam_power_cnt < CAM_I2C_START_CYCLES)
				S_cam_power_cnt <= S_cam_power_cnt + 1'b1;
			if (S_cam_power_cnt >= CAM_PWDNB_LOW_CYCLES)
				S_cam_pwdnb <= 1'b1;
			if (S_cam_power_cnt >= CAM_I2C_START_CYCLES - 1)
				S_cam_i2c_ready <= 1'b1;
		end
	end

	assign O_cam_rst 	= S_cam_pwdnb;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( S_pll_reset       ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),
        .clk2_out    ( S_eth_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
    camera_auto_exposure #(
        .DARK_MIN_MEAN(AE_DARK_MIN_MEAN), .RECOVER_MIN_MEAN(AE_RECOVER_MIN_MEAN),
        .CONFIRM_SAMPLES(AE_CONFIRM_SAMPLES),
        .SETTLE_FRAMES(AE_SETTLE_FRAMES)
    ) u_camera_auto_exposure (
        .I_clk(S_24m_clk), .I_rst_n(S_cam_rst_n), .I_auto_enable(S_auto_enable_24m),
        .I_seed_ae(S_manual_seed_ae), .I_seed_ag(S_manual_seed_ag),
        .I_cam_cfg_done(S_cam_cfg_done), .I_ae_cfg_done(S_ae_cfg_done), .I_ae_req(S_ae_req),
        .I_submitted_ae(S_ae), .I_submitted_ag(S_ag), .I_iic_error(S_cam_i2c_error),
        .I_stat_toggle_async(S_ae_stat_toggle), .I_stat_sum_async(S_ae_stat_sum),
        .I_stat_valid_async(S_ae_stat_valid), .I_stat_gain_async(S_ae_stat_gain),
        .I_stat_epoch_async(S_ae_stat_epoch), .I_dgain_ack_async(S_auto_dgain_ack),
        .O_stat_request(S_ae_stat_request), .O_stat_skip(S_ae_stat_skip),
        .O_dgain_request(S_auto_dgain_request), .O_dgain(S_auto_dgain),
        .O_dgain_epoch(S_auto_dgain_epoch), .O_targets_valid(S_auto_targets_valid),
        .O_ae(S_auto_ae), .O_ag(S_auto_ag), .O_target_sum(), .O_target_valid(S_auto_target_valid)
    );

  ae_set u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_cam_rst_n),
      .I_config_valid(S_uart_cam_update && S_uart_cam_data[5]),
      .I_config_ag(S_uart_camera_ag),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .I_auto_enable(S_auto_enable_24m),
      .I_auto_targets_valid(S_auto_targets_valid),
      .O_seed_ae(S_manual_seed_ae), .O_seed_ag(S_manual_seed_ag),
      .I_auto_ae(S_auto_ae),
      .I_auto_ag(S_auto_ag),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );
  
    // SC500CS参考HD模式：1280x720@60、RAW10、2-Lane、名义480 Mbps/Lane。
    // 116笔配置沿用720p例程，stream-on后等待约10ms再释放302d。
    uicfgcs500_720p #(
      .CLK_DIV(23809524 / 100000 - 1)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_i2c_ready), // SC500CS power-up delay completed
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done),  //AE配置完成
      .O_sensor_id(S_cam_sensor_id),
      .O_sensor_id_ok(S_cam_sensor_id_ok),
      .O_iic_error(S_cam_i2c_error)
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_lp_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_csi_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_csi_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_csi_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

raw10_ae_stats u_raw10_ae_stats (
    .I_clk(S_csi_rx_clk), .I_rst_n(S_csi_rst_n), .I_auto_enable(S_auto_enable_csi),
    .I_request_async(S_ae_stat_request), .I_skip_async(S_ae_stat_skip),
    .I_gain_active(S_raw_gain_saved), .I_epoch(S_raw_gain_epoch),
    .I_tvalid(S_axis_tvalid), .I_tuser(S_axis_tuser), .I_tdata(S_axis_tdata),
    .O_frame_sum(S_ae_stat_sum), .O_frame_toggle(S_ae_stat_toggle),
    .O_frame_valid(S_ae_stat_valid), .O_frame_gain(S_ae_stat_gain), .O_frame_epoch(S_ae_stat_epoch)
);

raw10_dgain u_raw10_dgain (
    .I_clk(S_csi_rx_clk), .I_rst_n(S_csi_rst_n), .I_gain_sel(S_raw_gain_sel),
    .I_tuser(S_axis_tuser), .I_tlast(S_axis_tlast), .I_tvalid(S_axis_tvalid),
    .I_tdata(S_axis_tdata), .O_tuser(S_raw_gain_user), .O_tlast(S_raw_gain_last),
    .O_tvalid(S_raw_gain_valid), .O_tdata(S_raw_gain_data)
);

// 原厂HD模式直接输出1280x720 RAW10，不再进行FPGA固定窗口裁剪。
assign S_raw_tdata  = S_raw_gain_data;
assign S_raw_tlast  = S_raw_gain_last;
assign S_raw_tvalid = S_raw_gain_valid;
assign S_raw_tuser  = S_raw_gain_user;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


    // Read-only manual parameter HUD. Business control and video paths are
    // unchanged; only completed parameter records cross into the HDMI domain.
    wire S_ui_contrast_commit,S_ui_saturation_commit,S_ui_gain_commit,S_ui_camera_commit;
    wire [4:0] S_ui_contrast_level,S_ui_saturation_level,S_ui_gain_level,S_ui_camera_level;
    wire S_ui_csi_event,S_ui_cam_csi_event;
    wire [6:0] S_ui_csi_record,S_ui_cam_csi_record;
    reg S_ui_auto_csi_q;
    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n)
        if(!S_csi_rst_n)S_ui_auto_csi_q<=0;
        else S_ui_auto_csi_q<=S_auto_enable_csi;
    hud_level_commit u_ui_gain_commit(
        .clk(S_csi_rx_clk),.rst_n(S_csi_rst_n),
        .manual_enable(!S_auto_enable_csi && !S_ui_auto_csi_q),.frame_start(S_axis_tuser),
        .config_valid(S_uart_csi_update && S_uart_csi_data[17]),.config_level(S_uart_csi_data[14:10]),
        .commit(S_ui_gain_commit),.level(S_ui_gain_level));
    hud_camera_commit u_ui_camera_commit(
        .clk(S_24m_clk),.rst_n(S_cam_rst_n),.auto_enable(S_auto_enable_24m),
        .config_valid(S_uart_cam_update && S_uart_cam_data[5]),.config_level(S_uart_cam_data[4:0]),
        .config_ag(S_uart_camera_ag),.submitted_ag(S_ag),.ae_request(S_ae_req),
        .cam_done(S_cam_cfg_done),.ae_done(S_ae_cfg_done),.iic_error(S_cam_i2c_error),
        .commit(S_ui_camera_commit),.level(S_ui_camera_level));
    hud_event_cdc u_ui_csi_cdc(
        .src_clk(S_csi_rx_clk),.src_rst_n(S_csi_rst_n),
        .src_event(S_ui_cam_csi_event || S_ui_gain_commit || S_ui_contrast_commit || S_ui_saturation_commit),
        .src_record(S_ui_cam_csi_event ? S_ui_cam_csi_record :
            (S_ui_gain_commit ? {2'd2,S_ui_gain_level} :
            (S_ui_contrast_commit ? {2'd0,S_ui_contrast_level} : {2'd1,S_ui_saturation_level}))),
        .dst_clk(S_hdmi_pixel_clk),.dst_rst_n(S_hdmi_rst_n),
        .dst_event(S_ui_csi_event),.dst_record(S_ui_csi_record));
    // Merge camera commits in CSI before the CSI->HDMI mailbox. Both hops
    // cross the existing CSI asynchronous clock group; no new exception or
    // sub-cycle path between related PLL24M and HDMI clocks is introduced.
    hud_event_cdc u_ui_cam_cdc(
        .src_clk(S_24m_clk),.src_rst_n(S_cam_rst_n),.src_event(S_ui_camera_commit),
        .src_record({2'd3,S_ui_camera_level}),.dst_clk(S_csi_rx_clk),.dst_rst_n(S_csi_rst_n),
        .dst_event(S_ui_cam_csi_event),.dst_record(S_ui_cam_csi_record));

//ISP算法顶层模块
isp_top u_isp_top (
.I_contrast_valid (S_uart_csi_update && S_uart_csi_data[16]),
.I_contrast_level (S_uart_csi_data[9:5]),
.I_saturation_valid (S_uart_csi_update && S_uart_csi_data[15]),
.I_saturation_level (S_uart_csi_data[4:0]),
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_csi_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        (),
.O_control_rgb  (S_control_rgb),
.O_ui_contrast_commit(S_ui_contrast_commit),.O_ui_saturation_commit(S_ui_saturation_commit),
.O_ui_contrast_level(S_ui_contrast_level),.O_ui_saturation_level(S_ui_saturation_level),
.O_control_valid(S_control_rgb_valid),.O_control_user(S_control_rgb_user),
.O_control_last (S_control_rgb_last)
  );


    // Camera tag changes on the un-packed ISP SOF; packed SOF is one clock later.
    always @(posedge S_csi_rx_clk or negedge S_csi_rst_n)begin
        if(!S_csi_rst_n)begin S_photo_frame_id<=0;S_photo_user_d<=0;end
        else begin
            S_photo_user_d<=S_control_rgb_user;
            if(S_control_rgb_user && !S_photo_user_d)S_photo_frame_id<=S_photo_frame_id+1'b1;
        end
    end
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
        if(!S_hdmi_rst_n)begin
            S_photo_busy_sync<=0;S_photo_view_pending<=0;S_photo_view_active<=0;
        end else begin
            S_photo_busy_sync<={S_photo_busy_sync[0],S_photo_store_busy};
            if(S_photo_view_valid)S_photo_view_pending<=S_photo_view_received;
            // FIFO prefetch begins on falling VS, not on the original mode
            // commit's rising VS. Commit photo bank/valid BEFORE that prefetch.
            if(!S_hdmi_vsync && S_hdmi_vsync_d)S_photo_view_active<=S_photo_view_pending;
        end
    end
    always @(posedge S_ddr_clk or negedge S_ddr_rst_n)begin
        if(!S_ddr_rst_n)begin S_photo_view_sent<=0;S_photo_bank_ack_sync<=0;end
        else begin
            if(S_photo_view_send)S_photo_view_sent<=S_photo_view_source;
            S_photo_bank_ack_sync<={S_photo_bank_ack_sync[0],S_photo_view_active[18]};
        end
    end
    guard_photo_trigger #(.POLYGON_FEATURE(1),.ALL_FEATURE(1),.SAD_FEATURE(1)) u_photo_trigger(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .motion_mode(S_guard_motion_mode),.motion_photo_qualified(S_motion_photo_qualified),
        .motion_photo_taken(S_motion_photo_taken),.selected_mode(S_sad_guard),.source_reset(S_sad_guard_reset),
        .session(S_guard_session),.triggered(S_guard_triggered),.paused(S_photo_album || S_guard_edit_pause),
        .result_update(S_guard_polygon_update),.overflow(S_guard_polygon_overflow),
        .busy(S_photo_busy_sync[1] || S_photo_mail_busy),.epoch(S_guard_epoch),
        .guard_record(S_guard_polygon_record),.photo_record(S_guard_polygon_photo),
        .polygon_red_inside(S_guard_inside[0]),.polygon_green_inside(S_guard_inside[1]),
        .xmin(S_guard_xmin),.xmax(S_guard_xmax),.ymin(S_guard_ymin),.ymax(S_guard_ymax),
        .request(S_photo_trigger),.payload(S_photo_capture_source),.busy_event(S_photo_busy_event));
    photo_mailbox #(.WIDTH(18)) u_photo_capture_mail(.src_clk(S_hdmi_pixel_clk),.src_rst_n(S_hdmi_rst_n),
        .src_send(S_photo_trigger),.src_data(S_photo_capture_source),.src_busy(S_photo_mail_busy),
        .dst_clk(S_ddr_clk),.dst_rst_n(S_ddr_rst_n),.dst_valid(S_photo_capture),.dst_data(S_photo_capture_data));
    photo_mailbox #(.WIDTH(1)) u_photo_notice_mail(.src_clk(S_hdmi_pixel_clk),.src_rst_n(S_hdmi_rst_n),
        .src_send(S_photo_busy_event),.src_data(1'b1),.src_busy(S_photo_notice_mail_busy),
        .dst_clk(S_ddr_clk),.dst_rst_n(S_ddr_rst_n),.dst_valid(S_photo_busy_notice),.dst_data());
    photo_mailbox #(.WIDTH(16)) u_photo_command_mail(.src_clk(I_sys_clk),.src_rst_n(S_power_rst_n),
        .src_send(S_photo_command_src_valid),.src_data(S_photo_command_src),.src_busy(S_photo_command_mail_busy),
        .dst_clk(S_ddr_clk),.dst_rst_n(S_ddr_rst_n),.dst_valid(S_photo_command_valid),.dst_data(S_photo_command));
    photo_mailbox #(.WIDTH(20)) u_photo_view_mail(.src_clk(S_ddr_clk),.src_rst_n(S_ddr_rst_n),
        .src_send(S_photo_view_send),.src_data(S_photo_view_source),.src_busy(S_photo_view_mail_busy),
        .dst_clk(S_hdmi_pixel_clk),.dst_rst_n(S_hdmi_rst_n),.dst_valid(S_photo_view_valid),.dst_data(S_photo_view_received));
    sd_photo_store #(.SOURCE_FREEZE(1),.SLOT_COUNT(2)) u_photo_store(.clk(S_ddr_clk),.rst_n(S_ddr_rst_n),
        .video_pause(S_photo_video_pause),.video_paused(S_photo_video_paused),
        .capture(S_photo_capture && !S_template_busy),.capture_data(S_photo_capture_data),
        .command_valid(S_photo_command_valid && !S_template_busy),.command(S_photo_command),.busy_notice(S_photo_busy_notice),
        .frame_ids(S_photo_slot_ids),.frame_good(S_photo_slot_good),.display_ack_bank(S_photo_bank_ack_sync[1]),
        .busy(S_photo_store_busy),.status(S_photo_store_status),.album(S_photo_store_album),
        .display_bank(S_photo_store_bank),.display_index(S_photo_store_index),.photo_count(S_photo_store_count),
        .display_valid(S_photo_store_valid),
        .ddr_req(S_photo_ddr_req),.ddr_write(S_photo_ddr_write),.ddr_last(S_photo_ddr_last),
        .ddr_addr(S_photo_ddr_addr),.ddr_wdata(S_photo_ddr_wdata),.ddr_ready(S_photo_ddr_ready),
        .ddr_rvalid(S_photo_ddr_rvalid),.ddr_rdata(S_ddr_user_rd_data),
        .sd_request(S_photo_sd_req),.sd_write(S_photo_sd_write),.sd_lba(S_photo_sd_lba),
        .sd_ready(S_photo_sd_ready && !S_template_owner),.sd_done(S_photo_sd_done),.sd_error(S_photo_sd_error),.sd_sectors(S_photo_sd_sectors),
        .ram_we(S_photo_ram_we),.ram_addr(S_photo_ram_addr),.ram_wdata(S_photo_ram_wdata),.ram_rdata(S_photo_ram_rdata));
    photo_sector_bridge u_photo_sector(.clk(S_ddr_clk),.rst_n(S_ddr_rst_n),.sys_clk(I_sys_clk),.sys_rst_n(S_power_rst_n),
        .request(S_template_owner?S_template_sd_req:S_photo_sd_req),.write(S_template_owner?S_template_sd_write:S_photo_sd_write),
        .lba(S_template_owner?S_template_sd_lba:S_photo_sd_lba),
        .ram_we(S_template_owner?S_template_ram_we:S_photo_ram_we),.ram_addr(S_template_owner?S_template_ram_addr:S_photo_ram_addr),
        .ram_wdata(S_template_owner?S_template_ram_wdata:S_photo_ram_wdata),.ram_rdata(S_photo_ram_rdata),
        .done(S_sector_done),.error(S_sector_error),.ready(S_photo_sd_ready),.sectors(S_photo_sd_sectors),
        .sd_cs(O_sd_cs),.sd_clk(O_sd_clk),.sd_mosi(O_sd_mosi),.sd_miso(I_sd_miso));

    assign S_photo_sd_done=S_sector_done && !S_template_owner;
    assign S_photo_sd_error=S_sector_error;
    video_in #(.PHOTO_FEATURE(1),.PHOTO_FREEZE(1)) u_video_in(
        .I_photo_pause(S_photo_video_pause),.O_photo_paused(S_photo_video_paused),
        .I_photo_frame_id(S_photo_frame_id),.O_photo_slot_ids(S_photo_slot_ids),.O_photo_slot_good(S_photo_slot_good),
        .O_frame_write_start  ( S_latency_write_start ),
        .O_frame_write_slot   ( S_latency_write_slot ),
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_photo_video_ready   )
    );



    photo_ddr_arbiter u_photo_arbiter(
        .clk(S_ddr_clk),.rst_n(S_ddr_rst_n),
        .video_wr(S_vi_ddr_wr_en),.video_wr_busy(S_video_in_wr_busy),
        .video_rd(S_vo_ddr_rd_en),.video_rd_busy(S_video_out_rd_busy),
        .video_wr_addr(S_vi_ddr_wr_addr),.video_rd_addr(S_vo_ddr_rd_addr),.video_wr_data(S_vi_ddr_wr_data),
        .video_ready(S_photo_video_ready),.photo_req(S_photo_ddr_req),.photo_write(S_photo_ddr_write),
        .photo_last(S_photo_ddr_last),.photo_addr(S_photo_ddr_addr),.photo_data(S_photo_ddr_wdata),
        .photo_ready(S_photo_ddr_ready),.photo_rvalid(S_photo_ddr_rvalid),.video_rvalid(S_photo_video_rvalid),
        .user_ready(S_ddr_user_ready),.user_rvalid(S_ddr_user_rd_valid),.user_rdata(S_ddr_user_rd_data),
        .user_wr(S_ddr_user_wr_en),.user_rd(S_ddr_user_rd_en),.user_addr(S_ddr_user_addr),
        .user_wdata(S_ddr_user_wr_data),.fault(S_photo_arbiter_fault));


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out #(.PHOTO_FEATURE(1)) u_video_out(
        .I_photo_enable(S_photo_album && S_photo_display_valid),.I_photo_base(S_photo_display_base),
        .O_frame_read_start  ( S_latency_read_start ),
        .O_frame_read_slot   ( S_latency_read_slot ),
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_photo_video_ready  ),
        .I_ddr_user_rd_valid ( S_photo_video_rvalid ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_de           ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_ddr_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    vision #(
        .VIDEO_WIDTH  ( 1280 ),
        .VIDEO_HEIGHT ( 720  )
    )u_vision(
        .clk              ( S_hdmi_pixel_clk   ),
        .rst_n            ( S_hdmi_rst_n       ),
        .pre_frame_vsync  ( S_video_vs_aligned ),
        .pre_frame_href   ( S_video_hs_aligned ),
        .pre_frame_de     ( S_video_de_aligned ),
        .pre_rgb          ( S_photo_video_rgb  ),
        .proc_sel         ( S_proc_sel_effective),
        .post_frame_vsync ( S_vision_vsync     ),
        .post_frame_href  ( S_vision_href      ),
        .post_frame_de    ( S_vision_de        ),
        .post_rgb         ( S_vision_rgb       )
    );

    // 帧差法运动检测：只读观测像素流，输出 320x180 域包围盒四角坐标
    // 不插入数据通路，因此不影响 vision 的时序
    // Legacy coordinate display follows track zero. Only one frame RAM is instantiated.
    assign S_zc_box_valid = S_zc_multi_valid[0];
    assign S_zc_box_tl_x = S_zc_multi_xmin[8:0];
    assign S_zc_box_bl_x = S_zc_multi_xmin[8:0];
    assign S_zc_box_tr_x = S_zc_multi_xmax[8:0];
    assign S_zc_box_br_x = S_zc_multi_xmax[8:0];
    assign S_zc_box_tl_y = S_zc_multi_ymin[7:0];
    assign S_zc_box_tr_y = S_zc_multi_ymin[7:0];
    assign S_zc_box_bl_y = S_zc_multi_ymax[7:0];
    assign S_zc_box_br_y = S_zc_multi_ymax[7:0];

    wire S_motion_gain_restart;
    motion_gain_change_cdc u_motion_gain_change_cdc (
        .I_cam_clk(S_24m_clk), .I_cam_rst_n(S_cam_rst_n),
        .I_cam_cfg_done(S_cam_cfg_done), .I_ae_req(S_ae_req), .I_ae_cfg_done(S_ae_cfg_done),
        .I_iic_error(S_cam_i2c_error), .I_submitted_ag(S_ag),
        .I_hdmi_clk(S_hdmi_pixel_clk), .I_hdmi_rst_n(S_hdmi_rst_n),
        .I_hdmi_vsync(S_video_vs_aligned), .O_restart(S_motion_gain_restart)
    );

    zhencha_multi_ccl #(
        .H_ACTIVE (1280), .V_ACTIVE (720), .DS (4),
        .THRESH (`FPGA_MOTION_TOP_DIFF), .MIN_AREA (`FPGA_MOTION_TOP_AREA), .TRACK_MIN_AREA (`FPGA_MOTION_TOP_TRACK_AREA), .MAX_TRACK (2), .LABELS (16),
        .GAIN_SETTLE_FRAMES(MOTION_GAIN_SETTLE_FRAMES)
    )u_zhencha_multi_ccl(
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n),
        .detect_en(S_motion_run), .gain_change(S_motion_gain_restart),
        .pre_frame_vsync(S_video_vs_aligned),
        .pre_frame_de(S_video_de_aligned), .pre_rgb(S_video_rd_data),
        .box_valid(S_zc_multi_valid), .box_xmin(S_zc_multi_xmin),
        .box_xmax(S_zc_multi_xmax), .box_ymin(S_zc_multi_ymin),
        .box_ymax(S_zc_multi_ymax), .result_update(S_motion_result_update),
        .result_ready(S_motion_result_ready), .overflow(S_motion_overflow),.result_fresh(S_motion_result_fresh)
    );
    motion_guard_record u_motion_guard_record(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .enabled(S_guard_session && S_guard_motion_mode),.paused(S_guard_edit_pause || S_photo_album),
        .frame_boundary(S_frame_boundary),.frame_start(S_video_user_aligned && S_video_de_aligned),
        .frame_de(S_video_de_aligned && !S_video_vs_aligned),
        .source_id(S_motion_frame_id),.source_good(S_motion_frame_good),.epoch(S_guard_epoch),
        .result_update(S_motion_result_update),.result_ready(S_motion_result_ready),.overflow(S_motion_overflow),
        .fresh(S_motion_result_fresh),.box_xmin(S_zc_multi_xmin),.box_xmax(S_zc_multi_xmax),
        .box_ymin(S_zc_multi_ymin),.box_ymax(S_zc_multi_ymax),
        .out_update(S_motion_guard_update),.record(S_motion_guard_record),.photo_record(S_motion_guard_photo));

    // Match geometry to the actual DDR source frame, then commit before its
    // first RGB pixel. This replaces the duplicate post-DDR spatial engine.
    color_shared_display u_shared_display (
        .camera_clk(S_csi_rx_clk),.camera_rst_n(S_csi_rst_n),
        .candidate_update(S_shared_update),.candidate_record(S_shared_record),
        .ddr_clk(S_ddr_clk),.ddr_rst_n(S_ddr_rst_n),
        .read_start(S_latency_read_start),.read_slot(S_latency_read_slot),
        .write_start(S_latency_write_start),.write_slot(S_latency_write_slot),
        .slot_ids(S_photo_slot_ids),.slot_good(S_photo_slot_good),
        .pixel_clk(S_hdmi_pixel_clk),.pixel_rst_n(S_hdmi_rst_n),
        .vsync(S_hdmi_vsync),.first_pixel(S_hdmi_user && S_hdmi_de),.enable(S_recognition_run),
        .box_valid({S_triangle_valid,S_square_valid}),.seen({S_green_seen_frame,S_red_seen_frame}),
        .boxes({S_triangle_xmin,S_triangle_xmax,S_triangle_ymin,S_triangle_ymax,
                S_square_xmin,S_square_xmax,S_square_ymin,S_square_ymax}),
        .result_update(S_object_update),.overflow(S_shared_overflow),
        .latency_update(S_color_latency_update),.latency_valid(S_color_latency_valid),
        .latency_ticks(S_color_latency_ticks),.frame_matched(),.displayed_id(S_motion_frame_id),
        .source_frame_good(S_motion_frame_good));

    color_control_detect #(.GUARD_FEATURE(1),.PHOTO_FEATURE(1),.SHARE_DISPLAY(1)) u_control_detect (
        .photo_frame_id(S_photo_frame_id+16'd1),.photo_record(S_photo_record_csi),
        .clk(S_csi_rx_clk),.rst_n(S_csi_rst_n),.detect_en_async(S_recognition_run),
        .guard_epoch_async(S_guard_epoch),.guard_record(S_guard_record_csi),
        .rgb(S_control_rgb),.valid(S_control_rgb_valid),
        .user(S_control_rgb_user),.last(S_control_rgb_last),
        .result_update(S_control_update_csi),.target_valid(S_control_valid_csi),
        .target_id(S_control_id_csi),.center_x(S_control_x_csi),.center_y(S_control_y_csi),
        .protocol_error(S_control_protocol_error),
        .display_update(S_shared_update),.display_record(S_shared_record));
    color_control_result_cdc #(.GUARD_FEATURE(1),.PHOTO_FEATURE(1)) u_control_result_cdc (
        .photo_record(S_photo_record_csi),.out_photo_record(S_photo_record),
        .guard_record(S_guard_record_csi),.out_guard_record(S_guard_record),
        .wr_clk(S_csi_rx_clk),.wr_rst_n(S_csi_rst_n),
        .result_update(S_control_update_csi),.target_valid(S_control_valid_csi),
        .target_id(S_control_id_csi),.center_x(S_control_x_csi),.center_y(S_control_y_csi),
        .rd_clk(S_hdmi_pixel_clk),.rd_rst_n(S_hdmi_rst_n),
        .out_update(S_control_update),.out_valid(S_control_valid),
        .out_id(S_control_id),.out_x(S_control_x),.out_y(S_control_y),
        .overflow(S_control_overflow));

    // Center-reached notification, NOT measured-distance validity. Keep the
    // original one-register metadata latency so guard_first_tag stays aligned.
    // The public UDP core retains its distance_valid port name / byte3 bit1.
    wire S_send_reset_n;
    target_reset_sync u_send_reset(S_hdmi_pixel_clk,S_power_rst_n,S_send_reset_n);
    // Nested SAD is evidence for the original guard, never a direct bypass.
    wire S_sad_follow=S_sad_guard && S_a38_running && S_guard_triggered && !S_guard_wait &&
        !S_guard_edit_pause && S_guard_polygon_record[52] &&
        S_guard_polygon_record[51:44]==S_guard_epoch && S_guard_polygon_record[42];
    wire S_send_in_update = (!S_a38_active || S_sad_guard) &&
        (S_guard_event || ((S_sad_guard ? S_guard_polygon_update : S_control_update) && !S_guard_wait)) &&
        !(S_guard_session && (S_guard_edit_pause || S_guard_motion_mode)) && !S_sad_guard_reset;
    wire S_send_in_valid = S_guard_event || (S_sad_guard ? S_sad_follow : S_control_send_valid);
    wire [15:0] S_follow_id=S_sad_guard ? S_a38_ui_id : S_control_id;
    wire [15:0] S_follow_x=S_sad_guard ? {5'd0,S_guard_polygon_record[10:0]} : S_control_x;
    wire [15:0] S_follow_y=S_sad_guard ? {6'd0,S_guard_polygon_record[20:11]} : S_control_y;
    wire [15:0] S_send_in_id = S_guard_event ? S_guard_id : (S_send_in_valid ? S_follow_id : 16'd0);
    wire [15:0] S_send_in_x = S_guard_event ? S_guard_x : (S_send_in_valid ? S_follow_x : 16'd0);
    wire [15:0] S_send_in_y = S_guard_event ? S_guard_y : (S_send_in_valid ? S_follow_y : 16'd0);
    // Inclusive center-valid bounds match the fixed static tracking aim frame.
    localparam [15:0] CENTER_VALID_X_MIN=16'd560, CENTER_VALID_X_MAX=16'd720;
    localparam [15:0] CENTER_VALID_Y_MIN=16'd315, CENTER_VALID_Y_MAX=16'd405;
    wire S_send_in_center = (S_recognition_run || S_sad_guard) && !(S_guard_session && S_guard_edit_pause) &&
        S_send_in_valid && S_send_in_x >= CENTER_VALID_X_MIN && S_send_in_x <= CENTER_VALID_X_MAX &&
        S_send_in_y >= CENTER_VALID_Y_MIN && S_send_in_y <= CENTER_VALID_Y_MAX;
    reg S_send_update, S_send_target_valid, S_send_distance_valid;
    reg [15:0] S_send_id, S_send_x, S_send_y;
    wire [31:0] S_send_distance = 32'd0;
    always @(posedge S_hdmi_pixel_clk or negedge S_send_reset_n) begin
        if(!S_send_reset_n) begin
            S_send_update <= 1'b0;
            S_send_target_valid <= 1'b0;
            S_send_distance_valid <= 1'b0;
            S_send_id <= 16'd0;
            S_send_x <= 16'd0;
            S_send_y <= 16'd0;
        end else begin
            S_send_update <= S_send_in_update;
            if(S_send_in_update) begin
                S_send_target_valid <= S_send_in_valid;
                S_send_distance_valid <= S_send_in_center;
                S_send_id <= S_send_in_id;
                S_send_x <= S_send_in_x;
                S_send_y <= S_send_in_y;
            end
        end
    end

    reg S_guard_first_tag,S_guard_session_d;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n)begin S_guard_first_tag<=0;S_guard_session_d<=0;end
        else begin
            S_guard_first_tag<=S_guard_event && !S_guard_cancel;
            S_guard_session_d<=S_guard_session;
        end
    // A disabled editor keeps cancel asserted. Only a live/just-closed guard
    // session owns that cancellation; ordinary recognition must still pass.
    // Retaining one cycle of ownership also clears a queued first event on exit.
    wire S_guard_queue_cancel=S_sad_guard_reset || (S_guard_cancel && (S_guard_session || S_guard_session_d)) ||
        (S_guard_session && S_guard_edit_pause);
    wire S_legacy_tx_update;
    wire [81:0] S_legacy_tx_record;
    wire S_a38_owns=!(S_sad_guard_owned || S_sad_guard_d) && (S_a38_active || S_a38_active_d || S_a38_update);
    wire S_a38_center=S_a38_valid && S_a38_x>=CENTER_VALID_X_MIN && S_a38_x<=CENTER_VALID_X_MAX &&
        S_a38_y>=CENTER_VALID_Y_MIN && S_a38_y<=CENTER_VALID_Y_MAX;
    wire S_region_tx_update;
    wire [82:0] S_region_tx_record;
    guard_region_tx region_tx(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .ready(S_eth_ready),.link_ready(S_eth_result_link),.enabled(!S_a38_owns && !S_photo_album),
        .session(S_guard_session),.motion_mode(S_guard_motion_mode),
        .triggered(S_guard_triggered),.paused(S_guard_edit_pause),
        .region_update(S_region_update),.region_inside(S_region_inside),
        .in_update(S_legacy_tx_update),.in_record(S_legacy_tx_record),
        .out_update(S_region_tx_update),.out_record(S_region_tx_record));
    wire S_tx_update=S_a38_owns ? S_a38_update : S_region_tx_update;
    wire [81:0] S_tx_record=S_a38_owns ?
        {S_a38_valid,S_a38_center,S_a38_id,S_a38_x,S_a38_y,32'd0} : S_region_tx_record[81:0];
    guard_send_queue u_guard_send(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .cancel(S_guard_queue_cancel || S_a38_owns),
        .first_tag(S_guard_first_tag),.first_wait(S_guard_wait),
        .ready(S_eth_ready),.in_update(S_send_update && !S_photo_album && !(S_guard_session && S_guard_motion_mode)),
        .in_record({S_send_target_valid,S_send_distance_valid,S_send_id,S_send_x,S_send_y,S_send_distance}),
        .out_update(S_legacy_tx_update),.out_record(S_legacy_tx_record),.accepted(S_guard_accepted));
    // One result per acquired frame, including explicit no-target records.
    // Full records cross from 75 MHz to 125 MHz through the existing TX FIFO.
    target_eth_tx #(.MGMT_CLK_HZ(50000000),.PHY_ADDR(5'd4),.PHY_MDIO_ENABLE(0)) u_target_tx (
        .rst_n(S_power_rst_n),.mgmt_clk(I_sys_clk),.tx_clk(S_eth_clk),
        .result_clk(S_hdmi_pixel_clk),.result_update(S_tx_update),
        .region_valid(!S_a38_owns && S_region_tx_record[82]),
        .target_valid(S_tx_record[81]),.distance_valid(S_tx_record[80]),
        .target_id(S_tx_record[79:64]),.center_x(S_tx_record[63:48]),
        .center_y(S_tx_record[47:32]),.distance(S_tx_record[31:0]),
        .result_ready(S_eth_ready),.result_link_ready(S_eth_result_link),.overflow(S_eth_overflow),.dropped_results(S_eth_dropped),
        .tx_done(S_eth_done),.link_ready(S_eth_link),.phy_error(S_eth_error),.phy_id(S_eth_phy_id),
        .rgmii_txd(O_eth_txd),.rgmii_tx_ctl(O_eth_tx_ctl),.rgmii_tx_clk(O_eth_tx_clk),
        .phy_reset_n(O_phy_reset_n),.mdc(O_eth_mdc),.mdio(IO_eth_mdio));

    // Frame-latched recognition indicators for board debug LEDs.
    assign O_led_circle   = S_square_valid;
    assign O_led_triangle = S_triangle_valid;
    assign O_led_red_hit  = S_red_seen_frame;
    assign O_led_green_hit= S_green_seen_frame;

    // 打框：把 320x180 域坐标 x4 映射回 720p，在 vision 输出画面上叠加红框
    // 输出统一延迟 2 拍，user/last 与 de 同拍数，保证 hdmi_mixer 的 S_x 不错位
    dakuang #(
        .GUARD_FEATURE(1),.GUARD_POLYGON(1),
        .MULTI_BOX ( 1          ),
        .MOTION_COUNT ( 2       ),
        .H_ACTIVE  ( 1280       ),
        .V_ACTIVE  ( 720        ),
        .DS        ( 4          ),
        .BOX_COLOR ( 24'hff0000 ),
        .BOX_LINE  ( 2          )
    )u_dakuang(
        .sad_cross_active(S_a38_cross_active),.sad_cross_running(S_a38_cross_running),.sad_cross_live(S_a38_cross_live),
        .sad_cross_x(S_a38_cross_x),.sad_cross_y(S_a38_cross_y),
        .clk              ( S_hdmi_pixel_clk  ),
        .rst_n            ( S_hdmi_rst_n      ),
        .box_en           ( S_motion_run || S_guard_overlay ),
        .object_en        ( S_object_display ),
        .guard_overlay    ( S_guard_overlay ),
        .guard_points(S_guard_preview),.guard_selected(S_guard_selected),
        .guard_intrusion(S_sad_guard ? S_region_inside : S_guard_hud_intrusion),.guard_blink(S_guard_hud_blink),
        .square_valid(S_square_valid),.triangle_valid(S_triangle_valid),
        .square_xmin(S_square_xmin),.square_xmax(S_square_xmax),
        .square_ymin(S_square_ymin),.square_ymax(S_square_ymax),
        .triangle_xmin(S_triangle_xmin),.triangle_xmax(S_triangle_xmax),
        .triangle_ymin(S_triangle_ymin),.triangle_ymax(S_triangle_ymax),
        .box_valid        ( S_zc_box_valid    ),
        .box_tl_x         ( S_zc_box_tl_x     ),
        .box_tl_y         ( S_zc_box_tl_y     ),
        .box_tr_x         ( S_zc_box_tr_x     ),
        .box_tr_y         ( S_zc_box_tr_y     ),
        .box_bl_x         ( S_zc_box_bl_x     ),
        .box_bl_y         ( S_zc_box_bl_y     ),
        .box_br_x         ( S_zc_box_br_x     ),
        .box_br_y         ( S_zc_box_br_y     ),
        .multi_box_en     ( 1'b1              ),
        .multi_box_valid  ( S_zc_multi_valid ),
        .multi_box_xmin   ( S_zc_multi_xmin ),
        .multi_box_xmax   ( S_zc_multi_xmax ),
        .multi_box_ymin   ( S_zc_multi_ymin ),
        .multi_box_ymax   ( S_zc_multi_ymax ),
        .pre_frame_vsync  ( S_vision_vsync    ),
        .pre_frame_href   ( S_vision_href     ),
        .pre_frame_de     ( S_vision_de       ),
        .pre_frame_user   ( S_vision_user_sel ),
        .pre_frame_last   ( S_vision_last_sel ),
        .pre_rgb          ( S_vision_rgb      ),
        .post_frame_vsync ( S_dk_vsync        ),
        .post_frame_href  ( S_dk_href         ),
        .post_frame_de    ( S_dk_de           ),
        .post_frame_user  ( S_dk_user         ),
        .post_frame_last  ( S_dk_last         ),
        .post_rgb         ( S_dk_rgb          )
    );

    // Mixer has three register stages. This marker follows its first pixel
    // to the HDMI transmitter input, without changing the video data path.
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) S_latency_hdmi_user<=0;
        else S_latency_hdmi_user<={S_latency_hdmi_user[1:0],S_dk_user && S_dk_de};
    end
    video_latency_monitor #(.PIXEL_HZ(75000000)) u_video_latency_monitor(
        .rst_n(S_rst_n),.pixel_clk(S_hdmi_pixel_clk),
        .camera_clk(S_csi_rx_clk),.ddr_clk(S_ddr_clk),
        .raw_sof(S_raw_tuser && S_raw_tvalid),
        // Packed frame-start precedes the first valid 128-bit word.
        // Match video_in's unqualified frame-start event.
        .isp_sof(S_ISP_O_tuser),
        .write_start(S_latency_write_start),.write_slot(S_latency_write_slot),
        .read_start(S_latency_read_start),.read_slot(S_latency_read_slot),
        .hdmi_sof(S_latency_hdmi_user[2] && S_hdmi_out_de),
        .age_bcd(S_latency_bcd),.age_ticks(S_latency_ticks),.age_valid(S_latency_valid));

    auto_exposure_status_cdc u_auto_exposure_status_cdc (
        .I_csi_clk(S_csi_rx_clk), .I_csi_rst_n(S_csi_rst_n),
        .I_auto_enable(S_auto_enable_csi), .I_raw_gain_active(S_raw_gain_active),
        .I_target_valid_async(S_auto_target_valid), .I_iic_error_async(S_cam_i2c_error),
        .I_hdmi_clk(S_hdmi_pixel_clk), .I_hdmi_rst_n(S_hdmi_rst_n),
        .O_auto_active(S_ae_osd_active), .O_target_valid(S_ae_osd_ready),
        .O_iic_error(S_ae_osd_error), .O_raw_gain_active(S_ae_osd_gain)
    );

    // Motion is still measured in HDMI. Colour latency comes from the real
    // CSI spatial calculation, not from replaying a cached display result.
    detection_latency_monitor #(.H_ACTIVE(1280), .V_ACTIVE(720), .PIXEL_HZ(75000000))
    u_detection_latency_monitor (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n),
        .mode(S_motion_run ? 2'd1 : 2'd0),
        .measure_ready(S_motion_result_ready),
        .frame_start(S_video_user_aligned && S_video_de_aligned),
        .frame_de(S_video_de_aligned && !S_video_vs_aligned),
        .result_update(S_motion_result_update),.result_good(!S_motion_overflow),
        .average_bcd(),.average_valid(),
        .sample_update(S_motion_latency_update),.sample_valid(S_motion_latency_valid),
        .sample_ticks(S_motion_latency_ticks)
    );
    detection_latency_average u_shared_detection_average (
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
        .enabled(S_recognition_run || (S_motion_run && S_motion_result_ready)),
        .owner(S_recognition_run ? 2'd2 : (S_motion_run ? 2'd1 : 2'd0)),
        .sample_update(S_recognition_run ? S_color_latency_update : S_motion_latency_update),
        .sample_valid(S_recognition_run ? S_color_latency_valid : S_motion_latency_valid),
        .sample_ticks(S_recognition_run ? S_color_latency_ticks : S_motion_latency_ticks),
        .result_bcd(S_detect_latency_bcd),.result_valid(S_detect_latency_valid));

    hdmi_mixer #(
        .GUARD_FEATURE(1),
        .PHOTO_FEATURE(1),
        .INFO_FEATURE(1),
        .GUARD_SESSION_FEATURE(1),
        .TRACK_UI_FEATURE(1),
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    ),
        .SHOW_LATENCY( 1   )
    )u_hdmi_mixer(
        .O_static_track_active(S_static_track_active),.O_range_hold_active(S_range_hold_active),
        .I_sad_active(S_a38_active),.I_sad_running(S_a38_running),
        .I_sad_update(S_a38_ui_update),.I_sad_valid(S_a38_ui_live),
        .I_sad_id(S_a38_ui_id),.I_sad_x(S_a38_ui_x),.I_sad_y(S_a38_ui_y),
        .I_track_command_update(S_guard_config_update),.I_track_command(S_guard_command),
        .I_motion_update(S_motion_result_update),.I_motion_ready(S_motion_result_ready),.I_motion_overflow(S_motion_overflow),
        .I_motion_fresh(S_motion_result_fresh),.I_motion_valid(S_zc_multi_valid[1:0]),
        .I_motion_xmin(S_zc_multi_xmin[17:0]),.I_motion_xmax(S_zc_multi_xmax[17:0]),
        .I_motion_ymin(S_zc_multi_ymin[15:0]),.I_motion_ymax(S_zc_multi_ymax[15:0]),
        .I_param_update(S_ui_csi_event),
        .I_param_kind(S_ui_csi_record[6:5]),.I_param_level(S_ui_csi_record[4:0]),
        .I_photo_album(S_photo_album),.I_photo_index(S_photo_view_active[16:11]),
        .I_photo_count(S_photo_view_active[10:4]),.I_photo_status(S_photo_view_active[3:0]),
        .I_guard_warning(S_guard_warning),
        .I_guard_session(S_guard_session),
        .I_guard_active(S_guard_session && !S_guard_edit_pause),
        .I_guard_recognition(S_guard_view_recognition),.I_guard_motion(S_guard_motion_mode),
        .I_guard_intrusion(S_guard_hud_intrusion),.I_guard_region_inside(S_region_inside),.I_guard_seconds(S_guard_hud_seconds),
        .I_guard_elapsed(S_guard_hud_elapsed),.I_guard_epoch(S_guard_epoch),
        .I_target_update(S_control_update),.I_target_valid(S_control_valid && S_recognition_run),
        .I_target_overflow(S_control_overflow),.I_target_id(S_control_id),
        .I_target_x(S_control_x),.I_target_y(S_control_y),
        .I_object_active(S_object_display),.I_motion_active(S_motion_run),
        .I_latency_bcd   ( S_latency_bcd ),
        .I_latency_ticks ( S_latency_ticks ),
        .I_latency_valid ( S_latency_valid ),
        .I_detect_latency_bcd(S_detect_latency_bcd), .I_detect_latency_valid(S_detect_latency_valid),
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_dk_vsync         ),
        .I_video_hsync   ( S_dk_href          ),
        .I_video_de      ( S_dk_de            ),
        .I_video_user    ( S_dk_user          ),
        .I_video_last    ( S_dk_last          ),
        .I_debug_status  ( S_hdmi_debug_status),
        .I_proc_mode     ( S_proc_sel_effective),
        .I_ae_auto_active(S_ae_osd_active), .I_ae_target_valid(S_ae_osd_ready),
        .I_ae_iic_error(S_ae_osd_error), .I_ae_raw_gain(S_ae_osd_gain),
        .I_latency_enable(S_display_active),
        .O_video_rd_en   (                    ),
        .I_video_rd_data ( S_dk_rgb           ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_hdmi_out_data   ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );


    
endmodule

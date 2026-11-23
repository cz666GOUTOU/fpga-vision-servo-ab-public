module isp_top (
    input wire I_contrast_valid, input wire [4:0] I_contrast_level,
    input wire I_saturation_valid, input wire [4:0] I_saturation_level,
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,
    // Read-only control observer tap.  No new stage/backpressure in video.
    output wire [95:0] O_control_rgb,
    output wire O_control_valid, O_control_user, O_control_last,
    output wire O_ui_contrast_commit,O_ui_saturation_commit,
    output wire [4:0] O_ui_contrast_level,O_ui_saturation_level
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
 wire [127:0] awb_O_tdata_128;  //synthesis keep 
  wire [95:0] contrast_data;
  wire contrast_valid, contrast_user, contrast_last;
  assign O_control_rgb = contrast_data;
  assign O_control_valid = contrast_valid;
  assign O_control_user = contrast_user;
  assign O_control_last = contrast_last;


  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = contrast_last;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720 ), // 图像高度
    .IMG_WIDTH           (1280), // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

    wire [95:0] saturation_data;
    wire saturation_valid, saturation_user, saturation_last;
    // Match each existing RGB stage's coefficient latch boundary, including
    // its behavior when a configuration and SOF arrive on the same clock.
    hud_level_commit u_ui_saturation_commit(
        .clk(axi4s_video_aclk),.rst_n(I_rst_n),.manual_enable(1'b1),
        .frame_start(awb_O_tuser),.config_valid(I_saturation_valid),.config_level(I_saturation_level),
        .commit(O_ui_saturation_commit),.level(O_ui_saturation_level));
    hud_level_commit u_ui_contrast_commit(
        .clk(axi4s_video_aclk),.rst_n(I_rst_n),.manual_enable(1'b1),
        .frame_start(saturation_user),.config_valid(I_contrast_valid),.config_level(I_contrast_level),
        .commit(O_ui_contrast_commit),.level(O_ui_contrast_level));
    // Saturation now has two registered stages.  Data and frame/line markers
    // share the same pipeline, so contrast and the 96-to-128 packer consume
    // an aligned stream without a separate fixed-latency adjustment.
    rgb_saturation u_rgb_saturation (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n), .I_config_valid(I_saturation_valid), .I_level(I_saturation_level),
        .I_tdata(awb_O_tdata), .I_tvalid(awb_O_tvalid), .I_tuser(awb_O_tuser), .I_tlast(awb_O_tlast),
        .O_tdata(saturation_data), .O_tvalid(saturation_valid), .O_tuser(saturation_user), .O_tlast(saturation_last)
    );
    rgb_contrast u_rgb_contrast (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_config_valid(I_contrast_valid), .I_level(I_contrast_level), .I_tdata(saturation_data),
        .I_tvalid(saturation_valid), .I_tuser(saturation_user), .I_tlast(saturation_last),
        .O_tdata(contrast_data), .O_tvalid(contrast_valid),
        .O_tuser(contrast_user), .O_tlast(contrast_last)
    );
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( contrast_user ),
        .I_96b_valid        ( contrast_valid ),
        .I_96b_data         ( contrast_data ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule

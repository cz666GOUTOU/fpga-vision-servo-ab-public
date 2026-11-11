`timescale 1ns / 1ns
// SC500CS 1280x720 configuration controller.
module uicfgcs500_720p #(
    parameter integer CLK_DIV = 16'd239
)(
    input wire I_clk,I_rst_n,I_ae_req,
    input wire [15:0] I_ae,I_ag,
    output wire O_cam_scl,
    inout wire IO_cam_sda,
    output reg O_cfg_done,O_ae_cfg_done,
    output reg [15:0] O_sensor_id,
    output reg O_sensor_id_ok,O_iic_error
);
    localparam [7:0] CAM_ID=8'h6c;
    localparam [15:0] SC500_ID=16'hee27;
    localparam integer RESET_WAIT_CYCLES=119048;
    localparam integer POST_STREAM_DELAY=240000;
    localparam [3:0] ST_IDH_REQ=0,ST_IDH_BUSY=1,ST_IDH_DONE=2,
        ST_IDL_REQ=3,ST_IDL_BUSY=4,ST_IDL_DONE=5,ST_CHECK_ID=6,
        ST_IDLE=7,ST_WR_REQ=8,ST_WR_BUSY=9,ST_WR_DONE=10,ST_ERROR=11,
        ST_RESET_WAIT=12,ST_STREAM_WAIT=13;
    reg [3:0] state;
    reg iic_req,iic_mode;
    reg [7:0] wr_cnt,rd_cnt;
    reg [31:0] wr_data;
    reg [8:0] reg_index;
    reg [17:0] delay_cnt;
    reg [16:0] reset_wait_cnt;
    reg ae_table_active;
    reg [15:0] ae_latched,ag_latched;
    wire iic_busy,iic_bus_error;
    wire [7:0] rd_data;
    wire [23:0] init_data,ae_data;
    wire [15:0] gain_value;
    wire [8:0] init_size,ae_size;
    wire [23:0] selected_data=ae_table_active?ae_data:init_data;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=ST_IDH_REQ;iic_req<=0;iic_mode<=1;wr_cnt<=3;rd_cnt<=1;
            wr_data<=0;reg_index<=0;delay_cnt<=0;reset_wait_cnt<=0;
            ae_table_active<=0;ae_latched<=1990;ag_latched<=80;
            O_cfg_done<=0;O_ae_cfg_done<=0;O_sensor_id<=0;O_sensor_id_ok<=0;O_iic_error<=0;
        end else begin
            if(iic_bus_error) O_iic_error<=1;
            case(state)
                ST_IDH_REQ: if(!iic_busy) begin
                    wr_data<={8'h00,8'h07,8'h31,CAM_ID};wr_cnt<=3;rd_cnt<=1;iic_mode<=1;iic_req<=1;state<=ST_IDH_BUSY;
                end
                ST_IDH_BUSY: if(iic_busy) begin iic_req<=0;state<=ST_IDH_DONE;end
                ST_IDH_DONE: if(!iic_busy) begin O_sensor_id[15:8]<=rd_data;state<=ST_IDL_REQ;end
                ST_IDL_REQ: if(!iic_busy) begin
                    wr_data<={8'h00,8'h08,8'h31,CAM_ID};wr_cnt<=3;rd_cnt<=1;iic_mode<=1;iic_req<=1;state<=ST_IDL_BUSY;
                end
                ST_IDL_BUSY: if(iic_busy) begin iic_req<=0;state<=ST_IDL_DONE;end
                ST_IDL_DONE: if(!iic_busy) begin O_sensor_id[7:0]<=rd_data;state<=ST_CHECK_ID;end
                ST_CHECK_ID: if(O_sensor_id==SC500_ID) begin
                    O_sensor_id_ok<=1;reg_index<=0;ae_table_active<=0;state<=ST_IDLE;
                end else state<=ST_ERROR;
                ST_IDLE: begin
                    if(!O_cfg_done) begin
                        if(reg_index==init_size) begin O_cfg_done<=1;O_ae_cfg_done<=1;end
                        else state<=ST_WR_REQ;
                    end else if(ae_table_active) begin
                        if(reg_index==ae_size) begin ae_table_active<=0;O_ae_cfg_done<=1;end
                        else state<=ST_WR_REQ;
                    end else if(I_ae_req) begin
                        ae_latched<=I_ae;ag_latched<=I_ag;ae_table_active<=1;O_ae_cfg_done<=0;reg_index<=0;
                    end
                end
                ST_WR_REQ: if(!iic_busy) begin
                    wr_data[7:0]<=CAM_ID;wr_data[15:8]<=selected_data[23:16];
                    wr_data[23:16]<=selected_data[15:8];wr_data[31:24]<=selected_data[7:0];
                    wr_cnt<=4;rd_cnt<=0;iic_mode<=0;iic_req<=1;state<=ST_WR_BUSY;
                end
                ST_WR_BUSY: if(iic_busy) begin iic_req<=0;state<=ST_WR_DONE;end
                ST_WR_DONE: if(!iic_busy) begin
                    reg_index<=reg_index+1;
                    if(!ae_table_active && reg_index==0) begin reset_wait_cnt<=0;state<=ST_RESET_WAIT;end
                    // The reference waits after stream-on (index 114) and
                    // before the final 0x302d release write (index 115).
                    else if(!ae_table_active && reg_index==114) begin delay_cnt<=0;state<=ST_STREAM_WAIT;end
                    else state<=ST_IDLE;
                end
                ST_RESET_WAIT: if(reset_wait_cnt==RESET_WAIT_CYCLES-1) state<=ST_IDLE;
                               else reset_wait_cnt<=reset_wait_cnt+1;
                ST_STREAM_WAIT: if(delay_cnt==POST_STREAM_DELAY-1) state<=ST_IDLE;
                                else delay_cnt<=delay_cnt+1;
                ST_ERROR: begin iic_req<=0;O_cfg_done<=0;O_ae_cfg_done<=0;end
                default: state<=ST_ERROR;
            endcase
        end
    end
    uii2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) u_i2c(
        .I_clk(I_clk),.I_rstn(I_rst_n),.O_iic_scl(O_cam_scl),.IO_iic_sda(IO_cam_sda),
        .I_wr_data(wr_data),.I_wr_cnt(wr_cnt),.O_rd_data(rd_data),.I_rd_cnt(rd_cnt),
        .I_iic_req(iic_req),.I_iic_mode(iic_mode),.O_iic_busy(iic_busy),
        .O_iic_bus_error(iic_bus_error),.IO_iic_sda_dg());
    uics500reg_720p60 u_init_table(.REG_INDEX(reg_index),.REG_DATA(init_data),.REG_SIZE(init_size));
    SC500GainTbl u_gain_table(.I_clk(I_clk),.I_rstn(I_rst_n),.I(ag_latched-16),.O(gain_value));
    uics500regAE u_ae_table(.REG_INDEX(reg_index),.REG_DATA(ae_data),.REG_SIZE(ae_size),
                            .I_AG(gain_value),.I_AE(ae_latched));
endmodule

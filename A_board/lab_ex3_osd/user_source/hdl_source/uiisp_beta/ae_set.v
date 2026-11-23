/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

// UART absolute camera AG; SC500 startup AG=80 (UART level 08). No local buttons.
module ae_set (
    input wire I_clk,I_rst,
    input wire I_config_valid, input wire [15:0] I_config_ag,
    input wire I_ae_cfg_done,I_cam_cfg_done,I_auto_enable,I_auto_targets_valid,
    input wire [15:0] I_auto_ae,I_auto_ag,
    output wire [15:0] O_seed_ae,O_seed_ag,
    output wire O_ae_req, output wire [15:0] O_ae,O_ag
);
    localparam [15:0] INITIAL_AG=16'd80;
    reg [15:0] r_ae_set=1990,r_ag_set=INITIAL_AG;
    reg r_auto_enable_d=0;
    reg [15:0] r_manual_ae=1990,r_manual_ag=INITIAL_AG;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_ae_set<=1990;r_ag_set<=INITIAL_AG;r_auto_enable_d<=0;
            r_manual_ae<=1990;r_manual_ag<=INITIAL_AG;
        end else begin
            r_auto_enable_d<=I_auto_enable;
            if(I_auto_enable) begin
                if(!r_auto_enable_d) begin r_manual_ae<=r_ae_set;r_manual_ag<=r_ag_set;end
                if(r_auto_enable_d && I_auto_targets_valid) begin r_ae_set<=I_auto_ae;r_ag_set<=I_auto_ag;end
            end else if(r_auto_enable_d) begin r_ae_set<=r_manual_ae;r_ag_set<=r_manual_ag;end
            else if(I_config_valid && I_config_ag>=16 && I_config_ag<=89) r_ag_set<=I_config_ag;
        end
    end
    reg [15:0] r_ae,r_ag;
    reg r_ae_req=0;
    assign O_seed_ae=r_auto_enable_d?r_manual_ae:r_ae_set;
    assign O_seed_ag=r_auto_enable_d?r_manual_ag:r_ag_set;
    assign O_ae=r_ae;assign O_ag=r_ag;assign O_ae_req=r_ae_req;
    // Different reset values force one update after sensor initialization.
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin r_ae_req<=0;r_ae<=1990;r_ag<=17;end
        else if(r_ae_req) r_ae_req<=0;
        else if((r_ae!=r_ae_set || r_ag!=r_ag_set) && I_cam_cfg_done && I_ae_cfg_done) begin
            r_ae<=r_ae_set;r_ag<=r_ag_set;r_ae_req<=1;
        end
    end
endmodule

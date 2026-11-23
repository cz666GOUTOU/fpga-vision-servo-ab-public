// SC520 1280x720 LSC calibration configuration. NO measured gains yet.
// All nodes intentionally start at unity; this is NOT a colour correction preset.
// Grid: x=0,256,512,768,1024,1280; y=0,256,512,768.
// The final y node is outside the image and is a smooth boundary extension.
// Each row concatenation is {x1280,x1024,x768,x512,x256,x0}.
// Q2.10 examples: 1024=1.0, 960=0.9375, 1088=1.0625. Rebuild after editing.
module raw10_lsc_config #(
    parameter BAYER_MODE="BGGR",
    parameter integer ENABLE=1
) (
    input wire I_clk, I_rst_n,
    input wire [39:0] I_tdata,
    input wire I_tvalid, I_tuser, I_tlast,
    output wire [39:0] O_tdata,
    output wire O_tvalid, O_tuser, O_tlast
);
    localparam [71:0] R_Y0   ={6{12'd1024}};
    localparam [71:0] R_Y256 ={6{12'd1024}};
    localparam [71:0] R_Y512 ={6{12'd1024}};
    localparam [71:0] R_Y768 ={6{12'd1024}};
    localparam [71:0] GR_Y0   ={6{12'd1024}};
    localparam [71:0] GR_Y256 ={6{12'd1024}};
    localparam [71:0] GR_Y512 ={6{12'd1024}};
    localparam [71:0] GR_Y768 ={6{12'd1024}};
    localparam [71:0] GB_Y0   ={6{12'd1024}};
    localparam [71:0] GB_Y256 ={6{12'd1024}};
    localparam [71:0] GB_Y512 ={6{12'd1024}};
    localparam [71:0] GB_Y768 ={6{12'd1024}};
    localparam [71:0] B_Y0   ={6{12'd1024}};
    localparam [71:0] B_Y256 ={6{12'd1024}};
    localparam [71:0] B_Y512 ={6{12'd1024}};
    localparam [71:0] B_Y768 ={6{12'd1024}};
    localparam [1151:0] GAIN_TABLE={
        B_Y768,B_Y512,B_Y256,B_Y0,
        GB_Y768,GB_Y512,GB_Y256,GB_Y0,
        GR_Y768,GR_Y512,GR_Y256,GR_Y0,
        R_Y768,R_Y512,R_Y256,R_Y0
    };
    raw10_lsc #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.GRID_BITS(8),
        .BAYER_MODE(BAYER_MODE),.ENABLE(ENABLE),.GAIN_TABLE(GAIN_TABLE)) u_lsc (
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tdata(I_tdata),
        .I_tvalid(I_tvalid),.I_tuser(I_tuser),.I_tlast(I_tlast),
        .O_tdata(O_tdata),.O_tvalid(O_tvalid),.O_tuser(O_tuser),.O_tlast(O_tlast)
    );
endmodule

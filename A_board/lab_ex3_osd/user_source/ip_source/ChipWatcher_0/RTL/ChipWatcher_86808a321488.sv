// synthesis syn_black_box 
module ChipWatcher_86808a321488 ( 
    input [63:0] probe0, 
    input       clk  
);
    localparam string IP_TYPE  = "ChipWatcher";
    localparam CWC_BUS_NUM     = 1;
    localparam INPUT_PIPE_NUM  = 0;
    localparam OUTPUT_PIPE_NUM = 0;
    localparam RAM_DATA_DEPTH  = 1024;
    localparam CAPTURE_CONTROL = 0;

    localparam integer CWC_BUS_WIDTH   [CWC_BUS_NUM-1:0] = {64};
    localparam integer CWC_DATA_ENABLE [CWC_BUS_NUM-1:0] = {1};    
    localparam integer CWC_TRIG_ENABLE [CWC_BUS_NUM-1:0] = {1};    
endmodule




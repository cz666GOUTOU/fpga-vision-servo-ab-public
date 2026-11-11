// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module uart_gimbal_manual #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    parameter integer PACKET_TIMEOUT_MS=20
)(
    input wire clk,rst_n,rx,
    input wire self_select_parent,
    output reg manual_mode,enter_manual,dx_valid,dy_valid,
    output reg signed [7:0] dx,dy,
    output reg command_valid,
    output reg [7:0] command_code,command_data,
    output reg feature_guard_mode,
    output reg feature_region_selected,
    output reg [1:0] tracking_mode,
    output reg static_tracking_mode,static_tracking_hold,
    output reg all_target_guard_mode,selected_tracking_mode,
    output reg self_select_mode
);
    localparam integer BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer HALF_TICKS=BIT_TICKS/2;
    localparam integer BW=BIT_TICKS>1?$clog2(BIT_TICKS):1;
    localparam integer TIMEOUT_TICKS=(CLK_HZ/1000)*PACKET_TIMEOUT_MS;
    localparam integer PW=TIMEOUT_TICKS>1?$clog2(TIMEOUT_TICKS):1;
    localparam IDLE=0,START=1,DATA=2,STOP=3,RECOVER=4;
    (* async_reg="true" *) reg rx_meta,rx_sync;
    reg [2:0] state;
    reg [BW-1:0] tick;
    reg [2:0] bit_index;
    reg [7:0] shift;
    reg byte_valid,frame_error;
    reg [7:0] byte_data;
    reg waiting_data;
    reg [7:0] command;
    reg [PW-1:0] packet_age;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=rx;rx_sync<=rx_meta;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;tick<=0;bit_index<=0;shift<=0;
            byte_valid<=0;frame_error<=0;byte_data<=0;
        end else begin
            byte_valid<=0;frame_error<=0;
            case(state)
                IDLE:if(!rx_sync) begin state<=START;tick<=HALF_TICKS-1;end
                START:if(tick!=0) tick<=tick-1'b1;
                    else if(rx_sync) state<=IDLE;
                    else begin state<=DATA;tick<=BIT_TICKS-1;bit_index<=0;end
                DATA:if(tick!=0) tick<=tick-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync;tick<=BIT_TICKS-1;
                        if(bit_index==7) state<=STOP;
                        else bit_index<=bit_index+1'b1;
                    end
                STOP:if(tick!=0) tick<=tick-1'b1;
                    else if(rx_sync) begin byte_data<=shift;byte_valid<=1;state<=IDLE;end
                    else begin frame_error<=1;state<=RECOVER;end
                RECOVER:if(rx_sync) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            command_valid<=0;command_code<=0;command_data<=0;
            waiting_data<=0;command<=0;packet_age<=0;
        end else begin
            command_valid<=0;
            if(waiting_data) begin
                if(packet_age==TIMEOUT_TICKS-1) begin waiting_data<=0;packet_age<=0;end
                else packet_age<=packet_age+1'b1;
            end
            if(frame_error) begin waiting_data<=0;packet_age<=0;end
            else if(byte_valid) begin
                packet_age<=0;
                if(waiting_data && packet_age!=TIMEOUT_TICKS-1) begin
                    // Unknown opcodes still own exactly one payload byte.
                    // A payload may itself equal any opcode; never rescan it.
                    waiting_data<=0;
                    command_valid<=1;command_code<=command;command_data<=byte_data;
                end else begin
                    command<=byte_data;waiting_data<=1;
                end
            end
        end
    end

    // Command events update persistent state. The latest command/data values
    // are never used as level-sensitive mode enables; subsequent unrelated
    // commands cannot cancel guard/manual state or replay an earlier command.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;enter_manual<=0;tracking_mode<=0;
            static_tracking_mode<=0;static_tracking_hold<=0;
            all_target_guard_mode<=0;
            selected_tracking_mode<=0;
            self_select_mode<=0;
            dx_valid<=0;dy_valid<=0;dx<=0;dy<=0;
        end else begin
            enter_manual<=0;dx_valid<=0;dy_valid<=0;
            if(command_valid && ((command_code==8'h0e && command_data<=1) ||
                (command_code==8'h21 && command_data==2) ||
                (command_code==8'h26 && command_data<=1) ||
                (command_code==8'h28 && command_data==1) ||
                (command_code==8'h2c && (command_data==3 || (command_data==4 && static_tracking_mode))) ||
                (command_code==8'h2d && command_data==1)))self_select_mode<=0;
            if(command_valid) case(command_code)
                8'h0e:if(command_data==0 || command_data==1) begin
                    // Select/leave the region workflow. Every selection needs
                    // a subsequent 21 01, even if old coordinates are confirmed.
                    feature_region_selected<=command_data[0];
                    feature_guard_mode<=0;
                    if(command_data==1) begin
                        manual_mode<=0;static_tracking_mode<=0;static_tracking_hold<=0;
                        all_target_guard_mode<=0;
                        selected_tracking_mode<=0;
                    end
                end
                8'h21:if(command_data==1 && feature_region_selected) begin
                    // Confirmation is the only guard entry. It also releases
                    // manual positioning so the angle anchor is captured now.
                    feature_guard_mode<=1;manual_mode<=0;
                    all_target_guard_mode<=0;
                    selected_tracking_mode<=0;
                end else if(command_data==2) feature_guard_mode<=0;
                8'h26:if(command_data==0 || command_data==1) begin
                    manual_mode<=command_data[0];
                    static_tracking_mode<=0;static_tracking_hold<=0;
                    selected_tracking_mode<=0;
                    enter_manual<=command_data[0] && !manual_mode;
                    if(command_data==1)begin feature_guard_mode<=0;all_target_guard_mode<=0;end
                end
                8'h28:if(command_data==0 || command_data==1)begin
                    all_target_guard_mode<=command_data[0];
                    if(command_data==1)begin
                        // Whole-region guard holds entry pose and announces
                        // scene entries; top masks visual following entirely.
                        manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;
                        static_tracking_mode<=0;static_tracking_hold<=0;
                        selected_tracking_mode<=0;
                    end
                end
                8'h2c:if(command_data<=2) begin
                    // A profile command changes tuning only. Mode entry/exit
                    // belongs to its explicit command; never drop a static
                    // lock, applied distance control, guard, manual or hold.
                    tracking_mode<=command_data[1:0];
                end else if(command_data==3) begin
                    // Static coordinates use the saved shared profile.
                    // Target ownership is independent of profile selection.
                    static_tracking_mode<=1;static_tracking_hold<=0;
                    manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;
                    all_target_guard_mode<=0;
                    selected_tracking_mode<=0;
                end else if(command_data==4 && static_tracking_mode) begin
                    static_tracking_mode<=0;static_tracking_hold<=1;
                    selected_tracking_mode<=0;
                end
                8'h2d:if(command_data==1)begin
                    // Distance preparation keeps the selected static target
                    // under continuous visual tracking, including after hold.
                    static_tracking_mode<=1;static_tracking_hold<=0;
                    manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;
                    all_target_guard_mode<=0;
                    selected_tracking_mode<=0;
                end
                // Applied feature/static parents keep their full control path.
                // 38 01/00 enters/exits selection; 03/04 applies/cancels a
                // target inside it. Cancel must not exit selection or rearm
                // loss search. Legacy standalone03/04 keeps its old owner.
                8'h38:if(command_data==1)begin
                    if(self_select_parent===1'b1)self_select_mode<=1;
                end else if(command_data==0)self_select_mode<=0;
                else if(command_data==3)begin
                    if(self_select_parent===1'b1)self_select_mode<=1;
                    else begin
                        self_select_mode<=0;
                        selected_tracking_mode<=1;static_tracking_mode<=1;static_tracking_hold<=0;
                        manual_mode<=0;feature_guard_mode<=0;feature_region_selected<=0;all_target_guard_mode<=0;
                    end
                end else if(command_data==4)begin
                    if(!self_select_mode && selected_tracking_mode)begin
                        selected_tracking_mode<=0;static_tracking_mode<=0;static_tracking_hold<=1;
                    end
                end
                8'h29:if(manual_mode) begin dx<=$signed(command_data);dx_valid<=1;end
                8'h2a:if(manual_mode) begin dy<=$signed(command_data);dy_valid<=1;end
                default:begin end
            endcase
        end
    end
endmodule

// Fixed-frame photograph archive. RGB888 remains lossless. No automatic erase.
// Two explicit 0F A5 commands initialize a foreign card or clear a valid album.
// B4 resource profile: four photo slots are indexed; the SD sector layout
// remains volume=2048; photo n header=2049+n*8192, then image payload.
// GPH2 volume / PIC1 version 3: fixed full frame, no crop or row offset.
// Commit header/complement only AFTER every payload sector write succeeds.
// Legacy GPH1 cropped volumes are refused until explicit initialization.
module sd_photo_store #(
    parameter integer STRIDE=1920, MAX_WIDTH=1280, MAX_HEIGHT=720,
    parameter integer SLOT_COUNT=4,
    parameter integer FRAME_WAIT_CYCLES=10000000,
    parameter [24:0] CANVAS0=28000000,CANVAS1=30000000,
    parameter integer SOURCE_FREEZE=0
)(
    input wire clk,rst_n,
    input wire capture,input wire [17:0] capture_data,
    input wire command_valid,input wire [15:0] command,
    input wire busy_notice,
    input wire [63:0] frame_ids,input wire [3:0] frame_good,
    input wire display_ack_bank,
    output wire busy,output reg [3:0] status,
    output reg album,output reg display_bank,
    output wire [5:0] display_index,output wire [6:0] photo_count,
    output reg display_valid,
    output wire ddr_req,ddr_write,ddr_last,
    output wire [24:0] ddr_addr,output wire [127:0] ddr_wdata,
    input wire ddr_ready,ddr_rvalid,input wire [127:0] ddr_rdata,
    output reg sd_request,sd_write,output reg [31:0] sd_lba,
    input wire sd_ready,sd_done,sd_error,input wire [31:0] sd_sectors,
    output wire ram_we,output wire [4:0] ram_addr,output wire [127:0] ram_wdata,
    input wire [127:0] ram_rdata,
    output wire video_pause,
    input wire video_paused
);
    localparam WAIT_CARD=0,VOLUME_REQ=1,SD_WAIT=2,RAM_WAIT=3,HEADER0=4,HEADER1=5,
        SCAN_NEXT=6,IDLE=7,FRAME_WAIT=8,COPY_READ=9,COPY_DRAIN=10,
        WORD_WAIT=11,WORD_WRITE=12,COPY_NEXT=13,SAVE_READ=14,SAVE_DRAIN=15,FREEZE_WAIT=16,
        CLEAR_FILL=17,CLEAR_NEXT=18,CLEAR_RESCAN=19,SECTOR_NEXT=20,
        FILL_HEADER=21,HEADER1_SUM=22,LOAD_NEXT=23,FAIL=24,FORMAT_FILL=25,FINISH=26,
        FRAME_PRIME=27,FREEZE_VERIFY0=28,FREEZE_VERIFY1=29,FRAME_RETRY=30,HEADER0_SUM=31;
    // Geometry is compile-time only. Supported frames are an integer number
    // of 512-byte sectors and have the tightly packed RGB888 video stride.
    localparam integer IMAGE_WORDS=MAX_WIDTH*MAX_HEIGHT*3/16;
    localparam integer SLOT_BITS=(SLOT_COUNT<=2) ? 1 : $clog2(SLOT_COUNT);
    localparam [12:0] IMAGE_SECTORS=IMAGE_WORDS/32;
    localparam [15:0] FRAME_WIDTH=MAX_WIDTH,FRAME_HEIGHT=MAX_HEIGHT;
    // On-card format stays 64-slot GPH2 for compatibility. SLOT_COUNT is the
    // compiled active prefix (power of two, 2..64), not a new disk format.
    // Normal capture/browse leaves the rest untouched; explicit clear covers 64.
    localparam [127:0] VOLUME_HEADER={32'h47504832,16'd3,16'd64,32'd8192,
        FRAME_WIDTH,FRAME_HEIGHT};
    reg [4:0] state,after_sd,after_ram;
    // Existing status channel: B=frame wait, C=source stale, D=SD, F=header.
    // Keep the failure cause through FAIL without changing transaction timing.
    reg [3:0] fail_code;
    reg [1:0] purpose; // 0=save, 2=load, 3=copy the protected source frame
    reg [SLOT_COUNT-1:0] valid_slots;
    reg [SLOT_BITS-1:0] slot,scan_slot;
    reg [SLOT_BITS-1:0] display_slot;
    reg [SLOT_BITS:0] active_count;
    assign display_index={{(6-SLOT_BITS){1'b0}},display_slot};
    assign photo_count={{(6-SLOT_BITS){1'b0}},active_count};
    reg [15:0] source_id;
    reg [1:0] source_slot,kind;
    reg [24:0] read_addr,write_addr;
    reg target_bank;
    reg [5:0] issued,received;
    reg [4:0] ram_index;
    reg header_ok;
    reg [7:0] header_parts;
    reg [3:0] frame_match;
    reg source_snapshot_ok;
    // Full-cycle comparisons stop source_id feeding the video-pause data path.
    always @(posedge clk or negedge rst_n)
        if(!rst_n)frame_match<=0;
        else begin
            frame_match[0]<=frame_good[0] && frame_ids[15:0]==source_id;
            frame_match[1]<=frame_good[1] && frame_ids[31:16]==source_id;
            frame_match[2]<=frame_good[2] && frame_ids[47:32]==source_id;
            frame_match[3]<=frame_good[3] && frame_ids[63:48]==source_id;
        end
    reg [1:0] header_kind;
    reg [12:0] sector;
    reg formatted,format_armed;
    reg [28:0] arm_timer;
    reg [5:0] clear_slot;
    reg clear_active,clear_failed;
    // Confirm in any UI/transaction state; drain the current complete operation
    // before taking SD ownership. Initialization also absorbs repeated A5s.
    reg clear_pending,format_active;
    wire clear_occupied=clear_pending || clear_active || format_active;
    wire clear_command=command_valid && command==16'h0fa5;
    wire clear_confirm=clear_command && !clear_occupied && format_armed &&
        arm_timer<29'd400000000 && sd_ready && sd_sectors>=32'd526337;
    // FRAME_WAIT increments on the timeout edge as well. Include terminal+1
    // so powers of two preserve the original counter and exit cycle.
    // Keep legacy width for out-of-range parameters (including negatives).
    localparam integer FRAME_TIMER_BITS=(FRAME_WAIT_CYCLES<=0 ||
        FRAME_WAIT_CYCLES>=536870911) ? 29 : $clog2(FRAME_WAIT_CYCLES+2);
    reg [FRAME_TIMER_BITS-1:0] frame_timer;
    reg loading_header,volume_header;
    wire [24:0] target_base=target_bank ? CANVAS1 : CANVAS0;
    wire [31:0] slot_sector={{(19-SLOT_BITS){1'b0}},slot,13'd2049};
    wire [31:0] scan_sector={{(19-SLOT_BITS){1'b0}},scan_slot,13'd2049};
    wire [5:0] checked_slot=loading_header ? slot : scan_slot;
    function [127:0] photo_header;
        input [1:0] class_id;
        input [5:0] photo_slot;
        begin photo_header={32'h50494331,16'd3,FRAME_WIDTH,FRAME_HEIGHT,
            {6'd0,class_id},{2'd0,photo_slot},32'd0};end
    endfunction
    wire [127:0] header_expected=volume_header ? VOLUME_HEADER :
        photo_header(state==HEADER0 ? ram_rdata[41:40] : header_kind,checked_slot);
    // One field comparator feeds both header phases. Select polarity after
    // the field reductions, without a 128-bit input-selection network.
    wire [127:0] header_difference=ram_rdata ^ header_expected;
    wire [7:0] header_matches;
    genvar header_field;
    generate for(header_field=0;header_field<8;header_field=header_field+1)begin:g_header_compare
        assign header_matches[header_field]=(state==HEADER1) ?
            (&header_difference[header_field*16+:16]) :
            (~|header_difference[header_field*16+:16]);
    end endgenerate
    wire [127:0] fill_header=state==FORMAT_FILL ? VOLUME_HEADER : photo_header(kind,slot);
    function [24:0] video_base;input [1:0] s;
        begin case(s)0:video_base=0;1:video_base=7000000;2:video_base=14000000;3:video_base=21000000;endcase end
    endfunction
    // Tightly packed full frames use one constant increment, in 16-bit units.
    wire [24:0] advanced_addr=ddr_addr+25'd8;
    wire source_stale=!frame_good[source_slot] || frame_ids[source_slot*16+:16]!=source_id;
    wire copy_active=state==COPY_READ || state==COPY_DRAIN ||
        (state==WORD_WAIT && purpose==3) || (state==WORD_WRITE && purpose==3) || state==COPY_NEXT;
    assign busy=state!=IDLE || clear_pending || (album && display_bank!=display_ack_bank);
    assign ddr_req=(state==COPY_READ || state==SAVE_READ) ? issued<6'd32 : state==WORD_WRITE;
    assign ddr_write=state==WORD_WRITE;
    assign ddr_last=(state==COPY_READ || state==SAVE_READ) ? issued==6'd31 : ram_index==5'd31;
    assign ddr_addr=ddr_write ? write_addr : read_addr;
    assign ddr_wdata=ram_rdata;
    assign ram_we=((state==COPY_READ || state==COPY_DRAIN || state==SAVE_READ || state==SAVE_DRAIN) && ddr_rvalid) ||
        state==FILL_HEADER || state==FORMAT_FILL || state==CLEAR_FILL;
    assign ram_addr=(state==COPY_READ || state==COPY_DRAIN || state==SAVE_READ || state==SAVE_DRAIN) ? received[4:0] : ram_index;
    assign ram_wdata=state==CLEAR_FILL ? 128'd0 : (state==FILL_HEADER || state==FORMAT_FILL) ?
        (ram_index==0 ? fill_header : ram_index==1 ? ~fill_header : 128'd0) : ddr_rdata;
    integer k;
    reg found;
    reg [1:0] found_slot;
    reg free_found;
    reg [SLOT_BITS-1:0] free_slot;
    // Claim the freeze on the SAME edge as a matching frame is found, so a
    // simultaneous video SOF cannot invalidate that source before we stop it.
    // Keep it only through DDR copy, not through slow SD payload writes.
    assign video_pause=(SOURCE_FREEZE!=0) &&
        ((state==FRAME_WAIT && found) || state==FREEZE_WAIT ||
         state==FREEZE_VERIFY0 || state==FREEZE_VERIFY1 || copy_active);
    always @*begin
        found=0;found_slot=0;free_found=0;free_slot=0;
        for(k=0;k<4;k=k+1)
            if(SOURCE_FREEZE!=0 ? frame_match[k] :
                (frame_good[k] && frame_ids[k*16+:16]==source_id))begin found=1;found_slot=k;end
        for(k=SLOT_COUNT-1;k>=0;k=k-1)if(!valid_slots[k])begin free_found=1;free_slot=k;end
    end
    reg [SLOT_BITS-1:0] browse_cursor;
    reg browse_backward;
    reg browsing;
    reg [SLOT_BITS:0] browse_steps;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=WAIT_CARD;after_sd<=0;after_ram<=0;purpose<=0;valid_slots<=0;fail_code<=4'h6;
            header_parts<=0;source_snapshot_ok<=0;
            slot<=0;scan_slot<=0;source_id<=0;source_slot<=0;kind<=0;
            read_addr<=0;write_addr<=0;target_bank<=0;
            issued<=0;received<=0;ram_index<=0;
            header_ok<=0;header_kind<=0;
            sector<=0;formatted<=0;format_armed<=0;arm_timer<=0;frame_timer<=0;
            clear_slot<=0;clear_active<=0;clear_failed<=0;clear_pending<=0;format_active<=0;
            loading_header<=0;volume_header<=0;sd_request<=0;sd_write<=0;sd_lba<=0;
            status<=0;album<=0;display_bank<=0;display_slot<=0;active_count<=0;
            display_valid<=0;browse_cursor<=0;browse_backward<=0;browsing<=0;browse_steps<=0;
        end else begin
            sd_request<=0;
            if(format_armed)begin
                // Mode changes and normal I/O do not discard the first A5.
                // A reset, timeout or loss of this card still invalidates it.
                if(arm_timer==29'd400000000 || !sd_ready)begin
                    format_armed<=0;arm_timer<=0;
                    if(status==10)status<=state!=IDLE ? 4'h8 :
                        formatted ? (active_count==0 ? 4'h9 : 4'h2) : 4'h1;
                end
                else arm_timer<=arm_timer+1'b1;
            end
            case(state)
                WAIT_CARD:if(sd_ready)begin state<=VOLUME_REQ;volume_header<=1;loading_header<=0;end
                VOLUME_REQ:begin
                    sd_lba<=volume_header ? 32'd2048 : loading_header ? slot_sector : scan_sector;
                    sd_write<=0;sd_request<=1;after_sd<=RAM_WAIT;after_ram<=HEADER0;ram_index<=0;state<=SD_WAIT;
                end
                SD_WAIT:if(sd_done)begin
                    if(sd_error)begin
                        fail_code<=4'hd;
                        if(clear_active && !clear_failed)begin
                            // A failed header write may have partially cleared
                            // the card. Re-index survivors before accepting use.
                            clear_failed<=1;state<=CLEAR_RESCAN;
                        end else begin
                            // If recovery reads also fail, do not offer unknown
                            // slots for overwrite. Reboot/reinitialize to retry.
                            if(clear_active)formatted<=0;
                            clear_active<=0;clear_failed<=0;state<=FAIL;
                        end
                    end
                    else state<=after_sd;
                end
                RAM_WAIT:state<=after_ram;
                HEADER0:begin
                    header_kind<=ram_rdata[41:40];
                    header_parts<=header_matches;
                    state<=HEADER0_SUM;
                end
                HEADER0_SUM:begin
                    // Class 0 is a SAD-selected photo; all four class values are valid.
                    // Full header fields and complement still validate the record.
                    header_ok<=(&header_parts);
                    ram_index<=1;after_ram<=HEADER1;state<=RAM_WAIT;
                end
                HEADER1:begin
                    header_parts<=header_matches;
                    state<=HEADER1_SUM;
                end
                HEADER1_SUM:begin
                    if(volume_header)begin
                        volume_header<=0;
                        if(header_ok && (&header_parts) && sd_sectors>=526337)begin
                            formatted<=1;valid_slots<=0;active_count<=0;scan_slot<=0;state<=VOLUME_REQ;
                        end else begin formatted<=0;status<=1;state<=IDLE;end
                    end else if(loading_header)begin
                        if(!header_ok || !(&header_parts))begin
                            fail_code<=4'hf;state<=FAIL;
                        end
                        else begin
                            purpose<=2;write_addr<=target_base;
                            sector<=1;state<=LOAD_NEXT;
                        end
                    end else begin
                        if(header_ok && (&header_parts))begin
                            valid_slots[scan_slot]<=1;active_count<=active_count+1'b1;display_slot<=scan_slot;
                        end
                        state<=SCAN_NEXT;
                    end
                end
                SCAN_NEXT:if(scan_slot==SLOT_COUNT-1)begin
                        state<=IDLE;format_active<=0;
                        if(clear_active)begin
                            status<=(clear_failed || active_count!=0) ? 4'hd : 4'h9;
                            clear_active<=0;clear_failed<=0;
                        end else status<=2;
                    end
                    else begin scan_slot<=scan_slot+1'b1;state<=VOLUME_REQ;end
                IDLE:begin
                    frame_timer<=0;
                    if(status==8 && !busy)status<=formatted ? 2 : 1;
                    if(clear_pending)begin
                        // No accepted SD/DDR operation remains at IDLE. Do not
                        // wait for a display ACK to delete an inactive canvas.
                        if(sd_ready)begin
                            ram_index<=0;clear_slot<=0;clear_failed<=0;
                            clear_active<=formatted;format_active<=!formatted;clear_pending<=0;
                            display_valid<=0;browsing<=0;browse_steps<=0;
                            state<=formatted ? CLEAR_FILL : FORMAT_FILL;status<=8;
                        end
                    end else if(browsing && !clear_confirm)begin
                        if(valid_slots[browse_cursor])begin
                            slot<=browse_cursor;browsing<=0;loading_header<=1;volume_header<=0;
                            target_bank<=!display_bank;status<=5;state<=VOLUME_REQ;
                        end else if(browse_steps==SLOT_COUNT)begin browsing<=0;fail_code<=4'h6;state<=FAIL;end
                        else begin browse_steps<=browse_steps+1'b1;browse_cursor<=browse_backward ? browse_cursor-1'b1 : browse_cursor+1'b1;end
                    end else if(capture && !album && !clear_confirm)begin
                        if(!formatted)status<=1;
                        else if(!free_found)status<=7;
                        else begin
                            slot<=free_slot;kind<=capture_data[17:16];source_id<=capture_data[15:0];
                            target_bank<=!display_bank;status<=3;
                            state<=SOURCE_FREEZE!=0 ? FRAME_PRIME : FRAME_WAIT;
                        end
                    end
                end
                CLEAR_FILL:if(ram_index==31)begin
                    // Logical clear: invalidate only the 64 PIC1 header sectors,
                    // including slots outside this build's active prefix.
                    sd_lba<={13'd0,clear_slot,13'd2049};sd_write<=1;sd_request<=1;
                    after_sd<=CLEAR_NEXT;state<=SD_WAIT;
                end else ram_index<=ram_index+1'b1;
                CLEAR_NEXT:begin
                    if(clear_slot==63)state<=CLEAR_RESCAN;
                    else begin clear_slot<=clear_slot+1'b1;state<=CLEAR_FILL;ram_index<=0;end
                end
                CLEAR_RESCAN:begin
                    valid_slots<=0;active_count<=0;scan_slot<=0;display_slot<=0;
                    display_valid<=0;browsing<=0;browse_cursor<=0;browse_steps<=0;
                    volume_header<=0;loading_header<=0;state<=VOLUME_REQ;
                end
                FRAME_WAIT:begin
                    frame_timer<=frame_timer+1'b1;
                    if(found)begin
                        source_slot<=found_slot;
                        read_addr<=video_base(found_slot);write_addr<=target_base;
                        issued<=0;received<=0;ram_index<=0;
                        sector<=1;purpose<=3;
                        if(SOURCE_FREEZE!=0)begin state<=FREEZE_WAIT;end
                        else state<=COPY_READ;
                    end else if(frame_timer>=FRAME_WAIT_CYCLES)begin fail_code<=4'hb;state<=FAIL;end
                end
                FREEZE_WAIT:begin
                    frame_timer<=frame_timer+1'b1;
                    if(video_paused)state<=FREEZE_VERIFY0;
                    else if(frame_timer>=FRAME_WAIT_CYCLES)begin fail_code<=4'hb;state<=FAIL;end
                end
                FRAME_PRIME,FRAME_RETRY:begin
                    frame_timer<=frame_timer+1'b1;
                    if(frame_timer>=FRAME_WAIT_CYCLES)begin fail_code<=4'hb;state<=FAIL;end
                    else state<=state==FRAME_RETRY ? FRAME_PRIME : FRAME_WAIT;
                end
                FREEZE_VERIFY0:begin
                    frame_timer<=frame_timer+1'b1;
                    source_snapshot_ok<=!source_stale;
                    if(frame_timer>=FRAME_WAIT_CYCLES)begin fail_code<=4'hb;state<=FAIL;end
                    else state<=FREEZE_VERIFY1;
                end
                FREEZE_VERIFY1:begin
                    frame_timer<=frame_timer+1'b1;
                    if(frame_timer>=FRAME_WAIT_CYCLES)begin fail_code<=4'hb;state<=FAIL;end
                    else state<=source_snapshot_ok ? COPY_READ : FRAME_RETRY;
                end
                COPY_READ,SAVE_READ:begin
                    if(ddr_ready && ddr_req)begin
                        issued<=issued+1'b1;read_addr<=advanced_addr;
                        if(issued==6'd31)state<=state==COPY_READ ? COPY_DRAIN : SAVE_DRAIN;
                    end
                    if(ddr_rvalid)received<=received+1'b1;
                end
                COPY_DRAIN:begin
                    if(ddr_rvalid)received<=received+1'b1;
                    if(received==6'd32)begin ram_index<=0;state<=WORD_WAIT;end
                end
                WORD_WAIT:state<=WORD_WRITE;
                WORD_WRITE:if(ddr_ready)begin
                    write_addr<=advanced_addr;
                    if(ram_index==5'd31)state<=purpose==3 ? COPY_NEXT : SECTOR_NEXT;
                    else begin ram_index<=ram_index+1'b1;state<=WORD_WAIT;end
                end
                COPY_NEXT:begin
                    if(source_stale)begin fail_code<=4'hc;state<=FAIL;end
                    else if(sector==IMAGE_SECTORS)begin
                        purpose<=0;read_addr<=target_base;issued<=0;received<=0;
                        sector<=1;status<=4;state<=SAVE_READ;
                    end else begin
                        sector<=sector+1'b1;
                        issued<=0;received<=0;state<=COPY_READ;
                    end
                end
                SAVE_DRAIN:begin
                    if(ddr_rvalid)received<=received+1'b1;
                    if(received==6'd32)begin
                        sd_lba<=slot_sector+sector;sd_write<=1;sd_request<=1;after_sd<=SECTOR_NEXT;state<=SD_WAIT;
                    end
                end
                SECTOR_NEXT:begin
                    if(sector==IMAGE_SECTORS)begin
                        if(purpose==0)begin
                            ram_index<=0;state<=FILL_HEADER;
                        end else begin
                            display_bank<=target_bank;display_slot<=slot;display_valid<=1;
                            status<=2;state<=IDLE;
                        end
                    end else begin
                        sector<=sector+1'b1;
                        issued<=0;received<=0;ram_index<=0;
                        state<=purpose==0 ? SAVE_READ : LOAD_NEXT;
                    end
                end
                LOAD_NEXT:begin sd_lba<=slot_sector+sector;sd_write<=0;sd_request<=1;
                    ram_index<=0;after_sd<=WORD_WAIT;state<=SD_WAIT;end
                FILL_HEADER:if(ram_index==31)begin
                    sd_lba<=slot_sector;sd_write<=1;sd_request<=1;after_sd<=FINISH;state<=SD_WAIT;
                end else ram_index<=ram_index+1'b1;
                FINISH:begin valid_slots[slot]<=1;active_count<=active_count+1'b1;display_slot<=slot;status<=2;state<=IDLE;end
                FORMAT_FILL:if(ram_index==31)begin
                    sd_lba<=2048;sd_write<=1;sd_request<=1;after_sd<=VOLUME_REQ;
                    volume_header<=1;state<=SD_WAIT;
                end else ram_index<=ram_index+1'b1;
                FAIL:begin status<=fail_code;state<=IDLE;browsing<=0;format_active<=0;end
                default:begin fail_code<=4'h6;state<=FAIL;end
            endcase
            if(copy_active && source_stale)begin
                // Drain the currently accepted short burst before declaring failure.
                // Continue it but discard the entire photo at COPY_NEXT.
                status<=4'hc;
            end
            if(command_valid && command[15:8]==8'h27)begin
                if(command[7:0]==0)album<=0;
                else if(!clear_occupied && state==IDLE && !busy && formatted && active_count!=0)begin
                    album<=1;browsing<=1;browse_steps<=0;browse_backward<=command[7:0]==2;
                    browse_cursor<=command[7:0]==1 ? display_slot : command[7:0]==2 ? display_slot-1'b1 : display_slot+1'b1;
                end else if(!clear_occupied)status<=busy ? 8 : !formatted ? 1 : 9;
            end
            // A rejected extra capture must not hide the failure being reported.
            if(busy_notice && busy && !clear_occupied && !format_armed && state!=FAIL && status!=4'h6 && status<4'hb &&
                !(copy_active && source_stale))status<=8;
            // Keep confirmation/queued feedback visible while the old operation
            // drains; never override a live source/SD error with an ARMED label.
            if(state!=FAIL && !(state==SD_WAIT && sd_done && sd_error) &&
                !(copy_active && source_stale) && status<4'hb)begin
                if(format_armed && arm_timer<29'd400000000 && sd_ready)status<=10;
                if(clear_pending && sd_ready)status<=8;
            end
            if(clear_command && !clear_occupied)begin
                if(sd_ready)begin
                    if(clear_confirm)begin
                        clear_pending<=1;format_armed<=0;arm_timer<=0;
                        if(state!=FAIL && !(state==SD_WAIT && sd_done && sd_error) &&
                            !(copy_active && source_stale))status<=8;
                    end else begin
                        format_armed<=1;arm_timer<=0;
                        if(state!=FAIL && !(state==SD_WAIT && sd_done && sd_error) &&
                            !(copy_active && source_stale))status<=10;
                    end
                end else begin format_armed<=0;arm_timer<=0;end
            end
            // Do not carry a confirmed request onto a subsequently inserted card.
            // Active transfers retain their normal completion/error handling.
            if(!sd_ready && clear_pending)begin clear_pending<=0;status<=4'hd;end
        end
    end
endmodule

// Isolated single-reference prototype, no private RAM. Shares the existing 512B sector buffer.
// No filesystem. STM1 format is new. Save acknowledgement is not a power-fail atomicity proof.
module template_sd_manager #(parameter [31:0] TEMPLATE_LBA=32'd526337)(
 input clk,rst_n,request,load,cancel,photo_busy,
 output wire busy,storage_owner,output reg done,error,
 output reg io_req,output reg [1:0] io_op,output reg [7:0] io_addr,output reg [31:0] io_wdata,
 input io_ready,io_done,io_error,input [31:0] io_rdata,
 output reg sd_request,sd_write,output wire [31:0] sd_lba,
 input sd_ready,sd_done,sd_error,input [31:0] sd_sectors,
 output reg ram_we,output reg [4:0] ram_addr,output wire [127:0] ram_wdata,input [127:0] ram_rdata);
 localparam IDLE=0,WAIT_PHOTO=1,META_REQ=2,META_WAIT=3,GET_REQ=4,GET_WAIT=5,
 PAD=6,HEADER=7,SEND_WRITE=8,SEND_READ=9,WAIT_SD=10,H_WAIT0=11,H_WAIT1=12,H_CHECK=13,
 BEGIN_REQ=14,BEGIN_WAIT=15,R_WAIT0=16,R_WAIT1=17,R_CAPTURE=18,PUT_REQ=19,PUT_WAIT=20,
 META_PUT=21,META_PUT_WAIT=22,COMMIT_REQ=23,COMMIT_WAIT=24,FINISH=25,FAIL=26;
 reg [4:0] state;reg loading,abort_pending;
 reg [7:0] word_index;reg [31:0] meta;reg [15:0] sum,expected_sum;reg [127:0] pack;
 wire [15:0] next_sum=sum+pack[127:112];
 assign busy=state!=IDLE;assign storage_owner=state!=IDLE && state!=WAIT_PHOTO;
 assign sd_lba=TEMPLATE_LBA;
 // Reuse the serial pack register as the sector write bus. No duplicate128b latch.
 assign ram_wdata=ram_addr==0 ? {32'h53544d31,8'd1,8'ha5,16'd256,meta,sum,~sum} : pack;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state<=IDLE;loading<=0;abort_pending<=0;word_index<=0;meta<=0;sum<=0;expected_sum<=0;pack<=0;
 done<=0;error<=0;io_req<=0;io_op<=0;io_addr<=0;io_wdata<=0;
 sd_request<=0;sd_write<=0;ram_we<=0;ram_addr<=0;
 end else begin
 done<=0;io_req<=0;sd_request<=0;ram_we<=0;
 if(cancel && busy)abort_pending<=1;
 case(state)
 IDLE:if(request)begin loading<=load;abort_pending<=0;error<=0;word_index<=0;sum<=0;state<=WAIT_PHOTO;end
 WAIT_PHOTO:if(!photo_busy && sd_ready)begin
   if(sd_sectors<=TEMPLATE_LBA)state<=FAIL;
   else state<=loading?SEND_READ:META_REQ;
 end
 META_REQ:if(io_ready)begin io_req<=1;io_op<=0;io_addr<=128;state<=META_WAIT;end
 META_WAIT:if(io_done)begin if(io_error)state<=FAIL;else begin meta<=io_rdata;word_index<=0;sum<=0;pack<=0;state<=GET_REQ;end end
 GET_REQ:if(io_ready)begin io_req<=1;io_op<=0;io_addr<=word_index;state<=GET_WAIT;end
 GET_WAIT:if(io_done)begin
   if(io_error)state<=FAIL;else begin
     sum<=sum+io_rdata[15:0];pack<={pack[111:0],io_rdata[15:0]};
     if(word_index[2:0]==7)begin ram_we<=1;ram_addr<=1+word_index[6:3];end
     if(word_index==127)begin word_index<=17;state<=PAD;end
     else begin word_index<=word_index+1'b1;state<=GET_REQ;end
   end end
 PAD:begin ram_we<=1;ram_addr<=word_index[4:0];pack<=0;if(word_index==31)state<=HEADER;else word_index<=word_index+1'b1;end
 HEADER:begin ram_we<=1;ram_addr<=0;state<=SEND_WRITE;end
 SEND_WRITE:begin sd_write<=1;sd_request<=1;state<=WAIT_SD;end
 SEND_READ:begin sd_write<=0;sd_request<=1;state<=WAIT_SD;end
 WAIT_SD:if(sd_done)begin
   if(sd_error)state<=FAIL;
   else if(loading)begin ram_addr<=0;state<=H_WAIT0;end
   else state<=FINISH;
 end
 H_WAIT0:state<=H_WAIT1;
 H_WAIT1:state<=H_CHECK;
 H_CHECK:begin
   if(ram_rdata[127:64]!={32'h53544d31,8'd1,8'ha5,16'd256} || ram_rdata[15:0]!=~ram_rdata[31:16])state<=FAIL;
   else begin meta<=ram_rdata[63:32];expected_sum<=ram_rdata[31:16];sum<=0;word_index<=0;state<=BEGIN_REQ;end
 end
 BEGIN_REQ:if(io_ready)begin io_req<=1;io_op<=2;io_addr<=0;io_wdata<=0;state<=BEGIN_WAIT;end
 BEGIN_WAIT:if(io_done)begin if(io_error)state<=FAIL;else begin ram_addr<=1;state<=R_WAIT0;end end
 R_WAIT0:state<=R_WAIT1;
 R_WAIT1:state<=R_CAPTURE;
 R_CAPTURE:begin pack<=ram_rdata;state<=PUT_REQ;end
 PUT_REQ:if(io_ready)begin io_req<=1;io_op<=1;io_addr<=word_index;io_wdata<={16'd0,pack[127:112]};state<=PUT_WAIT;end
 PUT_WAIT:if(io_done)begin
   if(io_error)state<=FAIL;else begin
    sum<=next_sum;pack<={pack[111:0],16'd0};
    if(word_index==127)state<=next_sum==expected_sum?META_PUT:FAIL;
    else begin word_index<=word_index+1'b1;
      if(word_index[2:0]==7)begin ram_addr<=ram_addr+1'b1;state<=R_WAIT0;end else state<=PUT_REQ;
    end
   end end
 META_PUT:if(io_ready)begin io_req<=1;io_op<=1;io_addr<=128;io_wdata<=meta;state<=META_PUT_WAIT;end
 META_PUT_WAIT:if(io_done)state<=io_error?FAIL:COMMIT_REQ;
 COMMIT_REQ:if(io_ready)begin io_req<=1;io_op<=3;io_addr<=0;state<=COMMIT_WAIT;end
 COMMIT_WAIT:if(io_done)state<=io_error?FAIL:FINISH;
 FINISH:begin done<=1;error<=abort_pending || cancel;state<=IDLE;end
 FAIL:begin done<=1;error<=1;state<=IDLE;end
 default:state<=FAIL;
 endcase
 // Finish accepted I/O/SD transaction before cancellation is reported.
 // Core search/track eligibility is always suppressed while manager owns storage.
 end end
endmodule

// Prototype bridge: DDR owner100 <-> CSI60. Held payloads, one transaction in flight.
module template_io_cdc(
 input clk,rst_n,request,input [1:0] op,input [7:0] address,input [31:0] wdata,
 output wire ready,output wire done,error,output wire [31:0] rdata,
 input core_clk,core_rst_n,input core_ready,core_ack,core_error,input [31:0] core_rdata,
 output reg core_req,output wire [1:0] core_op,output wire [7:0] core_address,output wire [31:0] core_wdata);
 wire req_busy,received,reply_busy;wire [41:0] received_data;wire [32:0] reply;
 reg pending,waiting;
 photo_mailbox #(.WIDTH(42)) req_mail(.src_clk(clk),.src_rst_n(rst_n),.src_send(request && ready),
 .src_data({op,address,wdata}),.src_busy(req_busy),.dst_clk(core_clk),.dst_rst_n(core_rst_n),.dst_valid(received),.dst_data(received_data));
 photo_mailbox #(.WIDTH(33)) rsp_mail(.src_clk(core_clk),.src_rst_n(core_rst_n),.src_send(core_ack),
 .src_data({core_error,core_rdata}),.src_busy(reply_busy),.dst_clk(clk),.dst_rst_n(rst_n),.dst_valid(done),.dst_data(reply));
 assign ready=!req_busy && !waiting;
 assign error=reply[32];assign rdata=reply[31:0];
 // Mailbox payload remains stable until the outstanding reply is received.
 assign {core_op,core_address,core_wdata}=received_data;
 always @(posedge clk or negedge rst_n)if(!rst_n)waiting<=0;
 else begin if(request && ready)waiting<=1;if(done)waiting<=0;end
 always @(posedge core_clk or negedge core_rst_n)begin
 if(!core_rst_n)begin pending<=0;core_req<=0;end
 else begin
 core_req<=0;
 if(received)pending<=1;
 if(pending && core_ready && !reply_busy)begin core_req<=1;pending<=0;end
 end end
endmodule

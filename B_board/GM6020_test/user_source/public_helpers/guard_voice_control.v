// Public helper extracted from the mixed integration file.
// Core tracking and control implementations are not included.
module guard_voice_control #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    parameter integer COOLDOWN_MS=3000
)(
    input wire clk,rst_n,feature_enabled,all_enabled,
    input wire feature_suppress,feature_rearm,
    input wire command_valid,
    input wire [7:0] command_code,command_data,
    input wire result_update,inside_flag,comm_timeout,
    output wire tx,busy
);
    wire [1:0] mode=all_enabled?2'd2:(feature_enabled?2'd1:2'd0);
    reg [1:0] previous_mode;
    reg inside_seen,seconds_valid,deferred_entry,pending;
    reg [7:0] seconds_code,pending_code;
    reg next_inside,next_seconds_valid,next_deferred,next_pending;
    reg [7:0] next_seconds_code,next_pending_code;
    wire configure=command_valid && command_code==8'h25 && command_data>=1 && command_data<=10;
    wire reconfirm=command_valid && command_code==8'h21 && command_data==1 && feature_enabled;
    wire outside_update=result_update && !comm_timeout && !inside_flag;
    // Missing legacy simulation ports retain their former unmuted behavior.
    wire feature_muted=feature_suppress===1'b1;
    wire feature_rearmed=feature_rearm===1'b1;
    localparam [63:0] COOLDOWN_TICKS=(64'd1*CLK_HZ*COOLDOWN_MS+999)/1000;
    localparam integer CW=COOLDOWN_TICKS>0?$clog2(COOLDOWN_TICKS+1):1;
    reg [CW-1:0] cooldown_left;
    wire frame_done;
    wire request=pending && mode!=0 && mode==previous_mode && !reconfirm &&
        !comm_timeout && !outside_update && cooldown_left==0 &&
        !(mode==1 && (feature_muted || feature_rearmed));
    wire tx_ready;
    uart_voice_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) speech_uart(
        .clk(clk),.rst_n(rst_n),.valid(request),.payload(pending_code),
        .ready(tx_ready),.tx(tx),.busy(busy),.frame_done(frame_done));
    // A global post-frame cooldown: mode/target/config changes cannot bypass
    // it. Existing pending speech is retained only while still authorized;
    // outside/timeout/mode exit keep their original cancellation behavior.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)cooldown_left<=0;
        else if(frame_done)cooldown_left<=COOLDOWN_TICKS[CW-1:0];
        else if(cooldown_left!=0)cooldown_left<=cooldown_left-1'b1;
    end
    always @* begin
        next_inside=inside_seen;next_seconds_valid=seconds_valid;
        next_deferred=deferred_entry;next_pending=pending;
        next_seconds_code=seconds_code;next_pending_code=pending_code;
        if(request && tx_ready)next_pending=0;
        if(mode!=previous_mode || reconfirm)begin
            next_inside=0;next_deferred=0;next_pending=0;next_seconds_valid=0;
        end
        if(configure)begin next_seconds_valid=1;next_seconds_code=command_data+8'd1;end
        if(mode==0)begin
            next_inside=0;next_deferred=0;next_pending=0;
        end else if(comm_timeout)begin
            // Unknown network state is not a new entry. Do not reannounce a
            // continuously present target on reconnect, or queue stale speech.
            next_deferred=0;next_pending=0;
        end else if(!reconfirm)begin
            if(result_update)begin
                if(!inside_flag)begin next_inside=0;next_deferred=0;next_pending=0;end
                else if(!next_inside)begin
                    next_inside=1;
                    if(mode==2 || next_seconds_valid)begin
                        next_pending=1;next_pending_code=mode==2?8'h01:next_seconds_code;
                        next_deferred=0;
                    end else next_deferred=1;
                end
            end
            if(next_deferred && next_inside && next_seconds_valid)begin
                next_pending=1;next_pending_code=next_seconds_code;next_deferred=0;
            end
        end
        // Keep mode, configured seconds, inside memory and cooldown intact.
        // Cancel only future feature speech; never truncate a frame in flight.
        if(mode==1 && feature_muted)begin next_pending=0;next_deferred=0;end
        // Return completion retains seconds/cooldown but starts a fresh entry
        // cycle. Ignore a coincident old record; the next high result may warn.
        if(mode==1 && feature_rearmed)begin next_inside=0;next_deferred=0;next_pending=0;end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            previous_mode<=0;inside_seen<=0;seconds_valid<=0;
            deferred_entry<=0;pending<=0;seconds_code<=0;pending_code<=0;
        end else begin
            previous_mode<=mode;inside_seen<=next_inside;seconds_valid<=next_seconds_valid;
            deferred_entry<=next_deferred;pending<=next_pending;
            seconds_code<=next_seconds_code;pending_code<=next_pending_code;
        end
    end
`ifndef SYNTHESIS
    initial if(CLK_HZ<1000 || COOLDOWN_MS<0)$fatal(1,"Invalid speech cooldown parameters");
`endif
endmodule

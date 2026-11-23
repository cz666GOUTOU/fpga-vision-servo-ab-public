`include "fpga_motion_example_config.vh"
// Two-target fixed-background detector. DS=4. Single background grey RAM.
// Enable -> averaged complete stable background frames -> freeze.
// Completed camera gain changes clear history and wait before relearning.
// Capture one sampled row, then process it during the next three skipped rows.
// Component statistics: 16 x 50-bit synchronous single-write-port RAM.
// Bounded four-connectivity, 15 LIVE labels; completed components retire per row.
// Canonicalize the line before recycling labels: no stale aliases may survive.
module zhencha_multi_ccl #(
 parameter integer H_ACTIVE=1280,V_ACTIVE=720,DS=4,
 parameter [7:0] THRESH=`FPGA_MOTION_THRESH_DEFAULT,
 parameter integer MIN_AREA=`FPGA_MOTION_MIN_AREA_DEFAULT,MAX_TRACK=2,LABELS=16,HOLD_FRAMES=`FPGA_MOTION_HOLD_FRAMES_DEFAULT,MATCH_GAP=`FPGA_MOTION_MATCH_GAP_DEFAULT,
 parameter integer TRACK_MIN_AREA=`FPGA_MOTION_TRACK_MIN_AREA_DEFAULT,MERGE_GAP=`FPGA_MOTION_MERGE_GAP_DEFAULT,JUMP_LIMIT=`FPGA_MOTION_JUMP_LIMIT_DEFAULT,
 parameter integer GAIN_SETTLE_FRAMES=`FPGA_MOTION_GAIN_SETTLE_FRAMES_DEFAULT // complete HDMI frames, 0..255
)(
 input clk,rst_n,detect_en,pre_frame_vsync,pre_frame_de,
 input [23:0] pre_rgb,
 // Preserve top-level bus shape; only slots 0 and 1 can be valid.
 output reg [3:0] box_valid,
 output reg [35:0] box_xmin,box_xmax,
 output reg [31:0] box_ymin,box_ymax,
 output reg overflow,
 input wire gain_change, // frame-boundary event; connect explicitly (TD has no pulldown)
 output reg result_update,
 output wire result_ready,
 output reg [1:0] result_fresh
);
 localparam W=H_ACTIVE/4,H=V_ACTIVE/4;
 reg [10:0] cx;reg [9:0] cy;
 reg vs_d,armed,frame_complete,sd;
 reg capturing,background_valid;
 reg [1:0] stable_frames;
 // Only comparisons with W*H/`FPGA_MOTION_STABLE_RATIO consume these saturated counters.
 localparam integer CHANGE_BITS=(W*H/`FPGA_MOTION_STABLE_RATIO<1023)?10:16;
 localparam [CHANGE_BITS-1:0] CHANGE_MAX={CHANGE_BITS{1'b1}};
 reg [CHANGE_BITS-1:0] background_changes;
 reg [CHANGE_BITS-1:0] background_changes12,background_changes16;
 reg signed [25:0] background_drift;
 reg [4:0] background_threshold;
 // Preserve the legacy 8-bit loaded-value truncation outside 0..255.
 localparam integer GAIN_WAIT_WIDTH=(GAIN_SETTLE_FRAMES<0 || GAIN_SETTLE_FRAMES>255)?8:
     ((GAIN_SETTLE_FRAMES<2)?1:$clog2(GAIN_SETTLE_FRAMES+1));
 reg [GAIN_WAIT_WIDTH-1:0] gain_wait;
 reg [15:0] background_samples;
 reg [7:0] gray_d,yd;reg [8:0] xd;
 wire boundary=pre_frame_vsync&&!vs_d;
 wire sample;wire [8:0] sx;wire [7:0] sy;wire [7:0] sample_gray;
 wire detector_clear=!detect_en||gain_change||(gain_wait!=0);
 wire [15:0] sample_addr=sy*W+sx;
 wire [15:0] saved_addr=yd*W+xd;
 wire [17:0] weighted={10'b0,pre_rgb[23:16]}*18'd77+
                         {10'b0,pre_rgb[15:8]}*18'd150+
                         {10'b0,pre_rgb[7:0]}*18'd29;
 wire [7:0] old_gray;
 wire signed [8:0] signed_delta=$signed({1'b0,gray_d})-$signed({1'b0,old_gray});
 wire [7:0] delta=signed_delta[8] ? (~signed_delta[7:0]+8'd1) : signed_delta[7:0];
 localparam signed [25:0] DRIFT_LIMIT=W*H*`FPGA_MOTION_DRIFT;
 wire stable_candidate=(background_changes16<=W*H/`FPGA_MOTION_STABLE_RATIO)&&
                       (background_drift<=DRIFT_LIMIT)&&(background_drift>=-DRIFT_LIMIT);
 wire [9:0] smooth_sum=`FPGA_MOTION_BACKGROUND_BLEND;
 wire [7:0] background_pixel=background_valid?smooth_sum[9:2]:gray_d;
 // One-cycle delayed write shares the existing synchronous background RAM.
 // Samples are at least four clocks apart: read -> compare/blend/write.
 wire background_write=sd&&!detector_clear&&capturing&&!armed&&!frame_complete;
 wire [15:0] addr=background_write?saved_addr:sample_addr;
 motion_gray_block4 #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE)) gray_average
 (clk,rst_n,pre_frame_vsync,pre_frame_de&&!pre_frame_vsync,cx,cy,weighted[15:8],sample,sx,sy,sample_gray);
 zhencha U_zhencha(.clka(clk),.addra(addr),.dia(background_pixel),.wea(background_write),
 .doa(old_gray),.dob(),.addrb(16'd0),.ceb(1'b0),.dib(8'd0),.web(1'b0));
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin cx<=0;cy<=0;vs_d<=0;armed<=0;frame_complete<=0;sd<=0;gray_d<=0;xd<=0;yd<=0;capturing<=0;background_samples<=0;background_valid<=0;stable_frames<=0;background_changes<=0;background_changes12<=0;background_changes16<=0;background_drift<=0;background_threshold<=`FPGA_MOTION_BG_LOW;gain_wait<=0;end
 else begin
  vs_d<=pre_frame_vsync;
  if(pre_frame_vsync)begin cx<=0;cy<=0;end
  else if(pre_frame_de)begin
   if(cx==H_ACTIVE-1)begin cx<=0;cy<=(cy==V_ACTIVE-1)?0:cy+1'b1;end
   else cx<=cx+1'b1;
  end
  if(gain_change)gain_wait<=GAIN_SETTLE_FRAMES;
  else if(boundary&&gain_wait!=0)gain_wait<=gain_wait-1'b1;
  sd<=sample&&!detector_clear;gray_d<=sample_gray;xd<=sx;yd<=sy;
  if(detector_clear)begin
   armed<=0;frame_complete<=0;capturing<=0;background_samples<=0;background_valid<=0;
   stable_frames<=0;background_changes<=0;background_changes12<=0;background_changes16<=0;
   background_drift<=0;background_threshold<=`FPGA_MOTION_BG_LOW;
   // Start after exactly the configured number of complete settling frames.
   if(boundary&&detect_en&&((!gain_change&&gain_wait==1)||
      (gain_change&&GAIN_SETTLE_FRAMES==0)))capturing<=1;
  end
  else if(!armed) begin
   // Compare against the smoothed complete background, before this write.
   if(background_write&&background_valid)begin
    if(delta>`FPGA_MOTION_BG_DIFF_LOW&&background_changes!=CHANGE_MAX)background_changes<=background_changes+1'b1;
    if(delta>`FPGA_MOTION_BG_DIFF_MID&&background_changes12!=CHANGE_MAX)background_changes12<=background_changes12+1'b1;
    if(delta>`FPGA_MOTION_BG_DIFF_HIGH&&background_changes16!=CHANGE_MAX)background_changes16<=background_changes16+1'b1;
    background_drift<=background_drift+{{17{signed_delta[8]}},signed_delta};
   end
   if(background_write) begin
    background_samples<=background_samples+16'd1;
    if(xd==W-1&&yd==H-1&&background_samples==W*H-1)frame_complete<=1;
   end
   if(boundary)begin
    background_samples<=0;frame_complete<=0;background_changes<=0;
    background_changes12<=0;background_changes16<=0;background_drift<=0;
    capturing<=1;background_valid<=capturing&&frame_complete;
    if(capturing&&frame_complete&&background_valid&&stable_candidate)begin
     background_threshold<=background_changes<=W*H/`FPGA_MOTION_STABLE_RATIO?`FPGA_MOTION_BG_SELECT_LOW:
                           (background_changes12<=W*H/`FPGA_MOTION_STABLE_RATIO?`FPGA_MOTION_BG_SELECT_MID:`FPGA_MOTION_BG_SELECT_HIGH);
     if(stable_frames==`FPGA_MOTION_BG_CONFIRM)begin armed<=1;capturing<=0;end
     else stable_frames<=stable_frames+1'b1;
    end else stable_frames<=0;
   end
  end
 end
 wire fv0,fv1,fv,fb0,fb1,fb;
 wire [8:0] fx0,fx1,fx;wire [7:0] fy0,fy1,fy;
 wire filter_reset_n=rst_n&&!detector_clear&&armed;
 wire hv,hb;wire [8:0] hx;wire [7:0] hy;
 motion_bit_window #(.W(W),.H(H),.OP(0),.ERAM_ROWS(1)) majority_filter
 (clk,filter_reset_n,hv,hx,hy,hb,fv0,fx0,fy0,fb0);
 motion_bit_window #(.W(W),.H(H),.OP(1),.ERAM_ROWS(1)) close_dilate
 (clk,filter_reset_n,fv0,fx0,fy0,fb0,fv1,fx1,fy1,fb1);
 motion_bit_window #(.W(W),.H(H),.OP(2),.ERAM_ROWS(1)) close_erode
 (clk,filter_reset_n,fv1,fx1,fy1,fb1,fv,fx,fy,fb);
 (* ram_style="bram" *) reg row_mask[0:W-1];
 reg row_mask_read,row_mask_forward,row_mask_forward_bit;
 wire row_mask_q=row_mask_forward?row_mask_forward_bit:row_mask_read;
 reg filtered_frame_done;

 localparam IDLE=0,FETCH=1,ROOTS=2,CHOOSE=3,READ_A=4,GET_A=5,
 READ_B=6,GET_B=7,SAVE=8,DROP=9,NEXT=10,CLEAR=11,
 SCAN_READ=12,SCAN_GET=13,MATCH_DELTA=14,MATCH_COST=15,MATCH_PICK=16,
 SCAN_SAVE=17,TRACK_INIT=18,TRACK_NEW=19,PUBLISH=20,GET_A_PLUS=21,
 NORMALIZE=22,ROW_READY=23,SCAN_CHECK=24,RETIRE=25,
 GROUP_TEST=26,GROUP_SAVE=27,TRACK_UPDATE=28,DEDUP=29,GROUP_SORT=30,
 ASSOC_BEGIN=31,ASSOC_SAVE=32,
 TRACK_CLOSE_RAW=33,TRACK_CLOSE_JUMP=34,TRACK_CLOSE_DISPLAY=35,
 TRACK_SMOOTH_LOAD=36,TRACK_SMOOTH_CALC=37,TRACK_SMOOTH_STORE=38,TRACK_SMOOTH_UNUSED=39,
 MATCH_DIMS=40,MATCH_EVAL=41,TRACK_LOAD=42,
 TRACK_SMOOTH_UNUSED2=43,TRACK_SMOOTH_UNUSED3=44,
 TRACK_MOTION_LOAD=45,TRACK_MOTION_SUM=46,TRACK_MOTION_DELTA=47,TRACK_DECIDE=48,
 TRACK_NEW_LOAD=49,TRACK_NEW_PAD=50,
 DEDUP_LOAD=51,DEDUP_DIMS=52,DEDUP_SPAN=53,DEDUP_RESULT=54,DEDUP_PAD=55,
 GROUP_LOAD=56,GROUP_DIMS=57,GROUP_SPAN=58;
 reg [5:0] state;
 // Observation only: registered with the existing box publication, never a gate.
 assign result_ready=armed&&!detector_clear;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)result_update<=0;
  else result_update<=!detector_clear&&(state==PUBLISH);
 always @(posedge clk or negedge rst_n)
 if(!rst_n)filtered_frame_done<=0;
 else if(detector_clear||state==PUBLISH)filtered_frame_done<=0;
 else if(fv&&fx==W-1&&fy==H-1)filtered_frame_done<=1;
 reg [3:0] root[0:15];
 (* ram_style="bram" *) reg [3:0] line_label[0:W-1];
 reg [3:0] line_label_q;
 reg [3:0] left_label,up_raw,left_raw,a,b,keep,drop,index;
 reg [15:0] allocated,active_row;
 reg [3:0] free_label;
 reg flush_frame,label_overflow,timing_overflow;
 integer free_i;
 always @*begin
  free_label=0;
  for(free_i=15;free_i>0;free_i=free_i-1)
   if(!allocated[free_i])free_label=free_i;
 end
 reg [8:0] px;reg [7:0] py;
 reg frame_pending;
 // Record: {area[15:0], xmin[8:0], xmax[8:0], ymin[7:0], ymax[7:0]}.
 (* ram_style="bram" *) reg [49:0] stats[0:15];
 reg [49:0] ram_q,record_a,record_new,candidate;
 // Prefetch before the existing FETCH/NORMALIZE consumer; no FSM state or
 // per-row/result cycle is added. IDLE enters FETCH with px reset to zero.
 wire [8:0] label_read_address=(state==IDLE)?9'd0:
     ((state==NEXT || state==NORMALIZE)?((px==W-1)?9'd0:px+9'd1):px);
 always @(posedge clk)begin
  row_mask_read<=row_mask[label_read_address];
  row_mask_forward<=fv&&(fx==label_read_address);
  row_mask_forward_bit<=fb;
  if(fv)row_mask[fx]<=fb;
 end
 reg ram_we;reg [3:0] ram_addr;reg [49:0] ram_data;
 always @*begin
  ram_addr=keep;ram_we=0;ram_data=record_new;
  case(state)
   READ_B:ram_addr=drop;
   DROP:begin ram_addr=drop;ram_we=1;ram_data=0;end
   SAVE:ram_we=1;
   CLEAR:begin ram_addr=index;ram_we=1;ram_data=0;end
   SCAN_READ:ram_addr=index;
   RETIRE:begin ram_addr=index;ram_we=1;ram_data=0;end
   default:begin end
  endcase
  if(detector_clear)ram_we=0;
 end
 // No RAM reset; CLEAR initializes contents using the same single write port.
 always @(posedge clk)begin
  ram_q<=stats[ram_addr];
  line_label_q<=line_label[label_read_address];
  if(ram_we)stats[ram_addr]<=ram_data;
  if(!detector_clear&&state==FETCH&&!row_mask_q)line_label[px]<=0;
  else if(!detector_clear&&state==SAVE)line_label[px]<=keep;
  else if(!detector_clear&&state==NORMALIZE)line_label[px]<=root[line_label_q];
 end
 function [49:0] combine;
  input [49:0] u,v;
  reg [16:0] area;
  reg [8:0] xlo,xhi;reg [7:0] ylo,yhi;
  begin
   area={1'b0,u[49:34]}+{1'b0,v[49:34]};
   xlo=u[33:25]<v[33:25]?u[33:25]:v[33:25];
   xhi=u[24:16]>v[24:16]?u[24:16]:v[24:16];
   ylo=u[15:8]<v[15:8]?u[15:8]:v[15:8];
   yhi=u[7:0]>v[7:0]?u[7:0]:v[7:0];
   combine=u[49:34]==0?v:(v[49:34]==0?u:{(area[16]?16'hffff:area[15:0]),xlo,xhi,ylo,yhi});
  end
 endfunction
 wire [49:0] pixel_record={16'd1,px,px,py,py};
 reg [49:0] best[0:1],linked[0:1],work[0:1];
 // Association uses unsmoothed coordinates, never the lagging displayed box.
 reg [49:0] raw_track[0:1],jump_record[0:1];
 // Same-edge cache of the counting envelope, not display padding. Coordinates
 // are clipped to the complete encoded domain, independently of W and H.
 reg [33:0] motion_bounds[0:1];
 function [33:0] counting_bounds;
  input [49:0] r;reg [8:0] xlo,xhi;reg [7:0] ylo,yhi;
  begin
   xlo=r[33:25]>9'd1 ? r[33:25]-9'd2 : 9'd0;
   xhi=r[24:16]<9'd510 ? r[24:16]+9'd2 : 9'd511;
   ylo=r[15:8]>8'd1 ? r[15:8]-8'd2 : 8'd0;
   yhi=r[7:0]<8'd254 ? r[7:0]+8'd2 : 8'd255;
   counting_bounds={xlo,xhi,ylo,yhi};
  end
 endfunction
 reg [1:0] track_active,jump_valid;
 wire light_exclude=(track_active[0]&&xd>=raw_track[0][33:25]&&xd<=raw_track[0][24:16]&&yd>=raw_track[0][15:8]&&yd<=raw_track[0][7:0])||
                    (track_active[1]&&xd>=raw_track[1][33:25]&&xd<=raw_track[1][24:16]&&yd>=raw_track[1][15:8]&&yd<=raw_track[1][7:0]);
 motion_light_hysteresis #(.W(W),.H(H),.HIGH(THRESH),.LOW(`FPGA_MOTION_LOW_OVERRIDE)) light_filter
 (clk,filter_reset_n,boundary,sd,xd,yd,gray_d,old_gray,light_exclude,hv,hx,hy,hb);
 reg group_i,group_found,group_slot;
 reg [1:0] duplicate_age;
 reg [2:0] independent_age;
 reg [1:0] hits[0:1];
 reg assoc_i;
 reg [1:0] assigned;
 reg [1:0] work_valid;
 reg [1:0] track_confirmed;
 // Only zero and age<HOLD_FRAMES are externally observable. Saturate
 // at the hold boundary; simple truncation would revive an expired track.
 // Retain the original 0..255 domain for unusual/large integer parameters.
 localparam integer AGE_LIMIT=(HOLD_FRAMES>=1 && HOLD_FRAMES<255)?HOLD_FRAMES:255;
 localparam integer AGE_WIDTH=$clog2(AGE_LIMIT+1);
 reg [AGE_WIDTH-1:0] age[0:1],work_age[0:1];
 reg track_i,match_i,match_found,match_slot,gate;
 reg [9:0] dx;reg [8:0] dy;reg [10:0] cost,best_cost;
 integer i;
 reg chosen;
 // Foreground-change side channel: synchronous old-mask read/write, same address.
 // Configurable motion persistence and deadband.
 // TD's native inference directive (not Vivado's "block" spelling).
 (* ram_style="bram" *) reg previous_mask[0:W*H-1];
 wire [15:0] mask_addr=fy*W+fx;
 reg mask_q,mask_bit,mask_pending,mask_ready,mask_history;
 reg [8:0] mask_x;reg [7:0] mask_y;
 reg [15:0] motion_changes[0:1];
 reg [1:0] moving;
 reg [1:0] motion_pending;
 reg [2:0] still_age[0:1],anchor_age[0:1];
 reg [49:0] motion_anchor[0:1];
 // Admission metadata only: held display tracks must not count as fresh motion.
 always @(posedge clk or negedge rst_n)
  if(!rst_n) result_fresh<=0;
  else if(detector_clear) result_fresh<=0;
  else if(state==PUBLISH) result_fresh<=work_valid & moving &
    {work_age[1]==0,work_age[0]==0};
 // Configurable changed-area acceptance.
 function [15:0] motion_limit;
  input [15:0] area;reg [16:0] scaled;
  begin scaled=`FPGA_MOTION_MOTION_AREA_SCALE;
   motion_limit=`FPGA_MOTION_MOTION_AREA_FLOOR;end
 endfunction
 function center_moved;
  input [49:0] u,v;reg [9:0] ux,vx,uy,vy;
  reg signed [10:0] dx,dy;
  reg x_quiet,y_quiet;
  begin
   ux={1'b0,u[33:25]}+{1'b0,u[24:16]};vx={1'b0,v[33:25]}+{1'b0,v[24:16]};
   uy={2'b0,u[15:8]}+{2'b0,u[7:0]};vy={2'b0,v[15:8]}+{2'b0,v[7:0]};
   // Configurable motion persistence and deadband.
   // Eleven bits hold the complete signed difference -1022..1022.
   // Configurable motion persistence and deadband.
   dx=$signed({1'b0,ux})-$signed({1'b0,vx});
   dy=$signed({1'b0,uy})-$signed({1'b0,vy});
   x_quiet=`FPGA_MOTION_QUIET_X;
   y_quiet=`FPGA_MOTION_QUIET_Y;
   center_moved=!x_quiet || !y_quiet;
  end
 endfunction
 integer mi;
 always @(posedge clk)if(fv)begin mask_q<=previous_mask[mask_addr];previous_mask[mask_addr]<=fb;end
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  mask_pending<=0;mask_ready<=0;mask_history<=0;mask_bit<=0;mask_x<=0;mask_y<=0;
  for(mi=0;mi<2;mi=mi+1)motion_changes[mi]<=0;
 end else if(detector_clear||!armed)begin
  mask_pending<=0;mask_ready<=0;mask_history<=0;
  for(mi=0;mi<2;mi=mi+1)motion_changes[mi]<=0;
 end else begin
  mask_pending<=fv;mask_history<=mask_ready;
  if(fv)begin mask_bit<=fb;mask_x<=fx;mask_y<=fy;if(fx==W-1&&fy==H-1)mask_ready<=1;end
  for(mi=0;mi<2;mi=mi+1)begin
   if(state==PUBLISH)motion_changes[mi]<=0;
   else if(mask_pending&&mask_history&&(mask_q!=mask_bit)&&track_active[mi]&&
    mask_x>=motion_bounds[mi][33:25]&&mask_x<=motion_bounds[mi][24:16]&&
    mask_y>=motion_bounds[mi][15:8]&&mask_y<=motion_bounds[mi][7:0]&&motion_changes[mi]!=16'hffff)
     motion_changes[mi]<=motion_changes[mi]+1'b1;
  end
 end
 function consistent;
  input [49:0] u,v;
  reg [9:0] uw,vw,uh,vh;
  begin
   uw={1'b0,u[24:16]}-{1'b0,u[33:25]}+10'd1;vw={1'b0,v[24:16]}-{1'b0,v[33:25]}+10'd1;
   uh={2'b0,u[7:0]}-{2'b0,u[15:8]}+10'd1;vh={2'b0,v[7:0]}-{2'b0,v[15:8]}+10'd1;
   consistent=`FPGA_MOTION_CONSISTENT;
  end
 endfunction
 function [49:0] padded;
  input [49:0] r;reg [8:0] xlo,xhi;reg [7:0] ylo,yhi;
  begin
   xlo=r[33:25]>1?r[33:25]-9'd2:9'd0;
   xhi=r[24:16]<W-2?r[24:16]+9'd2:W-1;
   ylo=r[15:8]>1?r[15:8]-8'd2:8'd0;
   yhi=r[7:0]<H-2?r[7:0]+8'd2:H-1;
   padded={r[49:34],xlo,xhi,ylo,yhi};
  end
 endfunction
 // Overlap comparisons use axis lengths, not multipliers or division.
 function similar;
  input [49:0] u,v;
  reg [9:0] uw,vw,uh,vh,ox,oy,lx,hx,ly,hy;
  reg [10:0] x_span,y_span;
  begin
   uw={1'b0,u[24:16]}-{1'b0,u[33:25]}+10'd1;
   vw={1'b0,v[24:16]}-{1'b0,v[33:25]}+10'd1;
   uh={2'b0,u[7:0]}-{2'b0,u[15:8]}+10'd1;
   vh={2'b0,v[7:0]}-{2'b0,v[15:8]}+10'd1;
   lx=u[33:25]>v[33:25]?u[33:25]:v[33:25];hx=u[24:16]<v[24:16]?u[24:16]:v[24:16];
   ly=u[15:8]>v[15:8]?u[15:8]:v[15:8];hy=u[7:0]<v[7:0]?u[7:0]:v[7:0];
   // Full encoded edges are X9/Y8. Eleven bits retain signed inclusive
   // lengths -510..512, including reversed intervals and an empty overlap.
   x_span={1'b0,hx}-{1'b0,lx}+11'd1;
   y_span={1'b0,hy}-{1'b0,ly}+11'd1;
   ox=x_span[10]?10'd0:x_span[9:0];oy=y_span[10]?10'd0:y_span[9:0];
   similar=u[49:34]!=0&&v[49:34]!=0&&
    ((ox>=uw-(uw>>2)&&oy>=uh-(uh>>2))||(ox>=vw-(vw>>2)&&oy>=vh-(vh>>2)));
  end
 endfunction

 // Small fixed limits use one exact signed difference per boundary.
 // Keep the original ten-bit addition/wrap behavior for other parameters.
 function near_edge;
  input [8:0] a,b;input [9:0] limit;
  reg signed [9:0] delta;
  begin
   delta=$signed({1'b0,a})-$signed({1'b0,b});
   case(limit)
    10'd2: near_edge=!(|delta[9:1]) || (&delta[9:1]) || delta==10'sd2;
    10'd4: near_edge=!(|delta[9:2]) || (&delta[9:2]) || delta==10'sd4;
    10'd16:near_edge=!(|delta[9:4]) || (&delta[9:4]) || delta==10'sd16;
    default:near_edge=({1'b0,a}<={1'b0,b}+limit)&&({1'b0,b}<={1'b0,a}+limit);
   endcase
  end
 endfunction
 function close_edges;
  input [49:0] u,v;input [9:0] limit;
  begin
   close_edges=near_edge(u[33:25],v[33:25],limit)&&near_edge(u[24:16],v[24:16],limit)&&
    near_edge({1'b0,u[15:8]},{1'b0,v[15:8]},limit)&&near_edge({1'b0,u[7:0]},{1'b0,v[7:0]},limit);
  end
 endfunction
 function [8:0] smooth_axis;
  input [8:0] n,o;reg signed [9:0] delta;
  reg [9:0] midpoint;reg in_deadband,round_up;
  begin
   // One signed difference covers -511..511 without wraparound.
   delta=$signed({1'b0,n})-$signed({1'b0,o});
   in_deadband=!(|delta[9:1]) || (&delta); // 0,+1 or -1
   round_up=!delta[9] && (|delta[8:0]);    // exactly n>o
   // Exact old rounding: upwards when approaching a larger coordinate,
   // downwards when approaching a smaller one. Keep the one-cell deadband.
   // Ten bits hold 511+511+1; do not truncate before dividing by two.
   midpoint={1'b0,n}+{1'b0,o}+{9'd0,round_up};
   smooth_axis=in_deadband?o:midpoint[9:1];
  end
 endfunction
 function [49:0] smooth_box;
  input [49:0] n,o;reg [8:0] yl,yh;
  begin
   yl=smooth_axis({1'b0,n[15:8]},{1'b0,o[15:8]});yh=smooth_axis({1'b0,n[7:0]},{1'b0,o[7:0]});
   smooth_box={n[49:34],smooth_axis(n[33:25],o[33:25]),smooth_axis(n[24:16],o[24:16]),yl[7:0],yh[7:0]};
  end
 endfunction
 // Share noncritical CCL unions. DEDUP is deliberately separate so stats RAM
 // and its operand mux cannot feed the TRACK_UPDATE padding/smoothing cone.
 reg [49:0] combine_u,combine_v;
 always @*begin
  combine_u=50'd0;combine_v=50'd0;
  case(state)
   GET_A:begin combine_u=ram_q;combine_v=pixel_record;end
   GET_B:begin combine_u=record_a;combine_v=ram_q;end
   GET_A_PLUS:begin combine_u=record_a;combine_v=pixel_record;end
   GROUP_SAVE:begin combine_u=best[group_slot];combine_v=candidate;end
   default:begin end
  endcase
 end
 wire [49:0] combined_record=combine(combine_u,combine_v);
 wire [49:0] dedup_record=combine(raw_track[0],raw_track[1]);
 wire [49:0] dedup_padded=padded(dedup_record);
 // Frame-end engine: registered operand selection -> arithmetic -> commit.
 // record_a is idle after association and holds this target's raw observation;
 // candidate holds its old display box; record_new holds smoothed boundaries.
 // Reuse this scratch only after all candidate association has completed.
 localparam [9:0] TRACK_JUMP_LIMIT=JUMP_LIMIT;
 reg [49:0] pipe_u,pipe_v;
 reg track_close_raw,track_close_jump,track_close_display;
 reg [33:0] track_bounds_q;
 reg track_has_observation,track_admit,track_motion;
 reg [8:0] track_smooth_n,track_smooth_o;
 reg signed [9:0] track_smooth_delta;
 reg [9:0] track_smooth_sum;
 reg [1:0] track_smooth_axis;
 reg [9:0] geom_uw,geom_vw,geom_uh,geom_vh;
 reg [9:0] geom_lx,geom_hx,geom_ly,geom_hy;
 reg [10:0] geom_x_span,geom_y_span;
 reg geometry_similar_q;
 function track_near_edge;
  input [8:0] u,v;input [1:0] mode;
  reg signed [9:0] delta;reg raw_near,near2,near4;
  begin
   delta=$signed({1'b0,u})-$signed({1'b0,v});
   near2=!(|delta[9:1]) || (&delta[9:1]) || delta==10'sd2;
   near4=!(|delta[9:2]) || (&delta[9:2]) || delta==10'sd4;
   case(TRACK_JUMP_LIMIT)
    10'd2:raw_near=near2;
    10'd4:raw_near=near4;
    10'd16:raw_near=!(|delta[9:4]) || (&delta[9:4]) || delta==10'sd16;
    default:raw_near=({1'b0,u}<={1'b0,v}+TRACK_JUMP_LIMIT)&&
                     ({1'b0,v}<={1'b0,u}+TRACK_JUMP_LIMIT);
   endcase
   track_near_edge=(mode==0)?raw_near:((mode==1)?near4:near2);
  end
 endfunction
 wire [33:0] track_old_bounds={box_xmin[track_i*9+:9],box_xmax[track_i*9+:9],
                             box_ymin[track_i*8+:8],box_ymax[track_i*8+:8]};
 wire [1:0] track_close_mode=(state==TRACK_CLOSE_DISPLAY)?2'd2:((state==TRACK_CLOSE_JUMP)?2'd1:2'd0);
 wire track_close_result=track_near_edge(pipe_u[33:25],pipe_v[33:25],track_close_mode)&&
  track_near_edge(pipe_u[24:16],pipe_v[24:16],track_close_mode)&&
  track_near_edge({1'b0,pipe_u[15:8]},{1'b0,pipe_v[15:8]},track_close_mode)&&
  track_near_edge({1'b0,pipe_u[7:0]},{1'b0,pipe_v[7:0]},track_close_mode);
 wire smooth_deadband=!(|track_smooth_delta[9:1]) || (&track_smooth_delta);
 wire smooth_round_up=!track_smooth_delta[9] && (|track_smooth_delta[8:0]);
 wire [9:0] smooth_rounded=track_smooth_sum+{9'd0,smooth_round_up};
 wire [8:0] track_smooth_result=`FPGA_MOTION_TRACK_BLEND;
 // Geometric widths/minmax and overlap spans are separate register stages.
 // Matching reuses the same small registers for doubled centers. Ten-bit
 // modulo widths and eleven-bit signed spans retain the previous predicates.
 wire [49:0] geometry_u=pipe_u,geometry_v=pipe_v;
 wire [9:0] geom_ox=geom_x_span[10]?10'd0:geom_x_span[9:0];
 wire [9:0] geom_oy=geom_y_span[10]?10'd0:geom_y_span[9:0];
 wire geometry_nonzero=geometry_u[49:34]!=0&&geometry_v[49:34]!=0;
 wire geometry_consistent=`FPGA_MOTION_GEOMETRY_CONSISTENT;
 wire geometry_similar=geometry_nonzero&&
  ((geom_ox>=geom_uw-(geom_uw>>2)&&geom_oy>=geom_uh-(geom_uh>>2))||
   (geom_ox>=geom_vw-(geom_vw>>2)&&geom_oy>=geom_vh-(geom_vh>>2)));
 wire signed [10:0] match_x_delta=$signed({1'b0,geom_lx})-$signed({1'b0,geom_hx});
 wire signed [9:0] match_y_delta=$signed({1'b0,geom_ly[8:0]})-$signed({1'b0,geom_hy[8:0]});
 wire [9:0] match_dx=match_x_delta[10] ? (~match_x_delta[9:0]+10'd1) : match_x_delta[9:0];
 wire [8:0] match_dy=match_y_delta[9] ? (~match_y_delta[8:0]+9'd1) : match_y_delta[8:0];
 wire motion_x_quiet=`FPGA_MOTION_QUIET_PIPE_X;
 wire motion_y_quiet=`FPGA_MOTION_QUIET_PIPE_Y;
 // GROUP_* and DEDUP_* share registered widths/minmax and inclusive spans.
 // The 10-bit modulo widths and 11-bit signed overlap retain the old predicate.
 wire [9:0] group_mw=geom_uw>geom_vw?geom_uw:geom_vw;
 wire [9:0] group_mh=geom_uh>geom_vh?geom_uh:geom_vh;
 wire group_x_close=!geom_x_span[10] || (&geom_x_span);
 wire group_y_close=!geom_y_span[10] || (&geom_y_span);
 wire group_fragments=geometry_nonzero&&
  ((geometry_u[49:34]<=(geometry_v[49:34]>>2))||
   (geometry_v[49:34]<=(geometry_u[49:34]>>2)))&&
  ((group_x_close&&geom_oy>=group_mh-(group_mh>>3)&&(geom_uw<=2||geom_vw<=2))||
   (group_y_close&&geom_ox>=group_mw-(group_mw>>3)&&(geom_uh<=2||geom_vh<=2)));
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  state<=CLEAR;index<=0;allocated<=1;active_row<=0;left_label<=0;
  flush_frame<=0;label_overflow<=0;timing_overflow<=0;
  px<=0;py<=0;up_raw<=0;left_raw<=0;a<=0;b<=0;keep<=0;drop<=0;
  record_a<=0;record_new<=0;candidate<=0;frame_pending<=0;overflow<=0;
  box_valid<=0;box_xmin<=0;box_xmax<=0;box_ymin<=0;box_ymax<=0;
  track_i<=0;match_i<=0;match_found<=0;match_slot<=0;gate<=0;
  dx<=0;dy<=0;cost<=0;best_cost<=0;work_valid<=0;track_confirmed<=0;
  track_active<=0;jump_valid<=0;group_i<=0;group_found<=0;group_slot<=0;duplicate_age<=0;independent_age<=0;assigned<=0;assoc_i<=0;moving<=0;motion_pending<=0;
  for(i=0;i<2;i=i+1)begin best[i]<=0;linked[i]<=0;work[i]<=0;age[i]<=0;work_age[i]<=0;raw_track[i]<=0;motion_bounds[i]<=counting_bounds(50'd0);jump_record[i]<=0;hits[i]<=0;still_age[i]<=0;anchor_age[i]<=0;motion_anchor[i]<=0;end
 end else if(detector_clear)begin
  state<=CLEAR;index<=0;frame_pending<=0;box_valid<=0;overflow<=0;
  label_overflow<=0;timing_overflow<=0;
  track_active<=0;track_confirmed<=0;work_valid<=0;jump_valid<=0;duplicate_age<=0;independent_age<=0;moving<=0;motion_pending<=0;
  for(i=0;i<2;i=i+1)begin hits[i]<=0;still_age[i]<=0;anchor_age[i]<=0;end
 end else begin
  if(boundary&&armed)frame_pending<=1;
  // Processing must finish before the next sampled row. Never silently accept an overrun.
  if(fv&&fx==0&&state!=IDLE)begin overflow<=1;timing_overflow<=1;end
  case(state)
   CLEAR:begin
    root[index]<=index;
    if(index==15)begin
     state<=IDLE;allocated<=1;active_row<=0;left_label<=0;overflow<=0;
     label_overflow<=0;timing_overflow<=0;flush_frame<=0;
     for(i=0;i<2;i=i+1)begin best[i]<=0;linked[i]<=0;end
    end
    else index<=index+1'b1;
   end
   IDLE:begin
    if(frame_pending&&filtered_frame_done)begin
     frame_pending<=0;index<=1;flush_frame<=1;state<=SCAN_CHECK;
    end else if(fv&&fx==W-1)begin px<=0;py<=fy;left_label<=0;state<=FETCH;end
   end
   FETCH:begin
    if(!row_mask_q)begin left_label<=0;state<=NEXT;end
    else begin
     up_raw<=py==0?0:line_label_q;left_raw<=px==0?0:left_label;state<=ROOTS;
    end
   end
   ROOTS:begin a<=root[left_raw];b<=root[up_raw];state<=CHOOSE;end
   CHOOSE:begin
    drop<=(a!=0&&b!=0&&a!=b)?(a<b?b:a):0;
    if(a==0&&b==0)begin
     if(free_label!=0)begin
      keep<=free_label;allocated[free_label]<=1;
      record_new<=pixel_record;state<=SAVE;
     end else begin overflow<=1;label_overflow<=1;keep<=0;record_new<=0;state<=SAVE;end
    end else begin keep<=a==0?b:(b==0?a:(a<b?a:b));state<=READ_A;end
   end
   READ_A:state<=GET_A;
   GET_A:begin
    record_a<=ram_q;
    if(drop!=0)state<=READ_B;
    else begin record_new<=combined_record;state<=SAVE;end
   end
   READ_B:state<=GET_B;
   GET_B:begin record_a<=combined_record;state<=GET_A_PLUS;end
   GET_A_PLUS:begin record_new<=combined_record;state<=SAVE;end
   SAVE:begin left_label<=keep;state<=drop!=0?DROP:NEXT;end
   DROP:begin
    for(i=1;i<16;i=i+1)if(root[i]==drop)root[i]<=keep;
    state<=NEXT;
   end
   NEXT:if(px==W-1)begin px<=0;active_row<=0;state<=NORMALIZE;end
        else begin px<=px+1'b1;state<=FETCH;end
   NORMALIZE:begin
    active_row[root[line_label_q]]<=1;
    if(px==W-1)state<=ROW_READY;else px<=px+1'b1;
   end
   ROW_READY:begin
    // All line entries now reference canonical roots. Alias IDs are safe to reuse.
    for(i=0;i<16;i=i+1)root[i]<=i;
    allocated<=active_row|16'd1;index<=1;flush_frame<=0;state<=SCAN_CHECK;
   end
   SCAN_CHECK:begin
    if(!flush_frame&&active_row[index])begin
     if(index==15)state<=IDLE;else index<=index+1'b1;
    end else state<=SCAN_READ;
   end
   SCAN_READ:state<=SCAN_GET;
   SCAN_GET:begin
    candidate<=ram_q;group_i<=0;group_found<=0;
    state<=ram_q[49:34]<TRACK_MIN_AREA ? RETIRE : GROUP_LOAD;
   end
   MATCH_DELTA:begin
    pipe_u<=candidate;pipe_v<=raw_track[match_i];state<=MATCH_DIMS;
   end
   MATCH_DIMS:begin
    geom_uw<={1'b0,pipe_u[24:16]}-{1'b0,pipe_u[33:25]}+10'd1;
    geom_vw<={1'b0,pipe_v[24:16]}-{1'b0,pipe_v[33:25]}+10'd1;
    geom_uh<={2'b0,pipe_u[7:0]}-{2'b0,pipe_u[15:8]}+10'd1;
    geom_vh<={2'b0,pipe_v[7:0]}-{2'b0,pipe_v[15:8]}+10'd1;
    geom_lx<={1'b0,pipe_u[33:25]}+{1'b0,pipe_u[24:16]};
    geom_hx<={1'b0,pipe_v[33:25]}+{1'b0,pipe_v[24:16]};
    geom_ly<={2'b0,pipe_u[15:8]}+{2'b0,pipe_u[7:0]};
    geom_hy<={2'b0,pipe_v[15:8]}+{2'b0,pipe_v[7:0]};state<=MATCH_EVAL;
   end
   MATCH_EVAL:begin
    dx<=match_dx;dy<=match_dy;
    gate<=track_active[match_i]&&!assigned[match_i]&&geometry_consistent&&pipe_u[33:25]<=pipe_v[24:16]+MATCH_GAP&&
      pipe_v[33:25]<=pipe_u[24:16]+MATCH_GAP&&
      pipe_u[15:8]<=pipe_v[7:0]+MATCH_GAP&&pipe_v[15:8]<=pipe_u[7:0]+MATCH_GAP;
    state<=MATCH_COST;
   end
   MATCH_COST:begin cost<={1'b0,dx}+{2'b0,dy};state<=MATCH_PICK;end
   MATCH_PICK:begin
    if(gate&&cost<best_cost)begin best_cost<=cost;match_slot<=match_i;match_found<=1;end
    if(match_i)state<=ASSOC_SAVE;else begin match_i<=1;state<=MATCH_DELTA;end
   end
   GROUP_LOAD:begin pipe_u<=candidate;pipe_v<=best[group_i];state<=GROUP_DIMS;end
   GROUP_TEST:begin
    if(group_fragments&&!group_found)begin group_found<=1;group_slot<=group_i;end
    if(group_i)state<=GROUP_SAVE;else begin group_i<=1;state<=GROUP_LOAD;end
   end
   GROUP_SAVE:begin
    if(group_found)best[group_slot]<=combined_record;
    else if(candidate[49:34]>=MIN_AREA&&candidate[24:16]>=candidate[33:25]+9'd2&&candidate[7:0]>=candidate[15:8]+8'd2)begin
     if(candidate[49:34]>best[0][49:34])begin best[1]<=best[0];best[0]<=candidate;end
     else if(candidate[49:34]>best[1][49:34])best[1]<=candidate;
    end
    state<=GROUP_SORT;
   end
   GROUP_SORT:begin
    if(best[1][49:34]>best[0][49:34])begin best[0]<=best[1];best[1]<=best[0];end
    state<=RETIRE;
   end
   RETIRE:begin
    if(index==15)state<=flush_frame?TRACK_INIT:IDLE;
    else begin index<=index+1'b1;state<=SCAN_CHECK;end
   end
   TRACK_INIT:begin
    assoc_i<=0;assigned<=0;state<=ASSOC_BEGIN;
   end
   ASSOC_BEGIN:begin
    candidate<=best[assoc_i];match_i<=0;match_found<=0;best_cost<=11'h7ff;
    state<=MATCH_DELTA;
   end
   ASSOC_SAVE:begin
    if(!overflow&&candidate[49:34]!=0&&match_found)begin
     linked[match_slot]<=candidate;assigned[match_slot]<=1;best[assoc_i]<=0;
    end
    if(assoc_i)begin track_i<=0;state<=TRACK_LOAD;end
    else begin assoc_i<=1;state<=ASSOC_BEGIN;end
   end
   TRACK_LOAD:begin
    record_a<=linked[track_i];candidate<={16'd1,track_old_bounds};
    pipe_u<=linked[track_i];pipe_v<=raw_track[track_i];state<=TRACK_CLOSE_RAW;
   end
   TRACK_CLOSE_RAW:begin
    track_close_raw<=track_close_result;pipe_v<=jump_record[track_i];state<=TRACK_CLOSE_JUMP;
   end
   TRACK_CLOSE_JUMP:begin
    track_close_jump<=track_close_result;pipe_u<=padded(record_a);pipe_v<=candidate;state<=TRACK_CLOSE_DISPLAY;
   end
   TRACK_CLOSE_DISPLAY:begin
    track_close_display<=track_close_result;track_bounds_q<=counting_bounds(record_a);
    track_smooth_axis<=0;state<=TRACK_SMOOTH_LOAD;
   end
   TRACK_SMOOTH_LOAD:begin
    // One shared operand loader replaces four duplicated state bodies.
    case(track_smooth_axis)
     0:begin track_smooth_n<=pipe_u[33:25];track_smooth_o<=candidate[33:25];end
     1:begin track_smooth_n<=pipe_u[24:16];track_smooth_o<=candidate[24:16];end
     2:begin track_smooth_n<={1'b0,pipe_u[15:8]};track_smooth_o<={1'b0,candidate[15:8]};end
     default:begin track_smooth_n<={1'b0,pipe_u[7:0]};track_smooth_o<={1'b0,candidate[7:0]};end
    endcase
    state<=TRACK_SMOOTH_CALC;
   end
   TRACK_SMOOTH_CALC:begin
    track_smooth_delta<=$signed({1'b0,track_smooth_n})-$signed({1'b0,track_smooth_o});
    track_smooth_sum<={1'b0,track_smooth_n}+{1'b0,track_smooth_o};state<=TRACK_SMOOTH_STORE;
   end
   TRACK_SMOOTH_STORE:begin
    case(track_smooth_axis)
     0:record_new[33:25]<=track_smooth_result;
     1:record_new[24:16]<=track_smooth_result;
     2:record_new[15:8]<=track_smooth_result[7:0];
     default:record_new[7:0]<=track_smooth_result[7:0];
    endcase
    if(track_smooth_axis==3)state<=TRACK_MOTION_LOAD;
    else begin track_smooth_axis<=track_smooth_axis+1'b1;state<=TRACK_SMOOTH_LOAD;end
   end
   TRACK_MOTION_LOAD:begin pipe_v<=motion_anchor[track_i];state<=TRACK_MOTION_SUM;end
   TRACK_MOTION_SUM:begin
    geom_uw<={1'b0,record_a[33:25]}+{1'b0,record_a[24:16]};
    geom_vw<={1'b0,pipe_v[33:25]}+{1'b0,pipe_v[24:16]};
    geom_uh<={2'b0,record_a[15:8]}+{2'b0,record_a[7:0]};
    geom_vh<={2'b0,pipe_v[15:8]}+{2'b0,pipe_v[7:0]};state<=TRACK_MOTION_DELTA;
   end
   TRACK_MOTION_DELTA:begin
    geom_x_span<=$signed({1'b0,geom_uw})-$signed({1'b0,geom_vw});
    geom_y_span<=$signed({1'b0,geom_uh})-$signed({1'b0,geom_vh});state<=TRACK_DECIDE;
   end
   TRACK_DECIDE:begin
    track_has_observation<=!overflow&&record_a[49:34]!=0;
    track_admit<=!track_confirmed[track_i]||track_close_raw||(jump_valid[track_i]&&track_close_jump);
    track_motion<=motion_changes[track_i]>=motion_limit(record_a[49:34])||!motion_x_quiet||!motion_y_quiet;
    state<=TRACK_UPDATE;
   end
   TRACK_UPDATE:begin
    // Tentative tracks need a hit in the very next frame. Confirmed tracks
    // survive the configured hold interval and reject unrelated new candidates.
    work_valid[track_i]<=track_confirmed[track_i]&&age[track_i]<HOLD_FRAMES;
    track_active[track_i]<=track_confirmed[track_i]&&age[track_i]<HOLD_FRAMES;
    work_age[track_i]<=age[track_i]<AGE_LIMIT?age[track_i]+1'b1:age[track_i];
    work[track_i]<=candidate;
    jump_valid[track_i]<=0;
    // A missing/rejected observation breaks consecutive-start confirmation.
    motion_pending[track_i]<=0;
    if(!track_confirmed[track_i])hits[track_i]<=0;
    if(!track_active[track_i]||age[track_i]>=HOLD_FRAMES)moving[track_i]<=0;
    if(track_has_observation)begin
     if(track_admit)begin
      work_valid[track_i]<=track_confirmed[track_i]||hits[track_i]>=`FPGA_MOTION_START_CONFIRM;track_active[track_i]<=1;work_age[track_i]<=0;
      if(hits[track_i]<3)hits[track_i]<=hits[track_i]+1'b1;
      raw_track[track_i]<=record_a;
      motion_bounds[track_i]<=track_bounds_q;
      if(track_motion)begin
       motion_pending[track_i]<=1;still_age[track_i]<=0;
       if(moving[track_i]||motion_pending[track_i])begin
        moving[track_i]<=1;motion_anchor[track_i]<=record_a;anchor_age[track_i]<=0;
       end
      end else begin
       if(still_age[track_i]<6)still_age[track_i]<=still_age[track_i]+1'b1;
       if(still_age[track_i]>=`FPGA_MOTION_STILL_CONFIRM)moving[track_i]<=0;
       // Keep the last accepted center until motion is confirmed. Periodic
       // anchor replacement would erase slow displacement at arbitrary phases.
      end
      work[track_i]<=track_confirmed[track_i]?
       {record_a[49:34],record_new[33:0]}:pipe_u;
      // A stopped box uses the configured display deadband; association stays raw.
      if(track_confirmed[track_i]&&!moving[track_i]&&track_close_display)
       work[track_i]<={record_a[49:34],candidate[33:0]};
     end else begin jump_valid[track_i]<=1;jump_record[track_i]<=record_a;end
    end
    if(track_i)begin track_i<=0;state<=TRACK_NEW_LOAD;end
    else begin track_i<=1;state<=TRACK_LOAD;end
   end
   TRACK_NEW_LOAD:begin
    record_a<=best[track_i];chosen<=track_active[0]?1:0;state<=TRACK_NEW_PAD;
   end
   TRACK_NEW_PAD:begin pipe_u<=padded(record_a);track_bounds_q<=counting_bounds(record_a);state<=TRACK_NEW;end
   TRACK_NEW:begin
    if(!overflow&&record_a[49:34]!=0&&!track_active[chosen])begin
     track_active[chosen]<=1;work_valid[chosen]<=0;work_age[chosen]<=0;
     raw_track[chosen]<=record_a;motion_bounds[chosen]<=track_bounds_q;work[chosen]<=pipe_u;jump_valid[chosen]<=0;
     hits[chosen]<=1;moving[chosen]<=0;motion_pending[chosen]<=0;still_age[chosen]<=0;anchor_age[chosen]<=0;motion_anchor[chosen]<=record_a;
    end
    if(track_i)state<=DEDUP_LOAD;else begin track_i<=1;state<=TRACK_NEW_LOAD;end
   end
   DEDUP_LOAD:begin pipe_u<=raw_track[0];pipe_v<=raw_track[1];state<=DEDUP_DIMS;end
   GROUP_DIMS,DEDUP_DIMS:begin
    geom_uw<={1'b0,pipe_u[24:16]}-{1'b0,pipe_u[33:25]}+10'd1;
    geom_vw<={1'b0,pipe_v[24:16]}-{1'b0,pipe_v[33:25]}+10'd1;
    geom_uh<={2'b0,pipe_u[7:0]}-{2'b0,pipe_u[15:8]}+10'd1;
    geom_vh<={2'b0,pipe_v[7:0]}-{2'b0,pipe_v[15:8]}+10'd1;
    geom_lx<=pipe_u[33:25]>pipe_v[33:25]?pipe_u[33:25]:pipe_v[33:25];
    geom_hx<=pipe_u[24:16]<pipe_v[24:16]?pipe_u[24:16]:pipe_v[24:16];
    geom_ly<=pipe_u[15:8]>pipe_v[15:8]?pipe_u[15:8]:pipe_v[15:8];
    geom_hy<=pipe_u[7:0]<pipe_v[7:0]?pipe_u[7:0]:pipe_v[7:0];
    if(state==DEDUP_DIMS)record_a<=combine(pipe_u,pipe_v);
    state<=(state==GROUP_DIMS)?GROUP_SPAN:DEDUP_SPAN;
   end
   GROUP_SPAN,DEDUP_SPAN:begin
    geom_x_span<={1'b0,geom_hx}-{1'b0,geom_lx}+11'd1;
    geom_y_span<={1'b0,geom_hy}-{1'b0,geom_ly}+11'd1;
    state<=(state==GROUP_SPAN)?GROUP_TEST:DEDUP_RESULT;
   end
   DEDUP_RESULT:begin geometry_similar_q<=geometry_similar;state<=DEDUP_PAD;end
   DEDUP_PAD:begin pipe_u<=padded(record_a);track_bounds_q<=counting_bounds(record_a);state<=DEDUP;end
   DEDUP:begin
    // Evaluate the previous state once, and only commit after registered data
    // and similarity are ready. No geometry-to-wide-write-enable path.
    if(work_valid==2'b11)begin
     if(assigned==2'b11&&!geometry_similar_q)independent_age<=7;
     else if(independent_age!=0)independent_age<=independent_age-1'b1;
     if(geometry_similar_q&&independent_age==0&&assigned!=2'b11&&!overflow)begin
      if(duplicate_age==2)begin
       raw_track[0]<=record_a;motion_bounds[0]<=track_bounds_q;work[0]<=pipe_u;
       track_active[1]<=0;work_valid[1]<=0;jump_valid[1]<=0;duplicate_age<=0;
      end else duplicate_age<=duplicate_age+1'b1;
     end else duplicate_age<=0;
    end else begin duplicate_age<=0;independent_age<=0;end
    state<=PUBLISH;
   end
   PUBLISH:begin
    track_confirmed<=work_valid;
    box_valid<={2'b0,(work_valid&moving)};box_xmin[35:18]<=0;box_xmax[35:18]<=0;
    box_ymin[31:16]<=0;box_ymax[31:16]<=0;
    for(i=0;i<2;i=i+1)begin
     box_xmin[i*9+:9]<=work[i][33:25];box_xmax[i*9+:9]<=work[i][24:16];
     box_ymin[i*8+:8]<=work[i][15:8];box_ymax[i*8+:8]<=work[i][7:0];age[i]<=work_age[i];
    end
    index<=0;state<=CLEAR;
   end
   default:begin state<=CLEAR;index<=0;end
  endcase
 end
endmodule

// Detection-only robust brightness servo and pixel hysteresis. No RGB output.
// Input samples are >=4 clocks apart. Read old bit -> aligned residual -> write
// new bit/output, two registered boundaries. First frame ignores stale RAM bits.
module motion_light_hysteresis #(
 parameter integer W=320,H=180,HIGH=`FPGA_MOTION_HIGH_DEFAULT,LOW=`FPGA_MOTION_LOW_DEFAULT
)(input clk,rst_n,boundary,in_valid,input [8:0] in_x,input [7:0] in_y,
 input [7:0] gray,background,input exclude,
 output reg out_valid,output reg [8:0] out_x,output reg [7:0] out_y,output reg out_bit);
 (* ram_style="bram" *) reg foreground[0:W*H-1];
 reg old_bit,p_valid,p_history,p_exclude,history_ready,complete_frame;
 reg [8:0] px;reg [7:0] py;
 reg signed [9:0] residual;
 reg signed [8:0] light_offset;
 reg [15:0] trusted,positive,negative;
 reg [3:0] coverage;
 wire [15:0] read_addr=in_y*W+in_x,write_addr=py*W+px;
 wire [9:0] magnitude=residual[9] ? -residual : residual;
 wire next_bit=magnitude>((p_history&&old_bit)?LOW:HIGH);
 wire [2:0] covered={2'b0,coverage[0]}+{2'b0,coverage[1]}+{2'b0,coverage[2]}+{2'b0,coverage[3]};
 always @(posedge clk)begin
  if(rst_n&&in_valid)old_bit<=foreground[read_addr];
  if(rst_n&&p_valid)foreground[write_addr]<=next_bit;
 end
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  p_valid<=0;p_history<=0;p_exclude<=0;history_ready<=0;complete_frame<=0;
  px<=0;py<=0;residual<=0;light_offset<=0;trusted<=0;positive<=0;negative<=0;coverage<=0;
  out_valid<=0;out_x<=0;out_y<=0;out_bit<=0;
 end else begin
  p_valid<=in_valid;out_valid<=p_valid;
  if(in_valid)begin
   px<=in_x;py<=in_y;p_history<=history_ready;p_exclude<=exclude;
   residual<=$signed({2'b0,gray})-$signed({2'b0,background})-$signed({light_offset[8],light_offset});
  end
  if(p_valid)begin
   out_x<=px;out_y<=py;out_bit<=next_bit;
   if(px==W-1&&py==H-1)begin history_ready<=1;complete_frame<=1;end
   // Trust only previous-background pixels with small residuals, outside tracks.
   // Large/new foreground differences do not steer the brightness estimate.
   if(!p_exclude&&!(p_history&&old_bit)&&magnitude<=LOW)begin
    trusted<=trusted+1'b1;coverage[{(py>=H/2),(px>=W/2)}]<=1;
    if(residual>`FPGA_MOTION_LIGHT_DEADBAND)positive<=positive+1'b1;
    if(residual< -`FPGA_MOTION_LIGHT_DEADBAND)negative<=negative+1'b1;
   end
  end
  if(boundary)begin
   // Configurable support, deadband and brightness adaptation.
   // If lighting jumps beyond the trust window, hold rather than learn a target.
   if(complete_frame&&trusted>=W*H/`FPGA_MOTION_LIGHT_SUPPORT&&covered>=`FPGA_MOTION_LIGHT_COVERAGE)begin
    if(positive>(trusted>>`FPGA_MOTION_LIGHT_MAJORITY)&&light_offset<`FPGA_MOTION_LIGHT_LIMIT)light_offset<=light_offset+`FPGA_MOTION_LIGHT_STEP;
    else if(negative>(trusted>>`FPGA_MOTION_LIGHT_MAJORITY)&&light_offset> -`FPGA_MOTION_LIGHT_LIMIT)light_offset<=light_offset-`FPGA_MOTION_LIGHT_STEP;
   end
   trusted<=0;positive<=0;negative<=0;coverage<=0;complete_frame<=0;
  end
 end
endmodule

// Centered 3x3 binary window, one token per >=4 clocks, raster order.
// OP=0 majority, OP=1 dilation, OP=2 erosion. Zero exterior padding.
// Tail rows are paced to give the row-serial CCL the same processing budget.
module motion_bit_window #(
 parameter integer W=320,H=180,OP=0,TAIL_GAP=W*10+512,ERAM_ROWS=0
)(
 input clk,rst_n,in_valid,input [8:0] in_x,input [7:0] in_y,input in_bit,
 output reg out_valid,output reg [8:0] out_x,output reg [7:0] out_y,output reg out_bit
);
 wire q1,q2;
 reg p_bit,p_valid;
 reg [8:0] p_x,p_y;
 reg [2:0] col_old,col_last;
 reg right_pending,tail_active;
 reg [8:0] right_y,tail_x;
 // Width follows the loaded value. Out-of-range integer parameters retain
 // the original 16-bit truncation rather than changing their behavior.
 localparam integer TAIL_WAIT_WIDTH=(TAIL_GAP<0 || TAIL_GAP>65535)?16:
                                  ((TAIL_GAP<2)?1:$clog2(TAIL_GAP+1));
 reg [TAIL_WAIT_WIDTH-1:0] tail_wait;
 reg [1:0] pace;
 wire tail_token=tail_active&&tail_wait==0&&pace==0;
 wire accept=in_valid||right_pending||tail_token;
 wire [8:0] ax=in_valid?in_x:(right_pending?W:tail_x);
 wire [8:0] ay=in_valid?{1'b0,in_y}:(right_pending?right_y:H);
 wire abit=in_valid?in_bit:1'b0;
 wire [2:0] col_now={(p_y>=2?q2:1'b0),(p_y>=1?q1:1'b0),p_bit};
 wire [3:0] ones={3'b0,col_old[0]}+{3'b0,col_old[1]}+{3'b0,col_old[2]}+
                 {3'b0,col_last[0]}+{3'b0,col_last[1]}+{3'b0,col_last[2]}+
                 {3'b0,col_now[0]}+{3'b0,col_now[1]}+{3'b0,col_now[2]};
 // Each stage owns its state: morphology histories cannot be shared.
 generate if(ERAM_ROWS) begin : packed_rows
  (* ram_style="bram" *) reg [1:0] rows_mem[0:W-1];
  reg [1:0] row_q,forward_q;
  reg forwarded,padded;
  reg write_pending=1'b0;
  reg [8:0] write_addr;
  reg write_bit;
  wire [1:0] rows=padded?2'b00:(forwarded?forward_q:row_q);
  wire [1:0] write_word={write_bit,rows[1]};
  assign q1=rows[1]; assign q2=rows[0];
  // Delayed physical write, synchronous read, explicit same-address bypass.
  // A pre-reset accepted write is completed once; RAM/read/pending payloads
  // have no reset. This preserves the original persistent-memory semantics.
  always @(posedge clk) begin
   if(write_pending) rows_mem[write_addr]<=write_word;
   write_pending<=rst_n && accept && (ax<W);
   if(rst_n && accept) begin
    write_addr<=ax;write_bit<=abit;padded<=(ax>=W);
    if(ax<W) begin
     row_q<=rows_mem[ax];
     forwarded<=write_pending && (write_addr==ax);
     forward_q<=write_word;
    end
   end
  end
 end else begin : distributed_rows
  (* ram_style="dram" *) reg line1[0:W-1],line2[0:W-1];
  reg q1_local,q2_local;
  assign q1=q1_local;assign q2=q2_local;
 // RAM contents need no reset: top-row masking and raster writes invalidate them.
 always @(posedge clk)if(rst_n&&accept)begin
  if(ax<W)begin
   q1_local<=line1[ax];q2_local<=line2[ax];line1[ax]<=abit;line2[ax]<=line1[ax];
  end else begin q1_local<=0;q2_local<=0;end
 end
 end endgenerate

 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  p_bit<=0;p_valid<=0;p_x<=0;p_y<=0;col_old<=0;col_last<=0;
  right_pending<=0;right_y<=0;tail_active<=0;tail_x<=0;tail_wait<=0;pace<=0;
  out_valid<=0;out_x<=0;out_y<=0;out_bit<=0;
 end else begin
  out_valid<=0;p_valid<=accept;
  if(tail_active)begin
   if(tail_wait!=0)tail_wait<=tail_wait-1'b1;
   else pace<=pace+1'b1;
  end
  if(accept)begin
   p_bit<=abit;p_x<=ax;p_y<=ay;
   if(right_pending)begin
    right_pending<=0;
    if(right_y==H-1)begin tail_active<=1;tail_x<=0;tail_wait<=TAIL_GAP;pace<=0;end
    if(right_y==H)tail_active<=0;
   end else if(ax==W-1)begin right_pending<=1;right_y<=ay;end
   if(tail_token&&!right_pending)tail_x<=tail_x+1'b1;
  end
  if(p_valid)begin
   if(p_x==0)begin col_old<=0;col_last<=col_now;end
   else begin
    col_old<=col_last;col_last<=col_now;
    if(p_y>=1)begin
     out_valid<=1;out_x<=p_x-1'b1;out_y<=p_y-1'b1;
     if(OP==0)out_bit<=ones>=`FPGA_MOTION_VOTE;
     else if(OP==1)out_bit<=|{col_old,col_last,col_now};
     else out_bit<=&{col_old,col_last,col_now};
    end
   end
  end
 end
endmodule


// Detection-only 4x4 box mean, rounded. Full RGB continues on the original path.
// Two registered boundaries from each block's final pixel to the sample token.
module motion_gray_block4 #(
 parameter integer H_ACTIVE=1280,V_ACTIVE=720
)(input clk,rst_n,frame_vsync,in_valid,input [10:0] in_x,input [9:0] in_y,
 input [7:0] in_gray,
 output reg out_valid,output reg [8:0] out_x,output reg [7:0] out_y,
 output reg [7:0] out_gray);
 localparam W=H_ACTIVE/4;
 reg p_valid;reg [10:0] px;reg [9:0] py;reg [7:0] pixel;
 reg [9:0] row_sum;
 (* ram_style="bram" *) reg [11:0] partial[0:W-1];
 reg [11:0] vertical;
 wire [8:0] column=px[10:2];
 wire [11:0] row_total={2'b0,row_sum}+{4'b0,pixel};
 wire [11:0] block_total=(py[1:0]==0)?row_total:vertical+row_total;
 wire [12:0] rounded={1'b0,block_total}+13'd8;
 // Synchronous read at the first pixel, write at the fourth: one RAM port.
 // First block-row overwrites stale contents; RAM needs no reset loop.
 always @(posedge clk)if(rst_n&&!frame_vsync&&p_valid)begin
  if(px[1:0]==0)vertical<=partial[column];
  if(px[1:0]==3)partial[column]<=block_total;
 end
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  p_valid<=0;px<=0;py<=0;pixel<=0;row_sum<=0;
  out_valid<=0;out_x<=0;out_y<=0;out_gray<=0;
 end else if(frame_vsync)begin p_valid<=0;row_sum<=0;out_valid<=0;end
 else begin
  p_valid<=in_valid;
  if(in_valid)begin px<=in_x;py<=in_y;pixel<=in_gray;end
  out_valid<=p_valid&&px[1:0]==3&&py[1:0]==3;
  if(p_valid)begin
   if(px[1:0]==0)row_sum<={2'b0,pixel};
   else row_sum<=row_sum+{2'b0,pixel};
   if(px[1:0]==3&&py[1:0]==3)begin
    out_x<=column;out_y<=py[9:2];out_gray<=rounded[11:4];
   end
  end
 end
endmodule

// Observe successful submitted gain writes; never drives camera AE/AG or I2C.
// Events are held until an HDMI SOF ACK. Additional completions queue an event.
// There is no multi-bit camera->HDMI gain payload.
module motion_gain_change_cdc(
 input I_cam_clk,I_cam_rst_n,I_cam_cfg_done,I_ae_req,I_ae_cfg_done,I_iic_error,
 input [15:0] I_submitted_ag,
 input I_hdmi_clk,I_hdmi_rst_n,I_hdmi_vsync,
 output wire O_restart
);
 reg write_pending,busy_seen,gain_known,queued,request;
 reg [15:0] written_gain,last_gain;
 (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,request_sync;
 reg acknowledge,vs_d;
 wire complete=write_pending&&busy_seen&&I_ae_cfg_done&&!I_iic_error;
 wire changed=complete&&gain_known&&(written_gain!=last_gain);
 assign O_restart=I_hdmi_vsync&&!vs_d&&(request_sync[1]!=acknowledge);
 always @(posedge I_cam_clk or negedge I_cam_rst_n)
 if(!I_cam_rst_n)begin
  write_pending<=0;busy_seen<=0;gain_known<=0;queued<=0;request<=0;
  written_gain<=0;last_gain<=0;ack_sync<=0;
 end else begin
  ack_sync<={ack_sync[0],acknowledge};
  if(I_iic_error)begin write_pending<=0;busy_seen<=0;end
  else if(I_cam_cfg_done&&I_ae_req)begin
   written_gain<=I_submitted_ag;write_pending<=1;busy_seen<=0;
  end else if(write_pending)begin
   if(!I_ae_cfg_done)busy_seen<=1;
   if(complete)begin last_gain<=written_gain;gain_known<=1;write_pending<=0;busy_seen<=0;end
  end
  if(request==ack_sync[1]&&(queued||changed))begin request<=~request;queued<=0;end
  else if(changed)queued<=1;
 end
 always @(posedge I_hdmi_clk or negedge I_hdmi_rst_n)
 if(!I_hdmi_rst_n)begin request_sync<=0;acknowledge<=0;vs_d<=0;end
 else begin
  request_sync<={request_sync[0],request};vs_d<=I_hdmi_vsync;
  if(O_restart)acknowledge<=request_sync[1];
 end
endmodule

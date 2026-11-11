/*************************************************************\
**  Module: dakuang
**  在 720p 视频流上绘制矩形包围框及坐标文字
**  将 320x180 下采样域包围盒坐标映射回 720p 分辨率后绘制矩形框
**  并在框附近叠加显示 TL/BR 坐标数值文字 (5x7 点阵, 2 倍放大)
**  消隐期坐标预计算，像素通路固定两拍，无帧 RAM
**  纯 Verilog-2001，异步复位低有效
\*************************************************************/

module dakuang #(
    parameter integer MULTI_BOX  = 0,
    parameter integer MOTION_COUNT = 4,
    parameter integer H_ACTIVE   = 1280,
    parameter integer V_ACTIVE   = 720,
    parameter integer DS         = 4,
    parameter [23:0] BOX_COLOR   = 24'hff0000,
    parameter integer BOX_LINE   = 2,
    parameter [23:0] TEXT_COLOR  = 24'h00ff00,    // 文字颜色 (亮绿)
    parameter integer TX_GAP     = 4,             // 文字与框的间隙 (像素)
    parameter integer GUARD_FEATURE = 0,
    parameter integer GUARD_POLYGON = 0
)(
    input wire sad_cross_active,sad_cross_running,sad_cross_live,
    input wire [10:0] sad_cross_x,input wire [9:0] sad_cross_y,
    input             clk,
    input             rst_n,
    input             box_en,
    input             object_en,
    input             square_valid, triangle_valid,
    input [8:0]       square_xmin, square_xmax, triangle_xmin, triangle_xmax,
    input [7:0]       square_ymin, square_ymax, triangle_ymin, triangle_ymax,
    input             box_valid,
    input      [8:0]  box_tl_x,
    input      [7:0]  box_tl_y,
    input      [8:0]  box_tr_x,
    input      [7:0]  box_tr_y,
    input      [8:0]  box_bl_x,
    input      [7:0]  box_bl_y,
    input      [8:0]  box_br_x,
    input      [7:0]  box_br_y,
    // Four connected-component motion boxes, flattened as 4 entries.
    // These are used only in motion mode; the legacy single-box ports above
    // remain intact for fallback/debug compatibility.
    input             multi_box_en,
    input      [3:0]  multi_box_valid,
    input      [35:0] multi_box_xmin,
    input      [35:0] multi_box_xmax,
    input      [31:0] multi_box_ymin,
    input      [31:0] multi_box_ymax,
    input             pre_frame_vsync,
    input             pre_frame_href,
    input             pre_frame_de,
    input             pre_frame_user,
    input             pre_frame_last,
    input      [23:0] pre_rgb,
    output reg        post_frame_vsync,
    output reg        post_frame_href,
    output reg        post_frame_de,
    output reg        post_frame_user,
    output reg        post_frame_last,
    output reg [23:0] post_rgb,
    input guard_overlay,
    input [83:0] guard_points,
    input [2:0] guard_selected,
    input guard_intrusion,guard_blink
);

    // ================================================================
    // 本地常量
    // ================================================================
    localparam [10:0] TXT_W = 11'd88;   // Compact 11 characters x 8 pixels
    localparam integer SHARED_COORD_ROM=(MULTI_BOX && MOTION_COUNT==2);
    wire [31:0] shared_coordinate_data;
    wire [8:0] label_rom_address[0:MOTION_COUNT-1];
    localparam [9:0]  TXT_H = 10'd32;    // 文字块高度: 2 行 x 16 像素

    // ================================================================
    // 内部信号声明
    // ================================================================
    reg  [10:0] col_cnt;           // 列计数 0..H_ACTIVE-1 (1279)
    reg  [9:0]  row_cnt;           // 行计数 0..V_ACTIVE-1 (719)

    // 映射后的 720p 域坐标
    reg  [10:0] x0;                // 左边界 = box_tl_x * 4,       最大 1276
    reg  [10:0] x1;                // 右边界 = box_br_x * 4 + 3,   最大 1279
    reg  [9:0]  y0;                // 上边界 = box_tl_y * 4,       最大 716
    reg  [9:0]  y1;                // 下边界 = box_br_y * 4 + 3,   最大 719

    // 边沿判定
    wire        top_edge;
    wire        bottom_edge;
    wire        left_edge;
    wire        right_edge;
    wire        on_h_edge;
    wire        on_v_edge;
    wire        in_box;
    wire        draw;
    wire        multi_draw;
    wire [MOTION_COUNT-1:0] multi_text;
    reg [3:0] mv;
    reg [35:0] mx0,mx1;
    reg [31:0] my0,my1;

    // 文字块位置
    reg  [10:0] text_x;
    reg  [9:0]  text_y;

    // 文字区域内坐标
    wire        in_text;
    wire [10:0] ch_x;
    wire [9:0]  ch_y;
    wire [3:0]  ch_col;
    wire [3:0]  ch_row;
    wire [3:0]  ch_lx;
    wire [3:0]  ch_ly;

    // 点阵坐标
    wire        in_glyph;
    wire [3:0]  lx_off;
    wire [3:0]  ly_off;
    wire [2:0]  px;
    wire [2:0]  py;

    // 字符编码与点阵
    reg  [3:0]  char_code;
    wire [7:0] font_row;
    wire [2:0]  bit_sel;
    wire        pixel_on;
    wire        text_on;

    // Frame-constant display metadata. Updated atomically during blanking.
    reg motion_valid_display, pending_valid, vs_meta_d, meta_busy;
    reg [3:0] meta_step;
    reg [10:0] pending_x0, pending_x1, pending_y0, pending_y1;
    reg [10:0] pending_text_x;
    reg [9:0] pending_text_y;
    reg [10:0] binary_work[0:3];
    reg [15:0] bcd_work[0:3];
    reg [15:0] bcd_display[0:3];
    wire [10:0] source_x0={box_tl_x,2'b00}, source_x1={box_br_x,2'b11};
    wire [9:0] source_y0={box_tl_y,2'b00}, source_y1={box_br_y,2'b11};
    wire x0_thou=bcd_display[0][12], x1_thou=bcd_display[1][12];
    wire [3:0] x0_hund=bcd_display[0][11:8], x0_tens=bcd_display[0][7:4], x0_ones=bcd_display[0][3:0];
    wire [3:0] x1_hund=bcd_display[1][11:8], x1_tens=bcd_display[1][7:4], x1_ones=bcd_display[1][3:0];
    wire [3:0] y0_hund=bcd_display[2][11:8], y0_tens=bcd_display[2][7:4], y0_ones=bcd_display[2][3:0];
    wire [3:0] y1_hund=bcd_display[3][11:8], y1_tens=bcd_display[3][7:4], y1_ones=bcd_display[3][3:0];
    integer meta_i;
    // Twelve requests: main4, label0/4, label1/4. The first request is
    // sampled on the metadata-capture edge. The last response is committed
    // directly on the original twelfth work edge, avoiding a thirteenth.
    generate if(SHARED_COORD_ROM)begin:g_shared_coordinates
        reg [8:0] address;
        always @*begin
            if(vs_meta_d && !pre_frame_vsync && !pre_frame_de)address=source_x0[10:2];
            else case(meta_step)
                0:address=pending_x1[10:2];
                1:address=pending_y0[10:2];
                2:address=pending_y1[10:2];
                3,4,5,6:address=label_rom_address[0];
                default:address=label_rom_address[1];
            endcase
        end
        coordinate_bcd_lookup lookup(.clk(clk),.address(address),.data(shared_coordinate_data));
    end else begin:g_no_shared_coordinates
        assign shared_coordinate_data=32'd0;
    end endgenerate
    function [15:0] bcd_shift;
        input [15:0] digits;
        input next_bit;
        reg [15:0] corrected;
        integer digit;
        begin
            corrected=digits;
            for(digit=0;digit<4;digit=digit+1)
                if(digits[digit*4 +:4]>=4'd5)
                    corrected[digit*4 +:4]=digits[digit*4 +:4]+4'd3;
            bcd_shift={corrected[14:0],next_bit};
        end
    endfunction
    // Detector results settle near VS rising. Capture at VS falling, then use
    // 11 add-3/shift clocks and one atomic commit before active video starts.
    // Never publish partially converted metadata or change it mid active frame.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x0<=0;x1<=0;y0<=0;y1<=0;text_x<=0;text_y<=0;
            pending_x0<=0;pending_x1<=0;pending_y0<=0;pending_y1<=0;
            pending_text_x<=0;pending_text_y<=0;
            motion_valid_display<=0;pending_valid<=0;vs_meta_d<=0;meta_busy<=0;meta_step<=0;
            for(meta_i=0;meta_i<4;meta_i=meta_i+1) begin
                binary_work[meta_i]<=0;bcd_work[meta_i]<=0;bcd_display[meta_i]<=0;
            end
        end else begin
            vs_meta_d<=pre_frame_vsync;
            if(pre_frame_vsync && !vs_meta_d) begin
                motion_valid_display<=0;meta_busy<=0;
            end else if(vs_meta_d && !pre_frame_vsync && !pre_frame_de) begin
                pending_x0<=source_x0;pending_x1<=source_x1;
                pending_y0<={1'b0,source_y0};pending_y1<={1'b0,source_y1};
                pending_text_x<=(source_x1>11'd92)?source_x1-11'd84:11'd4;
                pending_text_y<=(source_y0>10'd36)?source_y0-10'd36:source_y1+10'd4;
                pending_valid<=box_valid && box_en && !object_en;
                if(!SHARED_COORD_ROM)begin
                    binary_work[0]<=source_x0;binary_work[1]<=source_x1;
                    binary_work[2]<={1'b0,source_y0};binary_work[3]<={1'b0,source_y1};
                end
                for(meta_i=0;meta_i<4;meta_i=meta_i+1)bcd_work[meta_i]<=0;
                meta_step<=0;meta_busy<=1;
            end else if(meta_busy) begin
                if(pre_frame_de) begin
                    // Invalid short blanking: suppress this frame, never tear.
                    meta_busy<=0;motion_valid_display<=0;
                end else if(meta_step<11) begin
                    if(SHARED_COORD_ROM)begin
                        case(meta_step)
                            0:bcd_work[0]<=shared_coordinate_data[15:0];
                            1:bcd_work[1]<=shared_coordinate_data[31:16];
                            2:bcd_work[2]<=shared_coordinate_data[15:0];
                            3:bcd_work[3]<=shared_coordinate_data[31:16];
                            default:begin end
                        endcase
                    end else for(meta_i=0;meta_i<4;meta_i=meta_i+1) begin
                        bcd_work[meta_i]<=bcd_shift(bcd_work[meta_i],binary_work[meta_i][10]);
                        binary_work[meta_i]<={binary_work[meta_i][9:0],1'b0};
                    end
                    meta_step<=meta_step+1'b1;
                end else begin
                    x0<=pending_x0;x1<=pending_x1;y0<=pending_y0[9:0];y1<=pending_y1[9:0];
                    text_x<=pending_text_x;text_y<=pending_text_y;
                    for(meta_i=0;meta_i<4;meta_i=meta_i+1)bcd_display[meta_i]<=bcd_work[meta_i];
                    motion_valid_display<=pending_valid;meta_busy<=0;
                end
            end
        end
    end

    // ================================================================
    // 1. 行列计数 (与 zhencha_shibie 相同规则)
    // ================================================================
    // col_cnt: 11bit, 计 0..H_ACTIVE-1 (1279)
    // row_cnt: 10bit, 计 0..V_ACTIVE-1 (719)
    // pre_frame_de 高有效期间递增; vsync 时强制归零
    // ================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            col_cnt <= 11'd0;
        else if (pre_frame_vsync)
            col_cnt <= 11'd0;
        else if (pre_frame_de) begin
            if (col_cnt == H_ACTIVE - 1)
                col_cnt <= 11'd0;
            else
                col_cnt <= col_cnt + 11'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            row_cnt <= 10'd0;
        else if (pre_frame_vsync)
            row_cnt <= 10'd0;
        else if (pre_frame_de && col_cnt == H_ACTIVE - 1) begin
            if (row_cnt == V_ACTIVE - 1)
                row_cnt <= 10'd0;
            else
                row_cnt <= row_cnt + 10'd1;
        end
    end

    // ================================================================
    // 2. 坐标 x4 映射回 720p (移位拼接, 无乘除法)
    // ================================================================
    // box_tl_x/box_br_x: 9bit, 范围 0..319
    // box_tl_y/box_br_y: 8bit, 范围 0..179
    //
    // x0 = box_tl_x << 2 = box_tl_x * 4       (11bit, 最大 1276)
    // x1 = box_br_x << 2 | 3 = box_br_x * 4 + 3 (11bit, 最大 1279)
    // y0 = box_tl_y << 2 = box_tl_y * 4       (10bit, 最大 716)
    // y1 = box_br_y << 2 | 3 = box_br_y * 4 + 3 (10bit, 最大 719)
    //
    // 注: box_tl_x 与 box_bl_x 相同, box_tr_x 与 box_br_x 相同
    //     (上游刻意冗余), 本模块只用 tl_x/br_x/tl_y/br_y 即可
    // ================================================================






    // ================================================================
    // 3. 矩形框判定 (2 像素线宽)
    // ================================================================
    // 上边: row_cnt == y0 || row_cnt == y0 + 1
    // 下边: row_cnt == y1 || row_cnt == y1 - 1
    // 左边: col_cnt == x0 || col_cnt == x0 + 1
    // 右边: col_cnt == x1 || col_cnt == x1 - 1
    //
    // 位宽说明:
    //   row_cnt [9:0] 与 y0/y1 [9:0] 同为 10bit, 直接比较
    //   col_cnt [10:0] 与 x0/x1 [10:0] 同为 11bit, 直接比较
    //   y0+1 最大 717 (10bit 无溢出), y1-1 最小 0
    //   x0+1 最大 1277 (11bit 无溢出), x1-1 最小 0
    // ================================================================

    assign top_edge    = (row_cnt == y0) || (row_cnt == y0 + 10'd1);
    assign bottom_edge = (row_cnt == y1) || (row_cnt == y1 - 10'd1);
    assign left_edge   = (col_cnt == x0) || (col_cnt == x0 + 11'd1);
    assign right_edge  = (col_cnt == x1) || (col_cnt == x1 - 11'd1);

    // 水平边沿: 当前像素同时位于框的列范围和上/下边界行
    assign on_h_edge   = (col_cnt >= x0) && (col_cnt <= x1)
                       && (row_cnt >= y0) && (row_cnt <= y1)
                       && (top_edge || bottom_edge);

    // 垂直边沿: 当前像素同时位于框的行范围和左/右边界列
    assign on_v_edge   = (row_cnt >= y0) && (row_cnt <= y1)
                       && (col_cnt >= x0) && (col_cnt <= x1)
                       && (left_edge || right_edge);

    // 矩形框上任意点: 水平边沿或垂直边沿
    assign in_box      = on_h_edge || on_v_edge;

    // ================================================================
    // 4. 画框条件
    // ================================================================
    // draw = pre_frame_de && box_en && motion_valid_display && in_box
    //   box_en == 0     -> 纯直通, 不画框
    //   box_valid == 0  -> 本帧无目标, 纯直通
    // ================================================================

    assign draw = pre_frame_de & box_en & ~object_en & motion_valid_display & in_box & !MULTI_BOX;

    // Multi-box overlay is intentionally independent of the legacy metadata
    // converter.  The four coordinates are committed once per frame by
    // zhencha_multi_ccl and remain constant during active video, so this
    // combinational edge test cannot tear a box mid-frame.
    motion_multi_overlay #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE),.DS(DS),.BOX_LINE(BOX_LINE),.COUNT(MOTION_COUNT))
    u_motion_multi_overlay(
        .x(col_cnt), .y(row_cnt),
        .enable(pre_frame_de && box_en && !object_en && (MULTI_BOX!=0)),
        .box_valid(mv), .box_xmin(mx0),
        .box_xmax(mx1), .box_ymin(my0),
        .box_ymax(my1), .edge_on(multi_draw));

    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin mv<=0;mx0<=0;mx1<=0;my0<=0;my1<=0;end
        else if(vs_meta_d && !pre_frame_vsync && !pre_frame_de)begin
            mv<=multi_box_en?multi_box_valid:4'b0;
            mx0<=multi_box_xmin;mx1<=multi_box_xmax;
            my0<=multi_box_ymin;my1<=multi_box_ymax;
        end

    // ================================================================
    // 5. 文字块位置计算 (跟随框, 贴边翻转避让)
    // ================================================================
    // 水平方向: 默认文字块右边缘与框右边缘近似对齐
    //   x1 > W+GAP 时: text_x = x1 - W + GAP = x1 - 172
    //   否则:           text_x = GAP (贴左边界)
    // 垂直方向: 默认放在框上方
    //   y0 > H+GAP 时: text_y = y0 - H - GAP (框上方)
    //   否则:           text_y = y1 + GAP     (框下方, 避免超出屏幕顶部)
    //
    // W=176, H=32, TX_GAP=4
    // ================================================================


    // 当 x1 > 180: text_x = x1 - 172 (x1 最小 181, text_x 最小 9, 无下溢)
    // 当 x1 <= 180: text_x = 4


    // 当 y0 > 36:  text_y = y0 - 36 (y0 最小 37, text_y 最小 1, 无下溢)
    // 当 y0 <= 36: text_y = y1 + 4  (y1 最大 719, text_y 最大 723, 10bit 无溢出)

    // ================================================================
    // 5a. 文字区域命中判断
    // ================================================================
    // 先比较再做减法, 避免无符号下溢
    // col_cnt [10:0] vs text_x [10:0], text_x + TXT_W 最大 1283 < 2048
    // row_cnt [9:0]  vs text_y [9:0],  text_y + TXT_H 最大 755 < 1024
    // ================================================================

    assign in_text = (col_cnt >= text_x) && (col_cnt < text_x + TXT_W)
                   && (row_cnt >= text_y) && (row_cnt < text_y + TXT_H);

    // 文字块内相对坐标 (in_text 保证 col_cnt >= text_x, row_cnt >= text_y)
    assign ch_x  = col_cnt - text_x;      // [10:0], 有效范围 0..175
    assign ch_y  = row_cnt - text_y;      // [9:0],  有效范围 0..31

    // 字符索引与字符内局部坐标
    assign ch_col = ch_x[6:3];            // 第几个字符 0..10 (4bit)
    assign ch_row = {3'b000, ch_y[4]};    // 第几行 0 或 1
    assign ch_lx  = {1'b0,ch_x[2:0]};            // 字符内局部 x, 0..15
    assign ch_ly  = ch_y[3:0];            // 字符内局部 y, 0..15

    // ================================================================
    // 5b. 点阵坐标映射 (5x7 点阵, 2 倍放大居中)
    // ================================================================
    // 字符单元 16x16, 点阵放大后 10x14
    // 水平边距: (16-10)/2 = 3, 所以 lx 在 3..12 时点阵有效
    // 垂直边距: (16-14)/2 = 1, 所以 ly 在 1..14 时点阵有效
    // px = (lx - 3) / 2, 范围 0..4
    // py = (ly - 1) / 2, 范围 0..6
    // ================================================================

    assign in_glyph = 1'b1; // Fixed 8x16 font supplies its own margins.

    assign lx_off = ch_lx - 4'd1;         // 0..9
    assign ly_off = ch_ly - 4'd1;         // 0..13
    assign px     = lx_off[2:0];          // >> 1, 0..4
    assign py     = ly_off[3:1];          // >> 1, 0..6

    // ================================================================
    // 6. Decimal digits are precomputed above; no per-pixel multipliers.
    // ================================================================

    // ================================================================
    // 7. 字符选择 (集中处理, 行 0 = TL, 行 1 = BR)
    // ================================================================
    // 字符编码定义:
    //   0..9 = 数字 '0'..'9'
    //   10   = 'T'
    //   11   = 'L'
    //   12   = 'B'
    //   13   = 'R'
    //   14   = ','
    //   15   = ' ' (空格)
    //
    // 行 0: T L _ x0千 x0百 x0十 x0个 , y0百 y0十 y0个
    // 行 1: B R _ x1千 x1百 x1十 x1个 , y1百 y1十 y1个
    // ================================================================

    always @(*) begin
        char_code = 4'd15; // 默认空格
        if (ch_row == 4'd0) begin
            case (ch_col)
                4'd0:    char_code = 4'd10;              // T
                4'd1:    char_code = 4'd11;              // L
                4'd2:    char_code = 4'd15;              // 空格
                4'd3:    char_code = {3'b000, x0_thou};  // x0 千位 (0 或 1)
                4'd4:    char_code = x0_hund;            // x0 百位
                4'd5:    char_code = x0_tens;            // x0 十位
                4'd6:    char_code = x0_ones;            // x0 个位
                4'd7:    char_code = 4'd14;              // 逗号
                4'd8:    char_code = y0_hund;            // y0 百位
                4'd9:    char_code = y0_tens;            // y0 十位
                4'd10:   char_code = y0_ones;            // y0 个位
                default: char_code = 4'd15;
            endcase
        end else begin // ch_row == 1
            case (ch_col)
                4'd0:    char_code = 4'd12;              // B
                4'd1:    char_code = 4'd13;              // R
                4'd2:    char_code = 4'd15;              // 空格
                4'd3:    char_code = {3'b000, x1_thou};  // x1 千位 (0 或 1)
                4'd4:    char_code = x1_hund;            // x1 百位
                4'd5:    char_code = x1_tens;            // x1 十位
                4'd6:    char_code = x1_ones;            // x1 个位
                4'd7:    char_code = 4'd14;              // 逗号
                4'd8:    char_code = y1_hund;            // y1 百位
                4'd9:    char_code = y1_tens;            // y1 十位
                4'd10:   char_code = y1_ones;            // y1 个位
                default: char_code = 4'd15;
            endcase
        end
    end

    // ================================================================
    // 8. 字模点阵查询 (5x7 点阵, 16 个字符编码)
    // ================================================================
    // 字符编码与行号直接输出 5bit；第 7 行与空格仍为全 0。
    // 不增加字模寄存器，也不改变原列选择/有效字形门控。
    // 每行 bit4 = 左, bit0 = 右 (低位在右)
    // ================================================================

    // Direct five-bit row lookup. Same 5x7 bitmap, bit4 on the left.
    // Do not build/select a 35-bit complete glyph on the pixel path.
    wire [7:0] coordinate_ascii;
    assign coordinate_ascii=char_code<10 ? 8'h30+{4'd0,char_code} :
        (char_code==10 ? "T" : char_code==11 ? "L" : char_code==12 ? "B" :
         char_code==13 ? "R" : char_code==14 ? "," : " ");
    hud_font coordinate_font(.character(coordinate_ascii),.row(ch_ly),.bits(font_row));

    // ================================================================
    // 9. 文字像素合成与叠加优先级
    // ================================================================
    // 点阵 bit4 = 左 (px=0), bit0 = 右 (px=4)
    // bit_sel = 4 - px, 将列号映射到位索引
    // text_on: 文字像素有效信号
    //   需要: de 有效 + 框使能 + 框有效 + 文字区域 + 点阵有效区 + 点阵亮点
    // ================================================================

    assign bit_sel  = 3'd4 - px;
    assign pixel_on = font_row[7-ch_lx[2:0]];

    assign text_on  = pre_frame_de & box_en & ~object_en & motion_valid_display & !MULTI_BOX
                    & in_text & in_glyph & pixel_on;

    // ================================================================
    // 10. 输出流水线 (统一延迟 2 拍)
    // ================================================================
    // 关键约束: post_frame_user / post_frame_last 必须与
    // post_frame_de 延迟相同的拍数 (都是 2 拍)。
    // 如果 user/last 与 de 相差哪怕 1 拍, 下游 hdmi_mixer
    // 内部的 S_x 会在每行提前归零, 偏移逐行累积, OSD 位置整体错位。
    //
    // 叠加优先级: 坐标文字 > 框 > 原视频
    // ================================================================


    // Compute label placement once per frame in the label helpers. Bound both
    // labels to the screen. If their rectangles overlap, put the later label
    // immediately below/above the earlier one (not on top of its digits).
    reg [10:0] label_x[0:MOTION_COUNT-1];
    reg [9:0] label_y[0:MOTION_COUNT-1];
    integer label_i,label_j;
    reg [10:0] label_right;
    reg [9:0] label_top,label_bottom;
    always @* begin
        label_right=0;label_top=0;label_bottom=0;
        for(label_i=0;label_i<MOTION_COUNT;label_i=label_i+1) begin
            label_right={multi_box_xmax[label_i*9+:9],2'b11};
            label_top={multi_box_ymin[label_i*8+:8],2'b00};
            label_bottom={multi_box_ymax[label_i*8+:8],2'b11};
            label_x[label_i]=label_right>92?label_right-84:4;
            if(label_x[label_i]>H_ACTIVE-88)label_x[label_i]=H_ACTIVE-88;
            label_y[label_i]=label_top>36?label_top-36:label_bottom+4;
            if(label_y[label_i]>V_ACTIVE-32)label_y[label_i]=V_ACTIVE-32;
            for(label_j=0;label_j<label_i;label_j=label_j+1) begin
                if(multi_box_valid[label_i] && multi_box_valid[label_j] &&
                   label_x[label_i]<label_x[label_j]+88 && label_x[label_j]<label_x[label_i]+88 &&
                   label_y[label_i]<label_y[label_j]+32 && label_y[label_j]<label_y[label_i]+32) begin
                    if(label_y[label_j]+68<=V_ACTIVE)label_y[label_i]=label_y[label_j]+36;
                    else label_y[label_i]=label_y[label_j]-36;
                end
            end
        end
    end
    genvar label_n;
    generate for(label_n=0;label_n<MOTION_COUNT;label_n=label_n+1) begin: coord_labels
        if(MULTI_BOX) begin: active
            motion_coordinate_label #(.EXTERNAL_COORD_ROM(SHARED_COORD_ROM),.ROM_SLOT(label_n)) label(
                .clk(clk),.rst_n(rst_n),.pre_frame_vsync(pre_frame_vsync),.pre_frame_de(pre_frame_de),
                .enable(box_en && !object_en && multi_box_en),
                .box_valid(multi_box_valid[label_n]),
                .xmin(multi_box_xmin[label_n*9+:9]),.xmax(multi_box_xmax[label_n*9+:9]),
                .ymin(multi_box_ymin[label_n*8+:8]),.ymax(multi_box_ymax[label_n*8+:8]),
                .x(col_cnt),.y(row_cnt),.label_x(label_x[label_n]),.label_y(label_y[label_n]),
                .shared_rom_data(shared_coordinate_data),.shared_rom_address(label_rom_address[label_n]),
                .text_on(multi_text[label_n]));
        end else begin: inactive
            assign multi_text[label_n]=1'b0;
            assign label_rom_address[label_n]=9'd0;
        end
    end endgenerate
    wire square_edge, square_text, triangle_edge, triangle_text;
    object_box_overlay #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE),.CIRCLE(1),.TRIANGLE(0),.BOX_LINE(BOX_LINE)) square_overlay (
        .x(col_cnt),.y(row_cnt),.enable(object_en && square_valid && pre_frame_de),
        .xmin(square_xmin),.xmax(square_xmax),.ymin(square_ymin),.ymax(square_ymax),
        .edge_on(square_edge),.text_on(square_text));
    object_box_overlay #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE),.TRIANGLE(1),.BOX_LINE(BOX_LINE)) triangle_overlay (
        .x(col_cnt),.y(row_cnt),.enable(object_en && triangle_valid && pre_frame_de),
        .xmin(triangle_xmin),.xmax(triangle_xmax),.ymin(triangle_ymin),.ymax(triangle_ymax),
        .edge_on(triangle_edge),.text_on(triangle_text));

    // Stage 1 terminates each independent glyph/edge path locally. Stage 2
    // only selects the overlay color. All five controls and RGB travel with
    // the same pixel, including blanking, first/last pixels and mode changes.
    // New ink uses the existing two-stage video path. All coordinates and
    // mode controls are frame-latched in a38_local_control, no payload delay.
    // Fixed 81x81 sight: selection marker, not measured object bounds.
    wire [11:0] sight_x={1'b0,col_cnt}+12'd40-{1'b0,sad_cross_x};
    wire [10:0] sight_y={1'b0,row_cnt}+11'd40-{1'b0,sad_cross_y};
    wire sight_window=sight_x<=80 && sight_y<=80;
    wire sad_bitmap;
    a38_sight_bitmap u_sad_bitmap(.clk(clk),
        .address({sight_y[6:0],sight_x[6:0]}),.q(sad_bitmap));
    // The synchronous bitmap occupies the existing first video stage.
    // This mask rejects wrapped coordinates and unqualified/reset pixels.
    wire sad_ink=sad_cross_active && pre_frame_de && sight_window;
    reg sad_ink_q,sad_running_q,sad_live_q;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin sad_ink_q<=0;sad_running_q<=0;sad_live_q<=0;end
        else begin sad_ink_q<=sad_ink;sad_running_q<=sad_cross_running;sad_live_q<=sad_cross_live;end
    reg [4:0] pixel_ctrl_q;
    reg [23:0] pixel_rgb_q;
    reg square_text_q, triangle_text_q, square_edge_q, triangle_edge_q;
    reg text_on_q, draw_q, guard_q,handle_q;
    reg [23:0] guard_color_q;
    reg guard_intrusion_frame,guard_blink_frame;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin guard_intrusion_frame<=0;guard_blink_frame<=0;end
        else if(pre_frame_user)begin guard_intrusion_frame<=guard_intrusion;guard_blink_frame<=guard_blink;end
    wire guard_active=GUARD_FEATURE ? guard_overlay : 1'b0;
    wire polygon_ink,handle_ink;
    generate if(GUARD_FEATURE && GUARD_POLYGON)begin:g_polygon
        wire raster_fault;
        guard_polygon_raster #(.H_ACTIVE(H_ACTIVE)) raster(
            .clk(clk),.rst_n(rst_n),.vsync(pre_frame_vsync),.de(pre_frame_de),
            .enable(guard_active),.x(col_cnt),.y(row_cnt),.points(guard_points),
            .selected(guard_selected),.edge_on(polygon_ink),.handle_on(handle_ink),.fault(raster_fault));
    end else begin:g_no_polygon
        assign polygon_ink=1'b0;assign handle_ink=1'b0;
    end endgenerate
    reg [MOTION_COUNT-1:0] multi_text_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_ctrl_q<=0; pixel_rgb_q<=0;
            square_text_q<=0; triangle_text_q<=0;
            square_edge_q<=0; triangle_edge_q<=0;
            text_on_q<=0; draw_q<=0; multi_text_q<=0;guard_q<=0;handle_q<=0;guard_color_q<=24'h65dcf0;
        end else begin
            pixel_ctrl_q<={pre_frame_vsync,pre_frame_href,pre_frame_de,pre_frame_user,pre_frame_last};
            pixel_rgb_q<=pre_rgb;
            square_text_q<=square_text; triangle_text_q<=triangle_text;
            square_edge_q<=square_edge; triangle_edge_q<=triangle_edge;
            text_on_q<=text_on; multi_text_q<=multi_text;
            guard_q<=guard_active && GUARD_POLYGON && polygon_ink;
            handle_q<=handle_ink;
            guard_color_q<=sad_cross_active ? (guard_intrusion_frame ? 24'hff0000 : 24'h0000ff) :
                (guard_intrusion_frame ? (guard_blink_frame ? 24'hffb36b : 24'hff655e) : 24'h65dcf0);
            draw_q<=draw | multi_draw;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            post_frame_vsync <= 1'b0;
            post_frame_href  <= 1'b0;
            post_frame_de    <= 1'b0;
            post_frame_user  <= 1'b0;
            post_frame_last  <= 1'b0;
            post_rgb         <= 24'd0;
        end else begin
            {post_frame_vsync,post_frame_href,post_frame_de,post_frame_user,post_frame_last} <= pixel_ctrl_q;
            post_rgb         <= (sad_ink_q && sad_bitmap) ? ((sad_running_q && sad_live_q) ? 24'hff0000 : 24'h0000ff) : handle_q ? 24'hffffff : square_text_q ? 24'hff958b : triangle_text_q ? 24'h75baff :
                               square_edge_q ? 24'hff0000 : triangle_edge_q ? 24'h0080ff :
                               (text_on_q | (|multi_text_q)) ? 24'hdcebf3 :
                               guard_q ? guard_color_q : (draw_q ? BOX_COLOR : pixel_rgb_q);
        end
    end

endmodule


// Per-target coordinate label. Frame-latched BCD, original 5x7 coordinate font.
// The parent registers this helper's result before the final color mux.
module motion_coordinate_label #(
 parameter integer EXTERNAL_COORD_ROM=0,ROM_SLOT=0
)(
 input clk,rst_n,pre_frame_vsync,pre_frame_de,enable,box_valid,
 input [8:0] xmin,xmax, input [7:0] ymin,ymax,
 input [10:0] x,label_x, input [9:0] y,label_y,
 input [31:0] shared_rom_data,output wire [8:0] shared_rom_address,
 output text_on
);
 localparam [10:0] TXT_W=88;
 localparam [9:0] TXT_H=32;
 reg [10:0] x0,x1;reg [9:0] y0,y1;
    reg  [10:0] text_x;
    reg  [9:0]  text_y;

    // 文字区域内坐标
    wire        in_text;
    wire [10:0] ch_x;
    wire [9:0]  ch_y;
    wire [3:0]  ch_col;
    wire [3:0]  ch_row;
    wire [3:0]  ch_lx;
    wire [3:0]  ch_ly;

    // 点阵坐标
    wire        in_glyph;
    wire [3:0]  lx_off;
    wire [3:0]  ly_off;
    wire [2:0]  px;
    wire [2:0]  py;

    // 字符编码与点阵
    reg  [3:0]  char_code;
    wire [7:0] font_row;
    wire [2:0]  bit_sel;
    wire        pixel_on;

    // Digits are a work area only while VS has hidden the entire label.
    // Visible validity still commits on the original twelfth clock.
    reg motion_valid_display, pending_valid, vs_meta_d, meta_busy;
    reg [3:0] meta_step;
    reg [10:0] pending_x0, pending_x1, pending_y0, pending_y1;
    reg [10:0] pending_text_x;
    reg [9:0] pending_text_y;
    reg [15:0] bcd_display[0:3];
    wire [10:0] source_x0={xmin,2'b00}, source_x1={xmax,2'b11};
    wire [9:0] source_y0={ymin,2'b00}, source_y1={ymax,2'b11};
    wire x0_thou=bcd_display[0][12], x1_thou=bcd_display[1][12];
    wire [3:0] x0_hund=bcd_display[0][11:8], x0_tens=bcd_display[0][7:4], x0_ones=bcd_display[0][3:0];
    wire [3:0] x1_hund=bcd_display[1][11:8], x1_tens=bcd_display[1][7:4], x1_ones=bcd_display[1][3:0];
    wire [3:0] y0_hund=bcd_display[2][11:8], y0_tens=bcd_display[2][7:4], y0_ones=bcd_display[2][3:0];
    wire [3:0] y1_hund=bcd_display[3][11:8], y1_tens=bcd_display[3][7:4], y1_ones=bcd_display[3][3:0];
    integer meta_i;
    reg [8:0] coordinate_address;
    wire [31:0] coordinate_bcd_q;
    assign shared_rom_address=coordinate_address;
    always @*begin
        if(EXTERNAL_COORD_ROM)begin
            case(meta_step[1:0])
                3:coordinate_address=pending_x0[10:2];
                0:coordinate_address=pending_x1[10:2];
                1:coordinate_address=pending_y0[10:2];
                default:coordinate_address=pending_y1[10:2];
            endcase
        end else case(meta_step)
            0:coordinate_address=pending_x0[10:2];
            1:coordinate_address=pending_x1[10:2];
            2:coordinate_address=pending_y0[10:2];
            default:coordinate_address=pending_y1[10:2];
        endcase
    end
    generate if(EXTERNAL_COORD_ROM)begin:g_shared_port
        assign coordinate_bcd_q=shared_rom_data;
    end else begin:g_private_port
        coordinate_bcd_lookup lookup(.clk(clk),.address(coordinate_address),.data(coordinate_bcd_q));
    end endgenerate
    // Capture at VS falling. Four serial reads finish inside the original
    // eleven work clocks; visible metadata still commits on clock twelve.
    // Never publish partially converted metadata or change it mid active frame.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x0<=0;x1<=0;y0<=0;y1<=0;text_x<=0;text_y<=0;
            pending_x0<=0;pending_x1<=0;pending_y0<=0;pending_y1<=0;
            pending_text_x<=0;pending_text_y<=0;
            motion_valid_display<=0;pending_valid<=0;vs_meta_d<=0;meta_busy<=0;meta_step<=0;
            for(meta_i=0;meta_i<4;meta_i=meta_i+1) begin
                bcd_display[meta_i]<=0;
            end
        end else begin
            vs_meta_d<=pre_frame_vsync;
            if(pre_frame_vsync && !vs_meta_d) begin
                motion_valid_display<=0;meta_busy<=0;
            end else if(vs_meta_d && !pre_frame_vsync && !pre_frame_de) begin
                pending_x0<=source_x0;pending_x1<=source_x1;
                pending_y0<={1'b0,source_y0};pending_y1<={1'b0,source_y1};
                pending_text_x<=label_x;
                pending_text_y<=label_y;
                pending_valid<=box_valid && enable;
                meta_step<=0;meta_busy<=1;
            end else if(meta_busy) begin
                if(pre_frame_de) begin
                    // Invalid short blanking: suppress this frame, never tear.
                    meta_busy<=0;motion_valid_display<=0;
                end else if(meta_step<11) begin
                    // q contains the request from the preceding work clock.
                    if(EXTERNAL_COORD_ROM)begin
                        case(meta_step)
                            (4+4*ROM_SLOT):bcd_display[0]<=coordinate_bcd_q[15:0];
                            (5+4*ROM_SLOT):bcd_display[1]<=coordinate_bcd_q[31:16];
                            (6+4*ROM_SLOT):bcd_display[2]<=coordinate_bcd_q[15:0];
                            (7+4*ROM_SLOT):bcd_display[3]<=coordinate_bcd_q[31:16];
                            default:begin end
                        endcase
                    end else begin
                    case(meta_step)
                        1:bcd_display[0]<=coordinate_bcd_q[15:0];
                        2:bcd_display[1]<=coordinate_bcd_q[31:16];
                        3:bcd_display[2]<=coordinate_bcd_q[15:0];
                        4:bcd_display[3]<=coordinate_bcd_q[31:16];
                        default:begin end
                    endcase
                    end
                    meta_step<=meta_step+1'b1;
                end else begin
                    x0<=pending_x0;x1<=pending_x1;y0<=pending_y0[9:0];y1<=pending_y1[9:0];
                    text_x<=pending_text_x;text_y<=pending_text_y;
                    if(EXTERNAL_COORD_ROM && ROM_SLOT==1)bcd_display[3]<=coordinate_bcd_q[31:16];
                    motion_valid_display<=pending_valid;meta_busy<=0;
                end
            end
        end
    end

    // Reuse full-range differences for both window and glyph addressing.
    // Keep the old 11/10-bit origin+extent overflow behavior explicitly.
    wire [11:0] text_dx={1'b0,x}-{1'b0,text_x};
    wire [10:0] text_dy={1'b0,y}-{1'b0,text_y};
    assign in_text = text_dx<12'd88 && text_dy<11'd32 &&
                     text_x<11'd1960 && text_y<10'd992;

    assign ch_x = text_dx[10:0];
    assign ch_y = text_dy[9:0];

    // 字符索引与字符内局部坐标
    assign ch_col = ch_x[6:3];            // 第几个字符 0..10 (4bit)
    assign ch_row = {3'b000, ch_y[4]};    // 第几行 0 或 1
    assign ch_lx  = {1'b0,ch_x[2:0]};            // 字符内局部 x, 0..15
    assign ch_ly  = ch_y[3:0];            // 字符内局部 y, 0..15

    // ================================================================
    // 5b. 点阵坐标映射 (5x7 点阵, 2 倍放大居中)
    // ================================================================
    // 字符单元 16x16, 点阵放大后 10x14
    // 水平边距: (16-10)/2 = 3, 所以 lx 在 3..12 时点阵有效
    // 垂直边距: (16-14)/2 = 1, 所以 ly 在 1..14 时点阵有效
    // px = (lx - 3) / 2, 范围 0..4
    // py = (ly - 1) / 2, 范围 0..6
    // ================================================================

    assign in_glyph = 1'b1; // Fixed 8x16 font supplies its own margins.

    assign lx_off = ch_lx - 4'd1;         // 0..9
    assign ly_off = ch_ly - 4'd1;         // 0..13
    assign px     = lx_off[2:0];          // >> 1, 0..4
    assign py     = ly_off[3:1];          // >> 1, 0..6

    // ================================================================
    // 6. Decimal digits are precomputed above; no per-pixel multipliers.
    // ================================================================

    // ================================================================
    // 7. 字符选择 (集中处理, 行 0 = TL, 行 1 = BR)
    // ================================================================
    // 字符编码定义:
    //   0..9 = 数字 '0'..'9'
    //   10   = 'T'
    //   11   = 'L'
    //   12   = 'B'
    //   13   = 'R'
    //   14   = ','
    //   15   = ' ' (空格)
    //
    // 行 0: T L _ x0千 x0百 x0十 x0个 , y0百 y0十 y0个
    // 行 1: B R _ x1千 x1百 x1十 x1个 , y1百 y1十 y1个
    // ================================================================

    always @(*) begin
        char_code = 4'd15; // 默认空格
        if (ch_row == 4'd0) begin
            case (ch_col)
                4'd0:    char_code = 4'd10;              // T
                4'd1:    char_code = 4'd11;              // L
                4'd2:    char_code = 4'd15;              // 空格
                4'd3:    char_code = {3'b000, x0_thou};  // x0 千位 (0 或 1)
                4'd4:    char_code = x0_hund;            // x0 百位
                4'd5:    char_code = x0_tens;            // x0 十位
                4'd6:    char_code = x0_ones;            // x0 个位
                4'd7:    char_code = 4'd14;              // 逗号
                4'd8:    char_code = y0_hund;            // y0 百位
                4'd9:    char_code = y0_tens;            // y0 十位
                4'd10:   char_code = y0_ones;            // y0 个位
                default: char_code = 4'd15;
            endcase
        end else begin // ch_row == 1
            case (ch_col)
                4'd0:    char_code = 4'd12;              // B
                4'd1:    char_code = 4'd13;              // R
                4'd2:    char_code = 4'd15;              // 空格
                4'd3:    char_code = {3'b000, x1_thou};  // x1 千位 (0 或 1)
                4'd4:    char_code = x1_hund;            // x1 百位
                4'd5:    char_code = x1_tens;            // x1 十位
                4'd6:    char_code = x1_ones;            // x1 个位
                4'd7:    char_code = 4'd14;              // 逗号
                4'd8:    char_code = y1_hund;            // y1 百位
                4'd9:    char_code = y1_tens;            // y1 十位
                4'd10:   char_code = y1_ones;            // y1 个位
                default: char_code = 4'd15;
            endcase
        end
    end

    // ================================================================
    // 8. 字模点阵查询 (5x7 点阵, 16 个字符编码)
    // ================================================================
    // 字符编码与行号直接输出 5bit；第 7 行与空格仍为全 0。
    // 不增加字模寄存器，也不改变原列选择/有效字形门控。
    // 每行 bit4 = 左, bit0 = 右 (低位在右)
    // ================================================================

    // Direct five-bit row lookup. Same 5x7 bitmap, bit4 on the left.
    // Do not build/select a 35-bit complete glyph on the pixel path.
    // All16 coordinate glyphs; exact old8x16 rows, no ASCII decode.
    function [7:0] coordinate_glyph_row;
        input [3:0] code,row;
        begin
            case({code,row})
                8'h24,8'h33,8'h36,8'h37:coordinate_glyph_row=8'h04;
                8'h56,8'h57:coordinate_glyph_row=8'h06;
                8'h13,8'h14,8'h15,8'h16,8'h17,8'h18,8'h19,8'h1a,8'h75,8'h97:coordinate_glyph_row=8'h08;
                8'h25,8'h34,8'h4a,8'h74:coordinate_glyph_row=8'h0c;
                8'h27,8'h42,8'h43,8'h62,8'h78,8'h99,8'ha3,8'ha4,8'ha5,8'ha6,8'ha7,8'ha8,8'ha9,8'haa,8'hea,8'heb,8'hec:coordinate_glyph_row=8'h10;
                8'h11,8'h12,8'h26,8'h35,8'h41,8'h61,8'h76,8'h77,8'h98:coordinate_glyph_row=8'h18;
                8'h64:coordinate_glyph_row=8'h20;
                8'h85:coordinate_glyph_row=8'h24;
                8'h45:coordinate_glyph_row=8'h2c;
                8'h28,8'h44,8'h63,8'h79,8'h7a,8'h9a,8'ha2:coordinate_glyph_row=8'h30;
                8'h21,8'h31,8'h3a,8'h6a,8'h91:coordinate_glyph_row=8'h38;
                8'h01,8'h0a,8'h5a,8'h81,8'h86,8'h8a,8'h96:coordinate_glyph_row=8'h3c;
                8'h23,8'h38,8'h67,8'h68,8'h93,8'h94:coordinate_glyph_row=8'h44;
                8'h04,8'h05,8'h06,8'h07,8'h58,8'h88:coordinate_glyph_row=8'h46;
                8'h72,8'h73:coordinate_glyph_row=8'h4c;
                8'h29,8'h52,8'h53:coordinate_glyph_row=8'h60;
                8'h02,8'h09,8'h82:coordinate_glyph_row=8'h64;
                8'h03,8'h08,8'h83,8'h84,8'h87,8'h89:coordinate_glyph_row=8'h66;
                8'h22,8'h32,8'h39,8'h46,8'h47,8'h55,8'h59,8'h66,8'h69,8'h92,8'h95:coordinate_glyph_row=8'h6c;
                8'h48,8'h49,8'h51,8'h54,8'h65,8'h71:coordinate_glyph_row=8'h7c;
                8'h2a:coordinate_glyph_row=8'h7e;
                8'hb1,8'hb2,8'hb3,8'hb4,8'hb5,8'hb6,8'hb7,8'hb8,8'hb9:coordinate_glyph_row=8'hc0;
                8'hc3,8'hc7,8'hc8,8'hd3,8'hd4,8'hda:coordinate_glyph_row=8'hc4;
                8'hd8:coordinate_glyph_row=8'hc8;
                8'hc2,8'hc4,8'hc6,8'hc9,8'hd2,8'hd5,8'hd9:coordinate_glyph_row=8'hcc;
                8'hd7:coordinate_glyph_row=8'hd8;
                8'hc1,8'hc5,8'hca,8'hd1,8'hd6:coordinate_glyph_row=8'hf8;
                8'ha1,8'hba:coordinate_glyph_row=8'hfe;
                default:coordinate_glyph_row=8'h00;
            endcase
        end
    endfunction
    assign font_row=coordinate_glyph_row(char_code,ch_ly);

    // ================================================================
    // 9. 文字像素合成与叠加优先级
    // ================================================================
    // 点阵 bit4 = 左 (px=0), bit0 = 右 (px=4)
    // bit_sel = 4 - px, 将列号映射到位索引
    // text_on: 文字像素有效信号
    //   需要: de 有效 + 框使能 + 框有效 + 文字区域 + 点阵有效区 + 点阵亮点
    // ================================================================

    assign bit_sel  = 3'd4 - px;
    assign pixel_on = font_row[7-ch_lx[2:0]];

    assign text_on  = pre_frame_de & enable & motion_valid_display
                    & in_text & in_glyph & pixel_on;


endmodule
// Four independent rectangle edge tests for the 320x180 motion domain.
// A candidate is rendered only when its frame-latched valid bit is set.
module motion_multi_overlay #(
    parameter integer H_ACTIVE=1280, V_ACTIVE=720, DS=4, BOX_LINE=2, COUNT=4
)(
    input [10:0] x, input [9:0] y, input enable,
    input [3:0] box_valid,
    input [35:0] box_xmin, box_xmax,
    input [31:0] box_ymin, box_ymax,
    output reg edge_on
);
    integer n;
    reg [10:0] x0,x1;
    reg [9:0] y0,y1;
    always @* begin
        edge_on = 1'b0;
        x0=0;x1=0;y0=0;y1=0;
        if (enable) begin
            for (n=0; n<COUNT; n=n+1) begin
                x0 = {box_xmin[n*9 +: 9],2'b00};
                x1 = {box_xmax[n*9 +: 9],2'b11};
                y0 = {box_ymin[n*8 +: 8],2'b00};
                y1 = {box_ymax[n*8 +: 8],2'b11};
                // Each sampled cell expands to four pixels. For a two-pixel
                // border, bit 1 selects the low/high half of the edge cell;
                // no full-resolution subtraction is needed.
                if (BOX_LINE == 2) begin
                    if (box_valid[n] &&
                        x[10:2]>=box_xmin[n*9 +: 9] && x[10:2]<=box_xmax[n*9 +: 9] &&
                        y[9:2]>=box_ymin[n*8 +: 8] && y[9:2]<=box_ymax[n*8 +: 8] &&
                        ((x[10:2]==box_xmin[n*9 +: 9] && !x[1]) ||
                         (x[10:2]==box_xmax[n*9 +: 9] &&  x[1]) ||
                         (y[9:2]==box_ymin[n*8 +: 8] && !y[1]) ||
                         (y[9:2]==box_ymax[n*8 +: 8] &&  y[1])))
                        edge_on = 1'b1;
                end else if (box_valid[n] && x>=x0 && x<=x1 && y>=y0 && y<=y1 &&
                    ((x-x0)<BOX_LINE || (x1-x)<BOX_LINE ||
                     (y-y0)<BOX_LINE || (y1-y)<BOX_LINE))
                    edge_on = 1'b1;
            end
        end
    end
endmodule

// Combinational overlay uses the SAME coordinates as the motion overlay.
// All names and borders share dakuang's single output register.
module object_box_overlay #(
    parameter integer H_ACTIVE=1280,V_ACTIVE=720,TRIANGLE=0,CIRCLE=0,BOX_LINE=2
)(
    input [10:0] x, input [9:0] y, input enable,
    input [8:0] xmin,xmax, input [7:0] ymin,ymax,
    output edge_on,text_on
);
    localparam integer NAME_WIDTH=TRIANGLE?72:80;
    // Recognition coordinates are sampled at 4-pixel intervals. Expand each
    // coordinate cell back to 4x4 display pixels for the 1280x720 overlay.
    wire [10:0] x0={xmin,2'b00},x1={xmax,2'b11};
    wire [9:0] y0={ymin,2'b00},y1={ymax,2'b11};
    wire inside_box=x>=x0 && x<=x1 && y>=y0 && y<=y1;
    generate
        if (BOX_LINE == 2) begin : g_two_pixel_border
            assign edge_on=enable &&
                x[10:2]>=xmin && x[10:2]<=xmax && y[9:2]>=ymin && y[9:2]<=ymax &&
                ((x[10:2]==xmin && !x[1]) || (x[10:2]==xmax && x[1]) ||
                 (y[9:2]==ymin && !y[1]) || (y[9:2]==ymax && y[1]));
        end else begin : g_other_border_width
            assign edge_on=enable && inside_box &&
                ((x-x0)<BOX_LINE || (x1-x)<BOX_LINE || (y-y0)<BOX_LINE || (y1-y)<BOX_LINE);
        end
    endgenerate
    wire [10:0] tx=(x0>H_ACTIVE-NAME_WIDTH)?H_ACTIVE-NAME_WIDTH:x0;
    wire [9:0] ty=(y0>=20)?y0-10'd20:
                  (({1'b0,y1}+11'd20<V_ACTIVE)?y1+10'd4:V_ACTIVE-16);
    wire [10:0] dx=x-tx;
    wire [9:0] dy=y-ty;
    reg [7:0] letter;
    wire [7:0] bits;
    always @* begin
        letter=8'h20;
        if(CIRCLE) begin
            case(dx[6:3])
                0:letter="R";1:letter="E";2:letter="D";4:letter="C";5:letter="I";
                6:letter="R";7:letter="C";8:letter="L";9:letter="E";default:letter=" ";
            endcase
        end else if(TRIANGLE) begin
            // Historical parameter aliases the second (BLUE RECT) class.
            case(dx[6:3])
                0:letter="B";1:letter="L";2:letter="U";3:letter="E";
                5:letter="R";6:letter="E";7:letter="C";8:letter="T";
                default:letter=" ";
            endcase
        end else begin
            case(dx[6:3])
                0:letter="S";1:letter="Q";2:letter="U";3:letter="A";4:letter="R";5:letter="E";default:letter=" ";
            endcase
        end
    end
    hud_font font(.character(letter),.row(dy[3:0]),.bits(bits));
    generate if(H_ACTIVE==1280 && V_ACTIVE==720)begin:g_720p_name_window
        // tx<=1200, ty<=1000: a wrapped negative delta is never <80/112
        // or <16, respectively. Thus the original lower bounds are redundant.
        assign text_on=enable && dx<NAME_WIDTH && dy<16 && bits[7-dx[2:0]];
    end else begin:g_generic_name_window
        assign text_on=enable && x>=tx && dx<NAME_WIDTH && y>=ty && dy<16 && bits[7-dx[2:0]];
    end endgenerate
endmodule

// One synchronous 512x32 ROM. Both inclusive DS4 edges share one address.
// No data reset: the per-consumer metadata transaction guards the output.
module coordinate_bcd_lookup(input wire clk,input wire[8:0]address,output reg[31:0]data);
    function [15:0]cell_bcd;
        input integer value;
        begin cell_bcd[15:12]=(value/1000)%10;cell_bcd[11:8]=(value/100)%10;
            cell_bcd[7:4]=(value/10)%10;cell_bcd[3:0]=value%10;end
    endfunction
    (* ram_style="bram" *) reg[31:0]coordinate_bcd_rom[0:511];
    integer n;
    initial for(n=0;n<512;n=n+1)coordinate_bcd_rom[n]={cell_bcd(n*4+3),cell_bcd(n*4)};
    always @(posedge clk)data<=coordinate_bcd_rom[address];
endmodule

// Full original 81x81 pattern, padded to a direct 14-bit XY address.
// One synchronous ERAM target; no external initialization/source dependency.
module a38_sight_bitmap(input wire clk,input wire [13:0] address,output reg q);
    (* ram_style="bram" *) reg [0:0] bitmap[0:16383];
    integer bitmap_index;
    function sight_cell;
        input integer index;
        integer x,y;reg arm,corner,tick;
        begin
            x=index%128;y=index/128;
            arm=((y==39 || y==40) && ((x>=12 && x<=33) || (x>=47 && x<=68))) ||
                ((x==39 || x==40) && ((y>=12 && y<=33) || (y>=47 && y<=68)));
            corner=((x<=1 || x>=79) && (y<=12 || y>=68)) ||
                   ((y<=1 || y>=79) && (x<=12 || x>=68));
            tick=((x==20 || x==60) && y>=36 && y<=44) ||
                 ((y==20 || y==60) && x>=36 && x<=44);
            sight_cell=x<=80 && y<=80 && (arm || corner || tick || (x==40 && y==40));
        end
    endfunction
    initial for(bitmap_index=0;bitmap_index<16384;bitmap_index=bitmap_index+1)bitmap[bitmap_index]=sight_cell(bitmap_index);
    always @(posedge clk)q<=bitmap[address];
endmodule

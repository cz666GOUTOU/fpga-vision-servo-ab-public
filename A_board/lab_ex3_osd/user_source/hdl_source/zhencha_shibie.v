`include "fpga_motion_example_config.vh"
/*************************************************************\
**  Module: zhencha_shibie
**  720p 帧差法运动检测 —— 灰度化 + 4x4 下采样 + 帧差 + 包围盒
**  纯 Verilog-2001，异步复位低有效
\*************************************************************/

module zhencha_shibie #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer DS       = 4,
    parameter [7:0]   THRESH   = `FPGA_MOTION_LEGACY_DIFF,
    parameter integer MIN_AREA = `FPGA_MOTION_LEGACY_AREA
)(
    input             clk,
    input             rst_n,
    input             detect_en,
    input             pre_frame_vsync,
    input             pre_frame_de,
    input      [23:0] pre_rgb,
    output reg        box_valid,
    output reg [8:0]  box_tl_x,
    output reg [7:0]  box_tl_y,
    output reg [8:0]  box_tr_x,
    output reg [7:0]  box_tr_y,
    output reg [8:0]  box_bl_x,
    output reg [7:0]  box_bl_y,
    output reg [8:0]  box_br_x,
    output reg [7:0]  box_br_y
);

    // ================================================================
    // 内部信号声明
    // ================================================================
    reg  [10:0] col_cnt;          // 列计数 0 .. H_ACTIVE-1 (1279)
    reg  [9:0]  row_cnt;          // 行计数 0 .. V_ACTIVE-1 (719)

    wire [7:0]  gray_r;           // R 通道
    wire [7:0]  gray_g;           // G 通道
    wire [7:0]  gray_b;           // B 通道
    wire [17:0] gray_sum;         // 加权和 (最大 255*256 = 65280, 18bit 足够)
    wire [7:0]  gray_now;         // 当前像素灰度值

    wire        sample_en;        // 4x4 下采样使能脉冲
    wire [8:0]  xd;               // 下采样 x 坐标 0..319 (9bit)
    wire [7:0]  yd;               // 下采样 y 坐标 0..179 (8bit)
    wire [15:0] ram_addr;         // RAM 读/写地址 (yd*320 + xd)

    wire [7:0]  ram_dout;         // RAM Port A 读数据 (doa)

    // ================================================================
    // 读延迟 1 拍对齐信号 (最关键)
    // ================================================================
    // IP RAM 配置: REGMODE=NOREG (同步读), WRITEMODE=READBEFOREWRITE
    // 时序关系:
    //   时钟 N   : addra 有效, wea=1 → RAM 锁存地址
    //   时钟 N+1 : doa 输出地址处的旧值 (读优先, 写前的值)
    // 因此必须把 sample_en / gray_now / xd / yd 各打 1 拍,
    // 使其与 N+1 拍出现的 ram_dout 在同一时钟沿对齐, 供帧差比较使用。
    // ================================================================
    reg         sample_en_d;      // sample_en 延迟 1 拍
    reg  [7:0]  gray_now_d;       // gray_now  延迟 1 拍
    reg  [8:0]  xd_d;             // xd        延迟 1 拍
    reg  [7:0]  yd_d;             // yd        延迟 1 拍

    reg         vsync_d;          // pre_frame_vsync 延迟 1 拍
    wire        vsync_rise;       // vsync 上升沿脉冲

    reg         frame_valid;      // 首帧保护标志: 首帧全部写入 RAM 后才允许比较

    wire [7:0]  diff;             // 帧差绝对值
    wire        motion;           // 运动像素标志

    reg  [8:0]  x_min;            // 包围盒 x 最小值 (9bit, 0..319)
    reg  [8:0]  x_max;            // 包围盒 x 最大值
    reg  [7:0]  y_min;            // 包围盒 y 最小值 (8bit, 0..179)
    reg  [7:0]  y_max;            // 包围盒 y 最大值
    reg  [17:0] motion_cnt;       // 运动像素计数 (最大 320*180=57600, 18bit)

    // ================================================================
    // 1. 位置计数 (col_cnt / row_cnt)
    // ================================================================
    // col_cnt: 11bit, 计 0 .. H_ACTIVE-1 (1279)
    // row_cnt: 10bit, 计 0 .. V_ACTIVE-1 (719)
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
    // 2. 灰度计算 (组合逻辑)
    // ================================================================
    // gray = (R*77 + G*150 + B*29) >> 8
    // 系数和: 77 + 150 + 29 = 256, 右移 8 位即除以 256, 无需除法器
    // 最大中间值: 255*77 + 255*150 + 255*29 = 255*256 = 65280 (17bit)
    // ================================================================
    assign gray_r  = pre_rgb[23:16];
    assign gray_g  = pre_rgb[15:8];
    assign gray_b  = pre_rgb[7:0];

    assign gray_sum = {7'd0, gray_r} * 8'd77
                    + {7'd0, gray_g} * 8'd150
                    + {7'd0, gray_b} * 8'd29;
    assign gray_now = gray_sum[15:8];   // >> 8, 取高 8 位

    // ================================================================
    // 3. 4x4 下采样 (抽取每 4x4 块左上角 1 个像素)
    // ================================================================
    // sample_en: 当列、行计数均为 4 的整数倍时产生单周期脉冲
    // xd = col_cnt / 4, 9bit, 范围 0..319
    // yd = row_cnt / 4, 8bit, 范围 0..179
    // 下采样后图像尺寸: 320 x 180 = 57600 像素
    // ================================================================
    assign sample_en = pre_frame_de
                     & (col_cnt[1:0] == 2'b00)
                     & (row_cnt[1:0] == 2'b00);

    assign xd = col_cnt[10:2];    // col_cnt / 4 (取高位)
    assign yd = row_cnt[9:2];     // row_cnt / 4 (取高位)

    // ================================================================
    // 4. RAM 地址计算 (yd * 320 + xd, 禁止乘法/除法)
    // ================================================================
    // yd * 320 = yd * (256 + 64) = (yd << 8) + (yd << 6)
    // 用拼接实现左移, 所有操作数扩展到 16bit 后相加:
    //   {2'b00, yd, 8'b0}  = yd << 8  (最大 179*256 = 45824)
    //   {4'b0,  yd, 6'b0}  = yd << 6  (最大 179*64  = 11456)
    //   {7'b0,  xd}        = xd       (最大 319)
    // 合计最大: 45824 + 11456 + 319 = 57599 < 65536 (16bit)
    // ================================================================
    assign ram_addr = {2'b00, yd, 8'h00}
                    + {4'h0,  yd, 6'h00}
                    + {7'h00, xd};

    // ================================================================
    // 5. RAM 接口与 IP 例化
    // ================================================================
    // 仅使用 Port A: 同拍读旧值 + 写新值
    //   addra = ram_addr (sample_en 时有效地址, 其余周期地址漂移但 wea=0 不影响)
    //   dia   = gray_now (当前灰度, 写入供下一帧比较)
    //   wea   = sample_en (采样时写, 其余周期读但不写)
    // Port B 全部关闭 (ceb=0 禁止)
    // ================================================================
    zhencha U_zhencha (
        // Port A - 读/写端口
        .doa    (ram_dout),
        .dia    (gray_now),
        .addra  (ram_addr),
        .wea    (sample_en),
        .clka   (clk),
        // Port B - 显式关闭
        .dob    (),
        .addrb  (16'd0),
        .ceb    (1'b0),
        .dib    (8'd0),
        .web    (1'b0)
    );

    // ================================================================
    // 6. 读延迟 1 拍对齐 (与 ram_dout 同步)
    // ================================================================
    // RAM 读时序:
    //   时钟 N   : addra 被锁存, RAM 内部开始读取
    //   时钟 N+1 : doa 输出地址 N 处的旧值 (READBEFOREWRITE + NOREG)
    // 因此 sample_en / gray_now / xd / yd 必须各延迟 1 拍,
    // 在时钟 N+1 与 doa 同时有效, 才能做帧差比较。
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_en_d <= 1'b0;
            gray_now_d  <= 8'd0;
            xd_d        <= 9'd0;
            yd_d        <= 8'd0;
        end else begin
            sample_en_d <= sample_en;
            gray_now_d  <= gray_now;
            xd_d        <= xd;
            yd_d        <= yd;
        end
    end

    // ================================================================
    // 7. 首帧保护 (vsync 上升沿检测 + frame_valid)
    // ================================================================
    // vsync_d: pre_frame_vsync 打 1 拍
    // vsync_rise: 上升沿脉冲, 标记帧边界
    // frame_valid: 复位为 0; 第一个 vsync_rise 时置 1
    //   此时首帧所有下采样像素已全部写入 RAM, 后续帧才开始比较
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vsync_d <= 1'b0;
        else
            vsync_d <= pre_frame_vsync;
    end

    assign vsync_rise = pre_frame_vsync & ~vsync_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_valid <= 1'b0;
        else if (vsync_rise)
            frame_valid <= 1'b1;
    end

    // ================================================================
    // 8. 帧差计算与运动检测
    // ================================================================
    // diff = |gray_now_d - ram_dout| (取绝对值)
    // motion = 采样有效 && 帧有效 && 差值超过阈值
    // frame_valid==0 期间 (首帧): 只写 RAM 不比较, motion 恒为 0
    // ================================================================
    assign diff = (gray_now_d > ram_dout) ? (gray_now_d - ram_dout)
                                          : (ram_dout - gray_now_d);

    // RAM continues to receive the current frame while detection is disabled.
    // Therefore re-enabling compares against the immediately preceding frame,
    // rather than against stale image data.
    assign motion = sample_en_d & frame_valid & detect_en & (diff > THRESH);

    // ================================================================
    // 9. 包围盒累积 (motion 为高时更新极值)
    // ================================================================
    // x_min/x_max: 9bit, 范围 0..319
    // y_min/y_max: 8bit, 范围 0..179
    // motion_cnt: 运动像素计数, 用于判断是否有足够运动
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_min      <= 9'd319;
            x_max      <= 9'd0;
            y_min      <= 8'd179;
            y_max      <= 8'd0;
            motion_cnt <= 18'd0;
        end else if (!detect_en || vsync_rise) begin
            // 帧末重置 (锁存在下方 always 块完成, 非阻塞保证锁存用旧值)
            x_min      <= 9'd319;
            x_max      <= 9'd0;
            y_min      <= 8'd179;
            y_max      <= 8'd0;
            motion_cnt <= 18'd0;
        end else if (motion) begin
            // 更新 x 最小值
            if (xd_d < x_min)
                x_min <= xd_d;
            // 更新 x 最大值
            if (xd_d > x_max)
                x_max <= xd_d;
            // 更新 y 最小值
            if (yd_d < y_min)
                y_min <= yd_d;
            // 更新 y 最大值
            if (yd_d > y_max)
                y_max <= yd_d;
            // 运动像素计数递增
            motion_cnt <= motion_cnt + 18'd1;
        end
    end

    // ================================================================
    // 10. 帧末锁存 (vsync_rise 同拍, 先锁存后重置)
    // ================================================================
    // 非阻塞赋值保证: 锁存使用的是本拍旧值 (累积了一帧的结果),
    // 重置操作 (x_min<=319 等) 在另一 always 块同时发生,
    // 两个块的非阻塞赋值互不干扰, 锁存天然先于重置生效。
    // box_valid: motion_cnt >= MIN_AREA 时有效, 否则无效
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            box_valid <= 1'b0;
            box_tl_x  <= 9'd0;
            box_tl_y  <= 8'd0;
            box_tr_x  <= 9'd0;
            box_tr_y  <= 8'd0;
            box_bl_x  <= 9'd0;
            box_bl_y  <= 8'd0;
            box_br_x  <= 9'd0;
            box_br_y  <= 8'd0;
        end else if (!detect_en) begin
            box_valid <= 1'b0;
            box_tl_x  <= 9'd0;
            box_tl_y  <= 8'd0;
            box_tr_x  <= 9'd0;
            box_tr_y  <= 8'd0;
            box_bl_x  <= 9'd0;
            box_bl_y  <= 8'd0;
            box_br_x  <= 9'd0;
            box_br_y  <= 8'd0;
        end else if (vsync_rise) begin
            // 锁存: 将本帧包围盒结果输出
            box_valid <= (motion_cnt >= MIN_AREA) ? 1'b1 : 1'b0;
            box_tl_x  <= x_min;     // 左上角 x
            box_tl_y  <= y_min;     // 左上角 y
            box_tr_x  <= x_max;     // 右上角 x
            box_tr_y  <= y_min;     // 右上角 y
            box_bl_x  <= x_min;     // 左下角 x
            box_bl_y  <= y_max;     // 左下角 y
            box_br_x  <= x_max;     // 右下角 x
            box_br_y  <= y_max;     // 右下角 y
        end
    end

endmodule

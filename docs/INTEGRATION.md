# 双板系统集成说明

## 工程入口

| 板卡 | 工程 | 顶层 |
|---|---|---|
| A 板 | `A_board/lab_ex3_osd/td_project/camera_to_dsi_display.al` | `design_top_wrapper` |
| B 板 | `B_board/GM6020_test/GM6020.al` | `top` |
| B 板备用入口 | `B_board/GM6020_test/GM6020_route_fixed.al` | `top` |

使用 Tang Dynasty 打开对应 `.al`，保留目录结构和相对路径。按[参数配置](CONFIGURATION.md)设置 include 路径和应用参数，然后核对工程登记、IP、引脚与时序约束。B 板两个入口的约束登记不同，选择前检查 `timing.sdc` 是否确实参与当前流程。

## A 板：视觉感知与显示

`A_board/lab_ex3_osd/user_source/hdl_source/` 按采集、ISP、视频处理、显示、通信和存档组织。摄像头配置位于 `uics500_cfg/`，图像处理与显示入口包括 `vision.v`、`dakuang.v` 和 `hdmi_mixer.v`，网络接口集中于 `target_eth_udp/`。

颜色形状和运动检测的源码入口如下：

| 文件 | 输入与主要职责 |
|---|---|
| `yanseshibie.v` | RGB888、帧同步和像素有效；颜色证据、空间筛选、形状资格、中心与包围框 |
| `color_ccl_pipeline.v` | 网格命中、行末和帧边界；游程/组件统计、候选筛选及确认 |
| `color_control_detect.v` | RGB96 四像素拍及 USER/LAST；帧末控制结果、帧身份和跨域显示记录 |
| `zhencha_multi_ccl.v` | RGB888、帧边界和 gain_change；背景差分、空间滤波、连通域和双目标结果 |
| `zhencha_shibie.v` | RGB888 流；独立的单目标差分与包围框模块 |

`mode38_local/` 包含 `a38_local_control`、`a38_sad16_capture`、`a38_sad16_core` 和 DSP 加减包装。该链路负责指令配置、图像与模板采集、SAD 搜索、结果发布、模板学习、锚点恢复和持久化交互；配套 `sd_photo_store.v` 中的模板管理及 `guard_photo_capture.v` 中的邮箱承担跨模块事务。

接口索引位于 `interfaces/A_board/`。历史命名中可能包含 `green`、`triangle` 等名称；当前颜色路径第二类为蓝色目标，具体形状资格取决于调用端的 `SHAPE` 配置。

### 颜色识别与控制结果

`yanseshibie.v` 使用 `include` 引入 `color_ccl_pipeline.v`。将所在目录加入 include 搜索路径，按工具的编译单元规则组织源文件；不要在重复预处理的单元里再次定义同名组件。

像素观察支持逐像素与四像素拍的使用场景。`color_control_detect` 观察四个 RGB888 像素组成的 RGB96，最高 24 位为第一像素；`USER` 和 `LAST` 的帧/行资格应与输入格式一致。有效完整帧在帧末发布结果，供控制发送和显示侧分别消费。

`color_shared_display` 与 `color_control_result_cdc` 使用 `target_eth_udp/target_async_fifo.v`，前者还使用 `guard_photo_capture.v` 中的 `photo_mailbox`。按实际深度和时钟配置 FIFO，复位与 Gray 总线约束随最终工程维护。显示结果需要核对帧身份和缓冲槽，不能只将最新坐标直接叠到任意显示帧。

### 运动检测与 RAM

`zhencha_multi_ccl.v` 默认路径按 4×4 灰度块工作，外部包围框总线保留四槽宽度，当前实现最多使用其中两个有效槽。差分、去噪、连通域和关联条件由该模块参数及源码规定。

差分、背景、关联和显示平滑的应用配置位于同目录 `fpga_motion_example_config.vh`，同时覆盖模块默认和顶层参数入口。先配置图像尺寸、工作网格和 RAM，再根据输入噪声与目标尺度调节这些应用参数。

运动模块使用名为 `zhencha` 的背景 RAM 包装接口。720p 参考配置为两端口各 8 位数据、16 位地址、57,600 深度，使用 `clka` 时钟，输出不附加寄存器，写模式为读旧值（`READBEFOREWRITE`）。应按所用 IP 的实际同步读拍、端口使能和读写冲突语义配置；仅有相同端口名不足以保证背景采样对齐。数组形式的行缓存与统计 RAM 也需检查实际工具推断。

`gain_change` 是明确的帧边界事件输入；不使用时应显式接入同步的常量低电平。改变增益后的稳定等待、背景准备、`result_ready` 与 `result_fresh` 需要由上层按语义消费，不能将准备期间旧坐标当作新检测。

## B 板：通信与执行接口

`B_board/GM6020_test/user_source/` 包括基础 PID、GM6020 模型与位置控制、视觉几何及非线性控制、CAN、Ethernet、PWM、底盘解算和运算辅助模块。`top.v` 集成启动回零、双轴跟踪、丢失搜索、回正、视距、底盘和语音流程。

`vision_geometry_map.v` 组织定点多项式、导数与边界延伸；`vision_nonlinear_ctrl.v` 结合坐标新鲜度、反馈、预测、几何映射和命令提交；`GM6020_id2_model_ctrl.v` 包含单轴和双轴包装，按不同工作档位管理模型与输出。应用系数从同目录 `fpga_b_example_config.vh` 取得。

### 基础 PID 组织

- `pid_ctrl.v` 接收有符号目标和测量，支持内部节拍或外部 `sample_valid`，包含 PID、可选前馈、积分及输出限制。系数必须包含所选采样周期和物理量单位。
- `vision_axis_pid.v` 对每个被接受的坐标采样计算控制，使用 Q8 系数，包含像素死区、积分约束、测量微分和低通滤波；输出单位由参数与下游映射确定。
- `vision_xy_pid.v` 实例化两个独立单轴模块，结合目标有效、通信超时、零坐标哨兵和画面范围管理跟踪资格。单独使能一轴时应消费对应轴的有效信号，不能只等待双轴共同有效。

这些模块需要集成者核对方向、目标值、采样周期、限幅和执行机构量程；CAN 总线指令格式与 PID 输出物理单位分开定义。

`top.v` 还包含以下接口模块：

- `chassis_encoder_ab`：编码器采集。
- `uart_gimbal_manual`、`uart_region_store`：串口指令与区域记录。
- `uart_guard_report`、`uart_home_report`：状态通知。
- `guard_voice_control`、`uart_voice_tx`：语音事件和串口发送。
- `tof_uart_rx`：测距串口解析。

CAN 驱动负责电机指令和反馈数据交换。集成时应分开检查总线通信、数据有效性和上层控制资格。

## 工程配置

- 目标平台参考 PH1P35MDG324，速度等级 -3，工具版本参考 Tang Dynasty 6.2.168116。
- MIPI D-PHY、DDR、HDMI、CAN、PLL 和部分 RAM/DSP 实例依赖目标器件的厂商 IP。应根据合法取得的组件及实际硬件配置工程。
- A/B 两板分别组织工作库和顶层，避免同名辅助模块重复定义。
- 多种传感器配置和解包路径按实际器件选择，文件清单不等于综合编译顺序。
- 引脚快照与实际板卡连接逐项核对；时钟、生成时钟、接口延时和 CDC 约束按最终工程建立。
- 模块的适用条件、阶段接口和配置要求以代码注释为准。`interfaces/` 中的 JSON 用于索引，不参与 HDL 编译。
- `.v` 源按 Verilog 语法编译。部分合法的 Verilog 信号名也是 SystemVerilog 关键字，将全部 `.v` 强制当作 SystemVerilog 解析可能产生额外诊断。
- 厂商 IP 源、包装和配置保留原有版权说明。器件原语仍由 TD 安装库提供，源码包不代替工具授权与组件许可。
- DDR PHY 使用初始化 ROM 裸文件名，跨工具仿真时需配置对应目录或初始化文件搜索路径。

## 验证顺序

先检查位宽、复位、时钟域和握手，再验证帧边界、有效信号、目标新鲜度及模式切换；最后分别完成系统仿真、实现时序与上板验证。阶段名称仅帮助理解信息流，不代替对实际数据、延迟和执行机构行为的验证。

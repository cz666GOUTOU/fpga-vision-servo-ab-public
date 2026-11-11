# 公开框架的集成边界

## A 板

公开 `user_source/hdl_source` 中经过筛选的采集、ISP、通用视频算法、OSD、网络和 SD 源码。以下原路径的实现未随仓库发布：

- `color_ccl_pipeline.v`、`color_control_detect.v`、`yanseshibie.v`：颜色形状检测及配套结果逻辑。
- `zhencha_multi_ccl.v`、`zhencha_shibie.v`：运动检测。
- `mode38_local/` 内的计算、模板采集、跟踪核心和控制：ROI/SAD 链路。
- `design_top_wrapper.v`：含内部算法配置的系统集成顶层。

相关端口说明位于 `interfaces/A_board/`。接口保留名称和声明位宽，不发布参数默认值、局部状态、函数、算法查表或行为实现。参数表达式出现在端口位宽中时，需由集成者自行提供有效定义；不能将空缺理解为默认零。

## B 板

公开 GM6020 CAN 驱动、Ethernet、基础 PWM、底盘通用解算与宽除法辅助模块。原 `top.v` 中以下独立模块拆入 `user_source/public_helpers/`：

- 编码器采集：`chassis_encoder_ab`。
- 串口指令与区域记录：`uart_gimbal_manual`、`uart_region_store`。
- 状态通知：`uart_guard_report`、`uart_home_report`。
- 语音接口：`guard_voice_control`、`uart_voice_tx`。
- 测距串口解析：`tof_uart_rx`。

GM6020 位置/模型控制、视觉几何与控制、PID、启动/搜索及混合顶层的其他行为实现不公开，接口位于 `interfaces/B_board/`。CAN 驱动描述总线与电机数据交换，不包含云台闭环控制律。

## 依赖与工程文件

- 本仓库不包含完整 `.al` 工程、旧构建脚本、参考测试和 netlist，避免混入核心源码副本或误导完整构建。
- 原设计引用 MIPI D-PHY、DDR 控制器/PHY、HDMI、CAN、PLL 及 RAM/DSP 资源。厂商 IP 需通过有权使用的工具和资料获得；源码中的实例名不是完整依赖清单。
- A/B 两板有同名辅助模块，各自属于独立顶层。不要把全部 Verilog 文件一次性编入同一工作库。
- A 板保留若干不同传感器/解包示例路径，应选择当前需要的实现。公开文件清单不等于实际综合编译顺序。
- 保留的引脚文件仅是原平台连接快照。时序约束应针对自行组装后的真实时钟、IP 和接口重新建立。

## 接口替代与验证

替代私有核心时，应自行约定复位、时钟域、valid/ready、帧边界、结果新鲜度及取消/超时语义。接口 JSON 不承诺缺失实现的具体延迟、状态转移和算法精度。

当前公开代码没有因发布筛选而改变原始框架逻辑；从混合文件拆出的模块保留模块内部原文。本次检查证明发布范围和原文来源，不证明重新组装后的功能、时序或执行机构行为。补齐依赖后应分别完成静态检查、仿真、实现时序与上板验证。

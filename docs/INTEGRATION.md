# 双板系统集成说明

## A 板：视觉感知与显示

`A_board/lab_ex3_osd/user_source/hdl_source/` 按采集、ISP、视频处理、显示、通信和存档组织。摄像头配置位于 `uics500_cfg/`，图像处理与显示入口包括 `vision.v`、`dakuang.v` 和 `hdmi_mixer.v`，网络接口集中于 `target_eth_udp/`。

主算法模块的结构入口位于 `core_outline/`：

| 文件 | 功能阶段 |
|---|---|
| `yanseshibie.v` | 图像输入、候选准备、形状评估与结果整理 |
| `zhencha_multi_ccl.v` | 图像输入、区域准备、运动评估与结果整理 |
| `a38_sad16_core.v` | 作业输入、样本准备、匹配评估与结果整理 |

接口索引位于 `interfaces/A_board/`，列出端口方向、数据宽度与信号名称。历史命名中可能包含 `green`、`triangle` 等名称；具体语义应结合系统模式和调用端核对。

## B 板：通信与执行接口

`B_board/GM6020_test/user_source/` 包括 GM6020 CAN、Ethernet、PWM、底盘通用解算和运算辅助模块。视觉控制的结构入口为 `core_outline/vision_nonlinear_ctrl.v`，按目标输入、反馈准备、控制评估和命令整理组织。

`public_helpers/` 集中以下模块：

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

## 验证顺序

先检查位宽、复位、时钟域和握手，再验证帧边界、有效信号、目标新鲜度及模式切换；最后分别完成系统仿真、实现时序与上板验证。阶段名称仅帮助理解信息流，不代替对实际数据、延迟和执行机构行为的验证。

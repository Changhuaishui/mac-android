# Agent Prompts

本目录保存可直接派发给多个 Agent 的提示词。

使用方式：

1. 先把 `00-共通派发约束.md` 发给所有 Agent。
2. 再按角色追加对应提示词。
3. 每个 Agent 只处理自己提示词里的允许范围。
4. 交付时把结果写入 `agents/reports/` 或按任务卡要求写入交付记录。

当前角色：

| 文件 | 角色 |
|---|---|
| `00-共通派发约束.md` | 所有 Agent 必读 |
| `01-M1-MacHost-Agent.md` | Mac 端采集、编码、TCP 发送 |
| `02-M1-AndroidClient-Agent.md` | Android 端接收、解码、SurfaceView 显示 |
| `03-M1-Protocol-Agent.md` | protocol v0 统一和两端对齐 |
| `04-KimiCode-调研验证-Agent.md` | Kimi Code 只读调研、页面/资料/验证观察 |
| `05-M1.1-USB画质帧率升级-MacHost-Agent.md` | Mac 端 USB 画质、帧率、码率档位升级 |
| `06-M1.1-USB画质帧率升级-AndroidClient-Agent.md` | Android 端高分辨率解码、低延迟队列、显示适配 |
| `07-M1.1-Pad电源温控安全-Agent.md` | Pad 电源、温控、安全提示与长时间使用策略 |
| `08-M1.1-主Agent整合验收提示词.md` | M1.1 多 Agent 结果整合与验收 |
| `09-M1.1-Android设备显示能力识别-Agent.md` | Android 端运行时读取真实 Display Mode、Surface 与刷新率 |
| `10-M1.1-Protocol设备能力协商-Agent.md` | 扩展 HELLO，让 Android 显示能力可被 Mac 使用 |
| `11-M1.1-MacHost动态原生档-Agent.md` | Mac 根据 Android 上报能力生成 detected-native 档位 |

派发原则：

- 不让多个 Agent 同时修改同一范围。
- 不让实现 Agent 自行改协议。
- 不让辅助 Agent 把建议当最终结论。
- 所有未验证内容必须明确写“未验证”。

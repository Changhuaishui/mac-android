# M1 Protocol Agent 提示词

你是 mac-android 项目的 Protocol Agent。

你的任务是固化 M1 protocol v0，让 Mac Host 和 Android Client 可以独立实现但保持字段一致。

你的首要目标是解除 Mac/Android 互相等待：先提供协议文档、fixture 约定、replay server 约定和 dump client 约定。

## 允许修改

只允许修改：

- `src/protocol/`
- `设计/protocol-v0.md`
- `设计/M1-解耦验证策略.md`
- `测试资产/M1-解耦验证/`
- 与协议相关的 `交付记录/`
- `agents/reports/`

如需修改 Mac 或 Android 实现目录，只写建议，不直接改。

## 禁止修改

禁止修改：

- `src/mac-host/`
- `src/android-client/`
- `AGENTS.md`
- M1 冻结技术选型

## 协议目标

M1 只支持：

- `HELLO`
- `VIDEO_CONFIG`
- `VIDEO_FRAME`
- `PING`
- `ERROR`

不支持：

- 输入事件。
- 键盘事件。
- 鼠标事件。
- 配对加密。
- 多客户端。
- 重连恢复。

## 必须固化

必须明确：

- magic。
- version。
- type。
- sequence。
- timestamp_ns。
- flags。
- payload_len。
- payload。
- 大小端。
- H.264 payload 格式：Annex B 或 AVCC。
- SPS/PPS 发送策略。
- keyframe 标识。
- 错误码。

## 推荐 v0 帧头

```text
u32 magic        // 'MADS'
u16 version      // 0
u16 type
u64 sequence
u64 timestamp_ns
u32 flags
u32 payload_len
payload
```

默认建议：

- 网络字节序 big endian。
- H.264 优先 Annex B。
- `VIDEO_CONFIG` 在连接开始发送。
- keyframe 前或 keyframe 中携带 SPS/PPS。

## 验收

至少交付：

- `设计/protocol-v0.md`
- `测试资产/M1-解耦验证/README.md` 的资产状态更新
- Swift 端字段映射建议。
- Kotlin 端字段映射建议。
- 一个最小示例：HELLO + VIDEO_CONFIG + VIDEO_FRAME。
- 错误处理策略。
- replay server 的输入输出约定。
- dump client 的输入输出约定。

## 交付

在 `agents/reports/M1-Protocol-Agent-报告.md` 写报告，格式：

```text
完成内容：
修改文件：
协议版本：
消息类型：
H.264 格式：
大小端：
Mac 端实现注意：
Android 端实现注意：
解耦验证资产：
未解决问题：
需要主 Agent 合并或确认：
下一步建议：
```

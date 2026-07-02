---
type: 任务卡
project: mac-android
status: 已完成（代码 + protocol v0 对齐）；真实采集/TCP 验证待授权
owner_agent: Codex (M1 MacHost Agent)
updated: 2026-06-30
---

# M1 Mac Host：采集、编码、TCP 发送

## 用户原话

> 然后就是我会派多个 agent 干活，一个是构建 mac 端的，一个是构建 Android 端的。Android 我用的是是小米平板 6pro。

## 本轮目标

构建 M1 Mac Host 最小可运行 POC：

1. 列出本机可采集 display。
2. 默认选择主屏。
3. 使用 ScreenCaptureKit 采集画面。
4. 使用 VideoToolbox 编码 H.264。
5. 将 H.264 转为 Annex B 格式。
6. 通过 TCP server 按 protocol v0 发送视频帧。
7. 断开后停止采集并进入明确错误/空闲状态。

## 明确不做

- 不创建虚拟显示器。
- 不做输入注入。
- 不做菜单栏 App / UI。
- 不做 Wi-Fi 发现或设备发现。
- 不做配对、加密、账号。
- 不引入 WebRTC / QUIC / UDP / RTP。
- 不改 `src/protocol/`、`src/android-client/`、`AGENTS.md`、M1 冻结技术选型。

## 已确认事实

- M1 固定：Swift + ScreenCaptureKit + VideoToolbox H.264 + TCP 长连接。
- 优先输出 Annex B；若用 AVCC 必须明确说明并负责转换。
- 目标 Android 设备为小米平板 6 Pro，M1 先横屏。
- 推荐起步档位：1280x800 30fps。
- protocol v0 帧头：magic(4) + version(2) + type(2) + sequence(8) + timestamp_ns(8) + flags(4) + payload_len(4)。

## 验收标准

- [ ] 能列出并选择主 display。
- [ ] 能采集屏幕并编码 H.264。
- [ ] TCP client 连接后能持续收到 VIDEO_FRAME。
- [ ] 日志包含 FPS、编码耗时、码率、连接状态、可见错误。
- [ ] 断开连接后停止发送，不会无限堆积帧。

## 交付物

- `src/mac-host/` 下可编译运行的 SwiftPM 工程。
- `agents/reports/M1-MacHost-Agent-报告.md`。
- `交付记录/2026-06-30-M1-MacHost-验证说明.md`。

## 下一步

- 与 Android Agent 对齐 protocol v0 字段和 H.264 格式。
- 端到端验证：Android 能显示 Mac 画面。

# M1 Protocol Agent 报告

完成内容：

- 固化 M1 protocol v0 的 header、消息类型、flags、payload、错误码和最小时序。
- 明确 H.264 payload 使用 Annex B byte stream。
- 明确所有定长整数使用 big endian。
- 补充 Swift 与 Kotlin 字段映射建议。
- 补充 HELLO、VIDEO_CONFIG、VIDEO_FRAME 的最小 header 示例。
- 补齐 M1 解耦验证资产约定：protocol frame 样例、replay server、dump client、`sample-annexb.h264` 生成方式。

修改文件：

- `任务记录/2026-06-30-M1-Protocol-v0固化.md`
- `任务记录/2026-06-30-M1-Protocol-解耦验证资产约定.md`
- `设计/protocol-v0.md`
- `src/protocol/README.md`
- `测试资产/M1-解耦验证/README.md`
- `测试资产/M1-解耦验证/protocol-frame-example.md`
- `测试资产/M1-解耦验证/replay-server-notes.md`
- `测试资产/M1-解耦验证/dump-client-notes.md`
- `测试资产/M1-解耦验证/sample-annexb-generation.md`
- `agents/reports/M1-Protocol-Agent-报告.md`
- `交付记录/2026-06-30-M1-Protocol-v0固化-验证说明.md`
- `交付记录/2026-06-30-M1-Protocol-解耦验证资产约定-验证说明.md`
- `当前工作台.md`

协议版本：

- `version = 0`

消息类型：

- `HELLO = 0`
- `VIDEO_CONFIG = 1`
- `VIDEO_FRAME = 2`
- `PING = 3`
- `ERROR = 4`

H.264 格式：

- Annex B byte stream。
- `VIDEO_CONFIG` 不携带二进制 SPS/PPS。
- `VIDEO_FRAME` 在连接开始后的第一个关键帧前或关键帧 payload 内携带 SPS/PPS。
- 每个关键帧前或关键帧 payload 内重复 SPS/PPS。

大小端：

- 网络字节序 big endian。

解耦验证资产：

- `protocol-frame-example.md` 已定义最小消息序列和 payload_len 样例。
- `replay-server-notes.md` 已定义假 Mac Host 行为，Android 可用它验证 TCP 接收、protocol v0 解析和 MediaCodec 输入。
- `dump-client-notes.md` 已定义假 Android Client 行为，Mac 可用它验证 TCP 输出、header、JSON config 和 Annex B payload。
- `sample-annexb-generation.md` 已定义无敏感内容的 `sample-annexb.h264` 生成命令和验收方式。
- `protocol-frame-example.bin` 与真实二进制 fixture 尚未生成，本轮只固化生成约定。

Mac 端实现注意：

- `MADS` magic 写为 `0x4D414453`。
- header 固定 32 字节。
- 当前 `src/mac-host/Sources/MacHost/Protocol.swift` 的消息编号已与本协议一致。
- `payload_len` 必须来自实际 payload 字节数。
- VideoToolbox 如输出 AVCC，发送前必须转 Annex B。
- 关键帧设置 `FLAG_KEYFRAME`。
- payload 含 SPS/PPS 时设置 `FLAG_CONFIG`。
- 断开连接后停止采集或进入明确暂停状态。

Android 端实现注意：

- 先精确读取 32 字节 header，再按 `payload_len` 读取 payload。
- 用 `ByteOrder.BIG_ENDIAN` 解析 header。
- `VIDEO_CONFIG` 到达后再配置依赖宽高和 codec 的解码状态。
- `VIDEO_FRAME` payload 按 Annex B 喂给 MediaCodec。
- 解码失败必须显示可见错误，不能静默黑屏。

Android 端解耦验证入口：

- 优先使用 `sample-annexb.h264` 本地 asset 验证 `MediaCodec -> SurfaceView`。
- 再使用 replay server 验证 `TCP -> protocol v0 -> MediaCodec -> SurfaceView`。
- 模拟器连接 Mac replay server 时使用 `10.0.2.2:19421`。
- 真机 USB 反向端口时使用 `adb reverse tcp:19421 tcp:19421` 后连接 `127.0.0.1:19421`。

未解决问题：

- 未生成 `sample-annexb.h264` 二进制 fixture。
- 未生成 `protocol-frame-example.bin`。
- 未实现 replay server 或 dump client 工具代码。
- 未在真机验证小米平板 6 Pro 的 MediaCodec 对当前 Annex B 输入策略的表现。
- 未验证 Mac VideoToolbox AVCC 到 Annex B 的实际转换代码。
- 未做端到端延迟、码率或 10 分钟连续运行验证。

需要主 Agent 合并或确认：

- Mac Host Agent 和 Android Client Agent 开始实现前应确认 `设计/protocol-v0.md` 为唯一协议来源。
- 后续如果要加入输入事件、配对加密、多客户端或重连恢复，应另开任务并更新协议版本或扩展文档。

下一步建议：

- Protocol Agent 下一步可以生成 `sample-annexb.h264`、`protocol-frame-example.bin`、replay server 和 dump client 最小工具。
- Mac Host Agent 不等 Android，按 `dump-client-notes.md` 自证 TCP 输出。
- Android Client Agent 不等 Mac，按 `sample-annexb-generation.md` 和 `replay-server-notes.md` 自证解码显示。

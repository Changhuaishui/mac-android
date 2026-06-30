# Protocol

本目录是 M1 protocol v0 的实现入口。

当前权威文档：

- `设计/protocol-v0.md`

M1 固定约定：

- TCP 长连接。
- 固定 32 字节 header。
- 所有整数使用 big endian。
- `magic = MADS`。
- `version = 0`。
- H.264 payload 使用 Annex B byte stream。
- `VIDEO_CONFIG` 使用 UTF-8 JSON，只描述流格式。
- `VIDEO_FRAME` 携带 Annex B NAL units，关键帧前或关键帧内重复 SPS/PPS。

消息类型：

| 名称 | type |
|---|---:|
| `HELLO` | 0 |
| `VIDEO_CONFIG` | 1 |
| `VIDEO_FRAME` | 2 |
| `PING` | 3 |
| `ERROR` | 4 |

实现建议：

- Mac Host 和 Android Client 都不要各自发明字段名。
- 任何协议变化先改 `设计/protocol-v0.md`，再改两端实现。
- 协议测试样例后续放在本目录，避免 Mac/Android 目录各自维护一份。

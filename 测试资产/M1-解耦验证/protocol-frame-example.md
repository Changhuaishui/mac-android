# Protocol v0 帧样例

本文件定义 M1 解耦验证使用的最小 protocol v0 消息序列。它用于 replay server、dump client、Mac Host、Android Client 对齐字段，不包含真实屏幕内容。

## 基本约定

- header 固定 32 字节。
- 所有整数为 big endian。
- `magic = MADS = 0x4D414453`。
- `version = 0`。
- `sequence` 在单连接内从 1 递增。
- `timestamp_ns` 使用发送端单调时钟纳秒；静态样例可填 0。
- `payload_len` 不包含 32 字节 header。

## 消息类型

| type | 名称 | 方向 |
|---:|---|---|
| 0 | `HELLO` | Android / dump client -> Mac / replay server |
| 1 | `VIDEO_CONFIG` | Mac / replay server -> Android / dump client |
| 2 | `VIDEO_FRAME` | Mac / replay server -> Android / dump client |
| 3 | `PING` | 双向 |
| 4 | `ERROR` | 双向 |

## flags

| mask | 名称 | 用途 |
|---:|---|---|
| `0x00000001` | `FLAG_KEYFRAME` | `VIDEO_FRAME` 是关键帧 |
| `0x00000002` | `FLAG_CONFIG` | payload 含 codec 参数集；对 `VIDEO_CONFIG` 建议设置 |
| `0x00000004` | `FLAG_END_OF_STREAM` | 发送端准备结束流 |

## 最小消息序列

```text
HELLO
VIDEO_CONFIG
VIDEO_FRAME keyframe + SPS/PPS + IDR
VIDEO_FRAME delta
PING
```

## HELLO

payload 为 UTF-8 JSON：

```json
{"client_name":"M1 Dump Client","platform":"test","protocol_version":0,"max_width":1280,"max_height":800,"max_fps":30,"supported_codecs":["h264"],"supported_h264_stream_formats":["annex_b"]}
```

该 payload 的 UTF-8 长度为 190 字节。

这是不含 `display_capabilities` 的 legacy/minimal HELLO，用于证明新字段可缺省。带设备显示能力的 HELLO 示例见：

- `hello-display-capabilities.example.json`

header 字段：

| 字段 | 值 |
|---|---|
| `magic` | `0x4D414453` |
| `version` | `0` |
| `type` | `0` |
| `sequence` | `1` |
| `timestamp_ns` | `0` |
| `flags` | `0` |
| `payload_len` | `190` / `0x000000BE` |

header 十六进制：

```text
4D 41 44 53  00 00  00 00
00 00 00 00  00 00 00 01
00 00 00 00  00 00 00 00
00 00 00 00  00 00 00 BE
```

## VIDEO_CONFIG

payload 为 UTF-8 JSON：

```json
{"codec":"h264","stream_format":"annex_b","width":1280,"height":800,"fps":30,"bitrate_bps":8000000,"sps_pps_policy":"repeat_before_keyframe","timestamp_unit":"ns"}
```

该 payload 的 UTF-8 长度为 163 字节。

header 字段：

| 字段 | 值 |
|---|---|
| `magic` | `0x4D414453` |
| `version` | `0` |
| `type` | `1` |
| `sequence` | `2` |
| `timestamp_ns` | `0` |
| `flags` | `0x00000002` |
| `payload_len` | `163` / `0x000000A3` |

header 十六进制：

```text
4D 41 44 53  00 00  00 01
00 00 00 00  00 00 00 02
00 00 00 00  00 00 00 00
00 00 00 02  00 00 00 A3
```

## VIDEO_FRAME

payload 必须是 H.264 Annex B byte stream：

```text
00 00 00 01 <SPS>
00 00 00 01 <PPS>
00 00 00 01 <IDR slice>
```

关键帧 header 字段：

| 字段 | 值 |
|---|---|
| `magic` | `0x4D414453` |
| `version` | `0` |
| `type` | `2` |
| `sequence` | `3` |
| `timestamp_ns` | `33333333` |
| `flags` | `0x00000003` |
| `payload_len` | 实际 Annex B 字节数 |

`flags = 0x00000003` 表示：

```text
FLAG_KEYFRAME | FLAG_CONFIG
```

delta 帧 header 字段：

| 字段 | 值 |
|---|---|
| `type` | `2` |
| `sequence` | `4` |
| `timestamp_ns` | `66666666` |
| `flags` | `0` |
| `payload_len` | 实际 Annex B 字节数 |

## protocol-frame-example.bin 生成约定

`protocol-frame-example.bin` 后续可由 Protocol Agent 或测试工具生成，内容应按以下顺序拼接：

```text
HELLO header + HELLO payload
VIDEO_CONFIG header + VIDEO_CONFIG payload
VIDEO_FRAME header + Annex B keyframe payload
```

二进制样例不得包含真实屏幕内容。若没有可用 H.264 payload，可以暂不生成 `.bin`，但必须保留本文件作为字段权威说明。

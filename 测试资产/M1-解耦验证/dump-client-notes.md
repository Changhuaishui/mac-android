# Dump Client 约定

Dump client 是假 Android Client，用于让 Mac Host 在没有 Android App 的情况下验证：

```text
ScreenCaptureKit
→ VideoToolbox
→ TCP server
→ protocol v0
→ dump client
```

## 目标

- 主动连接 Mac Host TCP server。
- 发送 `HELLO`。
- 读取 `VIDEO_CONFIG` 和 `VIDEO_FRAME`。
- 校验 header、payload 长度、flags、Annex B start code。
- 可选把 H.264 payload 写入 `dump-annexb.h264`。

## 默认参数

| 参数 | 默认值 |
|---|---|
| host | `127.0.0.1` |
| port | `19421` |
| output | `测试资产/M1-解耦验证/dump-annexb.h264` |
| max_payload | `8 MiB` |
| duration | `10 s` 或指定帧数 |

## 连接流程

### 1. TCP connect

Dump client 连接：

```text
127.0.0.1:19421
```

### 2. 发送 HELLO

payload：

```json
{"client_name":"M1 Dump Client","platform":"test","protocol_version":0,"max_width":1280,"max_height":800,"max_fps":30,"supported_codecs":["h264"],"supported_h264_stream_formats":["annex_b"]}
```

header：

```text
type = HELLO
flags = 0
payload_len = JSON UTF-8 byte length
```

### 3. 接收消息

Dump client 必须循环读取：

```text
32 byte header
payload_len byte payload
```

必须校验：

- `magic == MADS`
- `version == 0`
- `type` 属于 1、2、3、4；Mac 不应主动发 `HELLO`
- `payload_len <= 8 MiB`
- 实际读取长度等于 `payload_len`

## VIDEO_CONFIG 验证

`VIDEO_CONFIG` payload 必须是 UTF-8 JSON。

必需字段：

```text
codec = h264
stream_format = annex_b
width > 0
height > 0
fps > 0
timestamp_unit = ns
```

Dump client 应记录：

- width。
- height。
- fps。
- bitrate_bps。
- stream_format。

如果 `VIDEO_CONFIG` payload 是二进制 SPS/PPS，应判为失败，因为这不符合当前 protocol v0。

## VIDEO_FRAME 验证

`VIDEO_FRAME` payload 必须是 Annex B byte stream。

基本校验：

- payload 以 `00 00 01` 或 `00 00 00 01` 开始，或可在 payload 内找到 start code。
- `FLAG_KEYFRAME` 帧应包含 NAL type 5。
- `FLAG_CONFIG` 帧应包含 NAL type 7 和 8，或至少包含其中一个并记录 warning。
- delta 帧可包含 NAL type 1。

NAL type 判断：

```text
nal_type = first_byte_after_start_code & 0x1F
```

常见类型：

| NAL type | 含义 |
|---:|---|
| 1 | non-IDR slice |
| 5 | IDR slice |
| 7 | SPS |
| 8 | PPS |

## 输出文件

Dump client 可将所有 `VIDEO_FRAME` payload 顺序拼接到：

```text
dump-annexb.h264
```

规则：

- 不写入 header。
- 不写入 `VIDEO_CONFIG` JSON。
- 只拼接 H.264 Annex B payload。
- 文件仅用于本地调试，不作为公开长期 fixture，除非确认画面无敏感内容。

## 统计

Dump client 至少输出：

```text
connected
video_config_received = true/false
frames = N
keyframes = N
config_frames = N
bytes = N
duration_ms = N
fps_estimate = N
first_error = ...
```

## 验收

Mac Host 独立验收通过条件：

- dump client 能连接。
- 能收到 `VIDEO_CONFIG` JSON。
- 能收到连续 `VIDEO_FRAME`。
- 关键帧包含 SPS/PPS/IDR。
- 断开连接后 Mac Host 不继续无限排队。

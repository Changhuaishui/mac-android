# Protocol v0

日期：2026-06-30

## 1. 目标

M1 protocol v0 只服务一条本地视频链路：

```text
Mac Host
→ TCP 长连接
→ Android Client
```

本协议用于让 Mac Host 和 Android Client 在未互相依赖实现代码的情况下，保持消息字段、字节序、H.264 payload 和错误处理一致。

## 2. 非目标

Protocol v0 不支持：

- 输入事件、键盘事件、鼠标事件。
- 配对、加密、账号、云中继。
- 多客户端。
- 会话恢复和自动重连。
- 音频。
- 公网远程访问。

## 3. 传输

- 传输层：单条 TCP 长连接。
- 连接方向：Android Client 主动连接 Mac Host。
- 字节序：所有定长整数使用网络字节序 big endian。
- 粘包处理：接收端必须按固定 32 字节帧头读取，再按 `payload_len` 读取 payload。
- 最大 payload：v0 建议限制为 8 MiB。超过限制必须断开连接并上报 `ERR_PAYLOAD_TOO_LARGE`。

## 4. 固定帧头

每条消息由 32 字节 header 和可变 payload 组成：

```text
u32 magic
u16 version
u16 type
u64 sequence
u64 timestamp_ns
u32 flags
u32 payload_len
u8[payload_len] payload
```

| 字段 | 长度 | v0 取值或含义 |
|---|---:|---|
| `magic` | 4 | ASCII `MADS`，十六进制 `0x4D414453` |
| `version` | 2 | `0` |
| `type` | 2 | 消息类型，见第 5 节 |
| `sequence` | 8 | 单连接内从 1 递增，发送端维护 |
| `timestamp_ns` | 8 | 发送端单调时钟纳秒；没有可用时间时填 0 |
| `flags` | 4 | 类型相关标志位，未使用位必须为 0 |
| `payload_len` | 4 | payload 字节数，不含 32 字节 header |
| `payload` | 可变 | 类型相关内容 |

接收端必须校验：

- `magic == MADS`
- `version == 0`
- `type` 是已知类型
- `payload_len` 未超过本端上限
- 实际读取 payload 长度等于 `payload_len`

校验失败时，能发送 `ERROR` 就先发送 `ERROR`，然后断开连接。

## 5. 消息类型

| 名称 | type | 方向 | payload |
|---|---:|---|---|
| `HELLO` | `0` | Android -> Mac | UTF-8 JSON |
| `VIDEO_CONFIG` | `1` | Mac -> Android | UTF-8 JSON |
| `VIDEO_FRAME` | `2` | Mac -> Android | H.264 Annex B byte stream |
| `PING` | `3` | 双向 | UTF-8 JSON 或空 |
| `ERROR` | `4` | 双向 | UTF-8 JSON |

未知 `type` 必须按 `ERR_UNSUPPORTED_TYPE` 处理。

## 6. Flags

### 通用 flags

| bit | mask | 含义 |
|---:|---:|---|
| 0 | `0x00000001` | `FLAG_KEYFRAME`，当前视频帧是关键帧 |
| 1 | `0x00000002` | `FLAG_CONFIG`，payload 含 codec 配置或参数集 |
| 2 | `0x00000004` | `FLAG_END_OF_STREAM`，发送端准备结束流 |

### 各类型允许的 flags

| type | 允许 flags |
|---|---|
| `HELLO` | 必须为 0 |
| `VIDEO_CONFIG` | 可设置 `FLAG_CONFIG`，建议设置 |
| `VIDEO_FRAME` | 可设置 `FLAG_KEYFRAME`、`FLAG_CONFIG`、`FLAG_END_OF_STREAM` |
| `PING` | 必须为 0 |
| `ERROR` | 必须为 0 |

接收端看到不适用于当前类型的 flags 时，必须记录诊断；v0 可以继续处理该消息，但不应依赖未知位。

## 7. Payload

### 7.1 HELLO

Android Client 连接成功后首先发送 `HELLO`。

```json
{
  "client_name": "Xiaomi Pad 6 Pro",
  "platform": "android",
  "protocol_version": 0,
  "max_width": 1920,
  "max_height": 1200,
  "max_fps": 30,
  "supported_codecs": ["h264"],
  "supported_h264_stream_formats": ["annex_b"],
  "display_capabilities": {
    "current_mode": {
      "mode_id": 1,
      "physical_width": 2880,
      "physical_height": 1800,
      "refresh_rate": 144.0
    },
    "supported_modes": [
      {
        "mode_id": 1,
        "physical_width": 2880,
        "physical_height": 1800,
        "refresh_rate": 144.0
      },
      {
        "mode_id": 2,
        "physical_width": 2880,
        "physical_height": 1800,
        "refresh_rate": 60.0
      }
    ],
    "window_bounds": {
      "width": 2880,
      "height": 1800
    },
    "surface_size": {
      "width": 2880,
      "height": 1800
    },
    "density": 2.0,
    "density_dpi": 320,
    "orientation": "landscape"
  }
}
```

Mac Host 收到 `HELLO` 前不发送视频帧。`HELLO` 的 `protocol_version` 必须为 0。

`display_capabilities` 是可选扩展字段。旧 Android Client 可以不发送；Mac Host 收不到该字段、字段为空或解析失败时，必须降级到 `balanced` 或 `hd60`，不能因为缺少该字段断开连接。新 Android Client 发送该字段时，也不能要求旧 Mac Host 必须理解它；旧 Mac Host 忽略未知 JSON 字段仍属于兼容行为。

`display_capabilities` 字段含义：

| 字段 | 含义 |
|---|---|
| `current_mode.mode_id` | Android `Display.Mode.modeId`，只在本次运行和系统返回范围内有意义。 |
| `current_mode.physical_width` / `physical_height` | Android `Display.Mode` 返回的物理模式尺寸，不是网页规格或人工硬编码值。 |
| `current_mode.refresh_rate` | 当前 Display Mode 对应刷新率，单位 Hz。 |
| `supported_modes` | Android 运行时返回的可用 Display Mode 列表，可以为空数组。 |
| `window_bounds.width` / `height` | 当前 App window 可用边界，用于渲染约束；不等同于设备原生分辨率。 |
| `surface_size.width` / `height` | 当前 SurfaceView 实际尺寸，用于判断解码输出和渲染尺寸；不等同于设备原生分辨率。 |
| `density` | Android density scale。 |
| `density_dpi` | Android density DPI。 |
| `orientation` | 当前方向，建议值：`landscape`、`portrait`、`square`、`undefined`。 |

Mac Host 画质档选择建议：

| 档位 | 建议规则 |
|---|---|
| `balanced` | 固定 `1280x800@30`，作为保守默认档。 |
| `hd60` | 固定 `1920x1200@60`，作为无能力字段时的高清降级档。 |
| `detected-native-safe` | 使用 `current_mode.physical_width` / `physical_height`，FPS 上限先限制到 60 或更低。 |
| `detected-native` | 使用 `current_mode.physical_width` / `physical_height` 和 `current_mode.refresh_rate`，但 Mac 可因编码器能力、码率或温度降 FPS。 |

如果 `current_mode` 缺失，Mac Host 可以从 `supported_modes` 中选一个合理候选；如果两者都不可用，必须降级到 `hd60` 或 `balanced`。

### 7.2 VIDEO_CONFIG

Mac Host 在开始发送视频帧前发送 `VIDEO_CONFIG`。

```json
{
  "codec": "h264",
  "stream_format": "annex_b",
  "width": 1280,
  "height": 800,
  "fps": 30,
  "bitrate_bps": 8000000,
  "sps_pps_policy": "repeat_before_keyframe",
  "timestamp_unit": "ns"
}
```

`VIDEO_CONFIG` 只描述随后视频流的格式，不携带二进制 SPS/PPS。SPS/PPS 由 `VIDEO_FRAME` 的 Annex B payload 携带。

### 7.3 VIDEO_FRAME

`VIDEO_FRAME` payload 是 H.264 Annex B byte stream：

```text
00 00 00 01 <NAL unit>
00 00 00 01 <NAL unit>
...
```

M1 固定策略：

- Mac Host 如从 VideoToolbox 获得 AVCC，必须在发送前转成 Annex B。
- Mac Host 必须在连接开始后的第一个关键帧前或关键帧 payload 内包含 SPS/PPS。
- Mac Host 必须在每个关键帧前或关键帧 payload 内重复 SPS/PPS。
- 关键帧消息必须设置 `FLAG_KEYFRAME`。
- payload 中包含 SPS/PPS 的消息必须设置 `FLAG_CONFIG`。
- Android Client 不应假设 SPS/PPS 只出现一次。

推荐关键帧 payload 顺序：

```text
start_code + SPS
start_code + PPS
start_code + IDR slice
```

### 7.4 PING

`PING` 用于连接保活和粗略延迟估计。payload 可以为空，也可以是：

```json
{
  "ping_id": 1,
  "sent_timestamp_ns": 1234567890
}
```

收到 `PING` 的一端可以原样返回一个 `PING`，也可以只更新连接状态。M1 不要求严格 RTT 协议。

### 7.5 ERROR

`ERROR` payload 使用 UTF-8 JSON：

```json
{
  "code": "ERR_UNSUPPORTED_VERSION",
  "message": "protocol version is not supported",
  "detail": "received version 1"
}
```

`message` 和 `detail` 不得包含屏幕内容、账号、密钥、完整输入文本或其他敏感信息。

## 8. 错误码

| 错误码 | 含义 | 建议处理 |
|---|---|---|
| `ERR_BAD_MAGIC` | magic 不等于 `MADS` | 发送 `ERROR` 后断开 |
| `ERR_UNSUPPORTED_VERSION` | version 不是 0 | 发送 `ERROR` 后断开 |
| `ERR_UNSUPPORTED_TYPE` | 未知消息类型 | 发送 `ERROR` 后断开 |
| `ERR_PAYLOAD_TOO_LARGE` | payload 超过本端上限 | 发送 `ERROR` 后断开 |
| `ERR_BAD_PAYLOAD` | payload JSON 或视频格式无法解析 | 发送 `ERROR`，视情况断开 |
| `ERR_EXPECTED_HELLO` | Mac 在 HELLO 前收到其他消息 | 发送 `ERROR` 后断开 |
| `ERR_UNSUPPORTED_CODEC` | codec 不支持 | 发送 `ERROR` 后断开 |
| `ERR_DECODE_FAILED` | Android 解码失败 | 显示错误状态，断开或等待后续关键帧 |
| `ERR_INTERNAL` | 本端内部错误 | 显示错误状态，断开 |

## 9. 最小时序

```text
Android Client                       Mac Host
      |                                 |
      | TCP connect                     |
      |-------------------------------->|
      | HELLO                           |
      |-------------------------------->|
      |                                 | validate HELLO
      | VIDEO_CONFIG                    |
      |<--------------------------------|
      | VIDEO_FRAME keyframe + SPS/PPS  |
      |<--------------------------------|
      | VIDEO_FRAME delta               |
      |<--------------------------------|
      | PING                            |
      |<------------------------------->|
      | ERROR or TCP close              |
      |<------------------------------->|
```

## 10. 最小示例

### 10.1 HELLO header

假设：

- `type = 0`
- `sequence = 1`
- `timestamp_ns = 0`
- `flags = 0`
- `payload_len = 196`

这里使用不含 `display_capabilities` 的 legacy compact HELLO payload，说明新增可选字段不会改变 header 结构。

Header 十六进制：

```text
4D 41 44 53  00 00  00 00
00 00 00 00  00 00 00 01
00 00 00 00  00 00 00 00
00 00 00 00  00 00 00 C4
```

### 10.2 VIDEO_CONFIG header

假设：

- `type = 1`
- `sequence = 2`
- `timestamp_ns = 0`
- `flags = FLAG_CONFIG`
- `payload_len = 160`

Header 十六进制：

```text
4D 41 44 53  00 00  00 01
00 00 00 00  00 00 00 02
00 00 00 00  00 00 00 00
00 00 00 02  00 00 00 A0
```

### 10.3 VIDEO_FRAME header

假设：

- `type = 2`
- `sequence = 3`
- `timestamp_ns = 1234567890`
- `flags = FLAG_KEYFRAME | FLAG_CONFIG`
- `payload_len = 1024`

Header 十六进制：

```text
4D 41 44 53  00 00  00 02
00 00 00 00  00 00 00 03
00 00 00 00  49 96 02 D2
00 00 00 03  00 00 04 00
```

## 11. Swift 端字段映射建议

建议 Mac Host 使用等价结构：

```swift
struct MadsHeader {
    let magic: UInt32        // 0x4D414453
    let version: UInt16      // 0
    let type: UInt16
    let sequence: UInt64
    let timestampNs: UInt64
    let flags: UInt32
    let payloadLength: UInt32
}
```

实现注意：

- 写入网络时用 big endian。
- `payloadLength` 必须来自实际 payload 字节数。
- `sequence` 在单连接内递增，断开后新连接可从 1 重新开始。
- VideoToolbox 输出 AVCC 时，在发送 `VIDEO_FRAME` 前转 Annex B。
- 断开连接后停止采集或进入明确暂停状态。

## 12. Kotlin 端字段映射建议

建议 Android Client 使用等价结构：

```kotlin
data class MadsHeader(
    val magic: UInt,
    val version: UShort,
    val type: UShort,
    val sequence: ULong,
    val timestampNs: ULong,
    val flags: UInt,
    val payloadLength: UInt,
)
```

实现注意：

- 从 `InputStream` 精确读取 32 字节 header，再读取 payload。
- 用 `ByteBuffer.order(ByteOrder.BIG_ENDIAN)` 解析整数。
- `VIDEO_CONFIG` 到达前不要启动依赖宽高的解码配置。
- `VIDEO_FRAME` payload 按 Annex B 交给 MediaCodec。
- 解码失败时显示可见错误，不允许静默黑屏。

## 13. 兼容性规则

- v0 不做向后兼容，只接受 `version = 0`。
- v0 的 header、消息类型和 H.264 payload 格式不做隐式兼容；新增消息类型、改变 H.264 payload 格式、改变 header 字段，都必须升级文档并让 Mac/Android 同步修改。
- v0 的 JSON payload 允许做可选字段扩展；接收端必须忽略未知字段。
- `HELLO.display_capabilities` 是可选字段，不改变 `HELLO` type、flags、方向或 header 结构。
- Mac Host 收不到 `display_capabilities`、解析失败或字段值不可信时，必须降级到 `balanced` 或 `hd60`，不能中断 M1 视频链路。
- Android Client 发送 `display_capabilities` 后，不能因为 Mac Host 未读取或未回显该字段而断开连接。
- v0 未使用 header 保留位，未知 flags 不作为能力协商。

## 14. 安全与隐私

- 协议不保存屏幕画面。
- 日志只记录连接状态、错误码、帧率、码率、延迟和必要诊断。
- `ERROR.detail` 不得写入敏感内容。
- 默认只用于本机、USB 调试链路或局域网。
- 断开连接后 Mac Host 必须停止发送视频帧。

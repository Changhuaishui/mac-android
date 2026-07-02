# Replay Server 约定

Replay server 是假 Mac Host，用于让 Android Client 在没有真实 Mac Host 的情况下验证：

```text
TCP
→ protocol v0
→ H.264 Annex B
→ MediaCodec
→ SurfaceView
```

## 目标

- 监听本机或局域网 TCP 端口。
- 接收 Android Client 的 `HELLO`。
- 发送 `VIDEO_CONFIG`。
- 按 protocol v0 发送 H.264 Annex B `VIDEO_FRAME`。
- 可选发送 `PING`。
- 断开时停止发送。

## 默认参数

| 参数 | 默认值 |
|---|---|
| host | `127.0.0.1` 或 `0.0.0.0` |
| port | `19421` |
| width | `1280` |
| height | `800` |
| fps | `30` |
| codec | `h264` |
| stream_format | `annex_b` |
| fixture | `测试资产/M1-解耦验证/sample-annexb.h264` |

## 输入

Replay server 的输入是一个 Annex B H.264 文件：

```text
sample-annexb.h264
```

该文件必须包含：

- SPS。
- PPS。
- 至少一个 IDR 关键帧。
- 若用于连续播放，至少 3 秒、30fps 或明确实际 fps。

## 输出消息

### 1. 等待 HELLO

Android Client 连接后应先发 `HELLO`。

Replay server 必须：

- 读取 32 字节 header。
- 校验 `magic/version/type/payload_len`。
- `type` 必须为 `HELLO = 0`。
- 读取并记录 payload JSON。

若未收到 HELLO，允许在 M1 测试模式下记录 warning 后继续，但报告必须写明。

### 2. 发送 VIDEO_CONFIG

payload：

```json
{"codec":"h264","stream_format":"annex_b","width":1280,"height":800,"fps":30,"bitrate_bps":8000000,"sps_pps_policy":"repeat_before_keyframe","timestamp_unit":"ns"}
```

header：

```text
type = 1
flags = FLAG_CONFIG
payload_len = JSON UTF-8 byte length
```

### 3. 发送 VIDEO_FRAME

Replay server 应从 `sample-annexb.h264` 中按 access unit 发送。最小实现可以先按简化策略：

```text
将 SPS/PPS/IDR 作为第一帧 keyframe 发送
后续 slice 以 delta frame 发送
```

关键帧：

```text
type = VIDEO_FRAME
flags = FLAG_KEYFRAME | FLAG_CONFIG
payload = start_code + SPS + start_code + PPS + start_code + IDR
```

非关键帧：

```text
type = VIDEO_FRAME
flags = 0
payload = Annex B NAL units
```

时间戳：

```text
timestamp_ns = frame_index * 1_000_000_000 / fps
```

## Annex B 分帧策略

M1 replay server 可以使用保守分帧：

- 识别 start code：`00 00 01` 或 `00 00 00 01`。
- 根据 NAL unit type 判断：
  - `7` = SPS
  - `8` = PPS
  - `5` = IDR
  - `1` = non-IDR slice
- 遇到 IDR 时，把最近的 SPS/PPS 放在 IDR 前一起发送。

M1 可以不实现完整 H.264 access unit parser；如果分帧不完整，必须在报告中写“未验证/限制”。

## Android 端使用方式

模拟器连接宿主机：

```text
host = 10.0.2.2
port = 19421
```

真实小米平板同局域网：

```text
host = Mac 局域网 IP
port = 19421
```

真实小米平板 USB reverse：

```bash
adb reverse tcp:19421 tcp:19421
```

App 中填写：

```text
host = 127.0.0.1
port = 19421
```

## 日志要求

Replay server 至少记录：

- client connected。
- HELLO 是否收到。
- VIDEO_CONFIG 已发送。
- 发送帧数。
- keyframe 数。
- 总字节数。
- 断开原因。

日志不得记录屏幕内容或敏感数据。

## 验收

Android Client 独立验收通过条件：

- 能连接 replay server。
- 能解析 `VIDEO_CONFIG`。
- 能持续收到 `VIDEO_FRAME`。
- MediaCodec 有输出或失败可见。
- FPS/状态 UI 有更新。

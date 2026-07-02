# M1 MacHost Agent 报告

## 完成内容

1. 创建 `src/mac-host/` SwiftPM 工程，拆分为 **MacHostKit 库 + MacHostCLI + MacHostApp**。
2. 实现 display 枚举与默认主屏选择（`CGMainDisplayID` 匹配）。
3. 使用 **ScreenCaptureKit** 采集现有屏幕，输出 NV12 格式，支持固定分辨率与帧率。
4. 使用 **VideoToolbox** 硬件编码 H.264（Main AutoLevel、CABAC、关闭 B-frame、2 秒关键帧间隔）。
5. 修复编码器无输出问题：在 `VTCompressionSessionCreate` 中补全 `imageBufferAttributes`。
6. 将 VideoToolbox 输出的 AVCC 转换为 **Annex B byte stream**。
7. 按 protocol v0 发送 **UTF-8 JSON 格式的 `VIDEO_CONFIG`**，不携带二进制 SPS/PPS。
8. 在每个 **关键帧 `VIDEO_FRAME`** 的 Annex B payload 内重复携带 SPS/PPS，并设置 `FLAG_KEYFRAME | FLAG_CONFIG`。
9. 使用 **Network.framework** 实现 TCP server，M1 只服务一个 client。
10. **Mac Host 不再主动发送 HELLO**；连接建立后直接开始发送 `VIDEO_CONFIG` → `VIDEO_FRAME`。
11. 新增 **`--dump <path>` 自测模式**：不等 Android、不启动 TCP，直接把 `capture → encode` 后的 Annex B 数据写入本地 `.h264` 文件。
12. 新增 **SwiftUI 窗口 App**：显示状态、FPS、码率、编码耗时、日志，并提供「启动/停止服务」按钮。
13. 新增 `package-app.sh`，一键打包成可双击打开的 `.app` bundle。
14. client 断开后停止采集与编码，进入空闲等待状态。

## 修改文件

- `src/mac-host/Package.swift`
- `src/mac-host/README.md`
- `src/mac-host/Sources/MacHostKit/MacHost.swift`
- `src/mac-host/Sources/MacHostKit/CaptureSession.swift`
- `src/mac-host/Sources/MacHostKit/Encoder.swift`
- `src/mac-host/Sources/MacHostKit/H264Utilities.swift`
- `src/mac-host/Sources/MacHostKit/TCPServer.swift`
- `src/mac-host/Sources/MacHostKit/Protocol.swift`
- `src/mac-host/Sources/MacHostKit/Logger.swift`
- `src/mac-host/Sources/MacHostCLI/main.swift`
- `src/mac-host/Sources/MacHostApp/MacHostApp.swift`
- `src/mac-host/package-app.sh`
- `任务记录/2026-06-30-M1-MacHost-采集编码TCP发送.md`
- `任务记录/2026-07-01-M1-MacHost-可视化窗口App.md`
- `交付记录/2026-06-30-M1-MacHost-验证说明.md`
- `交付记录/2026-07-01-M1-MacHost-App-验证说明.md`

## 运行方式

```bash
cd src/mac-host
swift build

# 打包成可双击打开的 .app
./package-app.sh
open dist/MacHostApp.app

# 或直接用命令行运行窗口 App
./.build/debug/MacHostApp

# 命令行本地 dump 自测
./.build/debug/machost --dump /tmp/sample-annexb.h264 --dump-duration 5

# 命令行 TCP 模式
./.build/debug/machost
./.build/debug/machost --width 1920 --height 1200 --fps 30 --bitrate 12000000 --port 19421
```

首次运行需要在「系统设置 → 隐私与安全性 → 屏幕录制」中授权 `MacHostApp` / `machost`。

Android 端连接时请使用 **19421** 端口。

## 协议对齐情况

已按 `设计/protocol-v0.md` 和 `agents/reports/M1-Protocol-Agent-报告.md` 完成以下对齐：

| 协议要求 | Mac Host 实现 |
|---|---|
| 连接方向：Android → Mac | 是，Mac 监听 TCP |
| Mac 不先发 HELLO | 是，连接建立后直接发 `VIDEO_CONFIG` |
| `VIDEO_CONFIG` 为 UTF-8 JSON | 是，字段包含 codec/stream_format/width/height/fps/bitrate_bps/sps_pps_policy/timestamp_unit |
| `VIDEO_CONFIG` 不携带二进制 SPS/PPS | 是，SPS/PPS 只出现在 `VIDEO_FRAME` |
| `VIDEO_FRAME` 为 Annex B | 是，内部已完成 AVCC → Annex B 转换 |
| 关键帧携带 SPS/PPS | 是，payload 顺序：start_code+SPS、start_code+PPS、start_code+IDR |
| 关键帧设置 `FLAG_KEYFRAME` | 是 |
| 含 SPS/PPS 设置 `FLAG_CONFIG` | 是 |
| 固定 32 字节大端帧头 | 是，`MADS` magic、version 0 |
| 断开后停止发送 | 是 |

**仍未实现/未验证：**

- Mac Host 不读取/解析 Android 发来的 `HELLO`（连接建立即推流）。
- 未实现 `PING` 接收与回复。
- 未实现 `ERROR` 发送。
- TCP server 目前默认只监听 IPv6 通配地址，Android 通过局域网 IPv4 连接前需替换为双栈 server。
- `MacHostApp` 的真实 UI 点击交互（当前环境无图形界面，仅通过代码审查）。

## 执行验证

| 验证项 | 结果 |
|---|---|
| `swift build` 编译通过（含 CLI + App） | 通过 |
| 屏幕录制权限授权后程序启动 | 通过 |
| `--dump` 模式生成本地 Annex B 文件 | 通过，5 秒约 500KB~1.2MB |
| dump 文件以 `00 00 00 01` start code 开头 | 通过 |
| TCP server 监听 19421（IPv6） | 通过 |
| IPv6 dump client 收到 `VIDEO_CONFIG` + `VIDEO_FRAME` | 通过，5 秒约 1MB+ |
| 每秒 FPS / 码率 / 编码耗时日志 | 通过 |
| `MacHostApp` 进程可启动且未崩溃 | 通过 |
| `MacHostApp` 按钮点击 → 启动服务 → 连接 → 状态更新 | 未验证（环境无 GUI） |
| 断线后停止采集 | 未验证 |
| 连续运行 10 分钟 | 未验证 |
| Android 端解码显示 | 未验证（无 Android client） |

## 仍未验证内容

- `MacHostApp` 的真实窗口交互。
- TCP server 在 IPv4 / 双栈环境下的可达性。
- Android 端解码并显示画面。
- 断线、重连、长时间稳定性。

## H.264 输出格式

- **Annex B byte stream**，每个 NAL 前带 start code `00 00 00 01`。
- VideoToolbox 默认输出为 AVCC，Mac Host 内部已完成 AVCC → Annex B 转换。
- SPS/PPS 不通过 `VIDEO_CONFIG` 发送，而是嵌入在每个关键帧的 payload 开头。
- 每个关键帧 `VIDEO_FRAME` 的 `flags` 为 `FLAG_KEYFRAME | FLAG_CONFIG`。
- 非关键帧 `flags` 为 0。

## protocol v0 对接事项

帧头定义（大端）：

```text
u32 magic        // 'MADS'
u16 version      // 0
u16 type         // 1=VIDEO_CONFIG, 2=VIDEO_FRAME, 3=PING, 4=ERROR
u64 sequence
u64 timestamp_ns
u32 flags
u32 payload_len
payload
```

当前 Mac Host 发送的消息类型数值：

| 类型 | 数值 |
|---|---|
| VIDEO_CONFIG | 1 |
| VIDEO_FRAME | 2 |

`VIDEO_FRAME` 的 `timestamp_ns` 取编码前 CMSampleBuffer 的 `presentationTimeStamp.value`。

## 需要 Android 端注意

1. 解码器默认接收 **Annex B** 格式。
2. 收到 `VIDEO_CONFIG`（JSON）后，用其中的 `width/height/fps/codec` 配置解码器；**不要**从 `VIDEO_CONFIG` 取 SPS/PPS。
3. 第一个收到的 `VIDEO_FRAME` 很可能是关键帧，其 payload 开头已包含 SPS/PPS，需一并送入 `MediaCodec`。
4. 后续每个关键帧都会重复携带 SPS/PPS， Android 端可按需重新配置 `MediaCodec`。
5. 关键帧标志在 `flags` bit0；payload 含 SPS/PPS 时 `flags` bit1 也为 1。
6. Android 端连接端口请填 **19421**。

## 需要主 Agent 合并或确认

1. 是否将 protocol v0 的 header 编解码正式写入 `src/protocol/` 供两端共享。
2. 是否要求 Mac Host 在发送 `VIDEO_CONFIG` 前至少等待并忽略 Android 的 `HELLO`（M1 暂不实现）。
3. TCP server 是否需要在本阶段就替换为 POSIX socket 双栈实现，还是留到 Android 联调前再做。

## 下一步建议

1. 用户在本地图形环境运行 `MacHostApp`，验证窗口、按钮、状态更新。
2. Android Agent 实现 `MediaCodec` + `SurfaceView` 解码显示。
3. 在 Mac 与 Android 联调前，把 TCP server 替换为双栈 POSIX socket server，确保局域网 IPv4 可连。
4. 端到端联调，验证 1280x800 30fps 基础画面。

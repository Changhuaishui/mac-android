# M1 Mac Host

M1 阶段最小 Mac 端 POC：采集现有屏幕 → H.264 编码 → TCP 发送给 Android Client。

## 技术栈

- Swift
- ScreenCaptureKit
- VideoToolbox
- Network.framework (TCP)
- 自定义 protocol v0

## 构建

```bash
cd src/mac-host
swift build
```

## 运行

```bash
swift run machost
# 或指定档位
swift run machost --width 1920 --height 1200 --fps 30 --bitrate 12000000 --port 19421
```

首次运行会触发 macOS **屏幕录制**权限提示，必须在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 Terminal / machost。

## 默认参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| width | 1280 | 输出宽度 |
| height | 800 | 输出高度 |
| fps | 30 | 目标帧率 |
| bitrate | 8_000_000 | 平均码率（bps） |
| port | 19421 | TCP 监听端口 |

## 协议 v0 行为

- 连接方向：Android Client 主动连接 Mac Host，Mac Host **不会主动发送 HELLO**。
- Android 连接后，Mac Host 先发送 `VIDEO_CONFIG`（UTF-8 JSON，不含二进制 SPS/PPS），然后发送 `VIDEO_FRAME`。
- `VIDEO_FRAME` payload 为 **Annex B byte stream**。
- 每个关键帧的 payload 内重复携带 SPS/PPS，并设置 `FLAG_KEYFRAME | FLAG_CONFIG`。
- 帧头字段：magic `MADS`、version `0`、大端、固定 32 字节。

## 默认参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| width | 1280 | 输出宽度 |
| height | 800 | 输出高度 |
| fps | 30 | 目标帧率 |
| bitrate | 8_000_000 | 平均码率（bps） |
| port | 19421 | TCP 监听端口；Android 端也需填 19421 |

## 日志

运行时会输出：

- 可采集 display 列表。
- 选中的主屏信息。
- TCP 连接/断开状态。
- 每秒 FPS、码率。
- 每帧编码耗时（ms）。
- 错误信息。

## 注意事项

- M1 不做虚拟显示、输入回传、Wi-Fi 发现、加密、菜单栏 UI。
- 默认只监听本机/局域网，不接公网。
- 断开后自动停止采集。
- M1 暂不解析 Android 发来的 HELLO，但 Mac Host 不会先发 HELLO。

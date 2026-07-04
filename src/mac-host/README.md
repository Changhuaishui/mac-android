# M1 Mac Host

M1 阶段最小 Mac 端 POC：采集现有屏幕 → H.264 编码 → TCP 发送给 Android Client。

本目录现在包含三个目标：

- `MacHostKit`：核心库（采集、编码、协议、TCP）。
- `MacHostCLI`：命令行可执行文件 `machost`。
- `MacHostApp`：SwiftUI 窗口 App `MacHostApp`。

## 技术栈

- Swift
- ScreenCaptureKit
- VideoToolbox
- Network.framework (TCP)
- SwiftUI
- 自定义 protocol v0

## 构建

```bash
cd src/mac-host
swift build
```

构建产物：

- `./.build/debug/machost`
- `./.build/debug/MacHostApp`

## 打包成可双击打开的 .app

```bash
cd src/mac-host
./package-app.sh
```

打包产物会放到 **`src/mac-host/dist/`**：

- `dist/MacHostApp.app`：可直接双击打开的 App bundle。
- `dist/MacHostApp.zip`：压缩包，方便拷贝或分享。

你可以把 `MacHostApp.app` 拖到「应用程序」文件夹，然后双击打开。

首次运行若提示「无法打开」或「无法验证开发者」，请在 Finder 中按住 `Control` 键点按 App，选择「打开」。

## 1. 可视化窗口 App（推荐日常使用）

```bash
./.build/debug/MacHostApp
```

或双击 `.build/MacHostApp.app`。

启动后会出现一个窗口，显示：

- 当前运行状态（已停止 / 监听中 / 已连接）。
- Android 上报的 current mode。
- 已选 profile（`balanced` / `hd60` / `detected-native-safe` / `detected-native`）。
- 实际输出分辨率 / FPS / 码率。
- 降级原因（如果发生降级）。
- 实时 FPS、码率、平均编码耗时。
- 最近日志。
- 「启动服务 / 停止服务」按钮。

首次运行需要在「系统设置 → 隐私与安全性 → 屏幕录制」中授权 `MacHostApp`。

## 2. 命令行 `machost`

### 本地 dump 自测（不等 Android）

```bash
./.build/debug/machost --dump /tmp/sample-annexb.h264 --dump-duration 5
```

验证文件：

```bash
xxd -l 16 /tmp/sample-annexb.h264
# 预期以 00 00 00 01 start code 开头
```

### 动态原生档自测（使用 fixture，不等 Android）

```bash
./.build/debug/machost \
  --profile detected-native-safe \
  --hello-fixture ../../测试资产/M1-解耦验证/hello-display-capabilities.example.json \
  --dump /tmp/native-safe.h264 --dump-duration 5
```

### TCP 模式

```bash
./.build/debug/machost
# 或指定 profile
./.build/debug/machost --profile detected-native-safe
# 或完全自定义参数
./.build/debug/machost --width 1920 --height 1200 --fps 30 --bitrate 12000000 --port 19421
```

Android 端连接端口请填 **19421**。

TCP server 现在同时监听 **IPv4 `0.0.0.0:19421`** 与 **IPv6 `[::]:19421`**，因此支持：

- 本机 `127.0.0.1` 或 `::1` 自测。
- `adb reverse tcp:19421 tcp:19421` 后真机连接 `127.0.0.1:19421`。
- 同一局域网内真机直接连接 Mac 的 IPv4 地址（如 `10.78.160.132:19421`）。

```bash
# 本机 IPv4 自测
nc -d 127.0.0.1 19421 > /tmp/capture.h264

# 局域网 IPv4（将 <mac-ip> 替换为 Mac 实际局域网地址）
nc -d <mac-ip> 19421 > /tmp/capture.h264
```

## 默认参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| profile | custom | 输出档位：balanced / hd60 / detected-native-safe / detected-native；未指定时使用显式 width/height/fps/bitrate |
| width | 1280 | 输出宽度（custom 档生效） |
| height | 800 | 输出高度（custom 档生效） |
| fps | 30 | 目标帧率（custom 档生效） |
| bitrate | 8_000_000 | 平均码率（custom 档生效） |
| port | 19421 | TCP 监听端口；Android 端也需填 19421 |
| dump-duration | 5 | dump 模式采集秒数 |
| hello-fixture | 无 | 从 JSON 文件加载 Android HELLO 用于自测 |

## 协议 v0 行为

- 连接方向：Android Client 主动连接 Mac Host，Mac Host **不会主动发送 HELLO**。
- Android 连接后，Mac Host **等待 Android 发来的 `HELLO`**，解析其中的 `display_capabilities`。
  - 若 5 秒内未收到 HELLO 或解析失败，则降级到 `hd60` 继续推流。
  - 收到 HELLO 后，按 `--profile` 与 `display_capabilities.current_mode.physical_width` / `physical_height` / `refresh_rate` 选择实际输出分辨率/FPS/码率。
  - 旧 fixture 中的 `width` / `height` 仍可作为兼容 fallback。
- Mac Host 发送 `VIDEO_CONFIG`（UTF-8 JSON，不含二进制 SPS/PPS），然后发送 `VIDEO_FRAME`。
- `VIDEO_FRAME` payload 为 **Annex B byte stream**。
- 每个关键帧的 payload 内重复携带 SPS/PPS，并设置 `FLAG_KEYFRAME | FLAG_CONFIG`。
- 帧头字段：magic `MADS`、version `0`、大端、固定 32 字节。

## 刷新率处理

`display_capabilities.current_mode.refresh_rate` 是浮点能力值，Mac Host 不会用 `== 60 / == 120 / == 144` 严格判断，而是按容差归一化：

```text
59.0  <= x <= 61.0  -> 60
89.0  <= x <= 91.0  -> 90
119.0 <= x <= 121.0 -> 120
143.0 <= x <= 145.0 -> 144
其他值              -> round(x)
```

- `detected-native-safe`：`selected_fps = min(normalized_fps, 60)`。
- `detected-native`：`selected_fps = normalized_fps`，超过 60fps 时标记降级警告。

## 码率估算

profile 档位的码率按以下公式估算：

```text
bitrate = clamp(width * height * fps * 0.08, 2_000_000, 40_000_000)  // bps
```

即每像素每帧 0.08 bits，下限 2 Mbps，上限 40 Mbps。

## 注意事项

- M1 不做虚拟显示、输入回传、Wi-Fi 发现、加密、菜单栏 UI。
- 默认只监听本机/局域网，不接公网。
- 断开后自动停止采集。
- Mac Host 已解析 Android 发来的 HELLO（含 `display_capabilities`），协议文档建议同步补充该字段。

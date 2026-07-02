# M1 AndroidClient Agent 提示词

你是 mac-android 项目的 Android 端实现 Agent。

目标设备是小米平板 6 Pro。你的任务是构建 M1 Android Client POC：连接 Mac Host，接收 protocol v0 视频帧，使用 MediaCodec 解码，并渲染到 SurfaceView。

你不能等待 Mac 端完成后才验证。必须先用 assets fixture 或 replay server 证明 Android 解码渲染链路可用。

## 允许修改

只允许修改：

- `src/android-client/`
- `agents/reports/`
- 与本任务直接相关的 `交付记录/` 文件

如需修改 `src/protocol/`、`设计/ADR/`、`设计/技术选型-M1.md`，只写建议，不直接改。

## 禁止修改

禁止修改：

- `src/mac-host/`
- `src/protocol/`，除非主 Agent 明确授权
- `AGENTS.md`
- M1 冻结技术选型
- 与 Android Client 无关的文档

## 技术约束

必须使用：

- Kotlin。
- Android 原生工程。
- MediaCodec。
- SurfaceView。
- TCP client。

M1 先横屏适配小米平板 6 Pro。

推荐显示档位：

- 起步：1280x800 30fps。
- 稳定后：1920x1200 30fps。
- 后续优化：1920x1200 60fps。

M1 不追求原生 2880x1800。

## 第一阶段实现目标

先做最小可验证链路：

1. 单 Activity。
2. SurfaceView 渲染区域。
3. 连接状态显示。
4. TCP client 连接 Mac Host。
5. 读取 protocol v0 frame。
6. 配置 MediaCodec H.264 decoder。
7. 解码到 Surface。
8. 显示 FPS 或基础统计。
9. 解码失败时显示可见错误。

## 解耦验证要求

必须支持至少一种无 Mac Host 验证路径：

```text
assets/sample-annexb.h264
→ MediaCodec
→ SurfaceView
```

以及后续：

```text
replay server
→ TCP client
→ protocol v0 frame
→ MediaCodec
→ SurfaceView
```

如果 fixture 或 replay server 尚未存在，先实现读取接口、解码模块和错误展示，并在报告中列明缺少的资产，不得停工等待 Mac。

## Android Studio / 模拟器卡点

M1 不依赖模拟器。

优先级：

1. 真实小米平板 6 Pro。
2. Gradle CLI `assembleDebug`。
3. Android Studio 打开工程。
4. 模拟器。

如果 Android Studio、Gradle 或模拟器下载卡住，仍然交付工程结构、关键 Kotlin 文件、Manifest、运行方式、未验证原因和下一步。

## H.264 要求

不要猜 Mac 端格式。

如果 Mac 端输出 Annex B：

- 以 Annex B byte stream 方式喂给 decoder。

如果 Mac 端输出 AVCC：

- 需要 `csd-0` / `csd-1` 或转换策略。
- 在报告中标明阻塞项。

## 不做

- 不做输入回传。
- 不做复杂 UI。
- 不做设备发现。
- 不做 Wi-Fi 自适应。
- 不做配对加密。
- 不做后台常驻服务。

## 验收

至少证明：

- App 能启动。
- Surface 生命周期处理明确。
- 能连接指定 Mac Host 地址。
- 能解析 protocol v0 frame。
- 能解码测试 H.264 流或 Mac Host 流。
- 解码失败不静默黑屏。
- 如果无法构建，必须说明是依赖下载、SDK、Gradle、设备授权还是其他问题。

## 交付

在 `agents/reports/M1-AndroidClient-Agent-报告.md` 写报告，格式：

```text
完成内容：
修改文件：
运行方式：
执行验证：
未验证内容：
目标设备适配：
MediaCodec 配置：
独立验证方式：
protocol v0 对接事项：
需要 Mac 端注意：
需要主 Agent 合并或确认：
下一步建议：
```

---
type: 验证交付
project: mac-android
requirement: M1 Android Client 接收解码 Surface 显示
status: 部分验证
updated: 2026-06-30
---

# 验证交付：M1 Android Client 接收解码 Surface 显示

## 1. 本次改动

- 解决的问题：M1 Android Client 侧缺少可接收 Mac Host 视频流并解码渲染的最小工程。
- 实际改动：
  - 新建 `src/android-client/` Gradle 工程。
  - 实现 TCP client、protocol v0 解析、MediaCodec 解码、SurfaceView 渲染、状态与 FPS 显示。
  - 编写 `src/android-client/README.md` 与 Agent 报告。
- 影响范围：仅 `src/android-client/`、`agents/reports/`、本交付记录。
- 明确未改动：`src/mac-host/`、`src/protocol/`、`AGENTS.md`、设计文档、M1 冻结技术选型。

## 2. 运行入口

- Mac Host：未涉及。
- Android Client：`src/android-client/app/src/main/java/com/macandroid/client/MainActivity.kt`
- Protocol：协议实现内嵌于 `Protocol.kt` 与 `TcpClient.kt`。
- 文档入口：`src/android-client/README.md`、`agents/reports/M1-AndroidClient-Agent-报告.md`。

## 3. 触发条件

- 前置环境：Android Studio 或命令行 Gradle、Android SDK 34、目标设备或模拟器。
- 必要权限：`INTERNET`、`ACCESS_NETWORK_STATE`（已在 AndroidManifest.xml 声明）。
- 连接方式：Android 与 Mac Host 在同一局域网，或通过 `adb reverse tcp:7878 tcp:7878` 使用 USB 调试网络。
- 操作步骤：
  1. 编译安装 APK。
  2. 启动 App，输入 Mac Host 地址与端口。
  3. 点击“连接”。
  4. 等待 `VIDEO_CONFIG` 与视频帧。

## 4. 验证步骤

1. `./gradlew assembleDebug` 编译通过。
2. `adb install app/build/outputs/apk/debug/app-debug.apk` 安装成功。
3. 启动 App，连接本地 H.264 测试 server 或 Mac Host。
4. 观察 SurfaceView 是否显示画面。
5. 观察右上角状态是否为“已连接”，左下角 FPS 是否更新。
6. 断开网络或停止 server，观察是否显示错误而不是静默黑屏。
7. 切换 Activity 到后台再返回，观察 Surface 重建后是否恢复渲染。

## 5. 预期结果

- Mac：与 Android 建立 TCP 连接，持续发送 protocol v0 视频帧。
- Android：成功解析消息、初始化解码器、渲染画面、显示 FPS。
- 网络：TCP 长连接稳定，PING/PONG 正常。
- 安全：仅使用局域网/USB 调试网络，不上传屏幕内容，不保存画面。

## 6. 已执行验证

| 层级 | 是否执行 | 结果 | 证据 |
|---|---|---|---|
| L0 现场与变更审计 | 是 | 通过 | 仅修改 `src/android-client/`、`agents/reports/`、交付记录，未越界。 |
| L1 静态验证 | 否 | 未验证 | 尚未运行 Android lint/ktlint。 |
| L2 构建验证 | 是 | 通过 | Android Studio / Gradle 执行 `:app:assembleDebug`，输出 `BUILD SUCCESSFUL in 20s`。 |
| L3 端到端 POC | 否 | 未验证 | Mac Host 尚未实现，无法联调。 |
| L4 真实设备体验 | 否 | 未验证 | 未连接小米平板 6 Pro 或模拟器。 |
| L5 安全验收 | 是 | 通过 | 未引入公网、云服务、账号、屏幕保存等越界行为。 |

## 7. 未验证内容

| 内容 | 原因 | 建议由谁验证 |
|---|---|---|
| APK 安装与启动 | 无模拟器/真实设备连接 | 主 Agent 或用户 |
| MediaCodec 解码 H.264 | 无法运行 App | 主 Agent 或用户 |
| 端到端 Mac Host 画面显示 | Mac Host 尚未实现 | 主 Agent 在 Mac 端完成后联调 |
| Surface 生命周期切换 | 无法运行 App | 主 Agent 或用户 |

## 8. 问题与修正

| 问题 | 证据 | 修正 | 是否需要进入长期规则 |
|---|---|---|---|
| AVCC 支持仅为实验性实现 | 当前代码在 `VideoDecoder` 中通过合并 SPS/PPS 到关键帧前处理 AVCC | 待 Mac 端确定输出格式后，若需 AVCC 则完善 csd-0/csd-1 路径 | 否，M1 优先 Annex B |
| AGP 8.9.0 要求 Gradle 8.11.1 | Android Studio 首次构建提示当前 Gradle 8.10.2 低于最低要求 | 已将 wrapper `distributionUrl` 调整为 Gradle 8.11.1 | 否，属于工具版本对齐 |
| Kotlin daemon 因 JDK 26 fallback | 构建日志显示 `IllegalArgumentException: 26.0.1` 后使用 fallback 编译 | 非阻塞，最终 `BUILD SUCCESSFUL`；如持续出现可执行 `./gradlew --stop` 或统一 Android Studio Gradle JDK | 否，环境差异 |
| Java compiler 提示 source/target 8 已过时 | 构建日志显示 JDK 21 下 Java 8 target deprecated warning | 非阻塞，不影响当前构建；可后续单独升级 Java/Kotlin target | 否，后续构建清理任务处理 |

## 9. 最终状态

- 代码状态：已完成 Android Client M1 最小实现，构建验证通过。
- 技术验证状态：L2 通过；L3/L4 未验证（未运行设备/模拟器，尚未端到端联调）。
- 人工验收状态：待主 Agent 复核协议字段与代码边界。
- 遗留风险：
  - AVCC 路径未充分验证。
  - 未在真实设备上测试小米平板 6 Pro 的 MediaCodec 能力。
  - 端到端延迟、发热、连续运行稳定性均未验证。

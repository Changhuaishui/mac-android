---
type: 任务卡
project: mac-android
status: 部分验证
owner_agent: AndroidClient Agent
updated: 2026-06-30
---

# 当前任务：M1 Android Client 接收解码 Surface 显示

## 1. 用户原话

> 然后就是我会派多个 agent 干活，一个是构建 mac 端的，一个是构建 Android 端的。Android 我用的是是小米平板 6pro。
>
> 来源：`任务记录/2026-06-30-M1-功能拆解与分布任务.md`

## 2. 本轮目标

- 构建 Android Client 最小可运行 POC。
- 使用 TCP 长连接连接 Mac Host。
- 按 protocol v0 接收视频帧。
- 使用 MediaCodec 解码 H.264 并渲染到 SurfaceView。
- 显示连接状态、解码错误和基础 FPS 统计。

明确不做：

- 输入回传。
- 复杂 UI。
- 设备发现。
- Wi-Fi 自适应。
- 配对加密。
- 后台常驻服务。

## 3. 技术范围

- Android Client：`src/android-client/` 最小 Gradle 工程，单 Activity + SurfaceView。
- Mac Host：本任务不修改。
- Protocol：内嵌实现 protocol v0 解析与打包，遵守 `设计/技术选型-M1.md` 约定。
- 文档：`src/android-client/README.md`、`agents/reports/M1-AndroidClient-Agent-报告.md`、本任务卡、交付记录。
- 测试：`./gradlew :app:assembleDebug` 已通过；设备安装、MediaCodec 实机解码和端到端联调仍未验证。

## 4. 当前事实

- 已确认：M1 使用 Kotlin + MediaCodec + SurfaceView + TCP client。
- 已确认：目标设备小米平板 6 Pro，M1 先横屏 16:10。
- 已确认：H.264 优先 Annex B byte stream。
- 当前假设：Mac Host 会发送 `VIDEO_CONFIG` 后再发 `VIDEO_FRAME`。
- 已验证：Android Studio / Gradle `:app:assembleDebug` 构建通过。
- 尚未验证：APK 安装、MediaCodec 解码、端到端画面显示。

## 5. 操作边界

### 允许

- 修改 `src/android-client/`。
- 修改 `agents/reports/`。
- 修改与本任务直接相关的 `交付记录/`。

### 禁止

- 修改 `src/mac-host/`。
- 修改 `src/protocol/`（发现协议问题时写建议）。
- 修改 `AGENTS.md`、M1 冻结技术选型、无关文档。
- 安装依赖、连接真实设备、提交代码，除非用户明确授权。

### 需要再次确认

- 是否允许在小米平板 6 Pro 上安装 APK 验证。
- 是否由主 Agent 统一维护 `src/protocol/`。

## 6. 计划

1. [x] 创建 `src/android-client/` 最小 Gradle 工程。
2. [x] 实现 TCP client 与 protocol v0 解析。
3. [x] 实现 MediaCodec 解码到 SurfaceView。
4. [x] 添加连接状态、FPS 与错误显示。
5. [x] 按 protocol v0 矫正：VIDEO_CONFIG `stream_format`、端口 19421、HELLO 字段、Annex B 直接喂帧。
6. [x] 调整 Gradle/AGP/Kotlin 版本，创建 gradlew wrapper 以便用户本地构建。
7. [x] 用户本地执行 `./gradlew :app:assembleDebug` 并反馈结果。
8. [ ] 用本地 H.264 测试流验证解码渲染。
9. [ ] 与 Mac Host 联调端到端画面显示。

## 7. 完成定义

- [x] `src/android-client/` 包含可编译运行的最小工程。
- [x] 能解析 protocol v0 视频帧。
- [x] 能用 MediaCodec 解码 H.264 并渲染到 SurfaceView。
- [x] 连接状态和解码错误可见。
- [x] VIDEO_CONFIG 按 protocol v0 读取 `stream_format` 并统一为 "annex_b"。
- [x] 默认端口改为 19421，README/界面一致。
- [x] HELLO payload 使用 protocol v0 标准字段。
- [x] VIDEO_FRAME payload 直接按 Annex B 喂给 MediaCodec，不拼接缓存的配置帧。
- [x] `./gradlew :app:assembleDebug` 由用户本地执行并反馈结果。
- [ ] 已执行本地 H.264 测试流验证。
- [ ] 已执行真实 Mac Host / 小米平板 6 Pro 端到端验证。
- [x] 未验证内容及原因已列明。

## 8. 验证要求

- 必须执行：
  - `./gradlew assembleDebug` 编译通过。
  - 在模拟器或真实设备上安装并启动。
  - 能解析本地测试 server 发送的 protocol v0 消息。
- 可选执行：
  - 在小米平板 6 Pro 上运行并记录 MediaCodec 能力。
- 必须人工检查：
  - Surface 生命周期切换是否不静默黑屏。
  - 解码失败时是否有可见错误。
- 禁止执行：
  - 在未授权设备上安装 APK。
  - 将接收的画面保存或上传。

## 9. 当前进度

- 当前状态：部分验证
- 已完成：工程骨架、TCP client、protocol v0 矫正、MediaCodec 解码、UI 状态、Gradle wrapper 与版本调整、Android Studio / Gradle 构建验证、文档与报告。
- 正在处理：无。
- 尚未处理：设备验证、端到端联调。
- 阻塞项：无构建阻塞；设备安装和实机画面验证仍需用户授权/执行。

## 10. 交接

- 最后可靠结论：Android Client M1 最小实现已完成，`./gradlew :app:assembleDebug` 构建通过，待设备运行与端到端验证。
- 已修改文件：
  - `src/android-client/` 全部工程文件
  - `agents/reports/M1-AndroidClient-Agent-报告.md`
  - `交付记录/2026-06-30-M1-AndroidClient-接收解码Surface显示.md`
  - `任务记录/2026-06-30-M1-AndroidClient-接收解码Surface显示.md`
- 已执行命令：`./gradlew :app:assembleDebug`。
- 已获得证据：Android Studio / Gradle 输出 `BUILD SUCCESSFUL in 20s`；Kotlin daemon fallback 与 Java source/target 8 warning 均未阻塞构建。
- 不确定事项：
  - Mac Host 实际输出 H.264 格式（Annex B 还是 AVCC）。
  - 是否需要在 `src/protocol/` 中统一协议定义。
- 下一位 Agent 应先读取：
  - `AGENTS.md`
  - `README.md`
  - `当前工作台.md`
  - `设计/系统架构.md`
  - `设计/技术选型-M1.md`
  - `agents/prompts/02-M1-AndroidClient-Agent.md`
  - `agents/reports/M1-AndroidClient-Agent-报告.md`

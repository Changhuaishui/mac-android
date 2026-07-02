---
type: 验证交付
project: mac-android
requirement: M1 Android Client 接收解码 Surface 显示
status: 待验证
updated: 2026-06-30
---

# 验证交付：M1 Android Client 接收解码 Surface 显示

## 1. 本次改动

- 解决的问题：Android Client 协议实现与 `设计/protocol-v0.md` 不完全一致，需要按 v0 矫正并确保可编译。
- 实际改动：
  - `VIDEO_CONFIG` 改为读取 `stream_format`，兼容 `format`，内部统一为 `"annex_b"`。
  - 默认端口改为 `19421`。
  - `HELLO` payload 使用 protocol v0 标准字段。
  - `VIDEO_FRAME` 直接按 Annex B 喂给 MediaCodec，删除 AVCC 分支与配置帧拼接逻辑。
  - 调整 AGP 8.9.0 + Kotlin 1.9.24 + Gradle 8.10.2，新建 `gradlew`。
- 影响范围：仅 `src/android-client/`、Agent 报告、任务卡、交付记录。
- 明确未改动：`src/mac-host/`、`src/protocol/`、`AGENTS.md`、设计文档、技术选型。

## 2. 运行入口

- Android Client：`src/android-client/app/src/main/java/com/macandroid/client/MainActivity.kt`
- 构建命令：`cd src/android-client && ./gradlew :app:assembleDebug`
- 文档入口：`src/android-client/README.md`、`agents/reports/M1-AndroidClient-Agent-报告.md`

## 3. 触发条件

- 前置环境：Android SDK、JDK、本地 Gradle wrapper 下载完成。
- 必要权限：`INTERNET`、`ACCESS_NETWORK_STATE`。
- 连接方式：Android 与 Mac Host 在同一局域网，或 `adb reverse tcp:19421 tcp:19421`。
- 操作步骤：
  1. 执行 `./gradlew :app:assembleDebug`。
  2. 安装 APK 到设备/模拟器。
  3. 启动 App，输入 Mac Host 地址与端口 `19421`，点击连接。
  4. 等待 `VIDEO_CONFIG` 与 `VIDEO_FRAME`。

## 4. 验证步骤

1. `./gradlew :app:assembleDebug` 编译通过，生成 APK。
2. `adb install app/build/outputs/apk/debug/app-debug.apk` 成功。
3. 启动 App 连接 Mac Host。
4. 观察右上角状态变为“已连接”，左下角 FPS 更新。
5. 观察 SurfaceView 显示 Mac 画面。
6. 断开网络或停止 Mac Host，观察是否显示错误而不静默黑屏。
7. 切换 Activity 到后台再返回，观察 Surface 重建后是否恢复渲染。

## 5. 预期结果

- Android Client 成功解析 protocol v0 消息。
- MediaCodec 初始化为 `VIDEO_CONFIG` 指定宽高。
- Annex B byte stream 正常解码到 SurfaceView。
- 失败时 UI 显示错误，不黑屏。

## 6. 已执行验证

| 层级 | 是否执行 | 结果 | 证据 |
|---|---|---|---|
| L0 现场与变更审计 | 是 | 通过 | 仅修改 `src/android-client/` 与相关文档，未越界。 |
| L1 静态验证 | 是 | 部分通过 | 检查了 import、端口、协议字段、生命周期处理；未运行 lint。 |
| L2 构建验证 | 否 | 未验证 | 本环境首次构建因 AGP/Gradle 不兼容失败；已升级配置，用户本地执行。 |
| L3 端到端 POC | 否 | 未验证 | 未成功构建 APK。 |
| L4 真实设备体验 | 否 | 未验证 | 未连接小米平板 6 Pro。 |
| L5 安全验收 | 是 | 通过 | 未引入公网、云服务、账号、屏幕保存等越界行为。 |

## 7. 未验证内容

| 内容 | 原因 | 建议由谁验证 |
|---|---|---|
| `./gradlew :app:assembleDebug` | 用户本地执行，本环境下载依赖超时 | 用户 |
| APK 安装启动 | 无设备/模拟器 | 用户 |
| MediaCodec 解码 | 未运行 App | 用户 |
| 端到端 Mac → Android 画面 | 未构建成功 | 用户 |
| Surface 生命周期 | 未运行 App | 用户 |
| 小米平板 6 Pro 实际表现 | 未连接设备 | 用户 |

## 8. 问题与修正

| 问题 | 证据 | 修正 | 是否需要进入长期规则 |
|---|---|---|---|
| AGP 8.2.0 与 Gradle 9.3.0 不兼容 | 构建报错 `org.gradle.api.internal.HasConvention` | AGP 升级到 8.9.0，Gradle wrapper 改为 8.10.2，Kotlin 改为 1.9.24 | 否，属于构建环境适配 |
| 缺少 gradlew | 无法执行 `./gradlew` | 新建 `gradlew` 与 `gradle-wrapper.properties` | 否，工程必备 |

## 9. 最终状态

- 代码状态：已完成 protocol v0 矫正与编译配置调整。
- 技术验证状态：未验证（构建由用户本地执行）。
- 人工验收状态：待用户反馈构建结果。
- 遗留风险：
  - 未实际编译通过。
  - 未在真实设备验证 MediaCodec 行为。
  - 未与 Mac Host 进行端到端联调。

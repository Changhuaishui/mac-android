---
type: 验证交付
project: mac-android
requirement: M1 Android Client asset fixture 本地播放
status: 待验证
updated: 2026-06-30
---

# 验证交付：M1 Android Client asset fixture 本地播放

## 1. 本次改动

- 解决的问题：Android Client 无法在不连接 Mac Host 的情况下独立验证解码渲染链路。
- 实际改动：
  - 生成 `sample-annexb.h264` fixture（1280x800，2s，30fps，baseline，移动条纹）。
  - 放置 fixture 到 Android assets 与项目测试资产目录。
  - 新增 `AssetPlayer.kt` 从 assets 读取 Annex B 并拆分 access unit。
  - 在 `MainActivity` 增加"播放本地 fixture"入口。
  - 复用 `VideoDecoder` 解码到 SurfaceView。
  - 更新 README 与测试资产文档。
- 影响范围：仅 `src/android-client/`、测试资产、Agent 报告、任务卡、交付记录。
- 明确未改动：`src/mac-host/`、`src/protocol/`、`AGENTS.md`、设计文档、技术选型。

## 2. 运行入口

- Android Client：`src/android-client/app/src/main/java/com/macandroid/client/MainActivity.kt`
- Asset 播放器：`src/android-client/app/src/main/java/com/macandroid/client/AssetPlayer.kt`
- Fixture：`src/android-client/app/src/main/assets/sample-annexb.h264`
- 构建命令：`cd src/android-client && ./gradlew :app:assembleDebug`
- 文档入口：`src/android-client/README.md`、`agents/reports/M1-AndroidClient-Agent-报告.md`

## 3. 触发条件

- 前置环境：Android SDK、JDK、Gradle wrapper 已下载完成。
- 必要权限：`INTERNET`、`ACCESS_NETWORK_STATE`。
- 操作步骤：
  1. 执行 `./gradlew :app:assembleDebug`。
  2. 安装 APK 到设备/模拟器。
  3. 启动 App，点击"播放本地 fixture"。
  4. 观察 SurfaceView 是否显示移动条纹画面。

## 4. 验证步骤

1. `./gradlew :app:assembleDebug` 编译通过，生成 APK。
2. 检查 APK 中是否包含 `assets/sample-annexb.h264`。
3. `adb install app/build/outputs/apk/debug/app-debug.apk` 成功。
4. 启动 App，点击"播放本地 fixture"。
5. 观察右上角状态与左下角 FPS。
6. 观察 SurfaceView 是否显示画面。
7. 点击"停止 fixture"，确认播放停止。
8. 切换 Activity 到后台再返回，确认无崩溃。

## 5. 预期结果

- 编译通过。
- APK 包含 fixture asset。
- App 启动后无需输入地址即可播放本地 fixture。
- MediaCodec 成功解码 Annex B 并渲染到 SurfaceView。
- 解码失败时 UI 显示错误，不黑屏。

## 6. 已执行验证

| 层级 | 是否执行 | 结果 | 证据 |
|---|---|---|---|
| L0 现场与变更审计 | 是 | 通过 | 仅修改 `src/android-client/` 与相关文档，未越界。 |
| L1 静态验证 | 是 | 通过 | 检查了 import、生命周期、access unit 拆分逻辑。 |
| L2 构建验证 | 是 | 通过 | `./gradlew :app:assembleDebug` BUILD SUCCESSFUL；APK 12MB，asset 已打包。 |
| L3 端到端 POC | 否 | 未验证 | 未在设备/模拟器运行。 |
| L4 真实设备体验 | 否 | 未验证 | 未连接小米平板 6 Pro。 |
| L5 安全验收 | 是 | 通过 | fixture 为无敏感测试图；未引入公网、云、账号、屏幕保存。 |

## 7. 未验证内容

| 内容 | 原因 | 建议由谁验证 |
|---|---|---|
| APK 安装启动 | 无设备/模拟器 | 用户 |
| AssetPlayer 实际渲染画面 | 无法运行 App | 用户 |
| MediaCodec 解码 fixture | 无法运行 App | 用户 |
| Surface 生命周期切换 | 未运行 App | 用户 |
| 小米平板 6 Pro 实际表现 | 未连接设备 | 用户 |

## 8. 问题与修正

| 问题 | 证据 | 修正 | 是否需要进入长期规则 |
|---|---|---|---|
| Kotlin daemon 因 JDK 26 fallback | 构建日志显示 `IllegalArgumentException: 26.0.1` | 非阻塞，fallback 编译成功 | 否，构建环境差异 |
| Java compiler 提示 source/target 8 已过时 | 构建日志显示 Java 26 deprecated warning | 非阻塞，不影响当前构建 | 否，可后续升级到 Java 11/17 |

## 9. 最终状态

- 代码状态：已完成本地 asset fixture 播放入口。
- 技术验证状态：L2 构建通过；L3/L4 未验证（无运行环境）。
- 人工验收状态：待用户在设备/模拟器上验证画面。
- 遗留风险：
  - 未在真实设备验证 MediaCodec 解码效果。
  - `AssetPlayer` 的 access unit 拆分算法基于简单 NALU 类型判断，极端 H.264 结构可能需要调整。

---
type: 任务卡
project: mac-android
status: 待验证
owner_agent: AndroidClient Agent
updated: 2026-06-30
---

# 当前任务：M1 Android Client asset fixture 本地播放

## 1. 用户原话

> Android Agent 跟进
> 目标：加 asset fixture 播放入口：
> assets/sample-annexb.h264
> 本地读取 → MediaCodec → SurfaceView
> 不等 Mac Host

## 2. 本轮目标

- 在 Android Client 增加本地 asset fixture 播放入口。
- 从 `assets/sample-annexb.h264` 读取 Annex B byte stream。
- 直接喂给 `VideoDecoder` / `MediaCodec`。
- 渲染到 `SurfaceView`。
- 不需要 Mac Host 即可验证解码渲染链路。

明确不做：

- 不改 Mac Host。
- 不改 protocol v0 定义。
- 不做网络发现或连接。
- 不做输入回传。
- 不连接真实小米平板（除非用户另行授权）。

## 3. 技术范围

- Android Client：`src/android-client/app/src/main/assets/`、`MainActivity`、新增 `AssetPlayer`。
- Protocol：复用现有 `VideoDecoder` 和 Annex B 解码路径；不新增协议消息。
- 文档：`src/android-client/README.md`、Agent 报告、交付记录、任务卡。
- 测试：生成/放置 fixture，执行 `./gradlew :app:assembleDebug`。

## 4. 当前事实

- 已确认：M1 使用 H.264 Annex B byte stream。
- 已确认：`sample-annexb.h264` 已生成并放置到 `src/android-client/app/src/main/assets/`。
- 已确认：`VideoDecoder` 已支持 Annex B 直接解码。
- 当前假设：asset 文件大小约 490KB，2 秒 30fps，关键帧间隔 30。
- 尚未验证：asset 在 Android MediaCodec 上的实际解码效果。

## 5. 操作边界

### 允许

- 修改 `src/android-client/`。
- 修改 `agents/reports/`。
- 修改与本任务直接相关的 `交付记录/`、`任务记录/`、`测试资产/`。

### 禁止

- 修改 `src/mac-host/`、`src/protocol/`、`AGENTS.md`、M1 技术选型。
- 安装依赖到系统全局环境。
- 连接真实设备或安装 APK，除非用户授权。

### 需要再次确认

- 是否允许在小米平板 6 Pro 上运行验证（本任务不主动执行）。

## 6. 计划

1. [x] 生成无敏感内容的 `sample-annexb.h264` fixture。
2. [x] 将 fixture 放置到 `src/android-client/app/src/main/assets/` 和 `测试资产/M1-解耦验证/`。
3. [x] 实现 `AssetPlayer`：从 assets 读取 Annex B 帧，拆分 access unit。
4. [x] 在 `MainActivity` 添加"播放本地 fixture"入口。
5. [x] 复用 `VideoDecoder` 解码到 SurfaceView。
6. [x] 执行 `./gradlew :app:assembleDebug`。
7. [x] 更新文档与报告。

## 7. 完成定义

- [x] `assets/sample-annexb.h264` 存在且非空。
- [x] App 能从 assets 读取该文件并按 Annex B access unit 拆分。
- [x] 本地 fixture 能送入 `VideoDecoder`。
- [x] UI 提供显式入口触发本地播放。
- [x] `./gradlew :app:assembleDebug` 编译通过。
- [x] APK 已打包 asset。
- [ ] 真实设备/模拟器播放画面未验证。
- [x] 未验证内容及原因已列明。

## 8. 验证要求

- 必须执行：
  - `./gradlew :app:assembleDebug` 编译通过。
  - asset 文件随 APK 打包（检查 APK assets）。
- 可选执行：
  - 在真实设备/模拟器上播放 fixture 并观察画面。
- 必须人工检查：
  - 解码失败时是否显示错误而不是静默黑屏。
- 禁止执行：
  - 在未授权设备上安装 APK。

## 9. 当前进度

- 当前状态：待验证
- 已完成：fixture 生成与放置、`AssetPlayer` 与 UI 入口实现、构建验证、文档与报告。
- 正在处理：无。
- 尚未处理：真实设备/模拟器画面验证。
- 阻塞项：无运行环境。

## 10. 交接

- 最后可靠结论：fixture 已就绪，等待 Android Client 本地播放代码实现。
- 已修改文件：
  - `测试资产/M1-解耦验证/sample-annexb.h264`
  - `测试资产/M1-解耦验证/README.md`
  - `测试资产/M1-解耦验证/sample-annexb-generation.md`
  - `src/android-client/app/src/main/assets/sample-annexb.h264`
  - 本任务卡
- 已执行命令：
  - 使用隔离 venv 生成 sample-annexb.h264。
- 已获得证据：
  - fixture 文件大小约 490KB，已复制到 assets 目录。
- 不确定事项：
  - asset 在小米平板 6 Pro 上的实际解码效果。
- 下一位 Agent 应先读取：
  - `AGENTS.md`
  - `当前工作台.md`
  - `设计/protocol-v0.md`
  - `设计/M1-解耦验证策略.md`
  - `测试资产/M1-解耦验证/README.md`
  - `agents/reports/M1-AndroidClient-Agent-报告.md`
  - 本任务卡

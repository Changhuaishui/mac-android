---
type: 任务卡
project: mac-android
status: 已完成（代码 + 构建）；App UI 交互待本机图形环境验证
owner_agent: Codex (M1 MacHost Agent)
updated: 2026-07-01
---

# M1 Mac Host 可视化窗口 App

## 用户原话

> 先做出一个 mac 的可视化 app

确认后形态：窗口 App（Dock 图标），核心功能先做 **状态展示 + 启停按钮**。

## 本轮目标

1. 把现有 `src/mac-host` 重构为库 + CLI + App 三层结构。
2. 新增 macOS SwiftUI 窗口 App：
   - 显示当前运行状态（监听中 / 已连接 / 已停止）。
   - 显示 FPS、码率、平均编码耗时。
   - 显示当前分辨率、帧率、码率配置。
   - 提供「启动服务 / 停止服务」按钮。
   - 底部显示最近日志（连接、错误、启停事件）。
3. 保留原有 CLI 可执行文件 `machost` 不变。
4. 构建通过，App 能正常启动并控制服务。

## 明确不做

- 不替换现有 `machost` CLI 核心逻辑。
- 不做菜单栏模式、设置面板、分辨率切换（后续迭代）。
- 不做 Android 端改动。
- 不做虚拟显示、输入回传。
- 不引入外部 UI 框架（SwiftUI 原生）。

## 已确认事实

- M1 固定：Swift + ScreenCaptureKit + VideoToolbox H.264 + TCP 长连接。
- 现有 CLI 已通过 `--dump` 和 IPv6 dump client 验证。
- TCP server 当前 IPv6-only，但 App 阶段先关注本机窗口控制，IPv4/双栈放到下一步。

## 验收标准

- [ ] `swift build` 同时生成 `machost` CLI 和 `MacHostApp` 可执行文件。
- [ ] 运行 `MacHostApp` 出现窗口，显示当前配置和停止状态。
- [ ] 点击「启动服务」后状态变为监听中，日志区显示监听信息。
- [ ] 用 IPv6 dump client 连接后状态变为已连接，FPS/码率/编码耗时开始更新。
- [ ] 点击「停止服务」后停止采集，状态恢复已停止。
- [ ] CLI 模式 `./.build/debug/machost --dump ...` 仍然可用。

## 交付物

- `src/mac-host/` 重构后的 SwiftPM 工程（含 `MacHostKit`、`MacHostCLI`、`MacHostApp`）。
- `agents/reports/M1-MacHost-Agent-报告.md`（更新）。
- `交付记录/2026-07-01-M1-MacHost-App-验证说明.md`。

## 下一步

- 接入 Android Client 联调。
- 把 TCP server 替换为双栈 POSIX socket server。

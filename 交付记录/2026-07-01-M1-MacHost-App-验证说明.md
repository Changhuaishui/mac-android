# M1 Mac Host 可视化窗口 App 验证说明

日期：2026-07-01
任务：M1 Mac Host 可视化窗口 App（状态展示 + 启停按钮）
Agent：Codex (M1 MacHost Agent)

## 验证目标

1. SwiftPM 工程拆分为 `MacHostKit` + `MacHostCLI` + `MacHostApp`。
2. `MacHostApp` 编译通过并能启动。
3. 窗口显示状态、FPS、码率、编码耗时、日志、启停按钮。
4. 原有 `machost` CLI 的 `--dump` 模式仍然可用。

## 验证环境

- macOS（当前开发机）
- Swift 5.9+ / Xcode Command Line Tools
- 已授予 `machost` 屏幕录制权限
- 无 Android Client 连接
- 当前环境无法显示真实 GUI，App 界面交互通过代码审查验证

## 验证结果

| 验证项 | 结果 | 说明 |
|---|---|---|
| `swift build` 编译通过 | 通过 | 生成 `machost` 和 `MacHostApp` 两个可执行文件 |
| `MacHostApp` 可执行文件能启动 | 通过 | `./.build/debug/MacHostApp` 进程存在且未崩溃 |
| `MacHostApp` 窗口 UI 代码审查 | 通过 | 包含状态徽章、FPS/码率/编码耗时、日志列表、启停按钮 |
| `./package-app.sh` 生成 `.app` bundle | 通过 | `.build/MacHostApp.app` 已生成并 ad-hoc 签名 |
| `.app` bundle 信息正确 | 通过 | Info.plist、可执行文件、签名检查通过 |
| `dist/MacHostApp.app` 和 `dist/MacHostApp.zip` | 通过 | 产物已复制/压缩到 `src/mac-host/dist/` |
| `MacHostApp` 点击启动后状态变为监听中 | 未验证 | 当前环境无法点击按钮；代码路径通过审查 |
| `MacHostApp` 连接 dump client 后状态变为已连接 | 未验证 | 当前环境无法点击按钮；依赖上一条 |
| `machost --dump` 模式 | 通过 | 3 秒生成约 373KB 有效 Annex B 文件 |
| `machost` TCP 模式 | 通过（IPv6） | 见上一份交付记录 |

## 复现命令

```bash
cd src/mac-host
swift build

# 窗口 App
./.build/debug/MacHostApp

# CLI dump 自测
./.build/debug/machost --dump /tmp/sample-annexb.h264 --dump-duration 3
xxd -l 16 /tmp/sample-annexb.h264
```

## 未验证原因

1. 当前运行环境为无图形界面的 shell，无法对 SwiftUI 窗口进行鼠标点击和视觉确认。
2. 因此「启动按钮点击 → 服务启动 → dump client 连接 → 状态更新」的完整 UI 交互链路未实际执行。

## 结论

- **工程重构完成，`MacHostApp` 编译通过，代码审查通过。**
- **CLI 模式功能保持正常。**
- **App 真实 UI 交互需在用户本机图形环境下手动验证。**

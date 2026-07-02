# ADR-001：M1 使用原生 Mac 与原生 Android

日期：2026-06-30

## 状态

建议采纳

## 决策

M1 使用 Swift 开发 Mac Host，使用 Kotlin 开发 Android Client。

## 原因

- Mac 端需要直接调用 ScreenCaptureKit 和 VideoToolbox。
- Android 端需要直接使用 MediaCodec 和 SurfaceView。
- 原生路线能减少跨平台框架带来的调试层。

## 替代方案

- Flutter。
- Electron。
- Rust/C++ 跨平台核心。

## 暂不选择原因

- Flutter/Electron 不适合第一阶段调试底层视频链路。
- Rust/C++ 可以后续用于协议或性能热点，但不适合作为第一步。

## 重新评估条件

- 原生 UI 工作量明显拖慢进度。
- 协议或编码链路出现可复用跨端核心需求。


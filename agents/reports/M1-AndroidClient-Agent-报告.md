# M1 Android Client Agent 报告

日期：2026-06-30

## 完成内容

- 生成无敏感内容的 H.264 Annex B fixture：`sample-annexb.h264`（1280x800，2s，30fps，baseline profile，移动条纹测试图）。
- 将 fixture 放置到：
  - `src/android-client/app/src/main/assets/sample-annexb.h264`（随 APK 打包）
  - `测试资产/M1-解耦验证/sample-annexb.h264`（项目级测试资产）
- 新增 `AssetPlayer.kt`：从 assets 读取 Annex B byte stream，按 access unit 拆分，按 30fps 节奏送入 `VideoDecoder`。
- 修改 `MainActivity.kt`：增加"播放本地 fixture"和"停止 fixture"按钮，支持不等 Mac Host 直接验证解码渲染。
- 修改布局与字符串资源，增加本地播放入口。
- 更新 `src/android-client/README.md` 与测试资产文档，说明 fixture 生成方式与本地播放步骤。
- 调整 Gradle 构建配置：AGP 8.9.0 + Kotlin 1.9.24 + Gradle 8.10.2，并新建 `gradlew` wrapper。

## 修改文件

- `src/android-client/app/src/main/java/com/macandroid/client/AssetPlayer.kt`（新建）
- `src/android-client/app/src/main/java/com/macandroid/client/MainActivity.kt`
- `src/android-client/app/src/main/res/layout/activity_main.xml`
- `src/android-client/app/src/main/res/values/strings.xml`
- `src/android-client/app/src/main/assets/sample-annexb.h264`（新建）
- `src/android-client/build.gradle.kts`
- `src/android-client/gradle/wrapper/gradle-wrapper.properties`（新建）
- `src/android-client/gradlew`（新建）
- `src/android-client/README.md`
- `测试资产/M1-解耦验证/sample-annexb.h264`（新建）
- `测试资产/M1-解耦验证/README.md`
- `测试资产/M1-解耦验证/sample-annexb-generation.md`
- `任务记录/2026-06-30-M1-AndroidClient-asset-fixture播放.md`（新建）
- `交付记录/2026-06-30-M1-AndroidClient-asset-fixture播放.md`（新建）
- `当前工作台.md`

未修改：

- `src/mac-host/`
- `src/protocol/`
- `AGENTS.md`
- `设计/技术选型-M1.md`
- `设计/ADR/`
- `src/android-client/app/src/main/java/com/macandroid/client/Protocol.kt`
- `src/android-client/app/src/main/java/com/macandroid/client/TcpClient.kt`
- `src/android-client/app/src/main/java/com/macandroid/client/VideoDecoder.kt`

## 协议对齐情况

本轮 asset fixture 播放不经过网络，但复用了 protocol v0 的 Annex B 解码路径：

| 协议项 | 当前实现 | 对齐状态 |
|---|---|---|
| H.264 格式 | `AssetPlayer` 读取 Annex B byte stream 并拆分 access unit | 对齐 |
| SPS/PPS 携带方式 | fixture 关键帧 payload 自带 SPS/PPS + IDR | 对齐 |
| `FLAG_KEYFRAME` / `FLAG_CONFIG` | `AssetPlayer` 在喂给 decoder 时设置 | 对齐 |
| 视频参数 | fixture 固定 1280x800 @ 30fps，与 `VIDEO_CONFIG` 默认值一致 | 对齐 |
| TCP / protocol v0 消息 | 本地播放不触发 | 不适用 |

`AssetPlayer` 输出的每个 access unit 直接对应一个 `VIDEO_FRAME` payload，便于后续与 TCP 路径统一验证。

## Surface/MediaCodec 生命周期处理

- 点击"播放本地 fixture"时：
  - 先断开 TCP（避免双路竞争）。
  - 检查 `hasSurface`，若未就绪显示错误。
  - 用固定 1280x800 / 30fps 配置 `VideoDecoder`。
  - 启动 `AssetPlayer` 后台线程读取 asset 并喂帧。
- 点击"停止 fixture"、Activity `onDestroy`、Surface `surfaceDestroyed` 时都会停止 `AssetPlayer` 并释放 `VideoDecoder`。
- `VideoDecoder` 解码失败仍通过 `onDecoderError` 回调显示错误并请求关键帧，不允许静默黑屏。
- `AssetPlayer` 使用 `System.nanoTime()` 控制播放节奏，目标 30fps，若解码慢则自然降速。

## 构建结果

- 执行命令：`cd src/android-client && ./gradlew :app:assembleDebug`
- 结果：**通过**
- APK 路径：`src/android-client/app/build/outputs/apk/debug/app-debug.apk`
- APK 大小：约 12MB
- asset 打包确认：`assets/sample-annexb.h264` 已包含在 APK 内，大小 501972 字节。
- 警告（非阻塞）：
  - 系统 JDK 为 26，Kotlin daemon 因版本解析问题 fallback 到非 daemon 编译，最终成功。
  - Java compiler 提示 source/target 8 已过时。

## 未验证内容

| 内容 | 原因 |
|---|---|
| APK 在真实设备/模拟器安装启动 | 未连接小米平板 6 Pro，未启动模拟器 |
| `AssetPlayer` 实际渲染画面 | 无法运行 App |
| MediaCodec 对 fixture 的解码效果 | 无法运行 App |
| 连续循环播放稳定性 | 未运行 App |
| Surface 生命周期切换 | 未运行 App |

## 下一步需要 Mac Agent 配合的点

1. **H.264 格式确认**：Mac Host 输出必须是 Annex B byte stream；若 VideoToolbox 输出 AVCC，需在 Mac 端转换。
2. **SPS/PPS 发送时机**：Mac Host 必须在连接开始后的第一个关键帧前或关键帧 payload 内包含 SPS/PPS，并设置 `FLAG_KEYFRAME | FLAG_CONFIG`。
3. **端口一致**：Mac Host 监听 `19421`。
4. **HELLO 处理**：Mac Host 收到 Android `HELLO` 后再发送 `VIDEO_CONFIG` 和视频帧。
5. **关键帧请求响应**：Mac Host 收到 ERROR `request_keyframe` 后应尽快发送带 SPS/PPS 的关键帧。
6. **fixture 对比**：Mac Host 的 capture-to-file 模式（如有）可生成同规格 Annex B 文件，与 Android asset 做逐字节或播放器对比。

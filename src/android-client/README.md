# Android Client (M1)

M1 阶段最小可验证 Android Client：通过 TCP 接收 protocol v0 视频帧，使用 MediaCodec 解码到 SurfaceView。

## 工程结构

```text
src/android-client/
├── app/src/main/java/com/macandroid/client/
│   ├── MainActivity.kt   # 主界面、连接控制、本地 fixture 播放、状态显示
│   ├── Protocol.kt       # protocol v0 消息解析与 VIDEO_CONFIG
│   ├── TcpClient.kt      # TCP 长连接与后台读取线程
│   ├── VideoDecoder.kt   # MediaCodec H.264 解码到 Surface
│   └── AssetPlayer.kt    # 本地 assets H.264 fixture 播放入口
├── app/src/main/assets/
│   └── sample-annexb.h264  # 无 Mac Host 时的解码测试 fixture
├── app/src/main/res/     # 布局、字符串、主题、启动图标
├── build.gradle.kts
├── settings.gradle.kts
└── gradle.properties
```

## 构建要求

- Android Studio Hedgehog (2023.1.1) 或更新版本，或命令行 Gradle。
- Android SDK 34（compileSdk）。
- minSdk 29，目标设备小米平板 6 Pro（Android 13+）。

## 构建与安装

### 命令行

```bash
cd src/android-client
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

### Android Studio

1. 打开 `src/android-client` 目录。
2. 同步 Gradle。
3. 选择运行设备，点击 Run。

## 运行方式

### 方式一：连接 Mac Host

1. 确保 Mac Host 已启动并监听 TCP 端口（默认 `19421`）。
2. 确保 Android 设备与 Mac 在同一局域网，或通过 USB 调试网络连接。推荐小米平板 6 Pro 先走 USB：
   ```bash
   ./start-adb-reverse.sh
   ```
   等价于：
   ```bash
   adb reverse tcp:19421 tcp:19421
   ```
3. 启动 App。USB reverse 模式下地址填 `127.0.0.1`，端口填 `19421`，点击“连接”。
4. 首次连接时会收到 `VIDEO_CONFIG`，解码器据此初始化。
5. 画面渲染到全屏 SurfaceView；左上角显示地址/端口，右上角显示连接状态，左下角显示 FPS 与队列长度。

### 方式二：本地 fixture 播放（不等 Mac Host）

1. 构建并安装 APK。
2. 启动 App，直接点击“播放本地 fixture”。
3. App 从 `assets/sample-annexb.h264` 读取 Annex B byte stream，拆分为 access unit 后送入 `MediaCodec`。
4. 画面渲染到 SurfaceView，右上角显示当前播放状态与帧数。

### 方式三：查看设备显示能力

1. 构建并安装 APK。
2. 启动 App，右上角状态文本下方会显示当前 Display Mode、推荐原生候选和 Surface 尺寸。
3. 无需连接 Mac Host，能力识别为纯本地读取。
4. 通过 adb logcat 抓取完整 JSON：
   ```bash
   adb logcat -s MacDisplayCapabilities:D
   ```

## H.264 格式约定

- v0 协议固定使用 **Annex B byte stream**（NALU 以 `00 00 00 01` 或 `00 00 01` 分隔）。
- `VIDEO_CONFIG` 只描述视频流格式，不携带二进制 SPS/PPS。
- SPS/PPS 由 `VIDEO_FRAME` 的关键帧 payload 携带；含 SPS/PPS 的帧必须设置 `FLAG_CONFIG`。
- Android 端直接把每个 `VIDEO_FRAME` payload 喂给 MediaCodec，不做额外拼接。

## 当前限制

- M1 只做视频接收与显示，不做输入回传。
- 固定横屏，未做竖屏适配。
- 不做设备发现，需手动输入 Mac Host 地址。
- 不做 Wi-Fi 自适应、后台常驻、配对加密。

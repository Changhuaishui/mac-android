# sample-annexb.h264 生成方式

`sample-annexb.h264` 是 Android 端无 Mac Host 验证的固定输入：

```text
assets/sample-annexb.h264
→ MediaCodec
→ SurfaceView
```

## 格式要求

- Codec：H.264 / AVC。
- Stream format：Annex B byte stream。
- Start code：`00 00 00 01` 或 `00 00 01`。
- 分辨率：首选 `1280x800`。
- FPS：首选 `30`。
- 时长：建议 `5s` 到 `10s`。
- 内容：不得包含真实屏幕、账号、聊天、文档或其他敏感信息。
- 内容建议：测试图、纯色、移动条纹、时间戳。

## 推荐生成方式：ffmpeg 测试图

如果本机已有 `ffmpeg`，使用公开测试图生成：

```bash
mkdir -p 测试资产/M1-解耦验证
ffmpeg \
  -f lavfi \
  -i testsrc2=size=1280x800:rate=30 \
  -t 5 \
  -c:v libx264 \
  -profile:v baseline \
  -level 3.1 \
  -pix_fmt yuv420p \
  -x264-params keyint=30:min-keyint=30:scenecut=0:repeat-headers=1 \
  -an \
  -f h264 \
  测试资产/M1-解耦验证/sample-annexb.h264
```

说明：

- `-f h264` 输出裸 H.264 byte stream。
- `repeat-headers=1` 让关键帧前重复 SPS/PPS。
- `testsrc2` 不含真实用户内容。

## 可选生成方式：Mac Host capture-to-file

Mac Host 后续可以增加只用于本地验证的 capture-to-file 模式：

```text
ScreenCaptureKit
→ VideoToolbox H.264
→ AVCC to Annex B
→ sample-annexb.h264
```

注意：

- 该方式可能采集真实屏幕，只能本地使用。
- 不得把含真实屏幕内容的文件提交、上传或作为长期 fixture。
- 如果要提交 fixture，必须使用无敏感测试图或公开素材。

## 校验方式

### 文件存在与大小

```bash
ls -lh 测试资产/M1-解耦验证/sample-annexb.h264
```

结果应为非 0 字节。

### start code 检查

```bash
xxd -l 32 测试资产/M1-解耦验证/sample-annexb.h264
```

开头或前若干字节内应看到：

```text
00 00 00 01
```

### ffprobe 检查

如果本机已有 `ffprobe`：

```bash
ffprobe -hide_banner 测试资产/M1-解耦验证/sample-annexb.h264
```

应能识别为 H.264，分辨率接近 `1280x800`。

## Android 放置方式

Android Agent 可复制 fixture 到：

```text
src/android-client/app/src/main/assets/sample-annexb.h264
```

然后实现：

```text
assets.open("sample-annexb.h264")
→ Annex B access unit reader
→ MediaCodec queueInputBuffer
→ SurfaceView
```

## 状态

- 已生成二进制 fixture：`测试资产/M1-解耦验证/sample-annexb.h264` 和 `src/android-client/app/src/main/assets/sample-annexb.h264`。
- 生成工具：Python 3 + PyAV（隔离 venv，未安装到系统）。
- 内容：1280x800 移动条纹测试图，无真实屏幕、账号、聊天、文档等敏感信息。
- 规格：H.264 / AVC，Annex B byte stream，baseline profile，level 3.1，30fps，2 秒，关键帧间隔 30。

生成脚本（参考）：

```python
import av
import numpy as np
import os

width, height = 1280, 800
fps = 30
frames = fps * 2
output = "sample-annexb.h264"

container = av.open(output, 'w', format='h264')
stream = container.add_stream('libx264', rate=fps)
stream.width = width
stream.height = height
stream.pix_fmt = 'yuv420p'
stream.options = {
    'profile': 'baseline',
    'level': '3.1',
    'x264opts': 'repeat-headers=1:keyint=30:min-keyint=30',
}

for i in range(frames):
    img = np.zeros((height, width, 3), dtype=np.uint8)
    stripe_w = 80
    offset = (i * 10) % (stripe_w * 2)
    for x in range(width):
        color = 40 + ((x + offset) // stripe_w % 2) * 160
        img[:, x] = [color, color // 2, 255 - color]
    frame = av.VideoFrame.from_ndarray(img, format='rgb24')
    for packet in stream.encode(frame):
        container.mux(packet)

for packet in stream.encode():
    container.mux(packet)

container.close()
```

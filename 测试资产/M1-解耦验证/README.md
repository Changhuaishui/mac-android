# M1 解耦验证测试资产

本目录用于保存 M1 独立验证材料，让 Mac 端和 Android 端不用互相等待。

## 目标资产

| 资产 | 用途 | 状态 |
|---|---|---|
| `sample-annexb.h264` | Android 端本地解码测试 | 已生成（1280x800，2s，30fps，baseline，移动条纹） |
| `sample-annexb-generation.md` | `sample-annexb.h264` 生成方式 | 已完成 |
| `sample-avcc-notes.md` | 如果 Mac 输出 AVCC，记录转换策略 | 待确认 |
| `protocol-frame-example.bin` | protocol v0 最小帧样例 | 待生成 |
| `protocol-frame-example.md` | 样例字段解释 | 已完成 |
| `replay-server-notes.md` | 假 Mac Host 发送策略 | 已完成 |
| `dump-client-notes.md` | 假 Android Client 接收策略 | 已完成 |
| `hello-display-capabilities.example.json` | 带 `display_capabilities` 的 Android HELLO 示例 | 已完成 |

## 规则

- 不保存真实屏幕敏感内容。
- 测试视频优先使用纯色、移动条纹、时间戳或公开无敏感画面。
- H.264 fixture 必须注明 Annex B 或 AVCC。
- 每个 fixture 都要说明生成方式。
- 当前 M1 首选 Annex B。`VIDEO_CONFIG` 使用 UTF-8 JSON；SPS/PPS 随关键帧 `VIDEO_FRAME` payload 携带。
- `HELLO.display_capabilities` 是可选扩展字段；缺失时 Mac Host 必须降级到 `balanced` 或 `hd60`。
- `hello-display-capabilities.example.json` 只是协议 fixture，不代表真实小米平板运行结果；真实验证必须来自 Android 运行时读取。

## 文档入口

- `sample-annexb-generation.md`：说明如何生成无敏感内容的 Annex B fixture。
- `protocol-frame-example.md`：说明最小 protocol v0 消息序列和 header 字段。
- `replay-server-notes.md`：说明假 Mac Host 如何向 Android Client 发送 fixture 流。
- `dump-client-notes.md`：说明假 Android Client 如何验证 Mac Host TCP 输出。
- `hello-display-capabilities.example.json`：说明 Android `HELLO` 如何携带显示能力，供 Mac Host `--hello-fixture` 或解析单元测试使用。

## 最小验收

Android 端拿到 `sample-annexb.h264` 后，应该能在没有 Mac Host 的情况下验证：

```text
assets/sample-annexb.h264
→ MediaCodec
→ SurfaceView
```

Mac 端拿到 dump client 后，应该能在没有 Android App 的情况下验证：

```text
ScreenCaptureKit
→ VideoToolbox
→ TCP server
→ dump client
```

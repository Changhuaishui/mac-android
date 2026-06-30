# Source Layout

当前仅预留源码目录，M1 开始后再填充具体工程。

```text
src/
    mac-host/        macOS Host，采集、编码、传输、输入注入
    android-client/  Android Client，连接、解码、渲染、输入
    protocol/        帧头、控制消息、输入事件、测试样例
```

初始约束：

- 先实现最小闭环。
- 协议结构先简单，保留版本号。
- 不在 POC 阶段引入云服务或账号系统。


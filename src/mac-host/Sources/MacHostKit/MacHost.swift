import Foundation
import ScreenCaptureKit

public struct Configuration {
    public var width: Int = 1280
    public var height: Int = 800
    public var fps: Double = 30.0
    public var bitrate: Int = 8_000_000
    public var port: UInt16 = 19421
    public var dumpPath: String?
    public var dumpDuration: Double = 5.0
    /// 输出档位。nil 或 .custom 表示使用上面的显式 width/height/fps/bitrate。
    public var profile: Profile = .custom
    public var helloFixturePath: String?

    public init() {}
}

public struct MacHostStats {
    public let fps: Double
    public let bitrateMbps: Double
    public let avgEncodeMs: Double

    public init(fps: Double, bitrateMbps: Double, avgEncodeMs: Double) {
        self.fps = fps
        self.bitrateMbps = bitrateMbps
        self.avgEncodeMs = avgEncodeMs
    }
}

public protocol MacHostStatusDelegate: AnyObject {
    func hostDidStartListening(_ host: MacHost)
    func hostDidReceiveHello(_ host: MacHost, capabilities: DisplayCapabilities?)
    func hostDidSelectProfile(_ host: MacHost, profile: Profile, output: StreamConfiguration)
    func hostDidAcceptConnection(_ host: MacHost)
    func hostDidLoseConnection(_ host: MacHost, error: Error?)
    func hostDidStop(_ host: MacHost)
}

public final class MacHost {
    public let config: Configuration
    public let logger = StatsLogger()
    public weak var statusDelegate: MacHostStatusDelegate?

    public private(set) var selectedProfile: Profile = .custom
    public private(set) var capabilities: DisplayCapabilities?
    public private(set) var streamConfig: StreamConfiguration?

    private var server: TCPServer!
    private var captureSession: CaptureSession!
    private var encoder: Encoder!
    private var protocolSequence: UInt64 = 0
    private var isRunning = false
    private var latestParameterSets: H264ParameterSets?
    private var dumpFileHandle: FileHandle?
    private var helloTimeoutWorkItem: DispatchWorkItem?

    public init(configuration: Configuration) {
        self.config = configuration
    }

    public func setLoggerDelegate(_ delegate: LoggerDelegate?) {
        logger.delegate = delegate
    }

    public func start() async -> Bool {
        logger.logState("当前 profile: \(config.profile)")
        if let dumpPath = config.dumpPath {
            let caps = loadHelloFixtureIfNeeded()
            capabilities = caps
            let (profile, output) = resolveProfileAndOutput(capabilities: caps)
            selectedProfile = profile
            streamConfig = output
            statusDelegate?.hostDidSelectProfile(self, profile: profile, output: output)
            return startDump(path: dumpPath, duration: config.dumpDuration, output: output)
        }

        server = TCPServer(port: config.port)
        server.delegate = self
        do {
            try server.start()
            logger.logState("TCP server 监听 0.0.0.0:\(config.port)")
        } catch {
            logger.logError("启动 TCP server 失败: \(error.localizedDescription)")
            return false
        }

        logger.logState("等待 Android client 连接...")
        statusDelegate?.hostDidStartListening(self)
        return true
    }

    public func stop() {
        cancelHelloTimeout()
        if config.dumpPath != nil {
            stopDump()
            logger.logState("dump 已停止")
        } else {
            stopStreaming()
            logger.logState("服务已停止")
        }
        statusDelegate?.hostDidStop(self)
    }

    // MARK: - Profile / output resolution

    private func resolveProfileAndOutput(capabilities: DisplayCapabilities?) -> (Profile, StreamConfiguration) {
        let profile = config.profile
        if profile == .custom {
            let output = StreamConfiguration(
                width: config.width,
                height: config.height,
                fps: config.fps,
                bitrate: config.bitrate
            )
            return (profile, output)
        }
        let output = ProfileResolver.resolve(profile: profile, capabilities: capabilities)
        return (profile, output)
    }

    private func loadHelloFixtureIfNeeded() -> DisplayCapabilities? {
        guard let path = config.helloFixturePath else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let hello = try JSONDecoder().decode(HelloMessage.self, from: data)
            if let caps = hello.displayCapabilities {
                let modeSummary = caps.currentMode?.summary ?? "null"
                logger.logState("从 fixture 加载 HELLO: current_mode=\(modeSummary)")
                return caps
            } else {
                logger.logError("HELLO fixture 缺少 display_capabilities")
                return nil
            }
        } catch {
            logger.logError("加载 HELLO fixture 失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseHello(data: Data) -> DisplayCapabilities? {
        let rawJSON = String(data: data.prefix(2048), encoding: .utf8) ?? "<non-utf8>"
        do {
            let hello = try JSONDecoder().decode(HelloMessage.self, from: data)
            if let caps = hello.displayCapabilities {
                let modeSummary = caps.currentMode?.summary ?? "null"
                logger.logState("收到 Android HELLO: 原始 JSON = \(rawJSON)")
                logger.logState("收到 Android HELLO: current_mode=\(modeSummary)")
                return caps
            } else {
                logger.logError("Android HELLO 缺少 display_capabilities, 原始 JSON = \(rawJSON)")
                return nil
            }
        } catch {
            logger.logError("解析 Android HELLO 失败: error = \(error.localizedDescription), 原始 JSON = \(rawJSON)")
            return nil
        }
    }

    // MARK: - Streaming

    private func startStreaming(output: StreamConfiguration) {
        guard !isRunning else { return }
        isRunning = true
        logger.logState("client 已连接，开始采集与编码：\(output.summary)")
        if output.rawRefreshRate != nil || output.normalizedFPS != nil {
            logger.logState("刷新率选择：\(output.refreshRateSummary)")
        }
        if let reason = output.degradationReason {
            logger.logState("降级原因: \(reason)")
        }

        captureSession = CaptureSession(width: output.width, height: output.height, fps: output.fps)
        encoder = Encoder(width: Int32(output.width), height: Int32(output.height), fps: output.fps, bitrate: output.bitrate)
        encoder.delegate = self
        if let error = encoder.start() {
            let errorText = "encoder_start_failed: \(error.localizedDescription)"
            logger.logError("启动编码器失败: \(error.localizedDescription)")
            sendError(errorText)
            isRunning = false
            stopStreaming()
            statusDelegate?.hostDidStop(self)
            return
        }

        captureSession.delegate = self

        Task {
            do {
                try await captureSession.start()
                logger.logState("屏幕采集已启动")
            } catch {
                let errorText = "capture_start_failed: \(error.localizedDescription)"
                logger.logError("启动屏幕采集失败: \(error.localizedDescription)")
                self.sendError(errorText)
                self.stopStreaming()
                self.statusDelegate?.hostDidStop(self)
            }
        }
    }

    private func startDump(path: String, duration: Double, output: StreamConfiguration) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        logger.logState("进入 dump 模式：\(output.summary)，输出文件: \(path)，采集 \(duration) 秒")
        if output.rawRefreshRate != nil || output.normalizedFPS != nil {
            logger.logState("刷新率选择：\(output.refreshRateSummary)")
        }
        if let reason = output.degradationReason {
            logger.logState("降级原因: \(reason)")
        }

        FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            logger.logError("无法创建 dump 文件: \(path)")
            isRunning = false
            return false
        }
        dumpFileHandle = handle

        captureSession = CaptureSession(width: output.width, height: output.height, fps: output.fps)
        encoder = Encoder(width: Int32(output.width), height: Int32(output.height), fps: output.fps, bitrate: output.bitrate)
        encoder.delegate = self
        if let error = encoder.start() {
            logger.logError("启动编码器失败: \(error.localizedDescription)")
            isRunning = false
            return false
        }

        captureSession.delegate = self

        Task {
            do {
                try await captureSession.start()
                logger.logState("屏幕采集已启动")
            } catch {
                logger.logError("启动屏幕采集失败: \(error.localizedDescription)")
                self.stopDump()
                self.statusDelegate?.hostDidStop(self)
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self.stopDump()
            logger.logState("dump 完成，文件: \(path)")
            exit(0)
        }

        statusDelegate?.hostDidStartListening(self)
        return true
    }

    private func stopDump() {
        guard isRunning else { return }
        isRunning = false
        captureSession?.stop()
        encoder?.stop { [weak self] in
            self?.logger.logState("编码器已停止")
        }
        dumpFileHandle?.closeFile()
        dumpFileHandle = nil
    }

    private func stopStreaming() {
        guard isRunning else { return }
        isRunning = false
        logger.logState("停止采集与编码")
        captureSession?.stop()
        encoder?.stop { [weak self] in
            self?.logger.logState("编码器已停止")
        }
    }

    // MARK: - HELLO timeout

    private func startHelloTimeout() {
        cancelHelloTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.logger.logError("等待 HELLO 超时（5 秒），按无能力信息降级")
            let (profile, output) = self.resolveProfileAndOutput(capabilities: nil)
            self.selectedProfile = profile
            self.streamConfig = output
            self.statusDelegate?.hostDidSelectProfile(self, profile: profile, output: output)
            self.startStreaming(output: output)
            self.statusDelegate?.hostDidAcceptConnection(self)
        }
        helloTimeoutWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func cancelHelloTimeout() {
        helloTimeoutWorkItem?.cancel()
        helloTimeoutWorkItem = nil
    }

    // MARK: - Protocol helpers

    private func sendVideoConfig(parameterSets: H264ParameterSets) {
        latestParameterSets = parameterSets
        let json = """
        {"codec":"h264","stream_format":"annex_b","width":\(streamConfig?.width ?? config.width),"height":\(streamConfig?.height ?? config.height),"fps":\(Int(streamConfig?.fps ?? config.fps)),"bitrate_bps":\(streamConfig?.bitrate ?? config.bitrate),"sps_pps_policy":"repeat_before_keyframe","timestamp_unit":"ns"}
        """
        let payload = Data(json.utf8)
        let header = ProtocolHeader(
            type: .videoConfig,
            sequence: nextProtocolSequence(),
            timestampNs: 0,
            flags: ProtocolFlags.config,
            payloadLength: UInt32(payload.count)
        )
        var packet = header.encode()
        packet.append(payload)
        server.send(packet)
        logger.logState("发送 VIDEO_CONFIG JSON (payload=\(payload.count) bytes)")
    }

    private func sendVideoFrame(data: Data, flags: UInt32, sequence: UInt64, timestampNs: UInt64, encodeDurationMs: Double) {
        let header = ProtocolHeader(
            type: .videoFrame,
            sequence: nextProtocolSequence(),
            timestampNs: timestampNs,
            flags: flags,
            payloadLength: UInt32(data.count)
        )
        var packet = header.encode()
        packet.append(data)
        server.send(packet)
        logger.logFrame(encodedBytes: data.count, encodeDurationMs: encodeDurationMs)
    }

    private func sendError(_ text: String) {
        let payload = Data(text.utf8)
        let header = ProtocolHeader(
            type: .error,
            sequence: nextProtocolSequence(),
            timestampNs: 0,
            flags: 0,
            payloadLength: UInt32(payload.count)
        )
        var packet = header.encode()
        packet.append(payload)
        server.send(packet)
        logger.logState("发送 ERROR 消息: \(text)")
    }

    private func nextProtocolSequence() -> UInt64 {
        protocolSequence += 1
        return protocolSequence
    }
}

// MARK: - HELLO payload helper

private struct HelloMessage: Codable {
    let displayCapabilities: DisplayCapabilities?

    enum CodingKeys: String, CodingKey {
        case displayCapabilities = "display_capabilities"
    }
}

// MARK: - TCPServerDelegate

extension MacHost: TCPServerDelegate {
    func serverDidAcceptConnection(_ server: TCPServer) {
        logger.logState("TCP client 已连接，等待 HELLO...")
        startHelloTimeout()
    }

    func serverDidReceiveHello(_ server: TCPServer, data: Data) {
        cancelHelloTimeout()
        guard !isRunning else {
            logger.logState("收到迟到的 Android HELLO，流已启动，忽略")
            return
        }
        let caps = parseHello(data: data)
        capabilities = caps
        statusDelegate?.hostDidReceiveHello(self, capabilities: caps)

        let (profile, output) = resolveProfileAndOutput(capabilities: caps)
        selectedProfile = profile
        streamConfig = output
        statusDelegate?.hostDidSelectProfile(self, profile: profile, output: output)

        startStreaming(output: output)
        statusDelegate?.hostDidAcceptConnection(self)
    }

    func serverDidLoseConnection(_ server: TCPServer, error: Error?) {
        cancelHelloTimeout()
        if let error = error {
            logger.logError("TCP 连接丢失: \(error.localizedDescription)")
        } else {
            logger.logState("TCP client 断开")
        }
        stopStreaming()
        statusDelegate?.hostDidLoseConnection(self, error: error)
    }
}

// MARK: - CaptureSessionDelegate

extension MacHost: CaptureSessionDelegate {
    func captureSession(_ session: CaptureSession, didOutput sampleBuffer: CMSampleBuffer) {
        encoder?.encode(sampleBuffer)
    }

    func captureSession(_ session: CaptureSession, didFailWith error: Error) {
        logger.logError("屏幕采集错误: \(error.localizedDescription)")
        stopStreaming()
        statusDelegate?.hostDidStop(self)
    }
}

// MARK: - EncoderDelegate

extension MacHost: EncoderDelegate {
    func encoder(_ encoder: Encoder, didOutputParameterSets parameterSets: H264ParameterSets) {
        latestParameterSets = parameterSets
        if config.dumpPath == nil {
            sendVideoConfig(parameterSets: parameterSets)
        }
    }

    func encoder(_ encoder: Encoder, didOutputAnnexBFrame data: Data, isKeyframe: Bool, sequence: UInt64, timestampNs: UInt64, encodeDurationMs: Double) {
        logger.logEncode(frameSequence: sequence, durationMs: encodeDurationMs, isKeyframe: isKeyframe)

        var payload = data
        var flags: UInt32 = 0
        if isKeyframe {
            flags |= ProtocolFlags.keyframe
            if let parameterSets = latestParameterSets {
                flags |= ProtocolFlags.config
                payload = parameterSets.annexBData + data
            }
        }

        if let handle = dumpFileHandle {
            handle.write(payload)
            return
        }

        sendVideoFrame(data: payload, flags: flags, sequence: sequence, timestampNs: timestampNs, encodeDurationMs: encodeDurationMs)
    }
}

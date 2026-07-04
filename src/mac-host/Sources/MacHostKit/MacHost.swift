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
    /// 本地事件注入测试文件路径；设置时不启动 TCP 和采集。
    public var injectTestPath: String?
    /// 跳过输入注入前的 Accessibility 权限检查（仅调试用）。
    public var skipInputPermissionCheck: Bool = false
    /// 虚拟显示器 POC 探针模式；设置时不启动 TCP 和采集。
    public var virtualDisplayProbe: Bool = false
    /// 虚拟显示器 POC 采集帧输出路径。
    public var virtualDisplayProbeOutputPath: String?
    /// M3.2：使用虚拟显示器作为采集源。false 则回退到 M1 镜像主屏。
    public var useVirtualDisplay: Bool = true

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
    private var inputInjector: InputInjector!
    private var coordinateMapper: CoordinateMapper!
    private var virtualDisplay: CGVirtualDisplayBackend?
    private var protocolSequence: UInt64 = 0
    private var isRunning = false
    private var latestParameterSets: H264ParameterSets?
    private var dumpFileHandle: FileHandle?
    private var helloTimeoutWorkItem: DispatchWorkItem?
    private var accessibilityChecked = false

    public init(configuration: Configuration) {
        self.config = configuration
    }

    public func setLoggerDelegate(_ delegate: LoggerDelegate?) {
        logger.delegate = delegate
    }

    public func start() async -> Bool {
        logger.logState("当前 profile: \(config.profile)")

        if let injectPath = config.injectTestPath {
            return await runInjectTest(path: injectPath)
        }

        if config.virtualDisplayProbe {
            return await runVirtualDisplayProbe()
        }

        if !config.skipInputPermissionCheck {
            accessibilityChecked = AccessibilityPermission.check(prompt: true)
            if !accessibilityChecked {
                logger.logError(AccessibilityPermission.guidance)
            } else {
                logger.logState("辅助功能权限已授予")
            }
        } else {
            logger.logState("跳过辅助功能权限检查（调试模式）")
        }

        setupInputInjector()

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

    private func runInjectTest(path: String) async -> Bool {
        if !config.skipInputPermissionCheck && !AccessibilityPermission.check(prompt: true) {
            logger.logError(AccessibilityPermission.guidance)
            return false
        }
        setupInputInjector()

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let events = try JSONDecoder().decode([InjectTestEvent].self, from: data)
            logger.logState("注入测试模式：读取 \(events.count) 条事件")
            for event in events {
                if event.delayMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(event.delayMs) * 1_000_000)
                }
                let inputEvent = event.toInputEvent()
                if let error = inputInjector.inject(inputEvent) {
                    logger.logError("注入失败: \(error.localizedDescription)")
                }
            }
            logger.logState("注入测试完成")
        } catch {
            logger.logError("读取注入测试文件失败: \(error.localizedDescription)")
            return false
        }

        statusDelegate?.hostDidStop(self)
        return true
    }

    private func runVirtualDisplayProbe() async -> Bool {
        let backend = VirtualDisplayProvider.preferredBackend()
        logger.logState("虚拟显示器 POC：preferred backend = \(backend)")

        for (name, available) in VirtualDisplayProvider.availabilityReport() {
            logger.logState("后端可用性: \(name) = \(available ? "可用" : "不可用")")
        }

        guard backend != .none else {
            logger.logError("当前系统没有可用虚拟显示器后端")
            logger.logState(DriverKitProbe.report())
            statusDelegate?.hostDidStop(self)
            return false
        }

        let vdisplayConfig = VirtualDisplayConfiguration(
            width: config.width,
            height: config.height,
            refreshRate: config.fps,
            name: "MacAndroid Probe"
        )
        guard let vdisplay = VirtualDisplayProvider.create(configuration: vdisplayConfig, logger: { [weak self] message, isError in
            if isError {
                self?.logger.logError(message)
            } else {
                self?.logger.logState(message)
            }
        }) else {
            logger.logError("无法创建虚拟显示器实例")
            statusDelegate?.hostDidStop(self)
            return false
        }

        let result = await vdisplay.runProbe(captureOutputPath: config.virtualDisplayProbeOutputPath)

        for message in result.messages {
            logger.logState(message)
        }

        if result.success {
            logger.logState("POC 成功: displayID=\(result.displayID.map { String($0) } ?? "nil"), 系统识别=\(result.systemDetected), 采集=\(result.captureSucceeded), 路径=\(result.capturePath ?? "nil")")
        } else {
            logger.logError("POC 失败: \(result.error?.description ?? "未知错误")")
            logger.logState(DriverKitProbe.report())
        }

        vdisplay.stop()
        statusDelegate?.hostDidStop(self)
        return result.success
    }

    private func setupInputInjector(displayID: CGDirectDisplayID? = nil) {
        coordinateMapper = CoordinateMapper(displayID: displayID)
        inputInjector = InputInjector(mapper: coordinateMapper, logger: logger)
        logger.logState("输入注入器已初始化，目标显示器: \(coordinateMapper.targetDisplayID), bounds: \(coordinateMapper.displayBounds)")
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
        inputInjector?.reset()
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

    // MARK: - Virtual display

    /// 若配置启用虚拟显示器，则创建并返回其 displayID；否则返回 nil（使用主屏）。
    private func setupVirtualDisplay(output: StreamConfiguration) -> CGDirectDisplayID? {
        guard config.useVirtualDisplay else {
            logger.logState("使用主屏作为采集源（--mirror 模式）")
            return nil
        }

        let vdisplayConfig = VirtualDisplayConfiguration(
            width: output.width,
            height: output.height,
            refreshRate: output.fps,
            name: "MacAndroid Virtual Display"
        )
        let backend = CGVirtualDisplayBackend(configuration: vdisplayConfig) { [weak self] message, isError in
            if isError {
                self?.logger.logError(message)
            } else {
                self?.logger.logState(message)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resultDisplayID: CGDirectDisplayID?
        var resultError: Error?

        Task.detached {
            do {
                try await backend.start()
                resultDisplayID = backend.displayID
            } catch {
                resultError = error
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 8)
        if waitResult == .timedOut {
            logger.logError("虚拟显示器注册超时，回退到主屏采集")
            return nil
        }
        if let error = resultError {
            logger.logError("创建虚拟显示器失败: \(error.localizedDescription)，回退到主屏采集")
            return nil
        }

        virtualDisplay = backend
        setupInputInjector(displayID: resultDisplayID)
        logger.logState("虚拟显示器已创建并作为采集源，displayID=\(resultDisplayID.map { String($0) } ?? "nil")")
        return resultDisplayID
    }

    private func teardownVirtualDisplay() {
        virtualDisplay?.stop()
        virtualDisplay = nil
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

        let targetDisplayID = setupVirtualDisplay(output: output)

        captureSession = CaptureSession(width: output.width, height: output.height, fps: output.fps)
        encoder = Encoder(width: Int32(output.width), height: Int32(output.height), fps: output.fps, bitrate: output.bitrate)
        encoder.delegate = self
        if let error = encoder.start() {
            let errorText = "encoder_start_failed: \(error.localizedDescription)"
            logger.logError("启动编码器失败: \(error.localizedDescription)")
            sendError(errorText)
            isRunning = false
            teardownVirtualDisplay()
            stopStreaming()
            statusDelegate?.hostDidStop(self)
            return
        }

        captureSession.delegate = self

        Task {
            do {
                try await captureSession.start(targetDisplayID: targetDisplayID)
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

        let targetDisplayID = setupVirtualDisplay(output: output)

        captureSession = CaptureSession(width: output.width, height: output.height, fps: output.fps)
        encoder = Encoder(width: Int32(output.width), height: Int32(output.height), fps: output.fps, bitrate: output.bitrate)
        encoder.delegate = self
        if let error = encoder.start() {
            logger.logError("启动编码器失败: \(error.localizedDescription)")
            isRunning = false
            teardownVirtualDisplay()
            return false
        }

        captureSession.delegate = self

        Task {
            do {
                try await captureSession.start(targetDisplayID: targetDisplayID)
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
        teardownVirtualDisplay()
    }

    private func stopStreaming() {
        guard isRunning else { return }
        isRunning = false
        logger.logState("停止采集与编码")
        captureSession?.stop()
        encoder?.stop { [weak self] in
            self?.logger.logState("编码器已停止")
        }
        teardownVirtualDisplay()
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

// MARK: - Inject test helper

private struct InjectTestEvent: Codable {
    let eventType: String
    let pointerId: Int?
    let normalizedX: Double?
    let normalizedY: Double?
    let pressure: Double?
    let keyCode: Int?
    let modifiers: [String]?
    let wheelDeltaX: Double?
    let wheelDeltaY: Double?
    let delayMs: UInt64

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case pointerId = "pointer_id"
        case normalizedX = "normalized_x"
        case normalizedY = "normalized_y"
        case pressure
        case keyCode = "key_code"
        case modifiers
        case wheelDeltaX = "wheel_delta_x"
        case wheelDeltaY = "wheel_delta_y"
        case delayMs = "delay_ms"
    }

    /// 兼容 Android Client 当前字段名。
    enum AndroidCodingKeys: String, CodingKey {
        case eventType = "type"
        case pointerId = "pointer_id"
        case normalizedX = "x"
        case normalizedY = "y"
        case pressure
        case keyCode = "key_code"
        case modifiers = "meta_state"
        case wheelDeltaX = "delta_x"
        case wheelDeltaY = "delta_y"
        case delayMs = "delay_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        if let container = container,
           let eventType = try? container.decode(String.self, forKey: .eventType) {
            self.eventType = eventType
            self.pointerId = try? container.decode(Int.self, forKey: .pointerId)
            self.normalizedX = try? container.decode(Double.self, forKey: .normalizedX)
            self.normalizedY = try? container.decode(Double.self, forKey: .normalizedY)
            self.pressure = try? container.decode(Double.self, forKey: .pressure)
            self.keyCode = try? container.decode(Int.self, forKey: .keyCode)
            self.modifiers = try? container.decode([String].self, forKey: .modifiers)
            self.wheelDeltaX = try? container.decode(Double.self, forKey: .wheelDeltaX)
            self.wheelDeltaY = try? container.decode(Double.self, forKey: .wheelDeltaY)
            self.delayMs = (try? container.decode(UInt64.self, forKey: .delayMs)) ?? 0
            return
        }

        let android = try decoder.container(keyedBy: AndroidCodingKeys.self)
        self.eventType = try android.decode(String.self, forKey: .eventType)
        self.pointerId = try? android.decode(Int.self, forKey: .pointerId)
        self.normalizedX = try? android.decode(Double.self, forKey: .normalizedX)
        self.normalizedY = try? android.decode(Double.self, forKey: .normalizedY)
        self.pressure = try? android.decode(Double.self, forKey: .pressure)
        self.keyCode = try? android.decode(Int.self, forKey: .keyCode)
        self.modifiers = try? android.decode([String].self, forKey: .modifiers)
        self.wheelDeltaX = try? android.decode(Double.self, forKey: .wheelDeltaX)
        self.wheelDeltaY = try? android.decode(Double.self, forKey: .wheelDeltaY)
        self.delayMs = (try? android.decode(UInt64.self, forKey: .delayMs)) ?? 0
    }

    func toInputEvent() -> InputEvent {
        InputEvent(
            eventType: InputEventType(rawValue: eventType) ?? .touchMove,
            pointerId: pointerId,
            normalizedX: normalizedX ?? 0.0,
            normalizedY: normalizedY ?? 0.0,
            pressure: pressure,
            keyCode: keyCode,
            modifiers: modifiers,
            wheelDeltaX: wheelDeltaX,
            wheelDeltaY: wheelDeltaY
        )
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

    func serverDidReceivePing(_ server: TCPServer, data: Data) {
        // M2 最小闭环：收到 PING 后记录日志，不强制回复，避免与视频发送争抢。
        logger.logState("收到 PING (payload=\(data.count) bytes)")
    }

    func server(_ server: TCPServer, didReceiveInputEvent data: Data) {
        switch InputEventParser.parse(data) {
        case .success(let event):
            if let error = inputInjector.inject(event) {
                logger.logError("输入注入失败: \(error.localizedDescription)")
                sendError("input_inject_failed: \(error.localizedDescription)")
            }
        case .failure(let error):
            logger.logError("解析 INPUT_EVENT 失败: \(error.localizedDescription)")
            sendError("bad_input_event: \(error.localizedDescription)")
        }
    }

    func server(_ server: TCPServer, didReceiveError data: Data) {
        let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
        logger.logError("收到对端 ERROR: \(preview)")
    }

    func serverDidLoseConnection(_ server: TCPServer, error: Error?) {
        cancelHelloTimeout()
        if let error = error {
            logger.logError("TCP 连接丢失: \(error.localizedDescription)")
        } else {
            logger.logState("TCP client 断开")
        }
        inputInjector?.reset()
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

import Foundation
import ScreenCaptureKit

struct Configuration {
    var width: Int = 1280
    var height: Int = 800
    var fps: Double = 30.0
    var bitrate: Int = 8_000_000
    var port: UInt16 = 19421
}

@main
final class MacHost {
    private let config: Configuration
    private let logger = StatsLogger()
    private var server: TCPServer!
    private var captureSession: CaptureSession!
    private var encoder: Encoder!
    private var protocolSequence: UInt64 = 0
    private var isRunning = false
    private var latestParameterSets: H264ParameterSets?

    init(arguments: [String]) {
        self.config = Self.parseArguments(arguments)
    }

    static func main() async {
        let app = MacHost(arguments: CommandLine.arguments)
        let started = await app.run()
        if !started {
            return
        }
        dispatchMain()
    }

    func run() async -> Bool {
        logger.logState("MacHost starting: \(config.width)x\(config.height)@\(Int(config.fps))fps, bitrate=\(config.bitrate) bps, port=\(config.port)")

        // 1. 列出可采集 display
        captureSession = CaptureSession(width: config.width, height: config.height, fps: config.fps)
        do {
            let displays = try await captureSession.listDisplays()
            logger.logState("发现 \(displays.count) 个 display:")
            for d in displays {
                let marker = d.displayID == CGMainDisplayID() ? " (main)" : ""
                logger.logState("  - \(d.displayID): \(d.width)x\(d.height)\(marker)")
            }
        } catch {
            logger.logError("列出 display 失败: \(error.localizedDescription)")
            return false
        }

        // 2. 启动 TCP server
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
        return true
    }

    private func startStreaming() {
        guard !isRunning else { return }
        isRunning = true
        logger.logState("client 已连接，开始采集与编码")

        encoder = Encoder(width: Int32(config.width), height: Int32(config.height), fps: config.fps, bitrate: config.bitrate)
        if let error = encoder.start() {
            logger.logError("启动编码器失败: \(error.localizedDescription)")
            isRunning = false
            server.stop()
            return
        }

        captureSession.delegate = self

        Task {
            do {
                try await captureSession.start()
                logger.logState("屏幕采集已启动")
            } catch {
                logger.logError("启动屏幕采集失败: \(error.localizedDescription)")
                isRunning = false
                server.stop()
            }
        }
    }

    private func stopStreaming() {
        guard isRunning else { return }
        isRunning = false
        logger.logState("停止采集与编码")
        captureSession.stop()
        encoder?.stop { [weak self] in
            self?.logger.logState("编码器已停止")
        }
    }

    // MARK: - Protocol helpers

    private func sendVideoConfig(parameterSets: H264ParameterSets) {
        latestParameterSets = parameterSets
        let json = """
        {"codec":"h264","stream_format":"annex_b","width":\(config.width),"height":\(config.height),"fps":\(Int(config.fps)),"bitrate_bps":\(config.bitrate),"sps_pps_policy":"repeat_before_keyframe","timestamp_unit":"ns"}
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

    private func sendVideoFrame(data: Data, isKeyframe: Bool, sequence: UInt64, timestampNs: UInt64, encodeDurationMs: Double) {
        var flags: UInt32 = 0
        var payload = data
        if isKeyframe {
            flags |= ProtocolFlags.keyframe
            if let parameterSets = latestParameterSets {
                flags |= ProtocolFlags.config
                payload = parameterSets.annexBData + data
            }
        }
        let header = ProtocolHeader(
            type: .videoFrame,
            sequence: nextProtocolSequence(),
            timestampNs: timestampNs,
            flags: flags,
            payloadLength: UInt32(payload.count)
        )
        var packet = header.encode()
        packet.append(payload)
        server.send(packet)
        logger.logFrame(encodedBytes: payload.count, encodeDurationMs: encodeDurationMs)
    }

    private func nextProtocolSequence() -> UInt64 {
        protocolSequence += 1
        return protocolSequence
    }

    // MARK: - Argument parsing

    private static func parseArguments(_ arguments: [String]) -> Configuration {
        var config = Configuration()
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--width":
                if i + 1 < arguments.count { config.width = Int(arguments[i + 1]) ?? config.width; i += 1 }
            case "--height":
                if i + 1 < arguments.count { config.height = Int(arguments[i + 1]) ?? config.height; i += 1 }
            case "--fps":
                if i + 1 < arguments.count { config.fps = Double(arguments[i + 1]) ?? config.fps; i += 1 }
            case "--bitrate":
                if i + 1 < arguments.count { config.bitrate = Int(arguments[i + 1]) ?? config.bitrate; i += 1 }
            case "--port":
                if i + 1 < arguments.count { config.port = UInt16(arguments[i + 1]) ?? config.port; i += 1 }
            default:
                break
            }
            i += 1
        }
        return config
    }
}

// MARK: - TCPServerDelegate

extension MacHost: TCPServerDelegate {
    func serverDidAcceptConnection(_ server: TCPServer) {
        startStreaming()
    }

    func serverDidLoseConnection(_ server: TCPServer, error: Error?) {
        if let error = error {
            logger.logError("TCP 连接丢失: \(error.localizedDescription)")
        } else {
            logger.logState("TCP client 断开")
        }
        stopStreaming()
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
    }
}

// MARK: - EncoderDelegate

extension MacHost: EncoderDelegate {
    func encoder(_ encoder: Encoder, didOutputParameterSets parameterSets: H264ParameterSets) {
        sendVideoConfig(parameterSets: parameterSets)
    }

    func encoder(_ encoder: Encoder, didOutputAnnexBFrame data: Data, isKeyframe: Bool, sequence: UInt64, timestampNs: UInt64, encodeDurationMs: Double) {
        logger.logEncode(frameSequence: sequence, durationMs: encodeDurationMs, isKeyframe: isKeyframe)
        sendVideoFrame(data: data, isKeyframe: isKeyframe, sequence: sequence, timestampNs: timestampNs, encodeDurationMs: encodeDurationMs)
    }
}

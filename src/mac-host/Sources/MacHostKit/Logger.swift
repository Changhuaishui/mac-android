import Foundation

struct Logger {
    static func writeLine(_ message: String) {
        let data = Data((message + "\n").utf8)
        FileHandle.standardOutput.write(data)
    }
}

public protocol LoggerDelegate: AnyObject {
    func loggerDidOutputMessage(_ message: String, isError: Bool)
    func loggerDidOutputStats(fps: Double, bitrateMbps: Double, avgEncodeMs: Double)
}

public final class StatsLogger {
    public weak var delegate: LoggerDelegate?
    private let queue = DispatchQueue(label: "com.macandroid.machost.logger")
    private var frameCount: UInt64 = 0
    private var byteCount: UInt64 = 0
    private var totalEncodeDurationMs: Double = 0
    private var lastLogTime = DispatchTime.now()

    private func writeLine(_ message: String, to handle: FileHandle) {
        let data = Data((message + "\n").utf8)
        handle.write(data)
    }

    public init() {}

    public func logState(_ message: String) {
        let date = ISO8601DateFormatter().string(from: Date())
        let full = "[\(date)] [STATE] \(message)"
        if let delegate = delegate {
            delegate.loggerDidOutputMessage(full, isError: false)
        } else {
            writeLine(full, to: FileHandle.standardOutput)
        }
    }

    public func logError(_ message: String) {
        let date = ISO8601DateFormatter().string(from: Date())
        let full = "[\(date)] [ERROR] \(message)"
        if let delegate = delegate {
            delegate.loggerDidOutputMessage(full, isError: true)
        } else {
            writeLine(full, to: FileHandle.standardError)
        }
    }

    public func logFrame(encodedBytes: Int, encodeDurationMs: Double) {
        queue.async {
            self.frameCount += 1
            self.byteCount += UInt64(encodedBytes)
            self.totalEncodeDurationMs += encodeDurationMs

            let now = DispatchTime.now()
            let elapsedNs = now.uptimeNanoseconds - self.lastLogTime.uptimeNanoseconds
            if elapsedNs >= 1_000_000_000 {
                let elapsedSec = Double(elapsedNs) / 1_000_000_000.0
                let fps = Double(self.frameCount) / elapsedSec
                let bitrateBps = Double(self.byteCount) * 8.0 / elapsedSec
                let avgEncodeMs = self.frameCount > 0 ? self.totalEncodeDurationMs / Double(self.frameCount) : 0
                let date = ISO8601DateFormatter().string(from: Date())
                let full = "[\(date)] [STATS] fps=\(String(format: "%.1f", fps)), bitrate=\(String(format: "%.2f", bitrateBps / 1_000_000.0)) Mbps, avg_encode=\(String(format: "%.2f", avgEncodeMs)) ms, frames=\(self.frameCount)"
                if let delegate = self.delegate {
                    delegate.loggerDidOutputStats(fps: fps, bitrateMbps: bitrateBps / 1_000_000.0, avgEncodeMs: avgEncodeMs)
                    delegate.loggerDidOutputMessage(full, isError: false)
                } else {
                    self.writeLine(full, to: FileHandle.standardOutput)
                }
                self.frameCount = 0
                self.byteCount = 0
                self.totalEncodeDurationMs = 0
                self.lastLogTime = now
            }
        }
    }

    public func logEncode(frameSequence: UInt64, durationMs: Double, isKeyframe: Bool) {
        let date = ISO8601DateFormatter().string(from: Date())
        let key = isKeyframe ? "K" : "D"
        let full = "[\(date)] [ENCODE] seq=\(frameSequence) type=\(key) duration=\(String(format: "%.2f", durationMs)) ms"
        if let delegate = delegate {
            delegate.loggerDidOutputMessage(full, isError: false)
        } else {
            writeLine(full, to: FileHandle.standardOutput)
        }
    }
}

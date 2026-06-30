import Foundation

final class StatsLogger {
    private let queue = DispatchQueue(label: "com.macandroid.machost.logger")
    private var frameCount: UInt64 = 0
    private var byteCount: UInt64 = 0
    private var totalEncodeDurationMs: Double = 0
    private var lastLogTime = DispatchTime.now()

    func logState(_ message: String) {
        let date = ISO8601DateFormatter().string(from: Date())
        print("[\(date)] [STATE] \(message)")
    }

    func logError(_ message: String) {
        let date = ISO8601DateFormatter().string(from: Date())
        print("[\(date)] [ERROR] \(message)", to: &standardError)
    }

    func logFrame(encodedBytes: Int, encodeDurationMs: Double) {
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
                print("[\(date)] [STATS] fps=\(String(format: "%.1f", fps)), bitrate=\(String(format: "%.2f", bitrateBps / 1_000_000.0)) Mbps, avg_encode=\(String(format: "%.2f", avgEncodeMs)) ms, frames=\(self.frameCount)")
                self.frameCount = 0
                self.byteCount = 0
                self.totalEncodeDurationMs = 0
                self.lastLogTime = now
            }
        }
    }

    func logEncode(frameSequence: UInt64, durationMs: Double, isKeyframe: Bool) {
        let date = ISO8601DateFormatter().string(from: Date())
        let key = isKeyframe ? "K" : "D"
        print("[\(date)] [ENCODE] seq=\(frameSequence) type=\(key) duration=\(String(format: "%.2f", durationMs)) ms")
    }
}

// MARK: - stderr output

struct StandardError: TextOutputStream {
    mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

var standardError = StandardError()

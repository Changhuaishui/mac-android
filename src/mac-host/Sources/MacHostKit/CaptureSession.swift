import Foundation
import ScreenCaptureKit
import CoreMedia

protocol CaptureSessionDelegate: AnyObject {
    func captureSession(_ session: CaptureSession, didOutput sampleBuffer: CMSampleBuffer)
    func captureSession(_ session: CaptureSession, didFailWith error: Error)
}

final class CaptureSession: NSObject, SCStreamOutput {
    weak var delegate: CaptureSessionDelegate?

    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.macandroid.machost.capture")
    private let width: Int
    private let height: Int
    private let fps: Double

    init(width: Int, height: Int, fps: Double) {
        self.width = width
        self.height = height
        self.fps = fps
    }

    func listDisplays() async throws -> [SCDisplay] {
        return try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let content = content {
                    continuation.resume(returning: content.displays)
                } else {
                    continuation.resume(throwing: CaptureError.noDisplayFound)
                }
            }
        }
    }

    func start(targetDisplayID: CGDirectDisplayID? = nil) async throws {
        let displays = try await listDisplays()
        guard let display = pickDisplay(from: displays, targetDisplayID: targetDisplayID) else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)

        try await newStream.startCapture()
        self.stream = newStream
    }

    func stop() {
        stream?.stopCapture { [weak self] _ in
            self?.stream = nil
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        delegate?.captureSession(self, didOutput: sampleBuffer)
    }

    private func pickDisplay(from displays: [SCDisplay], targetDisplayID: CGDirectDisplayID?) -> SCDisplay? {
        if let targetID = targetDisplayID {
            return displays.first { $0.displayID == targetID }
        }
        let mainID = CGMainDisplayID()
        return displays.first { $0.displayID == mainID } ?? displays.first
    }
}

enum CaptureError: LocalizedError {
    case noDisplayFound

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "未找到可采集的显示器"
        }
    }
}

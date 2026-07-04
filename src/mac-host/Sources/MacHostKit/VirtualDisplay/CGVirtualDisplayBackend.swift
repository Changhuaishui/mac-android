import Foundation
import CoreGraphics
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// 路线 A：通过 CoreGraphics 私有类 CGVirtualDisplay 创建虚拟显示器。
///
/// 本实现使用 Objective-C runtime + KVC 访问以下私有 API（macOS 14+）：
/// - CGVirtualDisplayDescriptor
/// - CGVirtualDisplayMode
/// - CGVirtualDisplaySettings
/// - CGVirtualDisplay
///
/// 这些 API 不在 SDK 头文件中，因此不直接链接符号，运行时动态查找类。
public final class CGVirtualDisplayBackend: VirtualDisplay {
    public private(set) var displayID: CGDirectDisplayID?

    private let config: VirtualDisplayConfiguration
    private var virtualDisplay: NSObject?
    private var logger: ((String, Bool) -> Void)?

    public init(configuration: VirtualDisplayConfiguration, logger: ((String, Bool) -> Void)? = nil) {
        self.config = configuration
        self.logger = logger
    }

    private func log(_ message: String, isError: Bool = false) {
        logger?(message, isError)
    }

    // MARK: - VirtualDisplay

    public func start() async throws {
        try createVirtualDisplay()
        try await waitForSystemRegistration()
        forceTargetResolution()
        disableMirroringIfNeeded()
    }

    public func stop() {
        virtualDisplay = nil
        displayID = nil
        log("CGVirtualDisplay 引用已释放")
    }

    // MARK: - Probe helpers

    /// 运行完整 POC：创建、检测、采集一帧。
    public func runProbe(captureOutputPath: String? = nil) async -> VirtualDisplayProbeResult {
        var messages: [String] = []
        let appendMessage: (String) -> Void = { messages.append($0) }

        do {
            appendMessage("开始创建 CGVirtualDisplay，分辨率 \(config.width)x\(config.height)@\(String(format: "%.0f", config.refreshRate))Hz")
            try createVirtualDisplay()
            appendMessage("CGVirtualDisplay 对象已创建，displayID=\(displayID.map { String($0) } ?? "nil")")

            appendMessage("等待系统注册...")
            try await waitForSystemRegistration()
            appendMessage("系统已识别虚拟显示器，displayID=\(displayID.map { String($0) } ?? "nil")")

            let capturePath = captureOutputPath ?? "/tmp/machost-virtual-display-frame.jpg"
            appendMessage("尝试采集一帧到: \(capturePath)")
            let captured = try await captureOneFrame(outputPath: capturePath)
            appendMessage(captured ? "采集成功" : "采集未返回帧")

            return VirtualDisplayProbeResult(
                success: true,
                displayID: displayID,
                displayName: config.name,
                systemDetected: true,
                captureSucceeded: captured,
                capturePath: captured ? capturePath : nil,
                messages: messages
            )
        } catch let error as VirtualDisplayError {
            appendMessage("POC 失败: \(error.description)")
            return VirtualDisplayProbeResult(
                success: false,
                displayID: displayID,
                displayName: config.name,
                messages: messages,
                error: error
            )
        } catch {
            appendMessage("POC 未知错误: \(error.localizedDescription)")
            return VirtualDisplayProbeResult(
                success: false,
                displayID: displayID,
                displayName: config.name,
                messages: messages,
                error: VirtualDisplayError.creationFailed(error.localizedDescription)
            )
        }
    }

    // MARK: - Private API access

    private func createVirtualDisplay() throws {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type else {
            throw VirtualDisplayError.missingClass("CGVirtualDisplayDescriptor")
        }
        guard let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type else {
            throw VirtualDisplayError.missingClass("CGVirtualDisplayMode")
        }
        guard let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            throw VirtualDisplayError.missingClass("CGVirtualDisplaySettings")
        }
        guard let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            throw VirtualDisplayError.missingClass("CGVirtualDisplay")
        }

        // 1. 创建 mode：initWithWidth:height:refreshRate:
        let mode = try createMode(modeClass: modeClass)

        // 2. 配置 descriptor
        let descriptor = descriptorClass.init()
        descriptor.setValue(config.name, forKey: "name")
        descriptor.setValue(NSNumber(value: UInt32(config.width)), forKey: "maxPixelsWide")
        descriptor.setValue(NSNumber(value: UInt32(config.height)), forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: config.sizeInMillimeters), forKey: "sizeInMillimeters")
        descriptor.setValue(NSNumber(value: config.vendorID), forKey: "vendorID")
        descriptor.setValue(NSNumber(value: config.serialNum), forKey: "serialNum")

        // 3. 创建 CGVirtualDisplay：initWithDescriptor:
        let display = try createDisplay(displayClass: displayClass, descriptor: descriptor)

        // 4. 配置 settings
        let settings = settingsClass.init()
        settings.setValue(NSNumber(value: 0), forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")

        // 5. 应用 settings
        let applied = try applySettings(display: display, settings: settings)
        guard applied else {
            throw VirtualDisplayError.activationFailed("applySettings 返回 false")
        }

        // 6. 读取 displayID
        guard let displayID = display.value(forKey: "displayID") as? UInt32 else {
            throw VirtualDisplayError.creationFailed("无法读取 displayID")
        }

        self.virtualDisplay = display
        self.displayID = displayID
    }

    /// 启动后强制把虚拟显示器切回配置的目标分辨率，防止 macOS 沿用用户上次选择的分辨率。
    private func forceTargetResolution() {
        guard let displayID = displayID else { return }

        let targetWidth = config.width
        let targetHeight = config.height

        var configRef: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&configRef)
        guard beginError == .success, let configRef = configRef else {
            log("无法开始显示器配置，跳过强制目标分辨率", isError: true)
            return
        }

        var bestMode: CGDisplayMode?
        if let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] {
            bestMode = modes.first { mode in
                mode.pixelWidth == targetWidth && mode.pixelHeight == targetHeight
            }
        }

        if let mode = bestMode {
            let configureError = CGConfigureDisplayWithDisplayMode(configRef, displayID, mode, nil)
            if configureError == .success {
                let completeError = CGCompleteDisplayConfiguration(configRef, .forSession)
                if completeError == .success {
                    log("已强制虚拟显示器回到目标分辨率 \(targetWidth)x\(targetHeight)")
                    return
                } else {
                    log("完成目标分辨率配置失败: \(completeError.rawValue)", isError: true)
                    CGCancelDisplayConfiguration(configRef)
                    return
                }
            } else {
                log("配置目标分辨率失败: \(configureError.rawValue)", isError: true)
                CGCancelDisplayConfiguration(configRef)
                return
            }
        }

        CGCancelDisplayConfiguration(configRef)
        log("未找到目标分辨率 \(targetWidth)x\(targetHeight) 的可用模式，保持系统当前模式", isError: true)
    }

    /// macOS 新显示器默认可能进入镜像模式。强制改为扩展模式，避免退化成主屏镜像。
    private func disableMirroringIfNeeded() {
        guard let displayID = displayID else { return }

        if CGDisplayIsInMirrorSet(displayID) == 0 {
            log("虚拟显示器当前未镜像")
            return
        }

        log("检测到虚拟显示器处于镜像模式，尝试强制扩展模式...")

        var config: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&config)
        guard beginError == .success, let config = config else {
            log("无法开始显示器配置，跳过强制扩展模式", isError: true)
            return
        }

        let mirrorError = CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
        if mirrorError != .success {
            log("强制扩展模式失败: \(mirrorError.rawValue)", isError: true)
            CGCancelDisplayConfiguration(config)
            return
        }

        let completeError = CGCompleteDisplayConfiguration(config, .forSession)
        if completeError == .success {
            log("已强制虚拟显示器进入扩展模式")
        } else {
            log("完成显示器配置失败: \(completeError.rawValue)，请手动在 系统设置 → 显示器 中取消镜像", isError: true)
        }
    }

    private func createMode(modeClass: NSObject.Type) throws -> NSObject {
        guard let allocMode = (modeClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplayMode alloc 失败")
        }
        let selector = NSSelectorFromString("initWithWidth:height:refreshRate:")
        guard allocMode.responds(to: selector) else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplayMode 缺少 initWithWidth:height:refreshRate:")
        }
        guard let imp = allocMode.method(for: selector) else {
            throw VirtualDisplayError.creationFailed("无法获取 CGVirtualDisplayMode init IMP")
        }
        typealias InitModeIMP = @convention(c) (NSObject, Selector, Int, Int, Double) -> NSObject?
        let initMode = unsafeBitCast(imp, to: InitModeIMP.self)
        guard let mode = initMode(allocMode, selector, config.width, config.height, config.refreshRate) else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplayMode init 返回 nil")
        }
        return mode
    }

    private func createDisplay(displayClass: NSObject.Type, descriptor: NSObject) throws -> NSObject {
        guard let allocDisplay = (displayClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplay alloc 失败")
        }
        let selector = NSSelectorFromString("initWithDescriptor:")
        guard allocDisplay.responds(to: selector) else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplay 缺少 initWithDescriptor:")
        }
        guard let imp = allocDisplay.method(for: selector) else {
            throw VirtualDisplayError.creationFailed("无法获取 CGVirtualDisplay init IMP")
        }
        typealias InitDisplayIMP = @convention(c) (NSObject, Selector, NSObject) -> NSObject?
        let initDisplay = unsafeBitCast(imp, to: InitDisplayIMP.self)
        guard let display = initDisplay(allocDisplay, selector, descriptor) else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplay init 返回 nil")
        }
        return display
    }

    private func applySettings(display: NSObject, settings: NSObject) throws -> Bool {
        let selector = NSSelectorFromString("applySettings:")
        guard display.responds(to: selector) else {
            throw VirtualDisplayError.creationFailed("CGVirtualDisplay 缺少 applySettings:")
        }
        guard let imp = display.method(for: selector) else {
            throw VirtualDisplayError.creationFailed("无法获取 CGVirtualDisplay applySettings IMP")
        }
        typealias ApplySettingsIMP = @convention(c) (NSObject, Selector, NSObject) -> Bool
        let apply = unsafeBitCast(imp, to: ApplySettingsIMP.self)
        return apply(display, selector, settings)
    }

    // MARK: - System registration detection

    private func waitForSystemRegistration() async throws {
        let deadline = ContinuousClock().now + .seconds(8)
        while ContinuousClock().now < deadline {
            if isDisplayRegistered(displayID: displayID) {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw VirtualDisplayError.timeout
    }

    private func isDisplayRegistered(displayID: CGDirectDisplayID?) -> Bool {
        guard let targetID = displayID else { return false }

        var displayCount: UInt32 = 0
        let error = CGGetActiveDisplayList(0, nil, &displayCount)
        guard error == .success, displayCount > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let listError = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard listError == .success else { return false }

        return displays.contains(targetID)
    }

    // MARK: - One-frame capture

    private func captureOneFrame(outputPath: String) async throws -> Bool {
        guard let displayID = displayID else {
            throw VirtualDisplayError.captureFailed("displayID 为空")
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw VirtualDisplayError.captureFailed("SCShareableContent 未找到 displayID=\(displayID) 的显示器")
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: Int32(config.refreshRate))
        streamConfig.queueDepth = 3

        let captureDelegate = VirtualDisplayCaptureDelegate()
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: captureDelegate)
        captureDelegate.stream = stream
        captureDelegate.outputPath = outputPath

        try stream.addStreamOutput(captureDelegate, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue(label: "com.macandroid.vdisplay.capture"))
        try await stream.startCapture()

        // 等待一帧，最多 5 秒
        let result = await captureDelegate.waitForFrame()
        try? await stream.stopCapture()

        return result
    }
}

// MARK: - ScreenCaptureKit capture delegate

private final class VirtualDisplayCaptureDelegate: NSObject, SCStreamOutput, SCStreamDelegate {
    weak var stream: SCStream?
    var outputPath: String?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var receivedFrame = false

    func waitForFrame() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, !receivedFrame else { return }
        receivedFrame = true

        var saved = false
        if let imageBuffer = sampleBuffer.imageBuffer {
            saved = savePixelBuffer(imageBuffer, to: outputPath ?? "/tmp/machost-virtual-display-frame.jpg")
        }

        continuation?.resume(returning: saved)
        continuation = nil
    }

    func stream(_ stream: SCStream, didStopWithBufferError error: Error?) {
        if !receivedFrame {
            continuation?.resume(returning: false)
            continuation = nil
        }
    }

    private func savePixelBuffer(_ pixelBuffer: CVPixelBuffer, to path: String) -> Bool {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: colorSpace) else {
            return false
        }
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination)
    }
}

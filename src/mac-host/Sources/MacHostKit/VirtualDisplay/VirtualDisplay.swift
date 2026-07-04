import Foundation
import CoreGraphics

/// 虚拟显示器创建失败的错误类型。
public enum VirtualDisplayError: Error, CustomStringConvertible {
    case notSupported
    case missingClass(String)
    case creationFailed(String)
    case activationFailed(String)
    case captureFailed(String)
    case timeout

    public var description: String {
        switch self {
        case .notSupported:
            return "当前系统不支持虚拟显示器"
        case .missingClass(let name):
            return "缺少私有类: \(name)"
        case .creationFailed(let reason):
            return "创建虚拟显示器失败: \(reason)"
        case .activationFailed(let reason):
            return "激活虚拟显示器失败: \(reason)"
        case .captureFailed(let reason):
            return "采集虚拟显示器失败: \(reason)"
        case .timeout:
            return "等待虚拟显示器注册超时"
        }
    }
}

/// 虚拟显示器配置。
public struct VirtualDisplayConfiguration {
    public var width: Int
    public var height: Int
    public var refreshRate: Double
    public var name: String
    public var vendorID: UInt32
    public var serialNum: UInt32
    /// 物理尺寸（毫米）。CGVirtualDisplay 对像素密度敏感，需设置合理尺寸。
    public var sizeInMillimeters: CGSize

    public init(
        width: Int,
        height: Int,
        refreshRate: Double = 60.0,
        name: String = "MacAndroid Virtual Display",
        vendorID: UInt32 = 0xF0F0,
        serialNum: UInt32? = nil
    ) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.name = name
        self.vendorID = vendorID
        // 使用变化的 serialNum，避免 macOS 记忆上次用户切换的分辨率。
        self.serialNum = serialNum ?? UInt32(Date().timeIntervalSince1970)
        // 约 24 英寸 16:9 显示器的物理尺寸，避免被系统以像素密度过高拒绝。
        let mmDiagonal: Double = 531.0
        let aspect = Double(width) / Double(height)
        let h = mmDiagonal / sqrt(aspect * aspect + 1.0)
        let w = aspect * h
        self.sizeInMillimeters = CGSize(width: w, height: h)
    }
}

/// 虚拟显示器抽象接口。
public protocol VirtualDisplay: AnyObject {
    /// 创建成功后返回的 CoreGraphics 显示 ID。
    var displayID: CGDirectDisplayID? { get }

    /// 启动虚拟显示器。
    func start() async throws

    /// 停止并销毁虚拟显示器。
    func stop()

    /// 运行完整 POC：创建、检测、采集一帧。默认实现返回失败。
    func runProbe(captureOutputPath: String?) async -> VirtualDisplayProbeResult
}

public extension VirtualDisplay {
    func runProbe(captureOutputPath: String? = nil) async -> VirtualDisplayProbeResult {
        return VirtualDisplayProbeResult(
            success: false,
            displayName: nil,
            error: VirtualDisplayError.notSupported
        )
    }
}

/// 探针结果。
public struct VirtualDisplayProbeResult {
    public let success: Bool
    public let displayID: CGDirectDisplayID?
    public let displayName: String?
    public let systemDetected: Bool
    public let captureSucceeded: Bool
    public let capturePath: String?
    public let messages: [String]
    public let error: VirtualDisplayError?

    public init(
        success: Bool,
        displayID: CGDirectDisplayID? = nil,
        displayName: String? = nil,
        systemDetected: Bool = false,
        captureSucceeded: Bool = false,
        capturePath: String? = nil,
        messages: [String] = [],
        error: VirtualDisplayError? = nil
    ) {
        self.success = success
        self.displayID = displayID
        self.displayName = displayName
        self.systemDetected = systemDetected
        self.captureSucceeded = captureSucceeded
        self.capturePath = capturePath
        self.messages = messages
        self.error = error
    }
}

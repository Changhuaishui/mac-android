import Foundation
import CoreGraphics

/// 虚拟显示器后端策略。
public enum VirtualDisplayBackend {
    /// CoreGraphics 私有 API（CGVirtualDisplay）。
    case coreGraphicsPrivate
    /// DriverKit Display Driver。
    case driverKit
    /// 当前没有可用后端。
    case none
}

/// 虚拟显示器工厂。
public enum VirtualDisplayProvider {
    /// 返回当前系统推荐的后端。
    public static func preferredBackend() -> VirtualDisplayBackend {
        // macOS 14+ 优先尝试 CGVirtualDisplay 私有 API。
        if #available(macOS 14.0, *), NSClassFromString("CGVirtualDisplayDescriptor") != nil {
            return .coreGraphicsPrivate
        }
        return .none
    }

    /// 创建指定后端的虚拟显示器实例。
    public static func create(
        backend: VirtualDisplayBackend = preferredBackend(),
        configuration: VirtualDisplayConfiguration,
        logger: ((String, Bool) -> Void)? = nil
    ) -> VirtualDisplay? {
        switch backend {
        case .coreGraphicsPrivate:
            return CGVirtualDisplayBackend(configuration: configuration, logger: logger)
        case .driverKit, .none:
            return nil
        }
    }

    /// 返回当前系统上各后端的可用性摘要。
    public static func availabilityReport() -> [String: Bool] {
        return [
            "CGVirtualDisplay (CoreGraphics private)": NSClassFromString("CGVirtualDisplayDescriptor") != nil,
            "DriverKit Display Driver": false // 需要额外 DEXT，本阶段未实现
        ]
    }
}

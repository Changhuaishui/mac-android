import Foundation
import CoreGraphics

/// 将 Android 发来的归一化坐标映射到 macOS 目标显示器的像素坐标。
public final class CoordinateMapper: @unchecked Sendable {
    private let displayID: CGDirectDisplayID
    private let bounds: CGRect

    /// 初始化坐标映射器。
    /// - Parameter displayID: 目标显示器 ID；nil 时使用主屏 `CGMainDisplayID()`。
    public init(displayID: CGDirectDisplayID? = nil) {
        self.displayID = displayID ?? CGMainDisplayID()
        self.bounds = CGDisplayBounds(self.displayID)
    }

    /// 目标显示器 ID。
    public var targetDisplayID: CGDirectDisplayID { displayID }

    /// 目标显示器像素边界。
    public var displayBounds: CGRect { bounds }

    /// 将归一化坐标映射到目标显示器像素坐标。
    /// - Parameters:
    ///   - normalizedX: `[0.0, 1.0]`，0 表示左边缘，1 表示右边缘。
    ///   - normalizedY: `[0.0, 1.0]`，0 表示上边缘，1 表示下边缘。
    /// - Returns: `CGPoint` 像素坐标，已按 `floor` 取整并限制在屏幕边界内。
    public func map(normalizedX: Double, normalizedY: Double) -> CGPoint {
        let clampedX = max(0.0, min(1.0, normalizedX))
        let clampedY = max(0.0, min(1.0, normalizedY))

        let pixelX = floor(clampedX * (bounds.width - 1))
        let pixelY = floor(clampedY * (bounds.height - 1))

        return CGPoint(
            x: max(bounds.minX, min(bounds.maxX - 1, pixelX + bounds.minX)),
            y: max(bounds.minY, min(bounds.maxY - 1, pixelY + bounds.minY))
        )
    }
}

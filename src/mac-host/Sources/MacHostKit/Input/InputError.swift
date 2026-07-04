import Foundation

/// 输入事件解析或注入过程中可能产生的错误。
public enum InputError: LocalizedError, Sendable {
    case unknownEventType(String)
    case invalidCoordinates(normalizedX: Double, normalizedY: Double)
    case missingKeyCode
    case missingWheelDelta
    case injectionFailed(String)
    case accessibilityPermissionDenied

    public var errorDescription: String? {
        switch self {
        case .unknownEventType(let raw):
            return "未知事件类型: \(raw)"
        case .invalidCoordinates(let x, let y):
            return "归一化坐标越界: x=\(x), y=\(y)，必须在 [0.0, 1.0] 之间"
        case .missingKeyCode:
            return "键盘事件缺少 key_code"
        case .missingWheelDelta:
            return "滚轮事件缺少 wheel_delta_x / wheel_delta_y"
        case .injectionFailed(let detail):
            return "输入注入失败: \(detail)"
        case .accessibilityPermissionDenied:
            return "辅助功能权限未授予，请在 系统设置 → 隐私与安全性 → 辅助功能 中启用本应用"
        }
    }
}

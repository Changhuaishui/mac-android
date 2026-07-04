import Foundation
import ApplicationServices

/// 封装 macOS Accessibility 权限检查。
public enum AccessibilityPermission {
    /// 检查当前进程是否已被授予 Accessibility 权限。
    /// - Parameter prompt: 是否在未授权时触发系统授权提示弹窗。
    /// - Returns: 已授权返回 `true`，否则返回 `false`。
    public static func check(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        return trusted
    }

    /// 未授权时的中文引导信息。
    public static var guidance: String {
        "辅助功能权限未授予。请在 系统设置 → 隐私与安全性 → 辅助功能 中启用本应用，然后重新启动。"
    }
}

import Foundation

/// Mac Host 输出档位。M1.1 新增，用于根据 Android 上报能力动态选择分辨率/帧率/码率。
public enum Profile: String, CaseIterable, CustomStringConvertible, Sendable {
    /// 平衡档：1280x800@30，兼容性与资源占用最低。
    case balanced = "balanced"
    /// 高清 60fps：1920x1200@60。
    case hd60 = "hd60"
    /// 安全原生档：使用 Android current mode 分辨率，帧率上限 60fps。
    case detectedNativeSafe = "detected-native-safe"
    /// 原生档：使用 Android current mode 分辨率与刷新率，允许因编码器能力降级。
    case detectedNative = "detected-native"
    /// 自定义档：未指定 --profile 时，使用 CLI 显式传入的 width/height/fps/bitrate。
    case custom = "custom"

    public var description: String { rawValue }

    public init?(_ string: String) {
        self.init(rawValue: string)
    }
}

/// 解析 Android HELLO 中的显示能力。
/// 字段定义以 `设计/protocol-v0.md` 为准。
public struct DisplayCapabilities: Codable, Sendable {
    public let currentMode: DisplayMode
    public let supportedModes: [DisplayMode]?
    public let windowBounds: Size?
    public let surfaceSize: Size?
    public let density: Double?
    public let densityDpi: Int?
    public let orientation: String?

    enum CodingKeys: String, CodingKey {
        case currentMode = "current_mode"
        case supportedModes = "supported_modes"
        case windowBounds = "window_bounds"
        case surfaceSize = "surface_size"
        case density
        case densityDpi = "density_dpi"
        case orientation
    }
}

public struct Size: Codable, Sendable {
    public let width: Int
    public let height: Int
}

/// Android 单一显示模式。
/// 优先使用 `physical_width` / `physical_height`；`width` / `height` 仅作为旧 fixture 的兼容 fallback。
public struct DisplayMode: Codable, Sendable {
    public let modeId: Int?
    public let physicalWidth: Int?
    public let physicalHeight: Int?
    /// 旧 fixture 兼容字段，不应在新协议 payload 中使用。
    public let width: Int?
    public let height: Int?
    /// Android 上报的原始刷新率（Hz），允许浮点值。
    public let refreshRate: Double?

    enum CodingKeys: String, CodingKey {
        case modeId = "mode_id"
        case physicalWidth = "physical_width"
        case physicalHeight = "physical_height"
        case width, height
        case refreshRate = "refresh_rate"
    }

    /// 实际用于画质选择的宽度：优先 physical_width，fallback 到 width。
    public var effectiveWidth: Int {
        physicalWidth ?? width ?? 1920
    }

    /// 实际用于画质选择的高度：优先 physical_height，fallback 到 height。
    public var effectiveHeight: Int {
        physicalHeight ?? height ?? 1200
    }

    /// 原始刷新率，nil 表示未上报。
    public var rawRefreshRate: Double? { refreshRate }

    /// 按容差归一化后的刷新率。
    public var normalizedFPS: Double {
        RefreshRateNormalizer.normalize(refreshRate)
    }

    public var summary: String {
        let w = effectiveWidth
        let h = effectiveHeight
        if let rate = refreshRate {
            return "\(w)x\(h) raw=\(rate)Hz normalized=\(Int(normalizedFPS))Hz"
        }
        return "\(w)x\(h)"
    }
}

/// 刷新率容差归一化。
/// refresh_rate 是浮点能力值，不允许用 == 60 / == 120 / == 144 做严格判断。
public struct RefreshRateNormalizer {
    public static func normalize(_ raw: Double?) -> Double {
        guard let raw = raw else { return 60.0 }
        if raw >= 59.0 && raw <= 61.0 { return 60.0 }
        if raw >= 89.0 && raw <= 91.0 { return 90.0 }
        if raw >= 119.0 && raw <= 121.0 { return 120.0 }
        if raw >= 143.0 && raw <= 145.0 { return 144.0 }
        return round(raw)
    }
}

/// 最终选定的输出流配置。
public struct StreamConfiguration: Sendable {
    public let width: Int
    public let height: Int
    public let fps: Double
    public let bitrate: Int
    /// 若发生降级，记录人类可读原因；nil 表示未降级。
    public let degradationReason: String?
    /// 原始刷新率（仅 profile 选择时有意义）。
    public let rawRefreshRate: Double?
    /// 容差归一化后的刷新率。
    public let normalizedFPS: Double?
    /// 最终选定的刷新率。
    public let selectedFPS: Double?

    public init(
        width: Int,
        height: Int,
        fps: Double,
        bitrate: Int,
        degradationReason: String? = nil,
        rawRefreshRate: Double? = nil,
        normalizedFPS: Double? = nil,
        selectedFPS: Double? = nil
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        self.degradationReason = degradationReason
        self.rawRefreshRate = rawRefreshRate
        self.normalizedFPS = normalizedFPS
        self.selectedFPS = selectedFPS
    }

    public var summary: String {
        "\(width)x\(height) @ \(Int(fps))fps, \(bitrate / 1_000_000) Mbps"
    }

    public var refreshRateSummary: String {
        let raw = rawRefreshRate.map { String($0) } ?? "nil"
        let normalized = normalizedFPS.map { String(Int($0)) } ?? "nil"
        let selected = selectedFPS.map { String(Int($0)) } ?? "nil"
        return "raw=\(raw)Hz normalized=\(normalized)Hz selected=\(selected)Hz"
    }
}

/// 根据 profile 与 Android 能力生成实际输出配置。
public struct ProfileResolver {
    /// 码率估算系数（bits per pixel per frame）。
    /// 该系数在清晰文字与动画之间取折中；实际码率还会被上下限裁剪。
    public static let bitrateFactor: Double = 0.08
    public static let minBitrate: Int = 2_000_000
    public static let maxBitrate: Int = 40_000_000

    /// 编码器推荐的 fps 上限。detected-native 超过此值时会标记降级，但仍尝试运行。
    public static let encoderRecommendedMaxFPS: Double = 60.0

    public static func resolve(profile: Profile, capabilities: DisplayCapabilities?) -> StreamConfiguration {
        switch profile {
        case .balanced:
            return make(width: 1280, height: 800, fps: 30)
        case .hd60:
            return make(width: 1920, height: 1200, fps: 60)
        case .detectedNativeSafe:
            return resolveDetectedNativeSafe(capabilities: capabilities)
        case .detectedNative:
            return resolveDetectedNative(capabilities: capabilities)
        case .custom:
            return make(width: 1280, height: 800, fps: 30)
                .withDegradation("custom profile 应使用显式配置，resolver 回退到 balanced")
        }
    }

    private static func resolveDetectedNativeSafe(capabilities: DisplayCapabilities?) -> StreamConfiguration {
        guard let caps = capabilities else {
            return make(width: 1920, height: 1200, fps: 60)
                .withDegradation("未收到 Android HELLO/display_capabilities，detected-native-safe 降级到 hd60")
        }
        let mode = caps.currentMode
        let raw = mode.rawRefreshRate
        let normalized = mode.normalizedFPS
        let selected = min(normalized, encoderRecommendedMaxFPS)
        var config = make(
            width: mode.effectiveWidth,
            height: mode.effectiveHeight,
            fps: selected,
            rawRefreshRate: raw,
            normalizedFPS: normalized,
            selectedFPS: selected
        )
        if mode.physicalWidth == nil || mode.physicalHeight == nil {
            config = config.withDegradation("legacy compatibility: 未上报 physical_width/physical_height，使用旧 fixture 字段 width/height")
        }
        if raw == nil {
            config = config.withDegradation("Android 未上报 refresh_rate，已按 \(Int(encoderRecommendedMaxFPS))fps 处理")
        } else if normalized > encoderRecommendedMaxFPS {
            config = config.withDegradation("Android 刷新率 raw=\(raw!)Hz normalized=\(Int(normalized))Hz 超过 \(Int(encoderRecommendedMaxFPS))fps，已限制到 \(Int(selected))Hz")
        }
        return config
    }

    private static func resolveDetectedNative(capabilities: DisplayCapabilities?) -> StreamConfiguration {
        guard let caps = capabilities else {
            return make(width: 1920, height: 1200, fps: 60)
                .withDegradation("未收到 Android HELLO/display_capabilities，detected-native 降级到 hd60")
        }
        let mode = caps.currentMode
        let raw = mode.rawRefreshRate
        let normalized = mode.normalizedFPS
        let selected = normalized
        var config = make(
            width: mode.effectiveWidth,
            height: mode.effectiveHeight,
            fps: selected,
            rawRefreshRate: raw,
            normalizedFPS: normalized,
            selectedFPS: selected
        )
        if mode.physicalWidth == nil || mode.physicalHeight == nil {
            config = config.withDegradation("legacy compatibility: 未上报 physical_width/physical_height，使用旧 fixture 字段 width/height")
        }
        if selected > encoderRecommendedMaxFPS {
            config = config.withDegradation("Android 刷新率 raw=\(raw ?? 0)Hz normalized=\(Int(normalized))Hz 超过编码器推荐上限 \(Int(encoderRecommendedMaxFPS))Hz，允许运行但可能掉帧")
        }
        return config
    }

    private static func make(
        width: Int,
        height: Int,
        fps: Double,
        rawRefreshRate: Double? = nil,
        normalizedFPS: Double? = nil,
        selectedFPS: Double? = nil
    ) -> StreamConfiguration {
        let raw = Double(width * height) * fps * bitrateFactor
        let bitrate = Int(min(max(raw, Double(minBitrate)), Double(maxBitrate)))
        return StreamConfiguration(
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate,
            rawRefreshRate: rawRefreshRate,
            normalizedFPS: normalizedFPS,
            selectedFPS: selectedFPS
        )
    }
}

extension StreamConfiguration {
    func withDegradation(_ reason: String) -> StreamConfiguration {
        StreamConfiguration(
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate,
            degradationReason: reason,
            rawRefreshRate: rawRefreshRate,
            normalizedFPS: normalizedFPS,
            selectedFPS: selectedFPS
        )
    }
}

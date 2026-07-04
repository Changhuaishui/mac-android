import Foundation

/// Android 端发送的输入事件类型。
public enum InputEventType: String, Codable, Sendable {
    case touchDown = "touch_down"
    case touchMove = "touch_move"
    case touchUp   = "touch_up"
    case wheel
    case keyDown   = "key_down"
    case keyUp     = "key_up"
}

/// Android → Mac 的输入事件模型。
///
/// 坐标使用归一化值 `[0.0, 1.0]`，Mac 端再映射到目标显示器像素坐标。
/// 日志只记录事件类型、归一化坐标和 keyCode，不记录文本内容。
public struct InputEvent: Codable, Sendable {
    public let eventType: InputEventType
    public let pointerId: Int?
    public let normalizedX: Double
    public let normalizedY: Double
    public let pressure: Double?
    public let keyCode: Int?
    public let modifiers: [String]?
    public let wheelDeltaX: Double?
    public let wheelDeltaY: Double?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case pointerId = "pointer_id"
        case normalizedX = "normalized_x"
        case normalizedY = "normalized_y"
        case pressure
        case keyCode = "key_code"
        case modifiers
        case wheelDeltaX = "wheel_delta_x"
        case wheelDeltaY = "wheel_delta_y"
    }

    /// 兼容 Android Client 当前使用的字段名。
    enum AndroidCodingKeys: String, CodingKey {
        case eventType = "type"
        case pointerId = "pointer_id"
        case normalizedX = "x"
        case normalizedY = "y"
        case pressure
        case keyCode = "key_code"
        case modifiers = "meta_state"
        case wheelDeltaX = "delta_x"
        case wheelDeltaY = "delta_y"
    }

    public init(
        eventType: InputEventType,
        pointerId: Int? = nil,
        normalizedX: Double,
        normalizedY: Double,
        pressure: Double? = nil,
        keyCode: Int? = nil,
        modifiers: [String]? = nil,
        wheelDeltaX: Double? = nil,
        wheelDeltaY: Double? = nil
    ) {
        self.eventType = eventType
        self.pointerId = pointerId
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.pressure = pressure
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.wheelDeltaX = wheelDeltaX
        self.wheelDeltaY = wheelDeltaY
    }

    public init(from decoder: Decoder) throws {
        // 优先尝试 Mac 端标准字段名。
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        if let container = container,
           let eventTypeRaw = try? container.decode(String.self, forKey: .eventType),
           let eventType = InputEventType(rawValue: eventTypeRaw) {
            self.eventType = eventType
            self.pointerId = try? container.decode(Int.self, forKey: .pointerId)
            self.normalizedX = (try? container.decode(Double.self, forKey: .normalizedX)) ?? 0.0
            self.normalizedY = (try? container.decode(Double.self, forKey: .normalizedY)) ?? 0.0
            self.pressure = try? container.decode(Double.self, forKey: .pressure)
            self.keyCode = try? container.decode(Int.self, forKey: .keyCode)
            self.modifiers = try? container.decode([String].self, forKey: .modifiers)
            self.wheelDeltaX = try? container.decode(Double.self, forKey: .wheelDeltaX)
            self.wheelDeltaY = try? container.decode(Double.self, forKey: .wheelDeltaY)
            return
        }

        // Fallback 到 Android Client 当前字段名。
        let android = try decoder.container(keyedBy: AndroidCodingKeys.self)
        let eventTypeRaw = try android.decode(String.self, forKey: .eventType)
        guard let eventType = InputEventType(rawValue: eventTypeRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .eventType, in: android, debugDescription: "未知事件类型: \(eventTypeRaw)")
        }
        self.eventType = eventType
        self.pointerId = try? android.decode(Int.self, forKey: .pointerId)
        self.normalizedX = (try? android.decode(Double.self, forKey: .normalizedX)) ?? 0.0
        self.normalizedY = (try? android.decode(Double.self, forKey: .normalizedY)) ?? 0.0
        self.pressure = try? android.decode(Double.self, forKey: .pressure)
        self.keyCode = try? android.decode(Int.self, forKey: .keyCode)
        // Android 的 meta_state 通常是 Int 掩码；这里先按字符串数组 fallback，后续可按需解析。
        self.modifiers = try? android.decode([String].self, forKey: .modifiers)
        self.wheelDeltaX = try? android.decode(Double.self, forKey: .wheelDeltaX)
        self.wheelDeltaY = try? android.decode(Double.self, forKey: .wheelDeltaY)
    }
}

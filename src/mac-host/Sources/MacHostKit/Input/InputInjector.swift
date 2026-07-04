import Foundation
import CoreGraphics

/// 将 `InputEvent` 注入到 macOS 事件系统。
///
/// 当前实现使用 `CGEventPost` + Accessibility 权限，M2 先支持主屏。
/// 不记录文本内容，只记录事件类型、归一化坐标和 keyCode。
public final class InputInjector: @unchecked Sendable {
    public weak var delegate: InputInjectorDelegate?

    private let mapper: CoordinateMapper
    private let logger: StatsLogger
    private var isMouseDown = false

    public init(mapper: CoordinateMapper, logger: StatsLogger) {
        self.mapper = mapper
        self.logger = logger
    }

    /// 注入单个输入事件。
    /// - Returns: 失败时返回 `InputError`，成功时返回 `nil`。
    @discardableResult
    public func inject(_ event: InputEvent) -> InputError? {
        log(event: event)

        switch event.eventType {
        case .touchDown:
            return handleTouchDown(event)
        case .touchMove:
            return handleTouchMove(event)
        case .touchUp:
            return handleTouchUp(event)
        case .wheel:
            return handleWheel(event)
        case .keyDown:
            return handleKey(event, keyDown: true)
        case .keyUp:
            return handleKey(event, keyDown: false)
        }
    }

    /// 断线或暂停时复位鼠标按下状态，避免遗留按下。
    public func reset() {
        if isMouseDown {
            _ = postMouseEvent(type: .leftMouseUp, at: lastMouseLocation ?? CGPoint(x: 0, y: 0))
            isMouseDown = false
        }
        lastMouseLocation = nil
    }

    // MARK: - Private state

    private var lastMouseLocation: CGPoint?

    // MARK: - Touch / mouse

    private func handleTouchDown(_ event: InputEvent) -> InputError? {
        let point = mapper.map(normalizedX: event.normalizedX, normalizedY: event.normalizedY)
        lastMouseLocation = point

        // 先移动光标到目标位置，再按下左键。
        if let error = postMouseEvent(type: .mouseMoved, at: point) { return error }
        if let error = postMouseEvent(type: .leftMouseDown, at: point) { return error }
        isMouseDown = true
        return nil
    }

    private func handleTouchMove(_ event: InputEvent) -> InputError? {
        let point = mapper.map(normalizedX: event.normalizedX, normalizedY: event.normalizedY)
        lastMouseLocation = point

        let type: CGEventType = isMouseDown ? .leftMouseDragged : .mouseMoved
        return postMouseEvent(type: type, at: point)
    }

    private func handleTouchUp(_ event: InputEvent) -> InputError? {
        let point = mapper.map(normalizedX: event.normalizedX, normalizedY: event.normalizedY)
        lastMouseLocation = point

        if let error = postMouseEvent(type: .leftMouseUp, at: point) { return error }
        isMouseDown = false
        return nil
    }

    private func postMouseEvent(type: CGEventType, at point: CGPoint) -> InputError? {
        guard let cgEvent = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            return .injectionFailed("无法创建 \(type) 事件")
        }
        cgEvent.post(tap: .cghidEventTap)
        return nil
    }

    // MARK: - Wheel

    private func handleWheel(_ event: InputEvent) -> InputError? {
        guard let deltaY = event.wheelDeltaY, let deltaX = event.wheelDeltaX else {
            return .missingWheelDelta
        }
        let point = lastMouseLocation ?? mapper.map(normalizedX: event.normalizedX, normalizedY: event.normalizedY)
        lastMouseLocation = point

        guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(deltaY), wheel2: Int32(deltaX), wheel3: 0) else {
            return .injectionFailed("无法创建滚轮事件")
        }
        cgEvent.post(tap: .cghidEventTap)
        return nil
    }

    // MARK: - Keyboard

    private func handleKey(_ event: InputEvent, keyDown: Bool) -> InputError? {
        guard let keyCode = event.keyCode else {
            return .missingKeyCode
        }
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: keyDown) else {
            return .injectionFailed("无法创建键盘事件 keyCode=\(keyCode)")
        }
        cgEvent.post(tap: .cghidEventTap)
        return nil
    }

    // MARK: - Logging

    private func log(event: InputEvent) {
        switch event.eventType {
        case .keyDown, .keyUp:
            logger.logState("[INPUT] type=\(event.eventType.rawValue) keyCode=\(event.keyCode ?? -1)")
        case .wheel:
            logger.logState("[INPUT] type=\(event.eventType.rawValue) normalized=(\(event.normalizedX), \(event.normalizedY)) wheel=(\(event.wheelDeltaX ?? 0), \(event.wheelDeltaY ?? 0))")
        default:
            logger.logState("[INPUT] type=\(event.eventType.rawValue) pointer=\(event.pointerId ?? 0) normalized=(\(event.normalizedX), \(event.normalizedY))")
        }
    }
}

public protocol InputInjectorDelegate: AnyObject {
    func injector(_ injector: InputInjector, didFailWith error: InputError)
}

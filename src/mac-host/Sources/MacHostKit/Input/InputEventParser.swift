import Foundation

/// 将 protocol `INPUT_EVENT` 的 JSON payload 解析为 `InputEvent`。
public enum InputEventParser {
    /// 解析单条 JSON payload。
    public static func parse(_ data: Data) -> Result<InputEvent, InputError> {
        do {
            let event = try JSONDecoder().decode(InputEvent.self, from: data)
            guard event.normalizedX >= 0.0 && event.normalizedX <= 1.0 &&
                  event.normalizedY >= 0.0 && event.normalizedY <= 1.0 else {
                return .failure(.invalidCoordinates(normalizedX: event.normalizedX, normalizedY: event.normalizedY))
            }
            return .success(event)
        } catch {
            // 尝试提取原始 event_type 用于错误信息。
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawType = json["event_type"] as? String {
                return .failure(.unknownEventType(rawType))
            }
            return .failure(.unknownEventType("<parse_error: \(error.localizedDescription)>"))
        }
    }
}

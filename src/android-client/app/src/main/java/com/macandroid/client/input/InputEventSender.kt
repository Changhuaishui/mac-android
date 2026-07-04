package com.macandroid.client.input

/**
 * 输入事件发送端抽象。
 *
 * TouchHandler / KeyboardHandler 只依赖此接口，便于单元测试和后续替换传输层。
 */
interface InputEventSender {
    fun sendInputEvent(event: InputEvent)
}

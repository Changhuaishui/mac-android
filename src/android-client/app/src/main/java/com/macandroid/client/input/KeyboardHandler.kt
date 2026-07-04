package com.macandroid.client.input

import android.util.Log
import android.view.KeyEvent
import android.view.View
import com.macandroid.client.input.InputEvent.EventType

/**
 * 基础按键事件监听器。
 *
 * 将方向键、回车、退格、Esc、字母数字等按键的 keyCode 发送给 Mac Host。
 * 只发送 keyCode 与 metaState，不记录用户输入的文本内容。
 */
class KeyboardHandler(
    private val sender: InputEventSender,
    private val coordinateMapper: CoordinateMapper
) : View.OnKeyListener {

    override fun onKey(v: View?, keyCode: Int, event: KeyEvent?): Boolean {
        if (event == null) return false

        val type = when (event.action) {
            KeyEvent.ACTION_DOWN -> EventType.KEY_DOWN
            KeyEvent.ACTION_UP -> EventType.KEY_UP
            else -> return false
        }

        val event = coordinateMapper.mapKey(type, keyCode, event.metaState)
        Log.d(TAG, "key ${event.type} code=${event.keyCode} meta=${event.metaState} display=${event.targetDisplayId}")
        sender.sendInputEvent(event)
        return true
    }

    companion object {
        private const val TAG = "MacInputKeyboard"
    }
}

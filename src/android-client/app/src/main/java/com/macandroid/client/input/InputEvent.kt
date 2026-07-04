package com.macandroid.client.input

import org.json.JSONObject

/**
 * Android Client → Mac Host 的输入事件。
 *
 * 触摸坐标必须归一化到 [0.0, 1.0]，以 SurfaceView 自身尺寸为基准。
 * 不携带也不记录用户输入的文本内容。
 */
data class InputEvent(
    val type: EventType,
    val x: Double = 0.0,
    val y: Double = 0.0,
    val deltaX: Double = 0.0,
    val deltaY: Double = 0.0,
    val keyCode: Int = 0,
    val metaState: Int = 0,
    val targetDisplayId: Int = 0
) {
    enum class EventType(val jsonName: String) {
        TOUCH_DOWN("touch_down"),
        TOUCH_MOVE("touch_move"),
        TOUCH_UP("touch_up"),
        WHEEL("wheel"),
        KEY_DOWN("key_down"),
        KEY_UP("key_up")
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("event_type", type.jsonName)
        put("pointer_id", 0)
        put("normalized_x", x)
        put("normalized_y", y)
        put("pressure", 1.0)
        put("key_code", keyCode)
        put("modifiers", org.json.JSONArray())
        put("wheel_delta_x", deltaX)
        put("wheel_delta_y", deltaY)
        put("target_display_id", targetDisplayId)
    }
}

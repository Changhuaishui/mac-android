package com.macandroid.client.input

import com.macandroid.client.display.DisplayModeManager

/**
 * 把 Android SurfaceView 上的输入坐标映射为 protocol v0 INPUT_EVENT。
 *
 * 当前职责：
 * - 将触摸坐标归一化到 [0.0, 1.0]。
 * - 为所有输入事件附加当前目标显示器 ID（来自 DisplayModeManager）。
 *
 * 不处理点击、长按、缩放等手势；不记录用户输入文本。
 */
class CoordinateMapper(private val displayModeManager: DisplayModeManager) {

    /**
     * 将 SurfaceView 像素坐标映射为带目标显示器 ID 的触摸事件。
     */
    fun mapTouch(
        rawX: Float,
        rawY: Float,
        surfaceWidth: Int,
        surfaceHeight: Int,
        type: InputEvent.EventType
    ): InputEvent {
        val nx = normalize(rawX, surfaceWidth)
        val ny = normalize(rawY, surfaceHeight)
        return InputEvent(
            type = type,
            x = nx,
            y = ny,
            targetDisplayId = displayModeManager.targetDisplayId
        )
    }

    /**
     * 将双指滚动增量映射为带目标显示器 ID 的滚轮事件。
     */
    fun mapWheel(deltaX: Double, deltaY: Double): InputEvent {
        return InputEvent(
            type = InputEvent.EventType.WHEEL,
            deltaX = deltaX,
            deltaY = deltaY,
            targetDisplayId = displayModeManager.targetDisplayId
        )
    }

    /**
     * 将 Android 按键事件映射为带目标显示器 ID 的 key_down / key_up 事件。
     */
    fun mapKey(type: InputEvent.EventType, keyCode: Int, metaState: Int): InputEvent {
        return InputEvent(
            type = type,
            keyCode = keyCode,
            metaState = metaState,
            targetDisplayId = displayModeManager.targetDisplayId
        )
    }

    private fun normalize(value: Float, size: Int): Double {
        return if (size > 0) {
            (value / size).toDouble().coerceIn(0.0, 1.0)
        } else {
            0.0
        }
    }
}

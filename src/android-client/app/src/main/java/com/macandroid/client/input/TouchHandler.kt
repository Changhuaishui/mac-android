package com.macandroid.client.input

import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import com.macandroid.client.input.InputEvent.EventType

/**
 * SurfaceView 触摸事件监听器。
 *
 * 职责：
 * - 单指 touch_down / touch_move / touch_up 转换为归一化坐标事件。
 * - 双指滚动（可选）转换为 wheel 事件。
 *
 * 不处理点击、长按、缩放等手势；不记录任何文本内容。
 */
class TouchHandler(
    private val sender: InputEventSender,
    private val coordinateMapper: CoordinateMapper,
    private val surfaceView: SurfaceView
) : View.OnTouchListener {

    private var activePointerCount = 0
    private var lastWheelCenterY = 0f

    override fun onTouch(v: View?, event: MotionEvent?): Boolean {
        if (event == null) return false

        val width = surfaceView.width
        val height = surfaceView.height
        if (width <= 0 || height <= 0) return false

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                activePointerCount = 1
                sendTouch(EventType.TOUCH_DOWN, event.x, event.y, width, height)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                activePointerCount = event.pointerCount
                if (event.pointerCount == 2) {
                    lastWheelCenterY = wheelCenterY(event)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount == 2) {
                    handleTwoFingerScroll(event, height)
                } else if (event.pointerCount == 1) {
                    sendTouch(EventType.TOUCH_MOVE, event.x, event.y, width, height)
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                activePointerCount = event.pointerCount - 1
            }
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                activePointerCount = 0
                if (event.pointerCount == 1) {
                    sendTouch(EventType.TOUCH_UP, event.x, event.y, width, height)
                }
            }
        }
        return true
    }

    private fun handleTwoFingerScroll(event: MotionEvent, height: Int) {
        val centerY = wheelCenterY(event)
        val deltaPixels = centerY - lastWheelCenterY
        if (kotlin.math.abs(deltaPixels) < WHEEL_PIXEL_THRESHOLD) return

        lastWheelCenterY = centerY
        val normalizedDelta = -(deltaPixels / height.toFloat()).toDouble() * WHEEL_SENSITIVITY

        Log.d(TAG, "wheel deltaY=$normalizedDelta")
        sender.sendInputEvent(
            coordinateMapper.mapWheel(
                deltaX = 0.0,
                deltaY = normalizedDelta.coerceIn(-1.0, 1.0)
            )
        )
    }

    private fun wheelCenterY(event: MotionEvent): Float {
        if (event.pointerCount < 2) return 0f
        val y0 = event.getY(0)
        val y1 = event.getY(1)
        return (y0 + y1) / 2f
    }

    private fun sendTouch(type: EventType, rawX: Float, rawY: Float, width: Int, height: Int) {
        val event = coordinateMapper.mapTouch(rawX, rawY, width, height, type)
        Log.d(TAG, "touch ${event.type} x=${event.x} y=${event.y} display=${event.targetDisplayId}")
        sender.sendInputEvent(event)
    }

    companion object {
        private const val TAG = "MacInputTouch"
        private const val WHEEL_PIXEL_THRESHOLD = 8f
        private const val WHEEL_SENSITIVITY = 8.0
    }
}

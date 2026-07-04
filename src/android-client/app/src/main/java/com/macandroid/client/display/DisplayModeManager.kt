package com.macandroid.client.display

import android.util.Log
import com.macandroid.client.Protocol
import com.macandroid.client.VideoConfig

private const val TAG = "MacDisplayModeManager"

/**
 * 管理 Android Client 当前的显示模式。
 *
 * 职责：
 * - 根据 Mac Host 下发的 VIDEO_CONFIG 切换 MIRROR / EXTENDED 模式。
 * - 维护目标显示器 ID、目标显示器边界与目标刷新率。
 * - 模式变化时通过回调通知 UI 刷新。
 *
 * 禁止把模式判断逻辑下放到 MainActivity；MainActivity 只负责把 VIDEO_CONFIG
 * 路由到这里，并在回调中更新界面。
 */
class DisplayModeManager {

    @Volatile
    private var _currentMode: DisplayMode = DisplayMode.MIRROR
    val currentMode: DisplayMode get() = _currentMode

    @Volatile
    var targetDisplayId: Int = Protocol.DEFAULT_TARGET_DISPLAY_ID
        private set

    @Volatile
    var targetDisplayBounds: DisplayBounds? = null
        private set

    @Volatile
    var targetFps: Int = 0
        private set

    /**
     * 模式或目标显示器发生变化时触发。
     * 回调运行在调用 updateFromVideoConfig 的线程，UI 更新需自行 post 到主线程。
     */
    var onModeChanged: (() -> Unit)? = null

    /**
     * 从 VIDEO_CONFIG 解析并更新当前模式。
     *
     * 缺少 display_mode 字段时默认回到 MIRROR，保证与旧 Mac Host 兼容。
     */
    fun updateFromVideoConfig(config: VideoConfig?) {
        val newMode = config?.displayModeEnum() ?: DisplayMode.MIRROR
        val newId = config?.targetDisplayId ?: Protocol.DEFAULT_TARGET_DISPLAY_ID
        val newBounds = config?.targetDisplayBounds
        val newFps = config?.fps ?: 0

        val changed = newMode != _currentMode
                || newId != targetDisplayId
                || newBounds != targetDisplayBounds
                || newFps != targetFps

        if (changed) {
            _currentMode = newMode
            targetDisplayId = newId
            targetDisplayBounds = newBounds
            targetFps = newFps
            Log.i(
                TAG,
                "Display mode changed: mode=$newMode, target_display_id=$newId, " +
                        "bounds=${newBounds}, fps=$newFps"
            )
            onModeChanged?.invoke()
        }
    }

    /**
     * 断开连接或回到初始状态时调用，默认回到镜像模式。
     */
    fun reset() {
        updateFromVideoConfig(null)
    }
}

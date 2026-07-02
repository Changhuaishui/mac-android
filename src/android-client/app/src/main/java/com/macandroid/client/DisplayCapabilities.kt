package com.macandroid.client

import android.app.Activity
import android.graphics.Point
import android.graphics.Rect
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import android.view.SurfaceView
import org.json.JSONArray
import org.json.JSONObject

private const val TAG = "MacDisplayCapabilities"

/**
 * 设备显示能力数据类。
 *
 * 所有字段都通过 Android 原生 API 在运行时读取，不依赖网页规格或硬编码。
 */
data class DisplayModeInfo(
    val modeId: Int,
    val physicalWidth: Int,
    val physicalHeight: Int,
    val refreshRate: Float
)

data class SizeInfo(
    val width: Int,
    val height: Int
)

data class DisplayCapabilities(
    val deviceName: String,
    val currentMode: DisplayModeInfo?,
    val supportedModes: List<DisplayModeInfo>,
    val windowBounds: SizeInfo,
    val surfaceSize: SizeInfo,
    val density: Float,
    val densityDpi: Int,
    val orientation: String
) {
    /**
     * 导出为稳定 JSON，供日志贴回与分析。
     *
     * 注意：refresh_rate 原样使用 Android Display.Mode.getRefreshRate() 返回的 Float 值，
     * 不转 Int、不归一化。Mac Host 负责按真实值决策 FPS。
     */
    fun toJson(): JSONObject {
        val current = currentMode?.let {
            JSONObject().apply {
                put("mode_id", it.modeId)
                put("physical_width", it.physicalWidth)
                put("physical_height", it.physicalHeight)
                put("refresh_rate", it.refreshRate.toDouble())
            }
        } ?: JSONObject.NULL

        val modes = JSONArray()
        supportedModes.forEach {
            modes.put(JSONObject().apply {
                put("mode_id", it.modeId)
                put("physical_width", it.physicalWidth)
                put("physical_height", it.physicalHeight)
                put("refresh_rate", it.refreshRate.toDouble())
            })
        }

        return JSONObject().apply {
            put("device_name", deviceName)
            put("display_capabilities", JSONObject().apply {
                put("current_mode", current)
                put("supported_modes", modes)
                put("window_bounds", JSONObject().apply {
                    put("width", windowBounds.width)
                    put("height", windowBounds.height)
                })
                put("surface_size", JSONObject().apply {
                    put("width", surfaceSize.width)
                    put("height", surfaceSize.height)
                })
                put("density", density.toDouble())
                put("density_dpi", densityDpi)
                put("orientation", orientation)
            })
        }
    }

    /**
     * 原生画质候选列表。
     *
     * 规则：
     * 1. 优先当前 Display Mode 的物理分辨率。
     * 2. 同分辨率多刷新率全部列出。
     * 3. 不强行选择 144/120/60Hz。
     */
    fun nativeCandidates(): List<String> {
        val base = currentMode ?: supportedModes.firstOrNull() ?: return emptyList()
        val sameResolution = supportedModes.filter {
            it.physicalWidth == base.physicalWidth && it.physicalHeight == base.physicalHeight
        }
        val candidates = if (sameResolution.isNotEmpty()) sameResolution else listOf(base)
        return candidates
            .sortedByDescending { it.refreshRate }
            .map { "${it.physicalWidth}x${it.physicalHeight} @ ${formatRefreshRate(it.refreshRate)}Hz" }
            .distinct()
    }

    /**
     * 界面展示用的单行摘要。
     */
    fun summaryText(): String {
        val current = currentMode?.let {
            "${it.physicalWidth}x${it.physicalHeight} @ ${formatRefreshRate(it.refreshRate)}Hz"
        } ?: "未知"
        val candidate = nativeCandidates().firstOrNull() ?: "未知"
        val surface = "${surfaceSize.width}x${surfaceSize.height}"
        return "当前模式：$current\n推荐原生候选：$candidate\nApp Surface：$surface"
    }

    companion object {
        /**
         * UI 展示用：四舍五入到 1-2 位小数，避免 `59.999004` 这种原始 Float 直接显示。
         * logcat JSON 与 HELLO JSON 仍使用原始 Float/Double。
         */
        fun formatRefreshRate(rate: Float): String {
            val rounded = (Math.round(rate * 100.0) / 100.0)
            return if (rounded == rounded.toLong().toDouble()) {
                rounded.toLong().toString()
            } else {
                rounded.toString()
            }
        }
    }
}

object DisplayCapabilitiesReader {

    /**
     * 读取当前 Activity 的完整显示能力。
     *
     * API 30+ 优先使用 WindowMetrics；API 29 及以下使用 Display 相关 API。
     * 所有分支都带 fallback，不会崩溃。
     *
     * refresh_rate 保持 Android Display.Mode.getRefreshRate() 原始 Float 值，不做 FPS 归一化。
     */
    fun read(activity: Activity, surfaceView: SurfaceView): DisplayCapabilities {
        val display = resolveDisplay(activity)

        val currentMode = readCurrentMode(display)
        val supportedModes = readSupportedModes(display)
        val windowBounds = readWindowBounds(activity)
        val surfaceSize = readSurfaceSize(surfaceView)
        val (density, densityDpi) = readDensity(activity)
        val orientation = readOrientation(activity)

        val capabilities = DisplayCapabilities(
            deviceName = Build.MODEL ?: "android tablet",
            currentMode = currentMode,
            supportedModes = supportedModes,
            windowBounds = windowBounds,
            surfaceSize = surfaceSize,
            density = density,
            densityDpi = densityDpi,
            orientation = orientation
        )

        Log.i(TAG, "Display capabilities: ${capabilities.toJson().toString(2)}")
        return capabilities
    }

    private fun resolveDisplay(activity: Activity): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
    }

    private fun readCurrentMode(display: Display?): DisplayModeInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || display == null) {
            return null
        }
        val mode = display.mode ?: return null
        return DisplayModeInfo(
            modeId = mode.modeId,
            physicalWidth = mode.physicalWidth,
            physicalHeight = mode.physicalHeight,
            refreshRate = mode.refreshRate
        )
    }

    private fun readSupportedModes(display: Display?): List<DisplayModeInfo> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || display == null) {
            return emptyList()
        }
        return display.supportedModes.map { mode ->
            DisplayModeInfo(
                modeId = mode.modeId,
                physicalWidth = mode.physicalWidth,
                physicalHeight = mode.physicalHeight,
                refreshRate = mode.refreshRate
            )
        }
    }

    private fun readWindowBounds(activity: Activity): SizeInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds: Rect = activity.windowManager.currentWindowMetrics.bounds
            SizeInfo(bounds.width(), bounds.height())
        } else {
            val size = Point()
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay?.getSize(size)
            SizeInfo(size.x, size.y)
        }
    }

    private fun readSurfaceSize(surfaceView: SurfaceView): SizeInfo {
        val width = if (surfaceView.width > 0) surfaceView.width else surfaceView.holder.surfaceFrame.width()
        val height = if (surfaceView.height > 0) surfaceView.height else surfaceView.holder.surfaceFrame.height()
        return SizeInfo(
            width = if (width > 0) width else 0,
            height = if (height > 0) height else 0
        )
    }

    private fun readDensity(activity: Activity): Pair<Float, Int> {
        val metrics: DisplayMetrics = activity.resources.displayMetrics
        return Pair(metrics.density, metrics.densityDpi)
    }

    private fun readOrientation(activity: Activity): String {
        return when (activity.resources.configuration.orientation) {
            android.content.res.Configuration.ORIENTATION_LANDSCAPE -> "landscape"
            android.content.res.Configuration.ORIENTATION_PORTRAIT -> "portrait"
            android.content.res.Configuration.ORIENTATION_SQUARE -> "square"
            else -> "undefined"
        }
    }
}

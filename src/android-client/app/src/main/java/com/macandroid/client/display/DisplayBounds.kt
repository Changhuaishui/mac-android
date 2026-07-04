package com.macandroid.client.display

/**
 * 目标显示器在 Mac 全局坐标系中的边界。
 *
 * 由 Mac Host 通过 VIDEO_CONFIG.target_display_bounds 下发，
 * Android Client 仅做透传与日志，不用于本地像素映射（v0 坐标归一化由 Android 端完成）。
 */
data class DisplayBounds(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int
)

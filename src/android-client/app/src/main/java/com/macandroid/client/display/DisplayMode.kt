package com.macandroid.client.display

/**
 * Android Client 当前相对于 Mac Host 的显示模式。
 */
enum class DisplayMode(val jsonName: String) {
    /** 镜像 Mac 主屏内容（M1/M2 默认行为）。 */
    MIRROR("mirror"),

    /** 作为 Mac 独立扩展屏显示虚拟显示器内容（M3）。 */
    EXTENDED("extended");

    companion object {
        fun fromString(value: String?): DisplayMode = when (value) {
            EXTENDED.jsonName -> EXTENDED
            else -> MIRROR
        }
    }
}

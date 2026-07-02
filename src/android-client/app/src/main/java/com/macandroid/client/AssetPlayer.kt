package com.macandroid.client

import android.content.res.AssetManager
import android.util.Log
import java.io.IOException
import kotlin.concurrent.thread

private const val TAG = "MacAssetPlayer"

interface AssetPlayerListener {
    fun onAssetStarted(assetName: String, totalFrameCount: Int)
    fun onAssetFrame(frameIndex: Int)
    fun onAssetFinished(assetName: String, totalFrames: Int)
    fun onAssetError(error: String)
}

/**
 * 从 assets 读取 Annex B H.264 fixture，直接送入 VideoDecoder。
 *
 * 不等 Mac Host，用于 M1 独立验证：
 * assets/sample-annexb.h264 → MediaCodec → SurfaceView
 */
class AssetPlayer(
    private val assets: AssetManager,
    private val decoder: VideoDecoder,
    private val listener: AssetPlayerListener
) {

    @Volatile
    private var running = false
    private var playerThread: Thread? = null

    /**
     * 播放指定 asset 文件。
     *
     * @param assetName assets 下的文件名，如 "sample-annexb.h264"
     * @param fps 播放帧率，fixture 为 30fps
     */
    fun play(assetName: String, fps: Int = 30) {
        stop()
        running = true
        playerThread = thread(name = "MacAssetPlayer") {
            try {
                val data = readAsset(assetName)
                if (data.isEmpty()) {
                    listener.onAssetError("Asset is empty: $assetName")
                    return@thread
                }
                val accessUnits = splitAnnexBAccessUnits(data)
                if (accessUnits.isEmpty()) {
                    listener.onAssetError("No Annex B access units found in $assetName")
                    return@thread
                }

                Log.i(TAG, "Playing asset $assetName, frames=${accessUnits.size}, fps=$fps")
                listener.onAssetStarted(assetName, accessUnits.size)

                val frameIntervalNs = 1_000_000_000L / fps
                val startTimeNs = System.nanoTime()

                for ((index, au) in accessUnits.withIndex()) {
                    if (!running) {
                        Log.i(TAG, "Asset playback stopped at frame $index")
                        break
                    }

                    val flags = if (isKeyframeAccessUnit(au)) {
                        Protocol.FLAG_KEYFRAME or Protocol.FLAG_CONFIG
                    } else {
                        0
                    }
                    val ptsUs = index * 1_000_000L / fps

                    if (!decoder.queueFrame(au, flags, ptsUs)) {
                        Log.w(TAG, "Decoder queue full at frame $index")
                    }
                    listener.onAssetFrame(index)

                    // 按目标帧率控制播放节奏
                    val expectedTimeNs = startTimeNs + index * frameIntervalNs
                    val sleepNs = expectedTimeNs - System.nanoTime()
                    if (sleepNs > 0) {
                        Thread.sleep(sleepNs / 1_000_000, (sleepNs % 1_000_000).toInt())
                    }
                }

                listener.onAssetFinished(assetName, accessUnits.size)
            } catch (e: IOException) {
                Log.e(TAG, "Failed to read asset", e)
                listener.onAssetError("Failed to read asset: ${e.message}")
            } catch (e: Exception) {
                Log.e(TAG, "Asset playback error", e)
                listener.onAssetError("Asset playback error: ${e.message}")
            } finally {
                running = false
            }
        }
    }

    fun stop() {
        running = false
        playerThread?.interrupt()
        playerThread = null
    }

    fun isPlaying(): Boolean = running

    private fun readAsset(assetName: String): ByteArray {
        return assets.open(assetName).use { it.readBytes() }
    }

    /**
     * 将 Annex B byte stream 拆分为 access unit（帧）。
     *
     * 策略：按 VCL NALU（slice，类型 1 或 5）作为新帧边界；
     * SPS/PPS/SEI 等非 VCL NALU 附加到当前帧。
     */
    private fun splitAnnexBAccessUnits(data: ByteArray): List<ByteArray> {
        val nalus = mutableListOf<Pair<Int, Int>>()
        var i = 0
        while (i < data.size - 3) {
            val startCodeLen = when {
                i + 3 < data.size &&
                    data[i] == 0x00.toByte() &&
                    data[i + 1] == 0x00.toByte() &&
                    data[i + 2] == 0x00.toByte() &&
                    data[i + 3] == 0x01.toByte() -> 4
                data[i] == 0x00.toByte() &&
                    data[i + 1] == 0x00.toByte() &&
                    data[i + 2] == 0x01.toByte() -> 3
                else -> 0
            }
            if (startCodeLen > 0) {
                if (nalus.isNotEmpty()) {
                    val last = nalus.last()
                    nalus[nalus.size - 1] = last.first to i
                }
                nalus.add(i to data.size)
                i += startCodeLen
            } else {
                i++
            }
        }

        val accessUnits = mutableListOf<ByteArray>()
        var currentAu = ByteArray(0)
        for ((start, end) in nalus) {
            val nalu = data.copyOfRange(start, end)
            val headerLen = if (nalu.size >= 4 &&
                nalu[2] == 0x00.toByte() &&
                nalu[3] == 0x01.toByte()
            ) 4 else 3
            val naluType = if (nalu.size > headerLen) {
                nalu[headerLen].toInt() and 0x1F
            } else {
                -1
            }

            // VCL NALU（1=non-IDR slice, 5=IDR slice）开始新的 access unit
            if ((naluType == 1 || naluType == 5) && currentAu.isNotEmpty()) {
                accessUnits.add(currentAu)
                currentAu = nalu
            } else {
                currentAu += nalu
            }
        }
        if (currentAu.isNotEmpty()) {
            accessUnits.add(currentAu)
        }

        return accessUnits
    }

    private fun isKeyframeAccessUnit(au: ByteArray): Boolean {
        var i = 0
        while (i < au.size - 4) {
            val startCodeLen = when {
                au[i] == 0x00.toByte() && au[i + 1] == 0x00.toByte() &&
                    au[i + 2] == 0x00.toByte() && au[i + 3] == 0x01.toByte() -> 4
                au[i] == 0x00.toByte() && au[i + 1] == 0x00.toByte() &&
                    au[i + 2] == 0x01.toByte() -> 3
                else -> 0
            }
            if (startCodeLen > 0 && i + startCodeLen < au.size) {
                val type = au[i + startCodeLen].toInt() and 0x1F
                if (type == 5) return true
                i += startCodeLen
            } else {
                i++
            }
        }
        return false
    }
}

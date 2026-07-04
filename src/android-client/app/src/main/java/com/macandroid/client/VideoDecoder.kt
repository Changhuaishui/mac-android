package com.macandroid.client

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "MacVideoDecoder"
private const val DEFAULT_WIDTH = 1280
private const val DEFAULT_HEIGHT = 800
private const val DEFAULT_FPS = 30

interface VideoDecoderListener {
    fun onDecoderError(error: String)
    fun onRequestKeyframe()
}

/**
 * 待解码的帧。
 */
data class DecodableFrame(
    val data: ByteArray,
    val flags: Int,
    val presentationTimeUs: Long
)

private const val MAX_QUEUE_SIZE = 5
private const val MAX_QUEUE_AGE_MS = 500

/**
 * M1 Android Client 视频解码器。
 *
 * v0 协议固定使用 H.264 Annex B byte stream：每个 VIDEO_FRAME payload 自身即为完整
 * Annex B 数据，SPS/PPS 已包含在关键帧 payload 中。Android 端不依赖 VIDEO_CONFIG
 * 携带二进制配置数据，也不把配置帧额外拼接到后续帧。
 *
 * M3 收尾优化：队列深度降到 5，并丢弃超过 500ms 的老非关键帧，降低端到端延迟。
 */
class VideoDecoder(private val listener: VideoDecoderListener) {

    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var configuredWidth = DEFAULT_WIDTH
    private var configuredHeight = DEFAULT_HEIGHT
    private var configuredFps = DEFAULT_FPS

    private val running = AtomicBoolean(false)
    private val queue = ArrayBlockingQueue<DecodableFrame>(MAX_QUEUE_SIZE)
    private var decoderThread: Thread? = null

    @Synchronized
    fun configure(width: Int, height: Int, fps: Int, surface: Surface) {
        release()
        this.configuredWidth = width
        this.configuredHeight = height
        this.configuredFps = fps
        this.surface = surface
        startDecoderThread()
    }

    @Synchronized
    fun release() {
        running.set(false)
        decoderThread?.interrupt()
        decoderThread = null
        queue.clear()
        try {
            codec?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "stop codec error", e)
        }
        try {
            codec?.release()
        } catch (e: Exception) {
            Log.w(TAG, "release codec error", e)
        }
        codec = null
    }

    fun queueFrame(data: ByteArray, flags: Int, presentationTimeUs: Long): Boolean {
        val nowUs = System.nanoTime() / 1000
        val ageUs = nowUs - presentationTimeUs
        val ageMs = ageUs / 1000
        val isKeyframe = (flags and Protocol.FLAG_KEYFRAME) != 0

        // 丢弃过老的非关键帧，降低延迟。
        if (!isKeyframe && ageMs > MAX_QUEUE_AGE_MS) {
            Log.d(TAG, "Drop stale frame: age=${ageMs}ms, keyframe=$isKeyframe")
            return true
        }

        val success = queue.offer(DecodableFrame(data, flags, presentationTimeUs))
        if (!success) {
            Log.w(TAG, "Decoder queue full, dropped frame")
            // 队列满时尝试丢弃最旧的一帧非关键帧，给新帧腾位置。
            val oldest = queue.peek()
            if (oldest != null && (oldest.flags and Protocol.FLAG_KEYFRAME) == 0) {
                queue.poll()
                queue.offer(DecodableFrame(data, flags, presentationTimeUs))
                Log.w(TAG, "Dropped oldest non-keyframe to make room")
                return true
            }
        }
        return success
    }

    fun queueSize(): Int = queue.size

    private fun startDecoderThread() {
        running.set(true)
        decoderThread = Thread({ decoderLoop() }, "MacVideoDecoder").apply {
            isDaemon = true
            start()
        }
    }

    private fun decoderLoop() {
        var consecutiveErrors = 0
        while (running.get() && !Thread.currentThread().isInterrupted) {
            try {
                val frame = queue.take()
                ensureCodecInitialized()
                val c = codec ?: continue

                if (!feedInput(c, frame.data, frame.presentationTimeUs)) {
                    consecutiveErrors++
                    if (consecutiveErrors >= 5) {
                        listener.onRequestKeyframe()
                        consecutiveErrors = 0
                    }
                    continue
                }

                drainOutput(c)
                consecutiveErrors = 0
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (e: Exception) {
                Log.e(TAG, "Decoder loop error", e)
                listener.onDecoderError("Decoder loop error: ${e.message}")
                consecutiveErrors++
                if (consecutiveErrors >= 5) {
                    listener.onRequestKeyframe()
                    consecutiveErrors = 0
                }
            }
        }
    }

    @Synchronized
    private fun ensureCodecInitialized() {
        if (codec != null) return
        val s = surface ?: return

        try {
            val mediaFormat = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                configuredWidth,
                configuredHeight
            )
            mediaFormat.setInteger(MediaFormat.KEY_FRAME_RATE, configuredFps)

            val c = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            c.configure(mediaFormat, s, null, 0)
            c.start()
            codec = c
            Log.i(TAG, "Decoder initialized: ${configuredWidth}x${configuredHeight} @${configuredFps}fps")
        } catch (e: IOException) {
            Log.e(TAG, "Failed to create decoder", e)
            listener.onDecoderError("Failed to create decoder: ${e.message}")
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Decoder configure failed", e)
            listener.onDecoderError("Decoder configure failed: ${e.message}")
        }
    }

    private fun feedInput(codec: MediaCodec, data: ByteArray, presentationTimeUs: Long): Boolean {
        return try {
            val inputBufferId = codec.dequeueInputBuffer(10_000)
            if (inputBufferId < 0) {
                Log.w(TAG, "No input buffer available")
                return false
            }
            val buffer = codec.getInputBuffer(inputBufferId) ?: return false
            buffer.clear()
            buffer.put(data)
            codec.queueInputBuffer(
                inputBufferId,
                0,
                data.size,
                presentationTimeUs,
                0
            )
            true
        } catch (e: IllegalStateException) {
            Log.e(TAG, "feedInput failed", e)
            false
        }
    }

    private fun drainOutput(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        try {
            var outputBufferId = codec.dequeueOutputBuffer(info, 10_000)
            while (outputBufferId >= 0) {
                codec.releaseOutputBuffer(outputBufferId, true)
                outputBufferId = codec.dequeueOutputBuffer(info, 0)
            }
            if (outputBufferId == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                Log.i(TAG, "Output format changed: ${codec.outputFormat}")
            }
        } catch (e: IllegalStateException) {
            Log.e(TAG, "drainOutput failed", e)
        }
    }
}

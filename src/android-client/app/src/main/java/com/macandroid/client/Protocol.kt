package com.macandroid.client

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * mac-android protocol v0
 *
 * 所有多字节字段采用大端（网络字节序）。
 *
 * Header（32 字节）：
 *   u32 magic        = 'MADS' (0x4D414453)
 *   u16 version      = 0
 *   u16 type
 *   u64 sequence
 *   u64 timestamp_ns
 *   u32 flags
 *   u32 payload_len
 *
 * Message types:
 *   HELLO          = 0
 *   VIDEO_CONFIG   = 1
 *   VIDEO_FRAME    = 2
 *   PING           = 3
 *   ERROR          = 4
 *
 * Flags (VIDEO_FRAME):
 *   KEYFRAME = 0x01
 *   CONFIG   = 0x02   // 该帧携带 SPS/PPS 等配置数据
 */
object Protocol {

    const val MAGIC: Int = 0x4D414453.toInt()
    const val VERSION: Short = 0

    const val HEADER_SIZE = 32

    const val TYPE_HELLO = 0
    const val TYPE_VIDEO_CONFIG = 1
    const val TYPE_VIDEO_FRAME = 2
    const val TYPE_PING = 3
    const val TYPE_ERROR = 4

    const val FLAG_KEYFRAME = 0x01
    const val FLAG_CONFIG = 0x02

    fun typeName(type: Int): String = when (type) {
        TYPE_HELLO -> "HELLO"
        TYPE_VIDEO_CONFIG -> "VIDEO_CONFIG"
        TYPE_VIDEO_FRAME -> "VIDEO_FRAME"
        TYPE_PING -> "PING"
        TYPE_ERROR -> "ERROR"
        else -> "UNKNOWN($type)"
    }
}

/**
 * 解析后的 protocol v0 消息。
 */
data class Message(
    val version: Int,
    val type: Int,
    val sequence: Long,
    val timestampNs: Long,
    val flags: Int,
    val payload: ByteArray
) {
    val isKeyframe: Boolean
        get() = (flags and Protocol.FLAG_KEYFRAME) != 0

    val isConfig: Boolean
        get() = (flags and Protocol.FLAG_CONFIG) != 0

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Message) return false
        return version == other.version &&
                type == other.type &&
                sequence == other.sequence &&
                timestampNs == other.timestampNs &&
                flags == other.flags &&
                payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = version
        result = 31 * result + type
        result = 31 * result + sequence.hashCode()
        result = 31 * result + timestampNs.hashCode()
        result = 31 * result + flags
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

/**
 * VIDEO_CONFIG payload 的 JSON 表示。
 *
 * v0 协议规定 `stream_format` 为 "annex_b"；为兼容旧字段也读取 `format`，
 * 内部统一转换为协议值 "annex_b"。M1 固定 Annex B byte stream。
 */
data class VideoConfig(
    val width: Int,
    val height: Int,
    val fps: Int,
    val codec: String,
    val streamFormat: String
) {
    companion object {
        fun fromPayload(payload: ByteArray): VideoConfig {
            val json = JSONObject(payload.toString(Charsets.UTF_8))
            val rawFormat = json.optString(
                "stream_format",
                json.optString("format", "annex_b")
            )
            return VideoConfig(
                width = json.optInt("width", 1280),
                height = json.optInt("height", 800),
                fps = json.optInt("fps", 30),
                codec = json.optString("codec", "h264"),
                streamFormat = normalizeStreamFormat(rawFormat)
            )
        }

        private fun normalizeStreamFormat(value: String): String = when (value.lowercase()) {
            "annex_b", "annex-b", "annexb" -> "annex_b"
            else -> "annex_b"
        }
    }
}

/**
 * 用于从输入流读取并解析 protocol v0 消息。
 */
class MessageParser {

    private val headerBuffer = ByteBuffer.allocate(Protocol.HEADER_SIZE).apply {
        order(ByteOrder.BIG_ENDIAN)
    }
    private var headerPosition = 0

    private var pendingMessage: Message? = null
    private var payloadBuffer: ByteBuffer? = null

    /**
     * 向解析器投喂数据，返回所有完整解析出的消息。
     */
    fun feed(data: ByteArray, offset: Int, length: Int): List<Message> {
        val messages = mutableListOf<Message>()
        var pos = offset
        val end = offset + length

        while (pos < end) {
            if (pendingMessage == null) {
                // 正在读 header
                val toRead = minOf(Protocol.HEADER_SIZE - headerPosition, end - pos)
                headerBuffer.put(data, pos, toRead)
                headerPosition += toRead
                pos += toRead

                if (headerPosition >= Protocol.HEADER_SIZE) {
                    headerBuffer.flip()
                    val magic = headerBuffer.int
                    if (magic != Protocol.MAGIC) {
                        throw ProtocolException("Bad magic: 0x${magic.toString(16)}, expected 0x${Protocol.MAGIC.toString(16)}")
                    }
                    val version = headerBuffer.short.toInt() and 0xFFFF
                    val type = headerBuffer.short.toInt() and 0xFFFF
                    val sequence = headerBuffer.long
                    val timestampNs = headerBuffer.long
                    val flags = headerBuffer.int
                    val payloadLen = headerBuffer.int

                    headerBuffer.clear()
                    headerPosition = 0

                    if (payloadLen < 0 || payloadLen > 16 * 1024 * 1024) {
                        throw ProtocolException("Invalid payload length: $payloadLen")
                    }

                    if (payloadLen == 0) {
                        messages.add(
                            Message(
                                version = version,
                                type = type,
                                sequence = sequence,
                                timestampNs = timestampNs,
                                flags = flags,
                                payload = ByteArray(0)
                            )
                        )
                    } else {
                        pendingMessage = Message(
                            version = version,
                            type = type,
                            sequence = sequence,
                            timestampNs = timestampNs,
                            flags = flags,
                            payload = ByteArray(payloadLen)
                        )
                        payloadBuffer = ByteBuffer.wrap(pendingMessage!!.payload)
                    }
                }
            } else {
                // 正在读 payload
                val pending = pendingMessage!!
                val buf = payloadBuffer!!
                val remaining = buf.remaining()
                val toRead = minOf(remaining, end - pos)
                buf.put(data, pos, toRead)
                pos += toRead

                if (!buf.hasRemaining()) {
                    messages.add(pending)
                    pendingMessage = null
                    payloadBuffer = null
                }
            }
        }

        return messages
    }

    fun reset() {
        headerBuffer.clear()
        headerPosition = 0
        pendingMessage = null
        payloadBuffer = null
    }
}

class ProtocolException(message: String) : Exception(message)

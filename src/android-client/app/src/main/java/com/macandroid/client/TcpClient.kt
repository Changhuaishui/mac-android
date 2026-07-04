package com.macandroid.client

import android.util.Log
import com.macandroid.client.input.InputEvent
import com.macandroid.client.input.InputEventSender
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

private const val TAG = "MacTcpClient"
private const val CONNECT_TIMEOUT_MS = 5000
private const val SOCKET_TIMEOUT_MS = 2000
private const val READ_BUFFER_SIZE = 65536

interface TcpClientListener {
    fun onConnectionStateChanged(state: ConnectionState)
    fun onMessage(message: Message)
    fun onError(error: String)
}

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED
}

class TcpClient(private val listener: TcpClientListener) : InputEventSender {

    private val running = AtomicBoolean(false)
    private var socket: Socket? = null
    private var readerThread: Thread? = null
    private val parser = MessageParser()
    private val inputSequence = AtomicLong(0)

    @Volatile
    private var currentHost: String = ""
    @Volatile
    private var currentPort: Int = 0
    @Volatile
    private var displayCapabilities: DisplayCapabilities? = null

    /**
     * 设置连接时发送的 HELLO 中使用的设备显示能力。
     */
    fun setDisplayCapabilities(capabilities: DisplayCapabilities?) {
        this.displayCapabilities = capabilities
    }

    fun connect(host: String, port: Int) {
        if (running.get()) {
            disconnect()
        }
        currentHost = host
        currentPort = port
        running.set(true)
        parser.reset()
        readerThread = Thread({ readerLoop(host, port) }, "MacTcpReader").apply {
            isDaemon = true
            start()
        }
    }

    fun disconnect() {
        running.set(false)
        try {
            socket?.close()
        } catch (e: IOException) {
            Log.w(TAG, "close socket error", e)
        }
        socket = null
        readerThread?.interrupt()
        readerThread = null
        listener.onConnectionStateChanged(ConnectionState.DISCONNECTED)
    }

    fun isConnected(): Boolean = socket?.isConnected == true && socket?.isClosed == false

    fun sendError(text: String) {
        val s = socket ?: return
        try {
            val payload = text.toByteArray(Charsets.UTF_8)
            val header = buildHeader(Protocol.TYPE_ERROR, 0, System.nanoTime(), 0, payload.size)
            val out = s.getOutputStream()
            synchronized(out) {
                out.write(header)
                out.write(payload)
                out.flush()
            }
        } catch (e: IOException) {
            Log.w(TAG, "send error failed", e)
        }
    }

    override fun sendInputEvent(event: InputEvent) {
        val s = socket ?: return
        try {
            val payload = event.toJson().toString().toByteArray(Charsets.UTF_8)
            val seq = inputSequence.incrementAndGet()
            val header = buildHeader(Protocol.TYPE_INPUT_EVENT, seq, System.nanoTime(), 0, payload.size)
            val out = s.getOutputStream()
            synchronized(out) {
                out.write(header)
                out.write(payload)
                out.flush()
            }
        } catch (e: IOException) {
            Log.w(TAG, "send input event failed", e)
        }
    }

    private fun readerLoop(host: String, port: Int) {
        listener.onConnectionStateChanged(ConnectionState.CONNECTING)
        val socket = Socket()
        this.socket = socket

        try {
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            socket.soTimeout = SOCKET_TIMEOUT_MS
            listener.onConnectionStateChanged(ConnectionState.CONNECTED)

            val input = socket.getInputStream()
            val buffer = ByteArray(READ_BUFFER_SIZE)

            // 发送 HELLO
            sendHello(socket)

            while (running.get() && !Thread.currentThread().isInterrupted) {
                val read = try {
                    input.read(buffer)
                } catch (e: SocketTimeoutException) {
                    -2 // timeout, continue loop
                }

                if (read == -1) {
                    Log.i(TAG, "EOF reached")
                    break
                }
                if (read > 0) {
                    try {
                        val messages = parser.feed(buffer, 0, read)
                        for (msg in messages) {
                            if (msg.type == Protocol.TYPE_PING) {
                                sendPong(socket, msg.sequence)
                            } else {
                                listener.onMessage(msg)
                            }
                        }
                    } catch (e: ProtocolException) {
                        Log.e(TAG, "Protocol error", e)
                        listener.onError("Protocol error: ${e.message}")
                        break
                    }
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Connection error", e)
            listener.onError("Connection error: ${e.message}")
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            running.set(false)
            try {
                socket.close()
            } catch (e: IOException) {
                // ignore
            }
            this.socket = null
            listener.onConnectionStateChanged(ConnectionState.DISCONNECTED)
        }
    }

    private fun sendHello(socket: Socket) {
        try {
            val payload = JSONObject().apply {
                put("client_name", "Xiaomi Pad 6 Pro")
                put("platform", "android")
                put("protocol_version", 0)
                put("max_width", 1920)
                put("max_height", 1200)
                put("max_fps", 30)
                put("supported_codecs", JSONArray().apply { put("h264") })
                put("supported_h264_stream_formats", JSONArray().apply { put("annex_b") })
                displayCapabilities?.toJson()?.let { caps ->
                    put("display_capabilities", caps.getJSONObject("display_capabilities"))
                }
            }.toString().toByteArray(Charsets.UTF_8)
            val header = buildHeader(Protocol.TYPE_HELLO, 0, 0, 0, payload.size)
            val out = socket.getOutputStream()
            synchronized(out) {
                out.write(header)
                out.write(payload)
                out.flush()
            }
        } catch (e: IOException) {
            Log.w(TAG, "send hello failed", e)
        }
    }

    private fun sendPong(socket: Socket, sequence: Long) {
        try {
            val header = buildHeader(Protocol.TYPE_PING, sequence, System.nanoTime(), 0, 0)
            val out = socket.getOutputStream()
            synchronized(out) {
                out.write(header)
                out.flush()
            }
        } catch (e: IOException) {
            Log.w(TAG, "send pong failed", e)
        }
    }

    companion object {
        fun buildHeader(type: Int, sequence: Long, timestampNs: Long, flags: Int, payloadLen: Int): ByteArray {
            val buf = java.nio.ByteBuffer.allocate(Protocol.HEADER_SIZE)
            buf.order(java.nio.ByteOrder.BIG_ENDIAN)
            buf.putInt(Protocol.MAGIC)
            buf.putShort(Protocol.VERSION)
            buf.putShort(type.toShort())
            buf.putLong(sequence)
            buf.putLong(timestampNs)
            buf.putInt(flags)
            buf.putInt(payloadLen)
            return buf.array()
        }
    }
}

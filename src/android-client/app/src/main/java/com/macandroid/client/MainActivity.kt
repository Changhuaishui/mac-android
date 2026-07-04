package com.macandroid.client

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.SurfaceHolder
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.macandroid.client.display.DisplayMode
import com.macandroid.client.display.DisplayModeManager
import com.macandroid.client.input.CoordinateMapper
import com.macandroid.client.input.KeyboardHandler
import com.macandroid.client.input.TouchHandler
private const val TAG = "MacMainActivity"

class MainActivity : AppCompatActivity(), TcpClientListener, VideoDecoderListener, AssetPlayerListener {

    private lateinit var surfaceView: android.view.SurfaceView
    private lateinit var hostInput: EditText
    private lateinit var portInput: EditText
    private lateinit var connectButton: Button
    private lateinit var disconnectButton: Button
    private lateinit var playAssetButton: Button
    private lateinit var stopAssetButton: Button
    private lateinit var statusText: TextView
    private lateinit var capabilityText: TextView
    private lateinit var modeText: TextView
    private lateinit var statsText: TextView
    private lateinit var errorText: TextView

    private val tcpClient = TcpClient(this)
    private val videoDecoder = VideoDecoder(this)
    private val displayModeManager = DisplayModeManager()
    private lateinit var coordinateMapper: CoordinateMapper
    private lateinit var assetPlayer: AssetPlayer
    private lateinit var touchHandler: TouchHandler
    private lateinit var keyboardHandler: KeyboardHandler

    private val mainHandler = Handler(Looper.getMainLooper())

    private var videoConfig: VideoConfig? = null
    private var hasSurface = false

    // 统计
    private var frameCount = 0
    private var lastStatsTime = 0L
    private var lastFrameTime = 0L
    private val statsRunnable = object : Runnable {
        override fun run() {
            updateStats()
            mainHandler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        surfaceView = findViewById(R.id.surfaceView)
        hostInput = findViewById(R.id.hostInput)
        portInput = findViewById(R.id.portInput)
        connectButton = findViewById(R.id.connectButton)
        disconnectButton = findViewById(R.id.disconnectButton)
        playAssetButton = findViewById(R.id.playAssetButton)
        stopAssetButton = findViewById(R.id.stopAssetButton)
        statusText = findViewById(R.id.statusText)
        capabilityText = findViewById(R.id.capabilityText)
        modeText = findViewById(R.id.modeText)
        statsText = findViewById(R.id.statsText)
        errorText = findViewById(R.id.errorText)

        coordinateMapper = CoordinateMapper(displayModeManager)
        assetPlayer = AssetPlayer(assets, videoDecoder, this)

        touchHandler = TouchHandler(tcpClient, coordinateMapper, surfaceView)
        keyboardHandler = KeyboardHandler(tcpClient, coordinateMapper)

        displayModeManager.onModeChanged = { runOnUiThread { updateDisplayModeUi() } }
        updateDisplayModeUi()

        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                Log.i(TAG, "Surface created")
                hasSurface = true

                surfaceView.setOnTouchListener(touchHandler)
                surfaceView.isFocusableInTouchMode = true
                surfaceView.requestFocus()
                surfaceView.setOnKeyListener(keyboardHandler)

                readDisplayCapabilities()
                videoConfig?.let { cfg ->
                    videoDecoder.configure(cfg.width, cfg.height, cfg.fps, holder.surface)
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                Log.i(TAG, "Surface changed: ${width}x${height}")
                readDisplayCapabilities()
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                Log.i(TAG, "Surface destroyed")
                hasSurface = false
                assetPlayer.stop()
                videoDecoder.release()
            }
        })

        connectButton.setOnClickListener { onConnectClicked() }
        disconnectButton.setOnClickListener { onDisconnectClicked() }
        playAssetButton.setOnClickListener { onPlayAssetClicked() }
        stopAssetButton.setOnClickListener { onStopAssetClicked() }

        // 布局完成后读取一次显示能力（Surface 尺寸可能尚未就绪时也会更新）
        surfaceView.post { readDisplayCapabilities() }

        mainHandler.post(statsRunnable)
    }

    override fun onDestroy() {
        super.onDestroy()
        mainHandler.removeCallbacks(statsRunnable)
        assetPlayer.stop()
        tcpClient.disconnect()
        videoDecoder.release()
    }

    private fun onPlayAssetClicked() {
        hideError()
        tcpClient.disconnect()
        if (hasSurface) {
            // fixture 规格：1280x800，30fps
            videoDecoder.configure(1280, 800, 30, surfaceView.holder.surface)
            assetPlayer.play("sample-annexb.h264", fps = 30)
        } else {
            showError("Surface 尚未就绪")
        }
    }

    private fun onStopAssetClicked() {
        assetPlayer.stop()
        updateAssetButtons(false)
    }

    private fun updateAssetButtons(playing: Boolean) {
        runOnUiThread {
            if (playing) {
                playAssetButton.visibility = View.GONE
                stopAssetButton.visibility = View.VISIBLE
            } else {
                playAssetButton.visibility = View.VISIBLE
                stopAssetButton.visibility = View.GONE
            }
        }
    }

    private fun onConnectClicked() {
        val host = hostInput.text.toString().trim()
        val portStr = portInput.text.toString().trim()
        if (host.isEmpty() || portStr.isEmpty()) {
            showError("请输入地址和端口")
            return
        }
        val port = portStr.toIntOrNull()
        if (port == null || port <= 0 || port > 65535) {
            showError("端口无效")
            return
        }
        hideError()
        tcpClient.connect(host, port)
    }

    private fun onDisconnectClicked() {
        assetPlayer.stop()
        tcpClient.disconnect()
        videoDecoder.release()
        frameCount = 0
        updateStats()
    }

    //region TcpClientListener

    override fun onConnectionStateChanged(state: ConnectionState) {
        runOnUiThread {
            when (state) {
                ConnectionState.DISCONNECTED -> {
                    statusText.text = getString(R.string.status_disconnected)
                    connectButton.visibility = View.VISIBLE
                    disconnectButton.visibility = View.GONE
                    statsText.visibility = View.GONE
                    videoDecoder.release()
                    displayModeManager.reset()
                    updateDisplayModeUi()
                }
                ConnectionState.CONNECTING -> {
                    statusText.text = getString(R.string.status_connecting)
                    connectButton.visibility = View.GONE
                    disconnectButton.visibility = View.VISIBLE
                }
                ConnectionState.CONNECTED -> {
                    statusText.text = getString(R.string.status_connected)
                    connectButton.visibility = View.GONE
                    disconnectButton.visibility = View.VISIBLE
                    statsText.visibility = View.VISIBLE
                    frameCount = 0
                    lastStatsTime = System.currentTimeMillis()
                }
            }
        }
    }

    override fun onMessage(message: Message) {
        when (message.type) {
            Protocol.TYPE_VIDEO_CONFIG -> {
                val cfg = VideoConfig.fromPayload(message.payload)
                videoConfig = cfg
                displayModeManager.updateFromVideoConfig(cfg)
                Log.i(TAG, "Received video config: ${cfg.width}x${cfg.height} ${cfg.fps}fps ${cfg.streamFormat} mode=${cfg.displayMode}")
                runOnUiThread {
                    if (hasSurface) {
                        videoDecoder.configure(cfg.width, cfg.height, cfg.fps, surfaceView.holder.surface)
                    }
                }
            }
            Protocol.TYPE_VIDEO_FRAME -> {
                val ptsUs = message.timestampNs / 1000
                if (!videoDecoder.queueFrame(message.payload, message.flags, ptsUs)) {
                    Log.w(TAG, "Decoder queue full, dropped frame seq=${message.sequence}")
                } else {
                    frameCount++
                    lastFrameTime = System.currentTimeMillis()
                }
            }
            Protocol.TYPE_ERROR -> {
                val text = message.payload.toString(Charsets.UTF_8)
                Log.w(TAG, "Server error: $text")
                runOnUiThread { showError("Server: $text") }
            }
            else -> {
                Log.d(TAG, "Unhandled message type: ${message.type}")
            }
        }
    }

    override fun onError(error: String) {
        runOnUiThread {
            showError(error)
            Toast.makeText(this, error, Toast.LENGTH_LONG).show()
        }
    }

    //endregion

    //region AssetPlayerListener

    override fun onAssetStarted(assetName: String, totalFrameCount: Int) {
        runOnUiThread {
            statusText.text = "播放 fixture: $assetName ($totalFrameCount 帧)"
            statsText.visibility = View.VISIBLE
            updateAssetButtons(true)
            this@MainActivity.frameCount = 0
            lastStatsTime = System.currentTimeMillis()
        }
    }

    override fun onAssetFrame(frameIndex: Int) {
        frameCount++
        lastFrameTime = System.currentTimeMillis()
    }

    override fun onAssetFinished(assetName: String, totalFrames: Int) {
        runOnUiThread {
            statusText.text = "fixture 播放完成: $totalFrames 帧"
            updateAssetButtons(false)
        }
    }

    override fun onAssetError(error: String) {
        runOnUiThread {
            showError(error)
            Toast.makeText(this, error, Toast.LENGTH_LONG).show()
            updateAssetButtons(false)
        }
    }

    //endregion

    //region VideoDecoderListener

    override fun onDecoderError(error: String) {
        runOnUiThread {
            showError(error)
            Toast.makeText(this, error, Toast.LENGTH_LONG).show()
        }
        sendError("decoder_error: $error")
    }

    override fun onRequestKeyframe() {
        Log.i(TAG, "Requesting keyframe")
        sendError("request_keyframe")
    }

    //endregion

    private fun sendError(text: String) {
        tcpClient.sendError(text)
    }

    private fun readDisplayCapabilities() {
        val capabilities = DisplayCapabilitiesReader.read(this, surfaceView)
        tcpClient.setDisplayCapabilities(capabilities)
        runOnUiThread {
            capabilityText.text = capabilities.summaryText()
        }
    }

    private fun updateDisplayModeUi() {
        val mode = displayModeManager.currentMode
        val text = when (mode) {
            DisplayMode.MIRROR -> getString(R.string.mode_mirror)
            DisplayMode.EXTENDED -> {
                val id = displayModeManager.targetDisplayId
                val bounds = displayModeManager.targetDisplayBounds
                val fps = displayModeManager.targetFps
                val resolution = bounds?.let { "${it.width}x${it.height}" }
                    ?: videoConfig?.let { "${it.width}x${it.height}" }
                    ?: "?"
                getString(R.string.mode_extended, id, resolution, fps)
            }
        }
        modeText.text = text
        modeText.visibility = View.VISIBLE
    }

    private fun updateStats() {
        val now = System.currentTimeMillis()
        val elapsed = now - lastStatsTime
        if (elapsed <= 0) return
        val fps = (frameCount * 1000 / elapsed).toInt()
        val latencyMs = if (lastFrameTime > 0) now - lastFrameTime else 0
        statsText.text = "FPS: $fps | last: ${latencyMs}ms | queued: ${videoDecoder.queueSize()}"
        frameCount = 0
        lastStatsTime = now
    }

    private fun showError(message: String) {
        errorText.text = message
        errorText.visibility = View.VISIBLE
    }

    private fun hideError() {
        errorText.visibility = View.GONE
    }
}

package com.johngalt.flutter_ai_communications

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.atomic.AtomicBoolean

class FlutterAiCommunicationsPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var methods: MethodChannel
    private lateinit var captureChannel: EventChannel
    private lateinit var eventsChannel: EventChannel
    private var appContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: Result? = null
    private val permissionCode = 0xFAC1
    private var captureSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null
    private var audioManager: AudioManager? = null
    private var recorder: AudioRecord? = null
    private var track: AudioTrack? = null
    private var captureThread: Thread? = null
    private val running = AtomicBoolean(false)
    private val paused = AtomicBoolean(false)
    private var selectedCaptureId: String? = null
    private var selectedRenderId: String? = null
    private val main = Handler(Looper.getMainLooper())
    private var focusRequest: AudioFocusRequest? = null

    private val deviceCallback =
        object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                emitCatalog()
                emitRoute()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                emitCatalog()
                emitRoute()
                if (enumerate().none { !(it["isCapture"] as Boolean) }) {
                    emitPath(false)
                }
            }
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        audioManager =
            binding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        methods = MethodChannel(binding.binaryMessenger, "flutter_ai_communications/methods")
        methods.setMethodCallHandler(this)
        captureChannel = EventChannel(binding.binaryMessenger, "flutter_ai_communications/capture")
        captureChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    captureSink = events
                }

                override fun onCancel(arguments: Any?) {
                    captureSink = null
                }
            },
        )
        eventsChannel = EventChannel(binding.binaryMessenger, "flutter_ai_communications/events")
        eventsChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
        audioManager?.registerAudioDeviceCallback(deviceCallback, main)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "enumerateEndpoints" -> result.success(enumerate())
            "requestMicrophonePermission" -> requestPermission(result)
            "startNative" -> {
                selectedCaptureId = call.argument("captureId")
                selectedRenderId = call.argument("renderId")
                result.success(startNative())
            }
            "stopNative" -> {
                stopNative()
                result.success(null)
            }
            "pauseNative" -> {
                paused.set(true)
                result.success(null)
            }
            "resumeNative" -> {
                paused.set(false)
                result.success(null)
            }
            "play" -> {
                play(call.arguments as? ByteArray)
                result.success(null)
            }
            "selectEndpoints" -> {
                selectedCaptureId = call.argument("captureId") ?: selectedCaptureId
                selectedRenderId = call.argument("renderId") ?: selectedRenderId
                applyRoute()
                restartCapture()
                result.success(null)
            }
            "openIsolationSettings" -> {
                emit("isolation", "unavailable")
                result.success(null)
            }
            "flushPlayback" -> {
                track?.pause()
                track?.flush()
                track?.play()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopNative()
        audioManager?.unregisterAudioDeviceCallback(deviceCallback)
        methods.setMethodCallHandler(null)
        captureChannel.setStreamHandler(null)
        eventsChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != permissionCode) {
            return false
        }
        val pending = pendingPermission ?: return false
        pendingPermission = null
        pending.success(permission())
        return true
    }

    private fun permission(): String {
        val context = appContext ?: return "denied"
        val granted =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        return if (granted) "granted" else "denied"
    }

    private fun requestPermission(result: Result) {
        if (permission() == "granted") {
            result.success("granted")
            return
        }
        val activity: Activity? = activityBinding?.activity
        if (activity == null) {
            result.success(permission())
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            permissionCode,
        )
    }

    private fun startNative(): String {
        val context = appContext ?: return "failed"
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return "failed"
        }
        val manager = audioManager ?: return "failed"
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        requestFocus(manager)
        applyRoute()
        return try {
            startCapture()
            startPlayback()
            running.set(true)
            paused.set(false)
            emitCatalog()
            emit("isolation", "unavailable")
            "started"
        } catch (_: Exception) {
            "failed"
        }
    }

    private fun stopNative() {
        running.set(false)
        captureThread?.join(250)
        captureThread = null
        recorder?.stop()
        recorder?.release()
        recorder = null
        track?.stop()
        track?.release()
        track = null
        val manager = audioManager
        if (manager != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { manager.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                manager.abandonAudioFocus(null)
            }
            manager.mode = AudioManager.MODE_NORMAL
        }
    }

    private fun startCapture() {
        emitSilence()
        recorder?.release()
        val min =
            AudioRecord.getMinBufferSize(
                24_000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        val rec =
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                24_000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                min * 2,
            )
        recorder = rec
        rec.startRecording()
        captureThread =
            Thread {
                val buf = ByteArray(min)
                while (running.get()) {
                    val n = rec.read(buf, 0, buf.size)
                    if (n > 0 && !paused.get()) {
                        val copy = buf.copyOf(n)
                        main.post { captureSink?.success(copy) }
                    }
                }
            }.also { it.start() }
    }

    private fun restartCapture() {
        if (!running.get()) {
            return
        }
        running.set(false)
        captureThread?.join(250)
        running.set(true)
        startCapture()
    }

    private fun startPlayback() {
        val min =
            AudioTrack.getMinBufferSize(
                24_000,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        val attrs =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        val format =
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(24_000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
        track =
            AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setBufferSizeInBytes(min * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        track?.play()
    }

    private fun play(bytes: ByteArray?) {
        if (bytes == null || paused.get() || !running.get()) {
            return
        }
        track?.write(bytes, 0, bytes.size)
    }

    private fun applyRoute() {
        val manager = audioManager ?: return
        val speaker = selectedRenderId == "speaker-out" || selectedRenderId == "speakerphone-out"
        @Suppress("DEPRECATION")
        manager.isSpeakerphoneOn = speaker
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val devices = manager.availableCommunicationDevices
            val match =
                devices.firstOrNull { it.id.toString() == selectedRenderId }
                    ?: devices.firstOrNull {
                        if (speaker) {
                            it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                        } else {
                            it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                        }
                    }
            if (match != null) {
                manager.setCommunicationDevice(match)
            }
        }
    }

    private fun enumerate(): List<Map<String, Any>> {
        val manager = audioManager ?: return emptyList()
        val items = mutableListOf<Map<String, Any>>()
        items += endpoint("handset-in", "Handset", "handset", true, "handset")
        items += endpoint("handset-out", "Handset", "handset", false, "handset")
        items += endpoint("speaker-in", "Speakerphone", "speakerphone", true, "speakerphone")
        items += endpoint("speaker-out", "Speakerphone", "speakerphone", false, "speakerphone")
        for (device in manager.getDevices(AudioManager.GET_DEVICES_ALL)) {
            val route = routeClass(device.type)
            if (route == "handset" || route == "speakerphone") {
                continue
            }
            items +=
                endpoint(
                    device.id.toString(),
                    device.productName?.toString() ?: "Endpoint",
                    route,
                    device.isSource,
                    device.address?.ifEmpty { device.id.toString() } ?: device.id.toString(),
                )
        }
        return items
    }

    private fun endpoint(
        id: String,
        name: String,
        route: String,
        capture: Boolean,
        pairId: String,
    ): Map<String, Any> =
        mapOf(
            "id" to id,
            "name" to name,
            "routeClass" to route,
            "isCapture" to capture,
            "pairId" to pairId,
        )

    private fun routeClass(type: Int): String =
        when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, AudioDeviceInfo.TYPE_BUILTIN_MIC -> "handset"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speakerphone"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            -> "bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE,
            -> "wired"
            AudioDeviceInfo.TYPE_BUS, AudioDeviceInfo.TYPE_AUX_LINE -> "car"
            else -> "wired"
        }

    private fun requestFocus(manager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request =
                AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setOnAudioFocusChangeListener { change ->
                        val state =
                            if (change == AudioManager.AUDIOFOCUS_LOSS) "interrupted" else "active"
                        emit("focus", state)
                    }
                    .build()
            focusRequest = request
            manager.requestAudioFocus(request)
        }
    }

    private fun emitSilence() {
        main.post { captureSink?.success(ByteArray(480)) }
    }

    private fun emitCatalog() {
        emit("catalog", enumerate())
    }

    private fun emitRoute() {
        val manager = audioManager ?: return
        val comm =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.communicationDevice
            } else {
                null
            }
        emit(
            "route",
            mapOf(
                "captureId" to selectedCaptureId,
                "renderId" to (comm?.id?.toString() ?: selectedRenderId),
            ),
        )
    }

    private fun emitPath(alive: Boolean) {
        emit("path", mapOf("alive" to alive, "reason" to if (alive) null else "pathDead"))
    }

    private fun emit(
        type: String,
        payload: Any?,
    ) {
        main.post { eventSink?.success(mapOf("type" to type, "payload" to payload)) }
    }
}

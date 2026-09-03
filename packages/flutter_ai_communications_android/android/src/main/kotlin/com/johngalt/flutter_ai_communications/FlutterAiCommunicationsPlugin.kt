package com.johngalt.flutter_ai_communications

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothManager
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
import io.flutter.view.TextureRegistry
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
    private var pendingCameraPermission: Result? = null
    private val permissionCode = 0xFAC1
    private val cameraPermissionCode = 0xFAC3
    private var textures: TextureRegistry? = null
    private var cameraGraph: AndroidCameraGraph? = null
    private val bluetoothCode = 0xFAC2
    private var bluetoothAsked = false
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
    private var captureGeneration = 0
    private var requestedCaptureRate = AndroidCapturePolicy.DEFAULT_SAMPLE_RATE
    private var requestedPlaybackRate = AndroidCapturePolicy.DEFAULT_SAMPLE_RATE
    private var nativeCaptureRate = AndroidCapturePolicy.DEFAULT_SAMPLE_RATE
    private var nativePlaybackRate = AndroidCapturePolicy.DEFAULT_SAMPLE_RATE
    private var captureFormatFailures = emptyList<Map<String, Any>>()
    private var playbackFormatFailures = emptyList<Map<String, Any>>()
    private var appliedCaptureId: String? = null
    private var appliedRenderId: String? = null
    private var noiseCancelling = true
    private var communicationDeviceListener: Any? = null

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
        textures = binding.textureRegistry
        cameraGraph = AndroidCameraGraph(binding.applicationContext, binding.textureRegistry)
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
        listenForCommunicationDevice()
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
                requestedCaptureRate =
                    AndroidCapturePolicy.requestedSampleRate(call.argument("captureFormat"))
                requestedPlaybackRate =
                    AndroidCapturePolicy.requestedSampleRate(call.argument("playbackFormat"))
                noiseCancelling = call.argument<Boolean>("noiseCancelling") ?: true
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
                restartPlayback()
                restartCapture()
                result.success(startedFormatMap())
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
            "enumerateCameras" -> result.success(cameraGraph?.enumerate() ?: emptyList<Any>())
            "requestCameraPermission" -> requestCameraPermission(result)
            "startCameraNative" -> {
                val graph = cameraGraph
                if (graph == null) {
                    result.success(mapOf("status" to "failed"))
                } else {
                    graph.start(
                        call.argument("cameraId"),
                        call.argument<Int>("width") ?: 1280,
                        call.argument<Int>("height") ?: 720,
                        call.argument<Boolean>("enabled") ?: true,
                        call.argument<Boolean>("muted") ?: false,
                    ) { map -> result.success(map) }
                }
            }
            "stopCameraNative" -> {
                cameraGraph?.stop()
                result.success(null)
            }
            "selectCameraNative" -> {
                call.argument<String>("cameraId")?.let { cameraGraph?.select(it) }
                result.success(null)
            }
            "setCameraEnabledNative" -> {
                cameraGraph?.setEnabled(call.argument<Boolean>("enabled") ?: true)
                result.success(null)
            }
            "setMuteVideoNative" -> {
                cameraGraph?.setMuted(call.argument<Boolean>("muted") ?: false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cameraGraph?.stop()
        stopNative()
        audioManager?.unregisterAudioDeviceCallback(deviceCallback)
        stopListeningForCommunicationDevice()
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
        if (requestCode == bluetoothCode) {
            emitCatalog()
            return true
        }
        if (requestCode == cameraPermissionCode) {
            val pending = pendingCameraPermission ?: return false
            pendingCameraPermission = null
            pending.success(cameraGraph?.permission() ?: "denied")
            return true
        }
        if (requestCode != permissionCode) {
            return false
        }
        val pending = pendingPermission ?: return false
        pendingPermission = null
        pending.success(permission())
        if (permission() == "granted") {
            requestBluetoothIdentity()
        }
        return true
    }

    private fun permission(): String {
        val context = appContext ?: return "denied"
        val granted =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        return if (granted) "granted" else "denied"
    }

    private fun requestCameraPermission(result: Result) {
        if (cameraGraph?.permission() == "granted") {
            result.success("granted")
            return
        }
        val activity: Activity? = activityBinding?.activity
        if (activity == null) {
            result.success(cameraGraph?.permission() ?: "denied")
            return
        }
        pendingCameraPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA),
            cameraPermissionCode,
        )
    }

    private fun requestPermission(result: Result) {
        if (permission() == "granted") {
            requestBluetoothIdentity()
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

    private fun startNative(): Any {
        val context = appContext ?: return "failed"
        val wantCapture =
            AndroidCapturePolicy.wantsCapture(selectedCaptureId, selectedRenderId)
        val wantPlayback =
            AndroidCapturePolicy.wantsPlayback(selectedCaptureId, selectedRenderId)
        if (wantCapture &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return "failed"
        }
        val manager = audioManager ?: return "failed"
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        requestFocus(manager)
        applyRoute()
        return try {
            captureGeneration++
            running.set(true)
            paused.set(false)
            if (wantCapture && !startCapture(captureGeneration)) {
                running.set(false)
                return "failed"
            }
            if (wantPlayback) {
                startPlayback()
            }
            emitCatalog()
            emitRoute()
            emit("isolation", "unavailable")
            requestBluetoothIdentity()
            startedFormatMap(wantCapture = wantCapture, wantPlayback = wantPlayback)
        } catch (_: Exception) {
            running.set(false)
            "failed"
        }
    }

    private fun stopNative() {
        running.set(false)
        captureGeneration++
        captureThread?.join(1000)
        captureThread = null
        recorder?.stop()
        recorder?.release()
        recorder = null
        track?.stop()
        track?.release()
        track = null
        val manager = audioManager
        if (manager != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.clearCommunicationDevice()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { manager.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                manager.abandonAudioFocus(null)
            }
            manager.mode = AudioManager.MODE_NORMAL
        }
    }

    private fun startCapture(generation: Int): Boolean {
        emitSilence()
        recorder?.release()
        recorder = null
        val rec = openRecorder() ?: return false
        recorder = rec
        rec.startRecording()
        val min =
            AudioRecord.getMinBufferSize(
                nativeCaptureRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            ).coerceAtLeast(480)
        captureThread =
            Thread {
                val buf = ByteArray(min)
                while (AndroidCapturePolicy.shouldRead(running.get(), captureGeneration, generation)) {
                    val n = rec.read(buf, 0, buf.size)
                    if (AndroidCapturePolicy.isFatalRead(n)) {
                        emitPath(false)
                        break
                    }
                    if (n > 0 && !paused.get()) {
                        val copy = buf.copyOf(n)
                        main.post { captureSink?.success(copy) }
                    }
                }
            }.also { it.start() }
        return true
    }

    private fun openRecorder(): AudioRecord? {
        val attempted = linkedSetOf<Int>()
        var rate: Int? = requestedCaptureRate
        while (rate != null) {
            attempted += rate
            val min =
                AudioRecord.getMinBufferSize(
                    rate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
            if (min <= 0) {
                rate = AndroidCapturePolicy.nextSampleRate(requestedCaptureRate, attempted)
                continue
            }
            val rec =
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    rate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    min * 2,
                )
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                rate = AndroidCapturePolicy.nextSampleRate(requestedCaptureRate, attempted)
                continue
            }
            applyPreferredCapture(rec)
            nativeCaptureRate = rec.sampleRate.takeIf { it > 0 } ?: rate
            captureFormatFailures =
                AndroidCapturePolicy.failures(attempted, nativeCaptureRate)
            return rec
        }
        captureFormatFailures =
            attempted.map { AndroidCapturePolicy.failureMap(it) }
        return null
    }

    private fun startedFormatMap(
        wantCapture: Boolean =
            AndroidCapturePolicy.wantsCapture(selectedCaptureId, selectedRenderId),
        wantPlayback: Boolean =
            AndroidCapturePolicy.wantsPlayback(selectedCaptureId, selectedRenderId),
    ): Map<String, Any> {
        val map =
            mutableMapOf<String, Any>(
                "status" to "started",
                "formatFailures" to captureFormatFailures + playbackFormatFailures,
            )
        if (wantCapture) {
            map["captureFormat"] = AndroidCapturePolicy.formatMap(nativeCaptureRate)
        }
        if (wantPlayback) {
            map["playbackFormat"] = AndroidCapturePolicy.formatMap(nativePlaybackRate)
        }
        return map
    }

    private fun applyPreferredCapture(rec: AudioRecord) {
        val device = resolveCaptureDevice() ?: return
        appliedCaptureId = catalogId(device, capture = true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            AndroidCapturePolicy.shouldPinPreferredCapture(selectedCaptureId)
        ) {
            rec.preferredDevice = device
        }
    }

    private fun restartCapture() {
        if (!running.get() ||
            !AndroidCapturePolicy.wantsCapture(selectedCaptureId, selectedRenderId)
        ) {
            return
        }
        val next = ++captureGeneration
        captureThread?.join(1000)
        captureThread = null
        startCapture(next)
        emitRoute()
    }

    private fun startPlayback() {
        val attempted = linkedSetOf<Int>()
        var rate: Int? = requestedPlaybackRate
        while (rate != null) {
            attempted += rate
            val min =
                AudioTrack.getMinBufferSize(
                    rate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
            if (min <= 0) {
                rate = AndroidCapturePolicy.nextSampleRate(requestedPlaybackRate, attempted)
                continue
            }
            val attrs =
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            val format =
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            val next =
                AudioTrack.Builder()
                    .setAudioAttributes(attrs)
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(min * 2)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
            if (next.state != AudioTrack.STATE_INITIALIZED) {
                next.release()
                rate = AndroidCapturePolicy.nextSampleRate(requestedPlaybackRate, attempted)
                continue
            }
            applyPreferredRender(next)
            nativePlaybackRate = next.sampleRate.takeIf { it > 0 } ?: rate
            playbackFormatFailures =
                AndroidCapturePolicy.failures(attempted, nativePlaybackRate)
            track = next
            next.play()
            return
        }
        playbackFormatFailures =
            attempted.map { AndroidCapturePolicy.failureMap(it) }
    }

    private fun play(bytes: ByteArray?) {
        if (bytes == null || paused.get() || !running.get()) {
            return
        }
        track?.write(bytes, 0, bytes.size)
    }

    private fun restartPlayback() {
        if (!running.get() ||
            !AndroidCapturePolicy.wantsPlayback(selectedCaptureId, selectedRenderId)
        ) {
            return
        }
        track?.stop()
        track?.release()
        track = null
        startPlayback()
    }

    private fun applyRoute() {
        val manager = audioManager ?: return
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        val plan = AndroidCapturePolicy.planApplyRoute(selectedRenderId)
        @Suppress("DEPRECATION")
        manager.isSpeakerphoneOn = plan.speakerphoneOn
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && plan.clearCommunicationDevice) {
            manager.clearCommunicationDevice()
        }
        val render = resolveRenderDevice()
        if (render != null) {
            appliedRenderId = catalogId(render, capture = false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.setCommunicationDevice(render)
            }
        }
    }

    private fun requestBluetoothIdentity() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        val context = appContext ?: return
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val activity = activityBinding?.activity ?: return
        if (bluetoothAsked) {
            return
        }
        bluetoothAsked = true
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            bluetoothCode,
        )
    }

    @SuppressLint("MissingPermission")
    private fun bluetoothIdentities(): List<BluetoothIdentityRecord> {
        val context = appContext ?: return emptyList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return emptyList()
        }
        val adapter =
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                ?: return emptyList()
        return try {
            adapter.bondedDevices.orEmpty().mapNotNull { device ->
                val name =
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            device.alias ?: device.name
                        } else {
                            @Suppress("DEPRECATION")
                            device.name
                        }
                    } catch (_: SecurityException) {
                        null
                    }
                if (name.isNullOrEmpty()) {
                    return@mapNotNull null
                }
                BluetoothIdentityRecord(
                    name = name,
                    classOfDevice = device.bluetoothClass?.deviceClass ?: 0,
                    address = device.address.orEmpty(),
                )
            }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    private fun enumerate(): List<Map<String, Any>> {
        val manager = audioManager ?: return emptyList()
        val items = mutableListOf<Map<String, Any>>()
        val bluetooth = bluetoothIdentities()
        val hasEarpiece =
            manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
            }
        if (AndroidCapturePolicy.shouldAdvertiseHandset(hasEarpiece)) {
            items += endpoint("handset-in", "Handset", "handset", true, "handset", "handset")
            items += endpoint("handset-out", "Handset", "handset", false, "handset", "handset")
        }
        items += endpoint("speaker-in", "Speakerphone", "speakerphone", true, "speakerphone")
        items += endpoint("speaker-out", "Speakerphone", "speakerphone", false, "speakerphone")
        for (device in manager.getDevices(AudioManager.GET_DEVICES_ALL)) {
            val route = routeClass(device.type)
            if (route == "handset" || route == "speakerphone") {
                continue
            }
            val name = device.productName?.toString() ?: "Endpoint"
            val address = device.address?.ifEmpty { device.id.toString() } ?: device.id.toString()
            val typeForm = AndroidBluetoothIdentity.formFactorForAudioType(device.type)
            val (hints, btForm) = AndroidBluetoothIdentity.merge(name, route, address, bluetooth)
            val form = if (btForm != "unknown") btForm else typeForm
            items +=
                endpoint(
                    device.id.toString(),
                    name,
                    route,
                    device.isSource,
                    address,
                    form,
                    hints,
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
        formFactor: String = "unknown",
        identityHints: List<String> = emptyList(),
    ): Map<String, Any> {
        val map =
            mutableMapOf<String, Any>(
                "id" to id,
                "name" to name,
                "routeClass" to route,
                "isCapture" to capture,
                "pairId" to pairId,
                "capabilities" to
                    mapOf(
                        "formFactor" to formFactor,
                        "aec" to false,
                        "ns" to false,
                        "agc" to false,
                        "carConnected" to false,
                    ),
            )
        if (identityHints.isNotEmpty()) {
            map["identityHints"] = identityHints
        }
        return map
    }

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
        val captureDevice = observedCaptureDevice()
        val renderDevice = observedRenderDevice()
        val captureId =
            AndroidCapturePolicy.observedId(
                selectedId = selectedCaptureId,
                physicalMatchesSelected = captureMatchesSelection(captureDevice),
                physicalCatalogId = captureDevice?.let { catalogId(it, capture = true) },
            )
        val speakerphoneOn =
            @Suppress("DEPRECATION")
            audioManager?.isSpeakerphoneOn == true
        val renderId =
            AndroidCapturePolicy.observedRenderId(
                selectedId = selectedRenderId,
                speakerphoneOn = speakerphoneOn,
                physicalMatchesSelected = renderMatchesSelection(renderDevice),
                physicalCatalogId = renderDevice?.let { catalogId(it, capture = false) },
            )
        emit(
            "route",
            mapOf(
                "captureId" to captureId,
                "renderId" to renderId,
                "generation" to captureGeneration,
            ),
        )
    }

    private fun resolveCaptureDevice(): AudioDeviceInfo? {
        val manager = audioManager ?: return null
        val sources = manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val selected = selectedCaptureId
        if (selected != null) {
            sources.firstOrNull { it.id.toString() == selected }?.let { return it }
            sources.firstOrNull { pairKey(it) == selected }?.let { return it }
        }
        return when (selected) {
            "handset-in", "speaker-in", null ->
                sources.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            else -> null
        }
    }

    private fun listenForCommunicationDevice() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        val manager = audioManager ?: return
        val listener =
            AudioManager.OnCommunicationDeviceChangedListener {
                emitRoute()
            }
        communicationDeviceListener = listener
        manager.addOnCommunicationDeviceChangedListener({ runnable -> main.post(runnable) }, listener)
    }

    private fun stopListeningForCommunicationDevice() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }
        val listener = communicationDeviceListener as? AudioManager.OnCommunicationDeviceChangedListener
        communicationDeviceListener = null
        if (listener != null) {
            audioManager?.removeOnCommunicationDeviceChangedListener(listener)
        }
    }

    private fun resolveRenderDevice(): AudioDeviceInfo? {
        val manager = audioManager ?: return null
        val comms =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.availableCommunicationDevices
            } else {
                emptyList()
            }
        val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        val sinks = (comms + outputs).distinctBy { it.id }
        val selected = selectedRenderId
        if (selected != null) {
            sinks.firstOrNull { it.id.toString() == selected }?.let { return it }
            sinks.firstOrNull { pairKey(it) == selected }?.let { return it }
        }
        val speaker = AndroidCapturePolicy.isSpeakerRender(selected)
        return sinks.firstOrNull {
            if (speaker) {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            } else {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
            }
        }
    }

    private fun applyPreferredRender(track: AudioTrack) {
        val device = resolveRenderDevice() ?: return
        appliedRenderId = catalogId(device, capture = false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            track.preferredDevice = device
        }
    }

    private fun observedCaptureDevice(): AudioDeviceInfo? {
        val preferred =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                recorder?.preferredDevice
            } else {
                null
            }
        return preferred ?: resolveCaptureDevice()
    }

    private fun observedRenderDevice(): AudioDeviceInfo? {
        val manager = audioManager
        if (manager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.communicationDevice?.let { return it }
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            track?.preferredDevice ?: resolveRenderDevice()
        } else {
            resolveRenderDevice()
        }
    }

    private fun captureMatchesSelection(device: AudioDeviceInfo?): Boolean {
        val selected = selectedCaptureId ?: return device != null
        if (AndroidCapturePolicy.isBuiltinCapture(selected)) {
            return device?.type == AudioDeviceInfo.TYPE_BUILTIN_MIC
        }
        return device?.id?.toString() == selected || device?.let(::pairKey) == selected
    }

    private fun renderMatchesSelection(device: AudioDeviceInfo?): Boolean {
        val selected = selectedRenderId ?: return device != null
        if (AndroidCapturePolicy.isSpeakerRender(selected)) {
            return device?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        }
        if (selected == "handset-out") {
            return device?.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
        }
        return device?.id?.toString() == selected || device?.let(::pairKey) == selected
    }

    private fun catalogId(
        device: AudioDeviceInfo,
        capture: Boolean,
    ): String {
        val route = routeClass(device.type)
        return when (route) {
            "handset" -> if (capture) "handset-in" else "handset-out"
            "speakerphone" -> if (capture) "speaker-in" else "speaker-out"
            else -> device.id.toString()
        }
    }

    private fun pairKey(device: AudioDeviceInfo): String =
        device.address?.ifEmpty { device.id.toString() } ?: device.id.toString()

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

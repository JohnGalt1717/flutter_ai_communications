package com.johngalt.flutter_ai_communications

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.OrientationEventListener
import android.view.Surface
import androidx.core.content.ContextCompat
import io.flutter.view.TextureRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class AndroidCameraGraph(
    private val context: Context,
    private val textures: TextureRegistry,
) {
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var camera: CameraDevice? = null
    private var session: android.hardware.camera2.CameraCaptureSession? = null
    private var surface: Surface? = null
    private var reader: ImageReader? = null
    private var selectedId: String? = null
    private var activity: android.app.Activity? = null
    private val processor = AndroidVideoProcessor()
    private var lastWidth = 1280
    private var lastHeight = 720
    var cameraEnabled = true
    var videoMuted = false
    private val startId = AtomicInteger(0)
    private val main = Handler(Looper.getMainLooper())
    private val cameraThread =
        HandlerThread("fac-camera").also { it.start() }
    private val cameraHandler = Handler(cameraThread.looper)
    private var closeLatch: CountDownLatch? = null
    private var argbScratch: IntArray? = null
    private var frameBitmap: Bitmap? = null
    private val frameCount = AtomicInteger(0)
    private val liveFrames = AtomicInteger(0)
    var onFormat: ((Int, Int, Int) -> Unit)? = null
    private var watchingDisplay = false
    private var lastAppliedRotation = -1
    private var listenerDisplayRotation: Int? = null
    private val orientationListener =
        object : OrientationEventListener(context.applicationContext) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == ORIENTATION_UNKNOWN) {
                    return
                }
                val rotation = displayRotationFromClockwiseTilt(orientation)
                if (listenerDisplayRotation == rotation) {
                    return
                }
                listenerDisplayRotation = rotation
                if (!cameraEnabled || selectedId == null || camera == null) {
                    return
                }
                lastAppliedRotation = -1
                displayListener.onDisplayChanged(0)
            }
        }
    private val displayRestart =
        Runnable {
            val id = selectedId ?: return@Runnable
            if (!cameraEnabled) {
                return@Runnable
            }
            val rotation = captureRotation()
            val sourceWidth = reader?.width ?: 1280
            val sourceHeight = reader?.height ?: 720
            val out = captureBufferSize(sourceWidth, sourceHeight, rotation)
            lastWidth = out.first
            lastHeight = out.second
            android.util.Log.i(
                "fac.camera",
                "upright window=${activityDisplayRotationDegrees()} " +
                    "listener=$listenerDisplayRotation " +
                    "used=${displayRotationDegrees()} capture=$rotation " +
                    "size=${lastWidth}x$lastHeight",
            )
            producer?.setSize(lastWidth, lastHeight)
            onFormat?.invoke(lastWidth, lastHeight, 0)
        }
    private val displayListener =
        object : android.hardware.display.DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) {}

            override fun onDisplayRemoved(displayId: Int) {}

            override fun onDisplayChanged(displayId: Int) {
                if (!cameraEnabled || selectedId == null || camera == null) {
                    return
                }
                val rotation = displayRotationDegrees()
                if (rotation == lastAppliedRotation) {
                    return
                }
                lastAppliedRotation = rotation
                main.removeCallbacks(displayRestart)
                main.postDelayed(displayRestart, 250)
            }
        }
    private val statsCallback =
        object : android.hardware.camera2.CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(
                session: android.hardware.camera2.CameraCaptureSession,
                request: CaptureRequest,
                result: android.hardware.camera2.TotalCaptureResult,
            ) {
                frameCount.incrementAndGet()
                if (!videoMuted) {
                    liveFrames.incrementAndGet()
                }
            }
        }

    private val configCallbacks =
        object : android.content.ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
                lastAppliedRotation = -1
                displayListener.onDisplayChanged(0)
            }

            override fun onLowMemory() {}
        }

    fun attachActivity(activity: android.app.Activity?) {
        this.activity?.unregisterComponentCallbacks(configCallbacks)
        this.activity = activity
        activity?.registerComponentCallbacks(configCallbacks)
    }

    fun enumerate(): List<Map<String, Any>> {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        return manager.cameraIdList.map { id ->
            val facing =
                when (manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)) {
                    CameraCharacteristics.LENS_FACING_FRONT -> "user"
                    CameraCharacteristics.LENS_FACING_BACK -> "environment"
                    CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
                    else -> "unspecified"
                }
            mapOf(
                "id" to id,
                "name" to "Camera $id",
                "facing" to facing,
                "modes" to
                    listOf(
                        mapOf("width" to 1280, "height" to 720, "frameRate" to 30),
                    ),
            )
        }
    }

    fun permission(): String {
        val granted =
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        return if (granted) "granted" else "denied"
    }

    @SuppressLint("MissingPermission")
    fun start(
        cameraId: String?,
        width: Int,
        height: Int,
        enabled: Boolean,
        muted: Boolean,
        onResult: (Map<String, Any>) -> Unit,
        keepTexture: Boolean = false,
    ) {
        val kept = if (keepTexture) producer else null
        stop(releaseTexture = !keepTexture)
        producer = kept
        val id = startId.incrementAndGet()
        cameraEnabled = enabled
        videoMuted = muted
        frameCount.set(0)
        liveFrames.set(0)
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val ids = manager.cameraIdList
        if (ids.isEmpty()) {
            onResult(mapOf("status" to "unavailable"))
            return
        }
        val chosen =
            ids.firstOrNull { it == cameraId }
                ?: ids.firstOrNull { camera ->
                    manager.getCameraCharacteristics(camera).get(CameraCharacteristics.LENS_FACING) ==
                        CameraCharacteristics.LENS_FACING_FRONT
                }
                ?: ids.first()
        selectedId = chosen
        cacheLens(chosen)
        lastAppliedRotation = displayRotationDegrees()
        ensureDisplayWatch()
        val rotation = captureRotation()
        android.util.Log.i(
            "fac.camera",
            "start window=${activityDisplayRotationDegrees()} " +
                "listener=$listenerDisplayRotation used=$lastAppliedRotation " +
                "capture=$rotation sensor-buffer=${width}x$height",
        )
        val out = captureBufferSize(width, height, rotation)
        lastWidth = out.first
        lastHeight = out.second
        val producer = this.producer ?: textures.createSurfaceProducer()
        this.producer = producer
        producer.setSize(lastWidth, lastHeight)
        val imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 2)
        imageReader.setOnImageAvailableListener({ onProcessedImage(it) }, cameraHandler)
        reader = imageReader
        val surface = imageReader.surface
        this.surface = surface
        val started =
            mapOf(
                "status" to "started",
                "textureId" to producer.id(),
                "width" to lastWidth,
                "height" to lastHeight,
                "frameRate" to 30,
                "quarterTurns" to 0,
            )
        if (!enabled) {
            onResult(started)
            return
        }
        if (permission() != "granted") {
            reader?.close()
            reader = null
            this.surface = null
            producer.release()
            this.producer = null
            onResult(mapOf("status" to "unavailable"))
            return
        }
        manager.openCamera(
            chosen,
            object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (id != startId.get()) {
                        device.close()
                        return
                    }
                    camera = device
                    device.createCaptureSession(
                        listOf(surface),
                        object : android.hardware.camera2.CameraCaptureSession.StateCallback() {
                            override fun onConfigured(captureSession: android.hardware.camera2.CameraCaptureSession) {
                                if (id != startId.get()) {
                                    captureSession.close()
                                    device.close()
                                    return
                                }
                                session = captureSession
                                val request =
                                    device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                        addTarget(surface)
                                        set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                                    }
                                if (!videoMuted) {
                                    captureSession.setRepeatingRequest(
                                        request.build(),
                                        noneModeStatsCallback(),
                                        cameraHandler,
                                    )
                                }
                                main.post {
                                    onFormat?.invoke(lastWidth, lastHeight, 0)
                                    onResult(started)
                                }
                            }

                            override fun onConfigureFailed(session: android.hardware.camera2.CameraCaptureSession) {
                                main.post { onResult(mapOf("status" to "failed")) }
                            }
                        },
                        cameraHandler,
                    )
                }

                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    if (camera === device) {
                        camera = null
                    }
                    closeLatch?.countDown()
                }

                override fun onClosed(device: CameraDevice) {
                    if (camera === device) {
                        camera = null
                    }
                    closeLatch?.countDown()
                }

                override fun onError(
                    device: CameraDevice,
                    error: Int,
                ) {
                    device.close()
                    if (id == startId.get()) {
                        main.post { onResult(mapOf("status" to "failed")) }
                    }
                    closeLatch?.countDown()
                }
            },
            cameraHandler,
        )
    }

    fun select(cameraId: String) {
        // Keep the SurfaceProducer so Session/CameraPreview keep a live texture
        // id. selectCameraNative is void and cameraFormat only updates size.
        start(
            cameraId,
            1280,
            720,
            cameraEnabled,
            videoMuted,
            onResult = {},
            keepTexture = true,
        )
    }

    fun setEnabled(enabled: Boolean) {
        cameraEnabled = enabled
        if (!enabled) {
            startId.incrementAndGet()
            stopRepeatingLocked()
            closeCameraLocked()
        } else {
            selectedId?.let { id ->
                start(
                    id,
                    1280,
                    720,
                    true,
                    videoMuted,
                    onResult = {},
                    keepTexture = true,
                )
            }
        }
    }

    fun setProcessor(args: Map<String, Any?>): String {
        val status = processor.apply(args)
        if (status != "ready") {
            return status
        }
        return status
    }

    fun setMuted(muted: Boolean) {
        videoMuted = muted
        val captureSession = session ?: return
        val device = camera ?: return
        val target = surface ?: return
        if (muted) {
            try {
                captureSession.stopRepeating()
            } catch (_: Exception) {
            }
            return
        }
        val request =
            device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(target)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
            }
        try {
            captureSession.setRepeatingRequest(
                request.build(),
                noneModeStatsCallback(),
                cameraHandler,
            )
        } catch (_: Exception) {
        }
    }

    fun stop(releaseTexture: Boolean = true) {
        startId.incrementAndGet()
        stopRepeatingLocked()
        closeCameraLocked()
        surface = null
        reader?.close()
        reader = null
        if (releaseTexture) {
            producer?.release()
            producer = null
        }
    }

    fun stats(): Map<String, Any> {
        return mapOf(
            "frameCount" to frameCount.get(),
            "liveFrames" to liveFrames.get(),
        )
    }

    private fun noneModeStatsCallback(): android.hardware.camera2.CameraCaptureSession.CaptureCallback? {
        return if (processor.mode is AndroidVideoProcessor.Mode.None) {
            statsCallback
        } else {
            null
        }
    }

    private fun onProcessedImage(imageReader: ImageReader) {
        val image = imageReader.acquireLatestImage() ?: return
        try {
            frameCount.incrementAndGet()
            val bitmap = yuvToBitmap(image) ?: return
            val processed = rotateUpright(processor.process(bitmap))
            val destProducer = producer ?: return
            if (processed.width != lastWidth || processed.height != lastHeight) {
                lastWidth = processed.width
                lastHeight = processed.height
                destProducer.setSize(lastWidth, lastHeight)
                main.post { onFormat?.invoke(lastWidth, lastHeight, 0) }
            }
            blit(processed, destProducer.surface)
            if (!videoMuted) {
                liveFrames.incrementAndGet()
            }
        } catch (error: Exception) {
            android.util.Log.e("fac.camera", "frame", error)
        } finally {
            image.close()
        }
    }

    private fun yuvToBitmap(image: Image): Bitmap? {
        if (image.planes.size < 3) {
            return null
        }
        val width = image.width
        val height = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        val uRowStride = uPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val vRowStride = vPlane.rowStride
        val vPixelStride = vPlane.pixelStride
        val count = width * height
        val pixels =
            argbScratch?.takeIf { it.size == count } ?: IntArray(count).also { argbScratch = it }
        for (row in 0 until height) {
            val yRow = row * yRowStride
            val uRow = (row / 2) * uRowStride
            val vRow = (row / 2) * vRowStride
            val outRow = row * width
            for (col in 0 until width) {
                val y = yBuffer.get(yRow + col * yPixelStride).toInt() and 0xFF
                val u = uBuffer.get(uRow + (col / 2) * uPixelStride).toInt() and 0xFF
                val v = vBuffer.get(vRow + (col / 2) * vPixelStride).toInt() and 0xFF
                val d = u - 128
                val e = v - 128
                val r = (y + ((351 * e) shr 8)).coerceIn(0, 255)
                val g = (y - ((179 * e + 86 * d) shr 8)).coerceIn(0, 255)
                val b = (y + ((443 * d) shr 8)).coerceIn(0, 255)
                pixels[outRow + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val cached = frameBitmap
        val bitmap =
            if (cached != null && cached.width == width && cached.height == height) {
                cached
            } else {
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                    frameBitmap = it
                }
            }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }

    private fun stopRepeatingLocked() {
        try {
            session?.stopRepeating()
        } catch (_: Exception) {
        }
        try {
            session?.close()
        } catch (_: Exception) {
        }
        session = null
    }

    private fun closeCameraLocked() {
        val device = camera
        if (device == null) {
            return
        }
        val latch = CountDownLatch(1)
        closeLatch = latch
        try {
            device.close()
        } catch (_: Exception) {
            latch.countDown()
        }
        latch.await(1500, TimeUnit.MILLISECONDS)
        closeLatch = null
        camera = null
    }

    private fun ensureDisplayWatch() {
        if (orientationListener.canDetectOrientation()) {
            orientationListener.enable()
        }
        if (watchingDisplay) {
            return
        }
        val displayManager =
            context.getSystemService(Context.DISPLAY_SERVICE) as android.hardware.display.DisplayManager
        displayManager.registerDisplayListener(displayListener, main)
        watchingDisplay = true
    }

    fun releaseDisplayWatch() {
        main.removeCallbacks(displayRestart)
        orientationListener.disable()
        activity?.unregisterComponentCallbacks(configCallbacks)
        activity = null
        if (!watchingDisplay) {
            return
        }
        val displayManager =
            context.getSystemService(Context.DISPLAY_SERVICE) as android.hardware.display.DisplayManager
        displayManager.unregisterDisplayListener(displayListener)
        watchingDisplay = false
    }

    private fun activityDisplayRotationDegrees(): Int {
        val rotation =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity?.display?.rotation
            } else {
                @Suppress("DEPRECATION")
                activity?.windowManager?.defaultDisplay?.rotation
            }
                ?: Surface.ROTATION_0
        return when (rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    /**
     * Counterclockwise degrees from [android.view.Display.getRotation].
     *
     * This must match the Flutter window, not gravity. OrientationEventListener
     * can report 180 while the activity is still ROTATION_0; using gravity then
     * inverts the camera against upright chrome. Listener is only used to pick
     * landscape 90 vs 270 when configuration is landscape but Display still
     * says 0 (Flutter `configChanges` lag).
     */
    private fun displayRotationDegrees(): Int {
        val resources = activity?.resources ?: context.resources
        val orientation = resources.configuration.orientation
        val display = activityDisplayRotationDegrees()
        val listener = listenerDisplayRotation
        if (orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE) {
            if (display == 90 || display == 270) {
                return display
            }
            if (listener == 90 || listener == 270) {
                return listener
            }
            return 90
        }
        if (display == 0 || display == 180) {
            return display
        }
        return 0
    }

    private fun displayRotationFromClockwiseTilt(clockwiseDegrees: Int): Int {
        val rounded = ((clockwiseDegrees % 360) + 360) % 360
        return when {
            rounded in 45 until 135 -> 270
            rounded in 135 until 225 -> 180
            rounded in 225 until 315 -> 90
            else -> 0
        }
    }

    private var cachedSensorOrientation = 90
    private var cachedFrontFacing = false

    private fun cacheLens(id: String) {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val chars = manager.getCameraCharacteristics(id)
        cachedSensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        cachedFrontFacing =
            chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
    }

    private fun captureRotation(): Int {
        if (selectedId == null) {
            return 0
        }
        return CameraBufferRotation.clockwisePostRotate(
            sensorOrientation = cachedSensorOrientation,
            displayRotationDegrees = displayRotationDegrees(),
            frontFacing = cachedFrontFacing,
        )
    }

    private fun captureBufferSize(
        sourceWidth: Int,
        sourceHeight: Int,
        rotationDegrees: Int,
    ): Pair<Int, Int> {
        return CameraBufferRotation.bufferSize(sourceWidth, sourceHeight, rotationDegrees)
    }

    private fun quarterTurns(): Int {
        val turns = captureRotation() / 90
        return ((turns % 4) + 4) % 4
    }

    private fun rotateAndCropMode(rotationDegrees: Int): Int {
        if (Build.VERSION.SDK_INT < 31) {
            return CaptureRequest.SCALER_ROTATE_AND_CROP_NONE
        }
        return when (rotationDegrees % 360) {
            90 -> CaptureRequest.SCALER_ROTATE_AND_CROP_90
            180 -> CaptureRequest.SCALER_ROTATE_AND_CROP_180
            270 -> CaptureRequest.SCALER_ROTATE_AND_CROP_270
            else -> CaptureRequest.SCALER_ROTATE_AND_CROP_NONE
        }
    }

    private fun supportsRotateAndCrop(
        chars: CameraCharacteristics,
        mode: Int,
    ): Boolean {
        if (Build.VERSION.SDK_INT < 31) {
            return false
        }
        if (mode == CaptureRequest.SCALER_ROTATE_AND_CROP_NONE) {
            return true
        }
        val modes = chars.get(CameraCharacteristics.SCALER_AVAILABLE_ROTATE_AND_CROP_MODES)
        return modes?.contains(mode) == true
    }

    private fun applyRotateAndCrop(
        request: CaptureRequest.Builder,
        chars: CameraCharacteristics,
    ) {
        if (Build.VERSION.SDK_INT < 31) {
            return
        }
        val mode = rotateAndCropMode(captureRotation())
        if (supportsRotateAndCrop(chars, mode)) {
            request.set(CaptureRequest.SCALER_ROTATE_AND_CROP, mode)
        }
    }

    private fun blit(
        bitmap: Bitmap,
        dest: Surface,
    ) {
        val canvas =
            try {
                dest.lockCanvas(null)
            } catch (_: Exception) {
                dest.lockHardwareCanvas()
            }
        try {
            canvas.drawColor(android.graphics.Color.BLACK)
            canvas.drawBitmap(bitmap, null, Rect(0, 0, canvas.width, canvas.height), null)
        } finally {
            dest.unlockCanvasAndPost(canvas)
        }
    }

    private fun isFrontFacing(): Boolean = cachedFrontFacing

    // CameraX ImageUtil.rotateBitmap = postRotate. TransformationInfo:
    // front mirror after rotation, vertical axis of the upright buffer.
    private fun rotateUpright(bitmap: Bitmap): Bitmap {
        val degrees = captureRotation()
        val front = isFrontFacing()
        val rotated =
            if (degrees == 0) {
                bitmap
            } else {
                val matrix = Matrix()
                matrix.postRotate(degrees.toFloat())
                Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            }
        if (!front) {
            return rotated
        }
        val mirror = Matrix()
        mirror.postScale(-1f, 1f, rotated.width / 2f, rotated.height / 2f)
        return Bitmap.createBitmap(rotated, 0, 0, rotated.width, rotated.height, mirror, true)
    }
}

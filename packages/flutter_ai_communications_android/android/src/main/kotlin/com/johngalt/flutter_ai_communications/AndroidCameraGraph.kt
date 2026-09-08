package com.johngalt.flutter_ai_communications

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.graphics.YuvImage
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import androidx.core.content.ContextCompat
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class AndroidCameraGraph(
    private val context: Context,
    private val textures: TextureRegistry,
) {
    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var camera: CameraDevice? = null
    private var session: android.hardware.camera2.CameraCaptureSession? = null
    private var surface: Surface? = null
    private var outputSurface: Surface? = null
    private var reader: ImageReader? = null
    private var selectedId: String? = null
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
        val kept = if (keepTexture) entry else null
        stop(releaseTexture = !keepTexture)
        entry = kept
        val id = startId.incrementAndGet()
        cameraEnabled = enabled
        videoMuted = muted
        lastWidth = width
        lastHeight = height
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
        val entry = this.entry ?: textures.createSurfaceTexture()
        this.entry = entry
        val texture: SurfaceTexture = entry.surfaceTexture()
        texture.setDefaultBufferSize(width, height)
        val flutterSurface = Surface(texture)
        val captureSurface: Surface
        if (processor.mode !is AndroidVideoProcessor.Mode.None) {
            val imageReader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 2)
            imageReader.setOnImageAvailableListener({ onProcessedImage(it) }, cameraHandler)
            reader = imageReader
            outputSurface = flutterSurface
            captureSurface = imageReader.surface
        } else {
            reader = null
            outputSurface = null
            captureSurface = flutterSurface
        }
        val surface = captureSurface
        this.surface = surface
        val started =
            mapOf(
                "status" to "started",
                "textureId" to entry.id(),
                "width" to width,
                "height" to height,
                "frameRate" to 30,
            )
        if (!enabled) {
            onResult(started)
            return
        }
        if (permission() != "granted") {
            surface.release()
            this.surface = null
            entry.release()
            this.entry = null
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
                                    captureSession.setRepeatingRequest(request.build(), null, cameraHandler)
                                }
                                main.post { onResult(started) }
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
        start(cameraId, 1280, 720, cameraEnabled, videoMuted) { }
    }

    fun setEnabled(enabled: Boolean) {
        cameraEnabled = enabled
        if (!enabled) {
            startId.incrementAndGet()
            stopRepeatingLocked()
            closeCameraLocked()
        } else {
            selectedId?.let { id -> start(id, 1280, 720, true, videoMuted) { } }
        }
    }

    fun setProcessor(args: Map<String, Any?>): String {
        val wasProcessed = processor.mode !is AndroidVideoProcessor.Mode.None
        val status = processor.apply(args)
        if (status != "ready") {
            return status
        }
        val nowProcessed = processor.mode !is AndroidVideoProcessor.Mode.None
        if (wasProcessed != nowProcessed && selectedId != null && cameraEnabled) {
            start(
                selectedId,
                lastWidth,
                lastHeight,
                cameraEnabled,
                videoMuted,
                { },
                keepTexture = true,
            )
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
            captureSession.setRepeatingRequest(request.build(), null, cameraHandler)
        } catch (_: Exception) {
        }
    }

    fun stop(releaseTexture: Boolean = true) {
        startId.incrementAndGet()
        stopRepeatingLocked()
        closeCameraLocked()
        surface?.release()
        surface = null
        outputSurface?.release()
        outputSurface = null
        reader?.close()
        reader = null
        if (releaseTexture) {
            entry?.release()
            entry = null
        }
    }

    private fun onProcessedImage(imageReader: ImageReader) {
        val image = imageReader.acquireLatestImage() ?: return
        try {
            val bitmap = yuvToBitmap(image) ?: return
            val processed = processor.process(bitmap)
            val dest = outputSurface ?: return
            val canvas = dest.lockHardwareCanvas()
            canvas.drawBitmap(processed, null, Rect(0, 0, lastWidth, lastHeight), null)
            dest.unlockCanvasAndPost(canvas)
        } catch (_: Exception) {
        } finally {
            image.close()
        }
    }

    private fun yuvToBitmap(image: Image): Bitmap? {
        val width = image.width
        val height = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val ySize = width * height
        val nv21 = ByteArray(ySize + width * height / 2)
        val yBuffer = yPlane.buffer
        val yRowStride = yPlane.rowStride
        var out = 0
        for (row in 0 until height) {
            val rowStart = row * yRowStride
            for (col in 0 until width) {
                nv21[out++] = yBuffer.get(rowStart + col)
            }
        }
        val vBuffer = vPlane.buffer
        val uBuffer = uPlane.buffer
        val vRowStride = vPlane.rowStride
        val vPixelStride = vPlane.pixelStride
        val uRowStride = uPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val chromaHeight = height / 2
        val chromaWidth = width / 2
        for (row in 0 until chromaHeight) {
            for (col in 0 until chromaWidth) {
                nv21[out++] = vBuffer.get(row * vRowStride + col * vPixelStride)
                nv21[out++] = uBuffer.get(row * uRowStride + col * uPixelStride)
            }
        }
        val yuv = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        val jpeg = ByteArrayOutputStream()
        yuv.compressToJpeg(Rect(0, 0, width, height), 90, jpeg)
        val bytes = jpeg.toByteArray()
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
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
}

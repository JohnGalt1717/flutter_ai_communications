package com.johngalt.flutter_ai_communications

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
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
    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var camera: CameraDevice? = null
    private var session: android.hardware.camera2.CameraCaptureSession? = null
    private var surface: Surface? = null
    private var selectedId: String? = null
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
    ) {
        stop()
        val id = startId.incrementAndGet()
        cameraEnabled = enabled
        videoMuted = muted
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
        val entry = textures.createSurfaceTexture()
        this.entry = entry
        val texture: SurfaceTexture = entry.surfaceTexture()
        texture.setDefaultBufferSize(width, height)
        val surface = Surface(texture)
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

    fun stop() {
        startId.incrementAndGet()
        stopRepeatingLocked()
        closeCameraLocked()
        surface?.release()
        surface = null
        entry?.release()
        entry = null
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

package com.johngalt.flutter_ai_communications

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

class AndroidScreenGraph(
    private val context: Context,
    private val textures: TextureRegistry,
    private val onSystemStop: () -> Unit,
) : PluginRegistry.ActivityResultListener {
    private val manager =
        context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var includeAudio = false
    private var motion = false
    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private val requestCode = 0xFAC4
    private val projectionCallback =
        object : MediaProjection.Callback() {
            override fun onStop() {
                main.post {
                    if (projection == null) {
                        return@post
                    }
                    stop()
                    onSystemStop()
                }
            }
        }

    fun attachActivity(activity: Activity?) {
        this.activity = activity
    }

    fun enumerate(): List<Map<String, Any>> =
        listOf(
            mapOf(
                "id" to "system-picker",
                "name" to "System picker",
                "kind" to "systemPicker",
                "canPreview" to false,
            ),
        )

    fun permission(): String = "granted"

    fun start(
        includeSystemAudio: Boolean,
        motion: Boolean,
        result: MethodChannel.Result,
    ) {
        stop()
        val host = activity
        if (host == null) {
            result.success(mapOf("status" to "unavailable", "reason" to "none"))
            return
        }
        includeAudio = includeSystemAudio
        this.motion = motion
        pending = result
        host.startActivityForResult(manager.createScreenCaptureIntent(), requestCode)
    }

    fun stop() {
        pending?.success(mapOf("status" to "unavailable", "reason" to "none"))
        pending = null
        virtualDisplay?.release()
        virtualDisplay = null
        val live = projection
        projection = null
        if (live != null) {
            if (Build.VERSION.SDK_INT >= 34) {
                live.unregisterCallback(projectionCallback)
            }
            live.stop()
        }
        surface?.release()
        surface = null
        entry?.release()
        entry = null
        context.stopService(Intent(context, ScreenCaptureService::class.java))
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != this.requestCode) {
            return false
        }
        val reply = pending
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            reply?.success(mapOf("status" to "unavailable", "reason" to "denied"))
            return true
        }
        val metrics = context.resources.displayMetrics
        val width = metrics.widthPixels.coerceAtMost(1920)
        val height = metrics.heightPixels.coerceAtMost(1080)
        val density = metrics.densityDpi
        val texture = textures.createSurfaceTexture()
        texture.surfaceTexture().setDefaultBufferSize(width, height)
        val surface = Surface(texture.surfaceTexture())
        entry = texture
        this.surface = surface
        val replied = AtomicBoolean(false)
        val finish: (Map<String, Any>) -> Unit = { payload ->
            if (replied.compareAndSet(false, true)) {
                reply?.success(payload)
            }
        }
        ScreenCaptureService.onStarted = {
            main.post {
                bindProjection(resultCode, data, texture, width, height, density, finish)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(Intent(context, ScreenCaptureService::class.java))
        } else {
            context.startService(Intent(context, ScreenCaptureService::class.java))
        }
        main.postDelayed(
            {
                if (replied.get()) {
                    return@postDelayed
                }
                ScreenCaptureService.onStarted = null
                stop()
                finish(mapOf("status" to "failed", "reason" to "none"))
            },
            2_000,
        )
        return true
    }

    private fun bindProjection(
        resultCode: Int,
        data: Intent,
        texture: TextureRegistry.SurfaceTextureEntry,
        width: Int,
        height: Int,
        density: Int,
        finish: (Map<String, Any>) -> Unit,
    ) {
        if (projection != null) {
            return
        }
        val projection =
            try {
                manager.getMediaProjection(resultCode, data)
            } catch (_: SecurityException) {
                stop()
                finish(mapOf("status" to "failed", "reason" to "none"))
                return
            }
        if (projection == null) {
            stop()
            finish(mapOf("status" to "failed", "reason" to "none"))
            return
        }
        this.projection = projection
        projection.registerCallback(projectionCallback, main)
        virtualDisplay =
            projection.createVirtualDisplay(
                "fac-screen",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface,
                null,
                main,
            )
        finish(
            mapOf(
                "status" to "started",
                "textureId" to texture.id(),
                "width" to width,
                "height" to height,
                "frameRate" to if (motion) 30 else 5,
                "systemAudio" to false,
            ),
        )
    }
}

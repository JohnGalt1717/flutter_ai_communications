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
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

class AndroidScreenGraph(
    private val context: Context,
    private val textures: TextureRegistry,
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
        projection?.stop()
        projection = null
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(Intent(context, ScreenCaptureService::class.java))
        } else {
            context.startService(Intent(context, ScreenCaptureService::class.java))
        }
        val projection = manager.getMediaProjection(resultCode, data)
        if (projection == null) {
            stop()
            reply?.success(mapOf("status" to "failed", "reason" to "none"))
            return true
        }
        this.projection = projection
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
        reply?.success(
            mapOf(
                "status" to "started",
                "textureId" to texture.id(),
                "width" to width,
                "height" to height,
                "frameRate" to if (motion) 30 else 5,
                "systemAudio" to false,
            ),
        )
        return true
    }
}

package com.johngalt.flutter_ai_communications_webrtc

import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.johngalt.flutter_ai_communications.AndroidVideoProcessor
import com.johngalt.flutter_ai_communications.YuvArgb
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import org.webrtc.YuvHelper
import java.nio.ByteBuffer

/**
 * FAC [AndroidVideoProcessor] on one flutter_webrtc track. Frames are turned
 * upright (selfie segmentation expects a standing person) and leave with
 * rotation 0.
 *
 * Fails closed: while blur/replace is requested and the processor is not
 * ready, errors, or hands back the input unchanged, the frame is black.
 * Before the first mask a frame is fully blurred (or fully the still).
 * [onUnavailable] fires when segmentation gives up after it was ready, never
 * after [close].
 */
internal class TrackProcessor(
    private val onUnavailable: () -> Unit,
) : LocalVideoTrack.ExternalVideoFrameProcessing {
    private val processor = AndroidVideoProcessor()
    private val shape = FrameShape()

    @Volatile
    private var ready = false

    /** Frames this processor has seen; [BypassWatch] reads it. */
    @Volatile
    var frames = 0L
        private set

    private var argb = IntArray(0)
    private var rgba: ByteBuffer? = null
    private var black: JavaI420Buffer? = null

    // LocalVideoTrack does not release the frame a processor returns. Keep
    // the last one and release it on the next frame.
    private var previous: VideoFrame? = null

    init {
        // Segmentation gave up mid-call: frames go black, then tell the host.
        processor.onUnavailable = {
            if (ready) {
                ready = false
                onUnavailable()
            }
        }
    }

    fun apply(args: Map<String, Any?>): String {
        val status = processor.apply(args)
        ready = status == "ready"
        return status
    }

    override fun onFrame(frame: VideoFrame): VideoFrame {
        frames += 1
        val out = (if (ready) processed(frame) else null) ?: blackFrame(frame)
        synchronized(this) {
            previous?.release()
            previous = out
        }
        return out
    }

    /** The sink may still hold the last frame; release after it is done. */
    fun close() {
        ready = false
        processor.close()
        val last: VideoFrame?
        val cached: JavaI420Buffer?
        synchronized(this) {
            last = previous
            previous = null
            cached = black
            black = null
        }
        Handler(Looper.getMainLooper()).postDelayed({
            last?.release()
            cached?.release()
        }, RELEASE_DELAY_MS)
    }

    private fun processed(frame: VideoFrame): VideoFrame? =
        try {
            val i420 = frame.buffer.toI420() ?: return null
            val upright =
                try {
                    uprightBitmap(i420, frame.rotation)
                } finally {
                    i420.release()
                }
            // Camera switch, rotation, or resolution change: the old mask no
            // longer lines up with the person.
            if (shape.changed(upright.width, upright.height, frame.rotation)) {
                processor.invalidateMask()
            }
            try {
                val result = processor.process(upright)
                sendable(upright, result, ready)?.let { VideoFrame(toI420(it), 0, frame.timestampNs) }
            } finally {
                upright.recycle()
            }
        } catch (_: Throwable) {
            null
        }

    private fun uprightBitmap(
        buffer: VideoFrame.I420Buffer,
        rotation: Int,
    ): Bitmap {
        val width = buffer.width
        val height = buffer.height
        if (argb.size != width * height) {
            argb = IntArray(width * height)
        }
        YuvArgb.convert(
            buffer.dataY,
            buffer.strideY,
            1,
            buffer.dataU,
            buffer.strideU,
            1,
            buffer.dataV,
            buffer.strideV,
            1,
            width,
            height,
            argb,
        )
        val bitmap = Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
        if (rotation % 360 == 0) {
            return bitmap
        }
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, width, height, matrix, true).also {
            if (it !== bitmap) {
                bitmap.recycle()
            }
        }
    }

    private fun toI420(bitmap: Bitmap): JavaI420Buffer {
        val width = bitmap.width
        val height = bitmap.height
        val bytes = width * height * 4
        val scratch =
            rgba?.takeIf { it.capacity() == bytes } ?: ByteBuffer.allocateDirect(bytes).also { rgba = it }
        scratch.clear()
        // ARGB_8888 is R, G, B, A in memory: libyuv "ABGR".
        bitmap.copyPixelsToBuffer(scratch)
        scratch.rewind()
        val out = JavaI420Buffer.allocate(width, height)
        try {
            YuvHelper.ABGRToI420(
                scratch,
                width * 4,
                out.dataY,
                out.strideY,
                out.dataU,
                out.strideU,
                out.dataV,
                out.strideV,
                width,
                height,
            )
        } catch (error: Throwable) {
            out.release()
            throw error
        }
        return out
    }

    private fun blackFrame(frame: VideoFrame): VideoFrame {
        val width = frame.rotatedWidth
        val height = frame.rotatedHeight
        val buffer =
            synchronized(this) {
                black?.takeIf { it.width == width && it.height == height }
                    ?: JavaI420Buffer.allocate(width, height).also {
                        fill(it.dataY, 16)
                        fill(it.dataU, 128)
                        fill(it.dataV, 128)
                        black?.release()
                        black = it
                    }
            }
        buffer.retain()
        return VideoFrame(buffer, 0, frame.timestampNs)
    }

    private fun fill(
        plane: ByteBuffer,
        value: Int,
    ) {
        for (index in 0 until plane.capacity()) {
            plane.put(index, value.toByte())
        }
    }

    private companion object {
        const val RELEASE_DELAY_MS = 1000L
    }
}

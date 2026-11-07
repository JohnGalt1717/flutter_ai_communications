package com.johngalt.flutter_ai_communications_webrtc

import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.johngalt.flutter_ai_communications.AndroidVideoProcessor
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
 */
internal class TrackProcessor : LocalVideoTrack.ExternalVideoFrameProcessing {
    private val processor = AndroidVideoProcessor()

    @Volatile
    private var ready = false

    private var argb = IntArray(0)
    private var rgba: ByteBuffer? = null
    private var black: JavaI420Buffer? = null

    // LocalVideoTrack does not release the frame a processor returns. Keep
    // the last one and release it on the next frame.
    private var previous: VideoFrame? = null

    init {
        processor.onUnavailable = { ready = false }
    }

    fun apply(args: Map<String, Any?>): String {
        val status = processor.apply(args)
        ready = status == "ready"
        return status
    }

    override fun onFrame(frame: VideoFrame): VideoFrame {
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
            try {
                val result = processor.process(upright)
                if (result === upright || !ready) null else VideoFrame(toI420(result), 0, frame.timestampNs)
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
        I420Argb.convert(
            buffer.dataY,
            buffer.strideY,
            buffer.dataU,
            buffer.strideU,
            buffer.dataV,
            buffer.strideV,
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

/** BT.601 I420 to ARGB, the same integer math FAC's camera graph uses. */
internal object I420Argb {
    fun convert(
        y: ByteBuffer,
        strideY: Int,
        u: ByteBuffer,
        strideU: Int,
        v: ByteBuffer,
        strideV: Int,
        width: Int,
        height: Int,
        out: IntArray,
    ) {
        for (row in 0 until height) {
            val yRow = row * strideY
            val uRow = (row / 2) * strideU
            val vRow = (row / 2) * strideV
            val outRow = row * width
            for (col in 0 until width) {
                val luma = y.get(yRow + col).toInt() and 0xFF
                val d = (u.get(uRow + col / 2).toInt() and 0xFF) - 128
                val e = (v.get(vRow + col / 2).toInt() and 0xFF) - 128
                val r = (luma + ((351 * e) shr 8)).coerceIn(0, 255)
                val g = (luma - ((179 * e + 86 * d) shr 8)).coerceIn(0, 255)
                val b = (luma + ((443 * d) shr 8)).coerceIn(0, 255)
                out[outRow + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }
}

package com.johngalt.flutter_ai_communications

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.SegmentationMask
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ML Kit selfie segmentation for blur / replace on the Production video path.
 *
 * [SegmentationMask.getBuffer] holds floats in \[0, 1\] (not bytes). Masks are
 * requested asynchronously; [process] composites with the last successful mask
 * so the camera thread never blocks on [Tasks.await].
 */
internal class AndroidVideoProcessor {
    sealed class Mode {
        data object None : Mode()

        data class Blur(
            val intensity: Int,
        ) : Mode()

        data object Replace : Mode()
    }

    private data class MaskSnapshot(
        val buffer: ByteBuffer,
        val width: Int,
        val height: Int,
    )

    var mode: Mode = Mode.None
    var still: Bitmap? = null
    private val segmenter =
        try {
            Segmentation.getClient(
                SelfieSegmenterOptions
                    .Builder()
                    .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
                    .build(),
            )
        } catch (_: Throwable) {
            null
        }

    private val maskInFlight = AtomicBoolean(false)

    @Volatile
    private var lastMask: MaskSnapshot? = null

    val available: Boolean get() = segmenter != null

    fun apply(args: Map<String, Any?>): String {
        when (args["kind"] as? String ?: "none") {
            "none" -> {
                mode = Mode.None
                still = null
                lastMask = null
                return "ready"
            }
            "blur" -> {
                if (!available) {
                    return "unavailable"
                }
                val intensity = (args["intensity"] as? Number)?.toInt() ?: 50
                if (intensity !in 0..100) {
                    return "invalid"
                }
                mode = Mode.Blur(intensity)
                return "ready"
            }
            "replace" -> {
                if (!available) {
                    return "unavailable"
                }
                val bytes = bytesOf(args["bytes"])
                val bitmap =
                    if (bytes != null) {
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    } else {
                        null
                    }
                if (bitmap == null) {
                    return "invalid"
                }
                still = bitmap
                mode = Mode.Replace
                return "ready"
            }
            else -> return "unavailable"
        }
    }

    fun process(bitmap: Bitmap): Bitmap {
        val current = mode
        if (current is Mode.None) {
            return bitmap
        }
        requestMaskAsync(bitmap)
        val snapshot = lastMask ?: return bitmap
        val background =
            when (current) {
                is Mode.Blur -> blur(bitmap, current.intensity)
                is Mode.Replace -> scaledStill(bitmap.width, bitmap.height)
                is Mode.None -> bitmap
            } ?: return bitmap
        return AndroidVideoMask.composite(
            person = bitmap,
            background = background,
            mask = snapshot.buffer,
            maskWidth = snapshot.width,
            maskHeight = snapshot.height,
        )
    }

    private fun bytesOf(value: Any?): ByteArray? =
        when (value) {
            is ByteArray -> value
            is List<*> -> ByteArray(value.size) { index -> (value[index] as Number).toByte() }
            else -> null
        }

    private fun requestMaskAsync(bitmap: Bitmap) {
        val client = segmenter ?: return
        if (!maskInFlight.compareAndSet(false, true)) {
            return
        }
        val copy =
            bitmap.copy(Bitmap.Config.ARGB_8888, false) ?: run {
                maskInFlight.set(false)
                return
            }
        try {
            client
                .process(InputImage.fromBitmap(copy, 0))
                .addOnSuccessListener { result ->
                    try {
                        lastMask = snapshotOf(result)
                    } finally {
                        copy.recycle()
                        maskInFlight.set(false)
                    }
                }.addOnFailureListener {
                    copy.recycle()
                    maskInFlight.set(false)
                }
        } catch (_: Throwable) {
            copy.recycle()
            maskInFlight.set(false)
        }
    }

    private fun snapshotOf(result: SegmentationMask): MaskSnapshot {
        val source = result.buffer
        source.rewind()
        source.order(ByteOrder.nativeOrder())
        val owned = ByteBuffer.allocateDirect(source.capacity()).order(ByteOrder.nativeOrder())
        owned.put(source)
        owned.rewind()
        return MaskSnapshot(
            buffer = owned,
            width = result.width,
            height = result.height,
        )
    }

    private fun blur(
        bitmap: Bitmap,
        intensity: Int,
    ): Bitmap {
        val factor = (1f - intensity / 100f).coerceIn(0.12f, 1f)
        val width = (bitmap.width * factor).toInt().coerceAtLeast(8)
        val height = (bitmap.height * factor).toInt().coerceAtLeast(8)
        val small = Bitmap.createScaledBitmap(bitmap, width, height, true)
        return Bitmap.createScaledBitmap(small, bitmap.width, bitmap.height, true)
    }

    private fun scaledStill(
        width: Int,
        height: Int,
    ): Bitmap? {
        val source = still ?: return null
        return Bitmap.createScaledBitmap(source, width, height, true)
    }
}

/** Pure mask composite helpers — JVM-testable without ML Kit or Bitmap. */
internal object AndroidVideoMask {
    const val PERSON_THRESHOLD = 0.5f

    /**
     * ML Kit mask floats are in \[0, 1\]. Sample with nearest-neighbor when
     * mask dimensions differ from the frame size.
     */
    fun compositePixels(
        personPixels: IntArray,
        backgroundPixels: IntArray,
        width: Int,
        height: Int,
        mask: ByteBuffer,
        maskWidth: Int,
        maskHeight: Int,
    ): IntArray {
        require(personPixels.size == width * height)
        require(backgroundPixels.size == width * height)
        val outPixels = backgroundPixels.copyOf()
        val ordered = mask.duplicate().order(ByteOrder.nativeOrder())
        ordered.rewind()
        val yDenom = (height - 1).coerceAtLeast(1)
        val xDenom = (width - 1).coerceAtLeast(1)
        for (y in 0 until height) {
            val my =
                if (maskHeight <= 1) {
                    0
                } else {
                    y * (maskHeight - 1) / yDenom
                }
            for (x in 0 until width) {
                val mx =
                    if (maskWidth <= 1) {
                        0
                    } else {
                        x * (maskWidth - 1) / xDenom
                    }
                val byteIndex = (my * maskWidth + mx) * 4
                if (byteIndex + 4 > ordered.capacity()) {
                    continue
                }
                val confidence = ordered.getFloat(byteIndex)
                if (confidence > PERSON_THRESHOLD) {
                    outPixels[y * width + x] = personPixels[y * width + x]
                }
            }
        }
        return outPixels
    }

    fun composite(
        person: Bitmap,
        background: Bitmap,
        mask: ByteBuffer,
        maskWidth: Int,
        maskHeight: Int,
    ): Bitmap {
        val width = person.width
        val height = person.height
        val personPixels = IntArray(width * height)
        val backgroundPixels = IntArray(width * height)
        person.getPixels(personPixels, 0, width, 0, 0, width, height)
        background.getPixels(backgroundPixels, 0, width, 0, 0, width, height)
        val outPixels =
            compositePixels(
                personPixels = personPixels,
                backgroundPixels = backgroundPixels,
                width = width,
                height = height,
                mask = mask,
                maskWidth = maskWidth,
                maskHeight = maskHeight,
            )
        val out = background.copy(Bitmap.Config.ARGB_8888, true)
        out.setPixels(outPixels, 0, width, 0, 0, width, height)
        return out
    }

    /** Builds a float mask buffer for tests (native byte order). */
    fun floatMask(
        width: Int,
        height: Int,
        confidence: (x: Int, y: Int) -> Float,
    ): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
        for (y in 0 until height) {
            for (x in 0 until width) {
                buffer.putFloat(confidence(x, y))
            }
        }
        buffer.rewind()
        return buffer
    }
}

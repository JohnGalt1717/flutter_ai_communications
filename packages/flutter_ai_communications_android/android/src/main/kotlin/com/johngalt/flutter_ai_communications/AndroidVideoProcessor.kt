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
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.math.roundToInt

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
        val floats: FloatArray,
        val width: Int,
        val height: Int,
    )

    private val modeRef = AtomicReference<Mode>(Mode.None)
    var mode: Mode
        get() = modeRef.get()
        set(value) {
            modeRef.set(value)
        }

    @Volatile
    var still: Bitmap? = null

    /** Fired once when runtime segmentation fails and the processor falls back to none. */
    var onUnavailable: (() -> Unit)? = null

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
    private val generation = AtomicInteger(0)
    private var consecutiveFailures = 0
    @Volatile
    private var lastMask: MaskSnapshot? = null

    private var personPixels = IntArray(0)
    private var outPixels = IntArray(0)
    private var outBitmap: Bitmap? = null

    val available: Boolean get() = segmenter != null

    /** Drop cached masks (camera switch / apply). In-flight callbacks are ignored. */
    fun invalidateMask() {
        generation.incrementAndGet()
        consecutiveFailures = 0
        lastMask = null
    }

    fun apply(args: Map<String, Any?>): String {
        invalidateMask()
        val kind = args["kind"] as? String ?: "none"
        when (kind) {
            "none" -> {
                mode = Mode.None
                still = null
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
        val background =
            when (current) {
                is Mode.Blur -> blur(bitmap, current.intensity)
                is Mode.Replace -> scaledStill(bitmap.width, bitmap.height)
                is Mode.None -> bitmap
            } ?: return bitmap
        val snapshot = lastMask ?: return background
        val width = bitmap.width
        val height = bitmap.height
        val buffers = ensureFrameBuffers(width, height)
        bitmap.getPixels(buffers.person, 0, width, 0, 0, width, height)
        background.getPixels(buffers.out, 0, width, 0, 0, width, height)
        PersonMask.composite(
            buffers.person,
            buffers.out,
            snapshot.floats,
            snapshot.width,
            snapshot.height,
            width,
            height,
            buffers.out,
        )
        buffers.bitmap.setPixels(buffers.out, 0, width, 0, 0, width, height)
        return buffers.bitmap
    }

    private data class FrameBuffers(
        val person: IntArray,
        val out: IntArray,
        val bitmap: Bitmap,
    )

    private fun ensureFrameBuffers(
        width: Int,
        height: Int,
    ): FrameBuffers {
        val count = width * height
        if (personPixels.size != count) {
            personPixels = IntArray(count)
            outPixels = IntArray(count)
        }
        val cached = outBitmap
        val bitmap =
            if (cached != null &&
                !cached.isRecycled &&
                cached.width == width &&
                cached.height == height
            ) {
                cached
            } else {
                cached?.recycle()
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                    outBitmap = it
                }
            }
        return FrameBuffers(person = personPixels, out = outPixels, bitmap = bitmap)
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
        val requestGeneration = generation.get()
        val copy =
            inferenceBitmap(bitmap) ?: run {
                maskInFlight.set(false)
                if (requestGeneration == generation.get()) {
                    noteInferenceFailure()
                }
                return
            }
        try {
            client
                .process(InputImage.fromBitmap(copy, 0))
                .addOnSuccessListener { result ->
                    try {
                        if (requestGeneration != generation.get()) {
                            return@addOnSuccessListener
                        }
                        consecutiveFailures = 0
                        val snapshot = snapshotOf(result)
                        if (snapshot != null) {
                            lastMask = snapshot
                        }
                    } finally {
                        if (!copy.isRecycled) {
                            copy.recycle()
                        }
                        maskInFlight.set(false)
                    }
                }.addOnFailureListener {
                    try {
                        if (requestGeneration != generation.get()) {
                            return@addOnFailureListener
                        }
                        noteInferenceFailure()
                    } finally {
                        if (!copy.isRecycled) {
                            copy.recycle()
                        }
                        maskInFlight.set(false)
                    }
                }
        } catch (_: Throwable) {
            if (!copy.isRecycled) {
                copy.recycle()
            }
            maskInFlight.set(false)
            if (requestGeneration == generation.get()) {
                noteInferenceFailure()
            }
        }
    }

    private fun inferenceBitmap(bitmap: Bitmap): Bitmap? {
        val longSide = max(bitmap.width, bitmap.height)
        if (longSide <= INFERENCE_MAX_SIDE) {
            return bitmap.copy(Bitmap.Config.ARGB_8888, false)
        }
        val scale = INFERENCE_MAX_SIDE / longSide.toFloat()
        val width = (bitmap.width * scale).toInt().coerceAtLeast(8)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(8)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    private fun snapshotOf(result: SegmentationMask): MaskSnapshot? {
        val floats = floatsFrom(result) ?: return null
        val prepared = PersonMask.prepare(floats, result.width, result.height)
        return MaskSnapshot(
            floats = prepared,
            width = result.width,
            height = result.height,
        )
    }

    private fun floatsFrom(result: SegmentationMask): FloatArray? {
        val width = result.width
        val height = result.height
        val count = width * height
        if (count <= 0) {
            return null
        }
        val buffer = result.buffer
        buffer.rewind()
        val remaining = buffer.remaining()
        val floats = FloatArray(count)
        when (remaining) {
            count * 4 -> {
                buffer.order(ByteOrder.nativeOrder())
                buffer.asFloatBuffer().get(floats)
            }
            count -> {
                for (i in 0 until count) {
                    floats[i] = (buffer.get().toInt() and 0xFF) / 255f
                }
            }
            else -> {
                return null
            }
        }
        return floats
    }

    private fun noteInferenceFailure() {
        consecutiveFailures += 1
        if (consecutiveFailures < FAILURE_LIMIT) {
            return
        }
        if (mode is Mode.None) {
            return
        }
        generation.incrementAndGet()
        mode = Mode.None
        still = null
        lastMask = null
        consecutiveFailures = 0
        onUnavailable?.invoke()
    }

    private fun blur(
        bitmap: Bitmap,
        intensity: Int,
    ): Bitmap {
        if (intensity <= 0) {
            return bitmap
        }
        val scale = DownscaleBlur.scale(intensity)
        val width = (bitmap.width * scale).toInt().coerceAtLeast(8)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(8)
        val small = Bitmap.createScaledBitmap(bitmap, width, height, true)
        val tinyScale = DownscaleBlur.tinyScale(intensity)
        val tinyWidth = (width * tinyScale).toInt().coerceAtLeast(4)
        val tinyHeight = (height * tinyScale).toInt().coerceAtLeast(4)
        val tiny = Bitmap.createScaledBitmap(small, tinyWidth, tinyHeight, true)
        if (small != bitmap && !small.isRecycled) {
            small.recycle()
        }
        val out = Bitmap.createScaledBitmap(tiny, bitmap.width, bitmap.height, true)
        if (tiny != bitmap && !tiny.isRecycled) {
            tiny.recycle()
        }
        return out
    }

    private fun scaledStill(
        width: Int,
        height: Int,
    ): Bitmap? {
        val source = still ?: return null
        return Bitmap.createScaledBitmap(source, width, height, true)
    }

    companion object {
        private const val FAILURE_LIMIT = 5
        private const val INFERENCE_MAX_SIDE = 384
    }
}

/** Pure mask composite helpers — JVM-testable without ML Kit or Bitmap. */
internal object AndroidVideoMask {
    const val PERSON_THRESHOLD = 0.5f

    /**
     * ML Kit mask floats are in \[0, 1\]. Sample nearest mask texel when
     * mask dimensions differ from the frame size. [outPixels] must already
     * hold the background; person pixels are written in place.
     */
    fun compositeInto(
        personPixels: IntArray,
        outPixels: IntArray,
        width: Int,
        height: Int,
        mask: ByteBuffer,
        maskWidth: Int,
        maskHeight: Int,
    ) {
        require(personPixels.size == width * height)
        require(outPixels.size == width * height)
        val ordered = mask.duplicate().order(ByteOrder.nativeOrder())
        ordered.clear()
        val floats = ordered.asFloatBuffer()
        val floatCount = floats.remaining()
        for (y in 0 until height) {
            val my = nearestMaskIndex(y, height, maskHeight)
            for (x in 0 until width) {
                val mx = nearestMaskIndex(x, width, maskWidth)
                val index = my * maskWidth + mx
                if (index < 0 || index >= floatCount) {
                    continue
                }
                val confidence = floats.get(index)
                if (confidence > PERSON_THRESHOLD) {
                    outPixels[y * width + x] = personPixels[y * width + x]
                }
            }
        }
    }

    /**
     * Nearest mask sample for a frame coordinate. Same-size maps 1:1; otherwise
     * rounds along the inclusive endpoint mapping so a 4→2 scale yields [0,0,1,1].
     */
    fun nearestMaskIndex(
        frameIndex: Int,
        frameSize: Int,
        maskSize: Int,
    ): Int {
        if (maskSize <= 1) {
            return 0
        }
        if (frameSize == maskSize) {
            return frameIndex.coerceIn(0, maskSize - 1)
        }
        if (frameSize <= 1) {
            return 0
        }
        return (frameIndex.toDouble() * (maskSize - 1) / (frameSize - 1))
            .roundToInt()
            .coerceIn(0, maskSize - 1)
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
        val outPixels = IntArray(width * height)
        person.getPixels(personPixels, 0, width, 0, 0, width, height)
        background.getPixels(outPixels, 0, width, 0, 0, width, height)
        compositeInto(
            personPixels = personPixels,
            outPixels = outPixels,
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

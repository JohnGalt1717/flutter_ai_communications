package com.johngalt.flutter_ai_communications

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit

internal class AndroidVideoProcessor {
    sealed class Mode {
        data object None : Mode()

        data class Blur(
            val intensity: Int,
        ) : Mode()

        data object Replace : Mode()
    }

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

    val available: Boolean get() = segmenter != null

    fun apply(args: Map<String, Any?>): String {
        when (args["kind"] as? String ?: "none") {
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
        val mask = personMask(bitmap) ?: return bitmap
        val background =
            when (current) {
                is Mode.Blur -> blur(bitmap, current.intensity)
                is Mode.Replace -> scaledStill(bitmap.width, bitmap.height)
                is Mode.None -> bitmap
            } ?: return bitmap
        return composite(bitmap, background, mask)
    }

    private fun bytesOf(value: Any?): ByteArray? =
        when (value) {
            is ByteArray -> value
            is List<*> -> ByteArray(value.size) { index -> (value[index] as Number).toByte() }
            else -> null
        }

    private fun personMask(bitmap: Bitmap): ByteBuffer? {
        val client = segmenter ?: return null
        return try {
            val task = client.process(InputImage.fromBitmap(bitmap, 0))
            val result = com.google.android.gms.tasks.Tasks.await(task, 80, TimeUnit.MILLISECONDS)
            result.buffer
        } catch (_: Throwable) {
            null
        }
    }

    private fun blur(
        bitmap: Bitmap,
        intensity: Int,
    ): Bitmap {
        val factor = (1f - intensity / 200f).coerceIn(0.12f, 1f)
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

    private fun composite(
        person: Bitmap,
        background: Bitmap,
        mask: ByteBuffer,
    ): Bitmap {
        val width = person.width
        val height = person.height
        val out = background.copy(Bitmap.Config.ARGB_8888, true)
        val personPixels = IntArray(width * height)
        val outPixels = IntArray(width * height)
        person.getPixels(personPixels, 0, width, 0, 0, width, height)
        out.getPixels(outPixels, 0, width, 0, 0, width, height)
        mask.rewind()
        val count = minOf(personPixels.size, mask.remaining())
        for (i in 0 until count) {
            val alpha = mask.get().toInt() and 0xFF
            if (alpha > 128) {
                outPixels[i] = personPixels[i]
            }
        }
        out.setPixels(outPixels, 0, width, 0, 0, width, height)
        return out
    }
}

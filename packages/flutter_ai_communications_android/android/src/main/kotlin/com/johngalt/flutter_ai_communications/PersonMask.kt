package com.johngalt.flutter_ai_communications

import kotlin.math.floor
import kotlin.math.pow

/** Samples an ML Kit selfie mask onto a camera frame and composites person vs background. */
internal object PersonMask {
    const val PERSON_THRESHOLD = 0.4f
    const val FEATHER = 0.2f
    const val ERODE_RADIUS = 1
    const val EXPAND_RADIUS = 2
    const val BLUR_RADIUS = 1
    const val GAMMA = 2.4f

    fun confidence(
        mask: FloatArray,
        maskWidth: Int,
        maskHeight: Int,
        x: Int,
        y: Int,
        destWidth: Int,
        destHeight: Int,
    ): Float {
        if (mask.isEmpty() || maskWidth <= 0 || maskHeight <= 0 || destWidth <= 0 || destHeight <= 0) {
            return 0f
        }
        val fx = (x + 0.5f) * maskWidth / destWidth - 0.5f
        val fy = (y + 0.5f) * maskHeight / destHeight - 0.5f
        val x0 = floor(fx.toDouble()).toInt()
        val y0 = floor(fy.toDouble()).toInt()
        val tx = fx - x0
        val ty = fy - y0
        val v00 = sample(mask, maskWidth, maskHeight, x0, y0)
        val v10 = sample(mask, maskWidth, maskHeight, x0 + 1, y0)
        val v01 = sample(mask, maskWidth, maskHeight, x0, y0 + 1)
        val v11 = sample(mask, maskWidth, maskHeight, x0 + 1, y0 + 1)
        val a = v00 + (v10 - v00) * tx
        val b = v01 + (v11 - v01) * tx
        return a + (b - a) * ty
    }

    fun prepare(
        mask: FloatArray,
        width: Int,
        height: Int,
    ): FloatArray {
        val count = width * height
        if (width <= 0 || height <= 0 || mask.size < count) {
            return mask.copyOf()
        }
        val gammad = FloatArray(count) { index -> mask[index].pow(GAMMA) }
        val eroded = erode(gammad, width, height, ERODE_RADIUS)
        val dilated = expand(eroded, width, height, EXPAND_RADIUS)
        return blur(dilated, width, height, BLUR_RADIUS)
    }

    fun expand(
        mask: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ): FloatArray = extrema(mask, width, height, radius, peak = true)

    fun erode(
        mask: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ): FloatArray = extrema(mask, width, height, radius, peak = false)

    fun composite(
        person: IntArray,
        background: IntArray,
        mask: FloatArray,
        maskWidth: Int,
        maskHeight: Int,
        width: Int,
        height: Int,
        out: IntArray,
    ) {
        val count = width * height
        val low = PERSON_THRESHOLD - FEATHER
        val span = FEATHER * 2f
        for (i in 0 until count) {
            val x = i % width
            val y = i / width
            val t = ((confidence(mask, maskWidth, maskHeight, x, y, width, height) - low) / span).coerceIn(0f, 1f)
            out[i] =
                when {
                    t <= 0f -> background[i]
                    t >= 1f -> person[i]
                    else -> mix(person[i], background[i], t * t * (3f - 2f * t))
                }
        }
    }

    private fun extrema(
        mask: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
        peak: Boolean,
    ): FloatArray {
        val count = width * height
        if (radius <= 0 || width <= 0 || height <= 0 || mask.size < count) {
            return mask.copyOf()
        }
        val tmp = FloatArray(count)
        val out = FloatArray(count)
        for (y in 0 until height) {
            val row = y * width
            for (x in 0 until width) {
                var value = if (peak) 0f else 1f
                val x0 = (x - radius).coerceAtLeast(0)
                val x1 = (x + radius).coerceAtMost(width - 1)
                for (xx in x0..x1) {
                    val sample = mask[row + xx]
                    value = if (peak) maxOf(value, sample) else minOf(value, sample)
                }
                tmp[row + x] = value
            }
        }
        for (x in 0 until width) {
            for (y in 0 until height) {
                var value = if (peak) 0f else 1f
                val y0 = (y - radius).coerceAtLeast(0)
                val y1 = (y + radius).coerceAtMost(height - 1)
                for (yy in y0..y1) {
                    val sample = tmp[yy * width + x]
                    value = if (peak) maxOf(value, sample) else minOf(value, sample)
                }
                out[y * width + x] = value
            }
        }
        return out
    }

    private fun blur(
        mask: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ): FloatArray {
        val count = width * height
        if (radius <= 0 || width <= 0 || height <= 0 || mask.size < count) {
            return mask.copyOf()
        }
        val tmp = FloatArray(count)
        val out = FloatArray(count)
        for (y in 0 until height) {
            val row = y * width
            for (x in 0 until width) {
                var sum = 0f
                val x0 = (x - radius).coerceAtLeast(0)
                val x1 = (x + radius).coerceAtMost(width - 1)
                for (xx in x0..x1) {
                    sum += mask[row + xx]
                }
                tmp[row + x] = sum / (x1 - x0 + 1)
            }
        }
        for (x in 0 until width) {
            for (y in 0 until height) {
                var sum = 0f
                val y0 = (y - radius).coerceAtLeast(0)
                val y1 = (y + radius).coerceAtMost(height - 1)
                for (yy in y0..y1) {
                    sum += tmp[yy * width + x]
                }
                out[y * width + x] = sum / (y1 - y0 + 1)
            }
        }
        return out
    }

    private fun sample(
        mask: FloatArray,
        width: Int,
        height: Int,
        x: Int,
        y: Int,
    ): Float {
        val sx = x.coerceIn(0, width - 1)
        val sy = y.coerceIn(0, height - 1)
        val index = sy * width + sx
        if (index !in mask.indices) {
            return 0f
        }
        return mask[index]
    }

    private fun mix(
        person: Int,
        background: Int,
        t: Float,
    ): Int {
        val a = ((background ushr 24) and 0xFF) + ((((person ushr 24) and 0xFF) - ((background ushr 24) and 0xFF)) * t).toInt()
        val r = ((background ushr 16) and 0xFF) + ((((person ushr 16) and 0xFF) - ((background ushr 16) and 0xFF)) * t).toInt()
        val g = ((background ushr 8) and 0xFF) + ((((person ushr 8) and 0xFF) - ((background ushr 8) and 0xFF)) * t).toInt()
        val b = (background and 0xFF) + (((person and 0xFF) - (background and 0xFF)) * t).toInt()
        return (a shl 24) or (r shl 16) or (g shl 8) or b
    }
}

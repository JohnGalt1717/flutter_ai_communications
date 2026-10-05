package com.johngalt.flutter_ai_communications

/** Cheap wide blur via two bilinear downscales. Matches iOS sigma ~20 at intensity 50. */
internal object DownscaleBlur {
    fun scale(intensity: Int): Float {
        val clamped = intensity.coerceIn(0, 100)
        return (0.10f - clamped / 100f * 0.06f).coerceIn(0.04f, 0.10f)
    }

    fun tinyScale(intensity: Int): Float {
        val clamped = intensity.coerceIn(0, 100)
        return (0.45f - clamped / 100f * 0.20f).coerceIn(0.25f, 0.45f)
    }
}

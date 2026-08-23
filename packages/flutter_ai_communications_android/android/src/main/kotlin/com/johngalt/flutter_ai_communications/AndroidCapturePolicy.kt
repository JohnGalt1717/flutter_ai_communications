package com.johngalt.flutter_ai_communications

/** Capture-thread and Format-retry policy for the Android adapter. */
internal object AndroidCapturePolicy {
    /** HAL/read status that requires a verified alternative Native Format. */
    const val ERROR_UNSUPPORTED = -20

    /** AudioRecord.ERROR_DEAD_OBJECT. */
    const val ERROR_DEAD_OBJECT = -6

    const val DEFAULT_SAMPLE_RATE = 24_000

    val sampleRates: List<Int> = listOf(24_000, 48_000, 16_000, 32_000, 8_000)

    fun shouldRead(
        running: Boolean,
        generation: Int,
        threadGeneration: Int,
    ): Boolean = running && generation == threadGeneration

    fun isFatalRead(n: Int): Boolean = n == ERROR_UNSUPPORTED || n == ERROR_DEAD_OBJECT

    fun nextSampleRate(
        requested: Int,
        attempted: Set<Int>,
    ): Int? {
        val ordered = listOf(requested) + sampleRates.filter { it != requested }
        return ordered.firstOrNull { it !in attempted }
    }

    fun requestedSampleRate(raw: Any?, defaultRate: Int = DEFAULT_SAMPLE_RATE): Int {
        val map = raw as? Map<*, *> ?: return defaultRate
        val rate = (map["sampleRate"] as? Number)?.toInt() ?: return defaultRate
        return if (rate > 0) rate else defaultRate
    }

    fun formatMap(sampleRate: Int): Map<String, Any> =
        mapOf(
            "encoding" to "pcm16le",
            "sampleRate" to sampleRate,
            "channels" to 1,
        )

    fun isBuiltinCapture(selectedId: String?): Boolean =
        selectedId == "handset-in" || selectedId == "speaker-in"

    fun isSpeakerRender(selectedId: String?): Boolean =
        selectedId == "speaker-out" || selectedId == "speakerphone-out"

    fun observedId(
        selectedId: String?,
        physicalMatchesSelected: Boolean,
        physicalCatalogId: String?,
    ): String? = if (physicalMatchesSelected) selectedId else physicalCatalogId ?: selectedId
}

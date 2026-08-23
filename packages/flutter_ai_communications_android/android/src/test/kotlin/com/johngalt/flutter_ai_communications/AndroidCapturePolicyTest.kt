package com.johngalt.flutter_ai_communications

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AndroidCapturePolicyTest {
    @Test
    fun readLoopRequiresRunningBeforeEvaluatingFrames() {
        assertFalse(AndroidCapturePolicy.shouldRead(false, 1, 1))
        assertTrue(AndroidCapturePolicy.shouldRead(true, 1, 1))
    }

    @Test
    fun staleGenerationCannotReadAfterRestart() {
        assertFalse(AndroidCapturePolicy.shouldRead(true, generation = 2, threadGeneration = 1))
    }

    @Test
    fun unsupportedReadSelectsNextVerifiedRate() {
        assertTrue(AndroidCapturePolicy.isFatalRead(-20))
        assertEquals(
            48_000,
            AndroidCapturePolicy.nextSampleRate(24_000, setOf(24_000)),
        )
        assertNull(
            AndroidCapturePolicy.nextSampleRate(8_000, AndroidCapturePolicy.sampleRates.toSet()),
        )
    }

    @Test
    fun startMustEstablishRunningBeforeTheReadLoop() {
        val generation = 1
        assertFalse(AndroidCapturePolicy.shouldRead(false, generation, generation))
        assertTrue(AndroidCapturePolicy.shouldRead(true, generation, generation))
    }

    @Test
    fun requestedSampleRateReadsFormatMap() {
        assertEquals(
            16_000,
            AndroidCapturePolicy.requestedSampleRate(
                mapOf("encoding" to "pcm16le", "sampleRate" to 16_000, "channels" to 1),
            ),
        )
        assertEquals(24_000, AndroidCapturePolicy.requestedSampleRate(null))
    }

    @Test
    fun observedCaptureKeepsAppliedBuiltinWhenPhysicalMatches() {
        assertEquals(
            "speaker-in",
            AndroidCapturePolicy.observedId(
                selectedId = "speaker-in",
                physicalMatchesSelected = true,
                physicalCatalogId = "7",
            ),
        )
    }

    @Test
    fun observedCaptureReportsPhysicalIdWhenPairDiverges() {
        assertEquals(
            "handset-in",
            AndroidCapturePolicy.observedId(
                selectedId = "3",
                physicalMatchesSelected = false,
                physicalCatalogId = "handset-in",
            ),
        )
    }
}

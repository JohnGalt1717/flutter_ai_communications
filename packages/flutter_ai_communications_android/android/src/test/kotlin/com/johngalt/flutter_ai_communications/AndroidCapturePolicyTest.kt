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
    fun builtinCaptureDoesNotPinPreferredDevice() {
        assertFalse(AndroidCapturePolicy.shouldPinPreferredCapture("handset-in"))
        assertFalse(AndroidCapturePolicy.shouldPinPreferredCapture("speaker-in"))
        assertFalse(AndroidCapturePolicy.shouldPinPreferredCapture(null))
        assertTrue(AndroidCapturePolicy.shouldPinPreferredCapture("12"))
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

    @Test
    fun handsetApplyClearsStickySpeakerBeforeSelectingEarpiece() {
        val plan = AndroidCapturePolicy.planApplyRoute("handset-out")
        assertFalse(plan.speakerphoneOn)
        assertTrue(plan.clearCommunicationDevice)
        assertTrue(plan.preferEarpiece)
    }

    @Test
    fun speakerApplyKeepsCommunicationDeviceAndTurnsSpeakerphoneOn() {
        val plan = AndroidCapturePolicy.planApplyRoute("speaker-out")
        assertTrue(plan.speakerphoneOn)
        assertFalse(plan.clearCommunicationDevice)
        assertFalse(plan.preferEarpiece)
    }

    @Test
    fun observedRenderReportsSpeakerWhileSpeakerphoneFlagStaysOn() {
        assertEquals(
            "speaker-out",
            AndroidCapturePolicy.observedRenderId(
                selectedId = "handset-out",
                speakerphoneOn = true,
                physicalMatchesSelected = false,
                physicalCatalogId = "speaker-out",
            ),
        )
    }

    @Test
    fun tabletWithoutEarpieceDoesNotAdvertiseHandset() {
        assertFalse(AndroidCapturePolicy.shouldAdvertiseHandset(false))
        assertTrue(AndroidCapturePolicy.shouldAdvertiseHandset(true))
    }

    @Test
    fun observedRenderKeepsHandsetWhenSpeakerphoneClears() {
        assertEquals(
            "handset-out",
            AndroidCapturePolicy.observedRenderId(
                selectedId = "handset-out",
                speakerphoneOn = false,
                physicalMatchesSelected = true,
                physicalCatalogId = "7",
            ),
        )
    }
}

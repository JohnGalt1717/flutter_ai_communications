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
    fun rejectedRatesStayStructured() {
        assertEquals(
            listOf(
                mapOf(
                    "encoding" to "pcm16le",
                    "sampleRate" to 24_000,
                    "channels" to 1,
                    "reason" to "unsupported",
                ),
            ),
            AndroidCapturePolicy.failures(setOf(24_000, 48_000), 48_000),
        )
    }

    @Test
    fun captureOnlyDoesNotWantPlayback() {
        assertTrue(AndroidCapturePolicy.wantsCapture("handset-in", null))
        assertFalse(AndroidCapturePolicy.wantsPlayback("handset-in", null))
    }

    @Test
    fun playbackOnlyDoesNotWantCapture() {
        assertFalse(AndroidCapturePolicy.wantsCapture(null, "speaker-out"))
        assertTrue(AndroidCapturePolicy.wantsPlayback(null, "speaker-out"))
        assertFalse(AndroidCapturePolicy.wantsCapture("", "speaker-out"))
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
    fun telephonySubmixAndHdmiStayOutOfTheCatalog() {
        assertFalse(AndroidCapturePolicy.isSelectableInput(18))
        assertFalse(AndroidCapturePolicy.isSelectableOutput(18))
        assertFalse(AndroidCapturePolicy.isSelectableInput(25))
        assertFalse(AndroidCapturePolicy.isSelectableOutput(25))
        assertFalse(AndroidCapturePolicy.isSelectableInput(28))
        assertFalse(AndroidCapturePolicy.isSelectableOutput(9))
        assertFalse(AndroidCapturePolicy.isSelectableInput(19))
        assertFalse(AndroidCapturePolicy.isSelectableOutput(19))
    }

    @Test
    fun headsetBluetoothUsbAndCarStaySelectable() {
        assertTrue(AndroidCapturePolicy.isSelectableInput(7))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(8))
        assertTrue(AndroidCapturePolicy.isSelectableInput(3))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(4))
        assertTrue(AndroidCapturePolicy.isSelectableInput(11))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(11))
        assertTrue(AndroidCapturePolicy.isSelectableInput(22))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(22))
        assertTrue(AndroidCapturePolicy.isSelectableInput(26))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(21))
        assertTrue(AndroidCapturePolicy.isSelectableInput(15))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(2))
        assertTrue(AndroidCapturePolicy.isSelectableInput(23))
        assertTrue(AndroidCapturePolicy.isSelectableOutput(23))
        assertTrue(AndroidCapturePolicy.isBluetoothVoiceType(23))
        assertTrue(AndroidCapturePolicy.isSyntheticType(15))
        assertTrue(AndroidCapturePolicy.isSyntheticType(1))
        assertTrue(AndroidCapturePolicy.isSyntheticType(2))
        assertFalse(AndroidCapturePolicy.isSyntheticType(22))
    }

    @Test
    fun phoneModelUsbRowsStayOutOfTheCatalog() {
        assertTrue(AndroidCapturePolicy.isSelfNamedUsb(11, "SM-A176U1", "SM-A176U1"))
        assertTrue(AndroidCapturePolicy.isSelfNamedUsb(22, "SM A176U1", "SM-A176U1"))
        assertFalse(AndroidCapturePolicy.isSelfNamedUsb(11, "USB-C Headset", "SM-A176U1"))
        assertFalse(AndroidCapturePolicy.isSelfNamedUsb(3, "SM-A176U1", "SM-A176U1"))
    }

    @Test
    fun a2dpTwinDropsWhenScoExists() {
        assertFalse(
            AndroidCapturePolicy.keepBluetoothOutput(8, "aa:bb", setOf("aa:bb")),
        )
        assertTrue(
            AndroidCapturePolicy.keepBluetoothOutput(8, "aa:bb", setOf("cc:dd")),
        )
        assertTrue(
            AndroidCapturePolicy.keepBluetoothOutput(7, "aa:bb", setOf("aa:bb")),
        )
    }

    @Test
    fun builtinCommunicationMarksSpeakerphoneOsDefault() {
        assertEquals("speakerphone", AndroidCapturePolicy.syntheticOsDefault(null))
        assertEquals("speakerphone", AndroidCapturePolicy.syntheticOsDefault(1))
        assertEquals("speakerphone", AndroidCapturePolicy.syntheticOsDefault(2))
        assertEquals("speakerphone", AndroidCapturePolicy.syntheticOsDefault(18))
    }

    @Test
    fun headsetCommunicationLeavesSyntheticOsDefaultUnset() {
        assertNull(AndroidCapturePolicy.syntheticOsDefault(7))
        assertNull(AndroidCapturePolicy.syntheticOsDefault(22))
        assertNull(AndroidCapturePolicy.syntheticOsDefault(3))
        assertNull(AndroidCapturePolicy.syntheticOsDefault(21))
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

package com.johngalt.flutter_ai_communications_webrtc

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FailClosedTest {
    @Test
    fun onlyAProcessedFrameWhileAppliedIsSent() {
        val input = Any()
        val processed = Any()
        assertEquals(processed, sendable(input, processed, ready = true))
        // No mask or mode fell to none: the input comes back. Send black.
        assertNull(sendable(input, input, ready = true))
        // Gave up or closed while this frame was processing.
        assertNull(sendable(input, processed, ready = false))
    }

    @Test
    fun processorOnTheCameraPathIsConfirmedOnTheFirstFrame() {
        val watch = BypassWatch()
        assertEquals(BypassWatch.Verdict.OnPath, watch.onDelivered(processed = 1))
    }

    @Test
    fun aFrameAlreadyPastTheProcessorIsNotABypass() {
        val watch = BypassWatch()
        assertEquals(BypassWatch.Verdict.Pending, watch.onDelivered(processed = 0))
        assertEquals(BypassWatch.Verdict.OnPath, watch.onDelivered(processed = 1))
    }

    @Test
    fun aProcessorThatNeverSeesAFrameIsBypassed() {
        // Shared camera track or a replaced registry entry: raw frames flow.
        val watch = BypassWatch()
        repeat(BypassWatch.LIMIT - 1) {
            assertEquals(BypassWatch.Verdict.Pending, watch.onDelivered(processed = 0))
        }
        assertEquals(BypassWatch.Verdict.Bypassed, watch.onDelivered(processed = 0))
    }

    @Test
    fun theVerdictIsReportedOnce() {
        val watch = BypassWatch()
        repeat(BypassWatch.LIMIT) { watch.onDelivered(processed = 0) }
        assertEquals(BypassWatch.Verdict.Pending, watch.onDelivered(processed = 0))
        assertEquals(BypassWatch.Verdict.Pending, watch.onDelivered(processed = 9))
    }

    @Test
    fun sizeOrRotationChangeDropsTheMask() {
        val shape = FrameShape()
        assertTrue(shape.changed(720, 1280, 270))
        assertFalse(shape.changed(720, 1280, 270))
        // Front to back camera: same upright size, other rotation.
        assertTrue(shape.changed(720, 1280, 90))
        assertTrue(shape.changed(480, 640, 90))
        assertFalse(shape.changed(480, 640, 90))
    }
}

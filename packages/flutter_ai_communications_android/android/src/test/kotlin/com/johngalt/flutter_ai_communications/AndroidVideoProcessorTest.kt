package com.johngalt.flutter_ai_communications

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AndroidVideoProcessorTest {
    @Test
    fun floatMaskKeepsPersonPixelsAboveThreshold() {
        val width = 4
        val height = 2
        val person = IntArray(width * height) { 0xFFFF0000.toInt() }
        val background = IntArray(width * height) { 0xFF0000FF.toInt() }
        val mask =
            AndroidVideoMask.floatMask(width, height) { x, _ ->
                if (x < width / 2) 0.9f else 0.1f
            }
        val out =
            AndroidVideoMask.compositePixels(
                personPixels = person,
                backgroundPixels = background,
                width = width,
                height = height,
                mask = mask,
                maskWidth = width,
                maskHeight = height,
            )
        assertEquals(0xFFFF0000.toInt(), out[0])
        assertEquals(0xFFFF0000.toInt(), out[1])
        assertEquals(0xFF0000FF.toInt(), out[2])
        assertEquals(0xFF0000FF.toInt(), out[3])
    }

    @Test
    fun byteStyleMaskReadWouldDropPersonConfidence() {
        // Documents the #86 bug: reading floats as unsigned bytes never sees
        // person confidence in (0, 1], so the person never composites.
        val width = 2
        val height = 1
        val mask = AndroidVideoMask.floatMask(width, height) { _, _ -> 0.75f }
        mask.rewind()
        var personHits = 0
        val count = width * height
        for (i in 0 until count) {
            val alpha = mask.get().toInt() and 0xFF
            if (alpha > 128) {
                personHits++
            }
        }
        assertEquals(0, personHits)
    }

    @Test
    fun floatMaskScalesWhenMaskResolutionDiffers() {
        val width = 4
        val height = 4
        val person = IntArray(width * height) { 0xFF00FF00.toInt() }
        val background = IntArray(width * height) { 0xFF000000.toInt() }
        val mask =
            AndroidVideoMask.floatMask(2, 2) { x, y ->
                if (x == 0 && y == 0) 1f else 0f
            }
        val out =
            AndroidVideoMask.compositePixels(
                personPixels = person,
                backgroundPixels = background,
                width = width,
                height = height,
                mask = mask,
                maskWidth = 2,
                maskHeight = 2,
            )
        assertEquals(0xFF00FF00.toInt(), out[0])
        assertEquals(0xFF000000.toInt(), out[width * height - 1])
    }

    @Test
    fun applyReplaceRejectsEmptyBytes() {
        val processor = AndroidVideoProcessor()
        if (!processor.available) {
            // JVM unit tests may lack Play Services; skip apply path.
            return
        }
        assertEquals("invalid", processor.apply(mapOf("kind" to "replace")))
    }

    @Test
    fun applyBlurRejectsOutOfRangeIntensity() {
        val processor = AndroidVideoProcessor()
        if (!processor.available) {
            return
        }
        assertEquals(
            "invalid",
            processor.apply(mapOf("kind" to "blur", "intensity" to 150)),
        )
    }

    @Test
    fun applyNoneClearsMode() {
        val processor = AndroidVideoProcessor()
        assertEquals("ready", processor.apply(mapOf("kind" to "none")))
        assertTrue(processor.mode is AndroidVideoProcessor.Mode.None)
    }
}

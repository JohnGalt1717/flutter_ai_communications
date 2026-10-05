package com.johngalt.flutter_ai_communications

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PersonMaskTest {
    @Test
    fun floatMaskIsSampledByFrameCoordinatesNotByteOrder() {
        val mask =
            floatArrayOf(
                1f, 0f,
                1f, 0f,
            )
        assertTrue(PersonMask.confidence(mask, 2, 2, 0, 0, 4, 4) > 0.9f)
        assertTrue(PersonMask.confidence(mask, 2, 2, 1, 3, 4, 4) > 0.5f)
        assertTrue(PersonMask.confidence(mask, 2, 2, 3, 0, 4, 4) < 0.5f)
        assertTrue(PersonMask.confidence(mask, 2, 2, 3, 3, 4, 4) < 0.5f)
    }

    @Test
    fun compositeKeepsPersonWhereConfidenceIsHigh() {
        val person = IntArray(16) { 0xFF00FF00.toInt() }
        val background = IntArray(16) { 0xFFFF0000.toInt() }
        val out = IntArray(16)
        val mask =
            floatArrayOf(
                1f, 0f,
                0.6f, 0.1f,
            )
        PersonMask.composite(person, background, mask, 2, 2, 4, 4, out)
        assertEquals(0xFF00FF00.toInt(), out[0])
        assertEquals(0xFFFF0000.toInt(), out[3])
        assertEquals(0xFF00FF00.toInt(), out[4])
        assertEquals(0xFFFF0000.toInt(), out[15])
    }

    @Test
    fun lowConfidenceStaysBackground() {
        assertTrue(PersonMask.confidence(floatArrayOf(0.15f), 1, 1, 0, 0, 1, 1) < PersonMask.PERSON_THRESHOLD - PersonMask.FEATHER)
    }

    @Test
    fun expandSpreadsPersonIntoNeighborCells() {
        val mask =
            floatArrayOf(
                0f, 0f, 0f,
                0f, 1f, 0f,
                0f, 0f, 0f,
            )
        val expanded = PersonMask.expand(mask, 3, 3, 1)
        assertEquals(1f, expanded[0])
        assertEquals(1f, expanded[1])
        assertEquals(1f, expanded[3])
        assertEquals(1f, expanded[4])
        assertEquals(1f, expanded[8])
    }

    @Test
    fun expandDoesNotFillFarBackground() {
        val mask =
            floatArrayOf(
                1f, 0f, 0f,
                0f, 0f, 0f,
                0f, 0f, 0f,
            )
        val expanded = PersonMask.expand(mask, 3, 3, 1)
        assertEquals(1f, expanded[0])
        assertEquals(1f, expanded[1])
        assertEquals(1f, expanded[3])
        assertEquals(0f, expanded[8])
    }

    @Test
    fun erodeRemovesAOnePixelIsland() {
        val mask =
            floatArrayOf(
                0f, 0f, 0f,
                0f, 1f, 0f,
                0f, 0f, 0f,
            )
        val eroded = PersonMask.erode(mask, 3, 3, 1)
        assertEquals(0f, eroded[4])
    }

    @Test
    fun prepareDoesNotPaintAWidePersonFrame() {
        val width = 9
        val height = 9
        val mask = FloatArray(width * height)
        for (y in 3..5) {
            for (x in 3..5) {
                mask[y * width + x] = 1f
            }
        }
        val prepared = PersonMask.prepare(mask, width, height)
        assertTrue(prepared[4 * width + 4] > 0.7f)
        assertTrue(prepared[0] < 0.2f)
        assertTrue(prepared[width - 1] < 0.2f)
        assertTrue(prepared[(height - 1) * width] < 0.2f)
    }

    @Test
    fun compositeFeathersMidConfidence() {
        val person = IntArray(1) { 0xFF00FF00.toInt() }
        val background = IntArray(1) { 0xFFFF0000.toInt() }
        val out = IntArray(1)
        PersonMask.composite(person, background, floatArrayOf(0.4f), 1, 1, 1, 1, out)
        val red = (out[0] shr 16) and 0xFF
        val green = (out[0] shr 8) and 0xFF
        assertTrue(red in 1..254)
        assertTrue(green in 1..254)
    }

    @Test
    fun downscaleBlurAtFiftyIsVisibleOnAPhoneTile() {
        val scale = DownscaleBlur.scale(50)
        val tiny = DownscaleBlur.tinyScale(50)
        assertTrue(scale <= 0.08f)
        assertTrue(tiny <= 0.40f)
        assertTrue(scale * tiny <= 0.03f)
    }

    @Test
    fun downscaleBlurAtOneHundredIsStrongerThanFifty() {
        assertTrue(DownscaleBlur.scale(100) < DownscaleBlur.scale(50))
        assertTrue(DownscaleBlur.tinyScale(100) < DownscaleBlur.tinyScale(50))
    }
}

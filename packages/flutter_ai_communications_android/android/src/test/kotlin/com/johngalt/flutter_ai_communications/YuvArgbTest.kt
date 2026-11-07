package com.johngalt.flutter_ai_communications

import java.nio.ByteBuffer
import kotlin.test.Test
import kotlin.test.assertEquals

class YuvArgbTest {
    private fun argb(
        r: Int,
        g: Int,
        b: Int,
    ) = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    @Test
    fun grayLumaKeepsNeutralChroma() {
        val out = IntArray(4)
        YuvArgb.convert(
            ByteBuffer.wrap(byteArrayOf(16, 128.toByte(), 235.toByte(), 0)),
            2,
            1,
            ByteBuffer.wrap(byteArrayOf(128.toByte())),
            1,
            1,
            ByteBuffer.wrap(byteArrayOf(128.toByte())),
            1,
            1,
            2,
            2,
            out,
        )
        assertEquals(listOf(argb(16, 16, 16), argb(128, 128, 128), argb(235, 235, 235), argb(0, 0, 0)), out.toList())
    }

    @Test
    fun chromaShiftsRedAndBlueAndClamps() {
        val out = IntArray(2)
        // One 2x1 row: V high pushes red; U high pushes blue past 255.
        YuvArgb.convert(
            ByteBuffer.wrap(byteArrayOf(128.toByte(), 128.toByte())),
            2,
            1,
            ByteBuffer.wrap(byteArrayOf(255.toByte())),
            1,
            1,
            ByteBuffer.wrap(byteArrayOf(255.toByte())),
            1,
            1,
            2,
            1,
            out,
        )
        // r = 128 + (351*127 >> 8) = 302 -> 255; g = 128 - ((179*127 + 86*127) >> 8) = -3 -> 0; b -> 255.
        assertEquals(argb(255, 0, 255), out[0])
        assertEquals(out[0], out[1])
    }

    @Test
    fun rowPaddingAndInterleavedChromaAreSkipped() {
        val out = IntArray(4)
        // Y rows padded to stride 3; U/V interleaved (pixel stride 2) like NV21 planes.
        val y = ByteBuffer.wrap(byteArrayOf(50, 60, 99, 70, 80, 99))
        val uv = ByteBuffer.wrap(byteArrayOf(128.toByte(), 7, 128.toByte(), 7))
        YuvArgb.convert(y, 3, 1, uv, 4, 2, uv, 4, 2, 2, 2, out)
        assertEquals(listOf(argb(50, 50, 50), argb(60, 60, 60), argb(70, 70, 70), argb(80, 80, 80)), out.toList())
    }
}

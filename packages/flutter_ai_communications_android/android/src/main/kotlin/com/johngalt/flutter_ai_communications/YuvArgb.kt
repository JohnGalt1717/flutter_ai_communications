package com.johngalt.flutter_ai_communications

import java.nio.ByteBuffer

/**
 * BT.601 YUV 4:2:0 to ARGB_8888 with integer math. The camera graph reads
 * Camera2 planes (pixel stride 1 or 2); the WebRTC Transport plugin reads
 * flutter_webrtc I420 planes (pixel stride 1).
 */
object YuvArgb {
    fun convert(
        y: ByteBuffer,
        yRowStride: Int,
        yPixelStride: Int,
        u: ByteBuffer,
        uRowStride: Int,
        uPixelStride: Int,
        v: ByteBuffer,
        vRowStride: Int,
        vPixelStride: Int,
        width: Int,
        height: Int,
        out: IntArray,
    ) {
        for (row in 0 until height) {
            val yRow = row * yRowStride
            val uRow = (row / 2) * uRowStride
            val vRow = (row / 2) * vRowStride
            val outRow = row * width
            for (col in 0 until width) {
                val luma = y.get(yRow + col * yPixelStride).toInt() and 0xFF
                val d = (u.get(uRow + (col / 2) * uPixelStride).toInt() and 0xFF) - 128
                val e = (v.get(vRow + (col / 2) * vPixelStride).toInt() and 0xFF) - 128
                val r = (luma + ((351 * e) shr 8)).coerceIn(0, 255)
                val g = (luma - ((179 * e + 86 * d) shr 8)).coerceIn(0, 255)
                val b = (luma + ((443 * d) shr 8)).coerceIn(0, 255)
                out[outRow + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }
}

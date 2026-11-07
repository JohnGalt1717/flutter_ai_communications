package com.johngalt.flutter_ai_communications_webrtc

/**
 * The processor's output may leave only while blur/replace is still applied
 * and it is not the input handed back (no mask, mode fell to none). Null
 * means send black.
 */
internal fun <T : Any> sendable(
    input: T,
    result: T,
    ready: Boolean,
): T? = if (ready && result !== input) result else null

/** Upright size plus rotation of the last frame; a change drops the mask. */
internal class FrameShape {
    private var width = -1
    private var height = -1
    private var rotation = -1

    fun changed(
        width: Int,
        height: Int,
        rotation: Int,
    ): Boolean {
        if (width == this.width && height == this.height && rotation == this.rotation) {
            return false
        }
        this.width = width
        this.height = height
        this.rotation = rotation
        return true
    }
}

/**
 * First-frame watchdog. flutter_webrtc runs only the processor of the
 * `LocalVideoTrack` that is its camera source's `VideoProcessor`. A registry
 * entry that is not (a shared camera track from `buildSharedVideoTrack`, or
 * an entry `mediaStreamGetTracks` replaced) takes the processor and never
 * runs it, while the raw camera still reaches the sender.
 *
 * Feed it each frame the track delivers with the processor's frame count.
 * Frames the track delivers run through the source processor first, so a
 * processor on the path has counted at least one by then. [LIMIT] frames
 * without one means it is bypassed. The margin covers a frame that was
 * already past the processor when it was added.
 */
internal class BypassWatch {
    enum class Verdict { Pending, OnPath, Bypassed }

    private var delivered = 0
    private var verdict = Verdict.Pending

    /** Returns a final verdict once, then [Verdict.Pending] for every later frame. */
    @Synchronized
    fun onDelivered(processed: Long): Verdict {
        if (verdict != Verdict.Pending) {
            return Verdict.Pending
        }
        delivered += 1
        verdict =
            when {
                processed > 0 -> Verdict.OnPath
                delivered >= LIMIT -> Verdict.Bypassed
                else -> Verdict.Pending
            }
        return verdict
    }

    companion object {
        const val LIMIT = 5
    }
}

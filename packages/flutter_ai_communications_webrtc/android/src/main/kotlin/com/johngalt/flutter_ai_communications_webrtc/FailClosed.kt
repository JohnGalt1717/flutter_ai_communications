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

/**
 * Replies to `process` for one attached processor. "ready" goes out only
 * once [BypassWatch] saw the processor on the camera path. Calls that come
 * while the verdict is pending wait for it; [timeout] answers them
 * "unavailable" (the host keeps the track disabled) while the watch goes on.
 */
internal class AppliedGate {
    private val waiting = mutableListOf<(String) -> Unit>()
    private var verdict = BypassWatch.Verdict.Pending

    /** [status] is what `apply` returned for this call. */
    fun request(
        status: String,
        reply: (String) -> Unit,
    ) {
        when {
            status != "ready" -> reply(status)
            verdict == BypassWatch.Verdict.OnPath -> reply("ready")
            verdict == BypassWatch.Verdict.Bypassed -> reply("unavailable")
            else -> waiting += reply
        }
    }

    fun timeout() = flush("unavailable")

    /** Records the watch verdict and answers every waiting call. */
    fun resolve(verdict: BypassWatch.Verdict) {
        if (verdict == BypassWatch.Verdict.Pending || this.verdict != BypassWatch.Verdict.Pending) {
            return
        }
        this.verdict = verdict
        flush(if (verdict == BypassWatch.Verdict.OnPath) "ready" else "unavailable")
    }

    /** The processor was removed (none, or the track went away). */
    fun detached() = flush("unavailable")

    private fun flush(status: String) {
        val replies = waiting.toList()
        waiting.clear()
        replies.forEach { it(status) }
    }
}

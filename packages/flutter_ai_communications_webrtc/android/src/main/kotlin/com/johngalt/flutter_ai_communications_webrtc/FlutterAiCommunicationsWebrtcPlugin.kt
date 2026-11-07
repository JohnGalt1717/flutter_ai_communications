package com.johngalt.flutter_ai_communications_webrtc

import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.VideoSink
import org.webrtc.VideoTrack

/**
 * Runs a FAC Video processor on a host flutter_webrtc local video track, in
 * place (ADR-0032). The host keeps its PeerConnection, sender, and camera.
 * All state is touched on the main thread.
 */
class FlutterAiCommunicationsWebrtcPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {
    /** The processor and the registry entry it was added to. */
    private class Attached(
        val track: LocalVideoTrack,
        val processor: TrackProcessor,
    ) {
        var probe: VideoSink? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val attached = HashMap<String, Attached>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel =
            MethodChannel(binding.binaryMessenger, "flutter_ai_communications_webrtc").also {
                it.setMethodCallHandler(this)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        attached.values.forEach(::detach)
        attached.clear()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != "process") {
            result.notImplemented()
            return
        }
        val trackId = call.argument<String>("trackId")
        val args = call.argument<Map<String, Any?>>("processor") ?: emptyMap()
        process(trackId, args, result::success)
    }

    private fun process(
        trackId: String?,
        args: Map<String, Any?>,
        reply: (String) -> Unit,
    ) {
        attached.keys.filter { localTrack(it) == null }.forEach { id ->
            attached.remove(id)?.let(::detach)
        }
        val track = trackId?.let(::localTrack) ?: return reply("noTrack")
        if ((args["kind"] as? String ?: "none") == "none") {
            attached.remove(trackId)?.let(::detach)
            return reply("ready")
        }
        attached[trackId]?.let { return reply(it.processor.apply(args)) }
        val entry = Attached(track, TrackProcessor { main.post { gaveUp(trackId) } })
        track.addProcessor(entry.processor)
        attached[trackId] = entry
        val status = entry.processor.apply(args)
        if (status != "ready") {
            attached.remove(trackId)
            detach(entry)
            return reply(status)
        }
        watch(trackId, entry, reply)
    }

    /**
     * Answers once the track's first frames show whether the processor is on
     * the camera path ([BypassWatch]). A track that is not delivering frames
     * yet sends nothing raw: answer after [FIRST_FRAME_TIMEOUT_MS] and keep
     * watching. A later bypass disables the track and reports it.
     */
    private fun watch(
        trackId: String,
        entry: Attached,
        reply: (String) -> Unit,
    ) {
        val video = entry.track.track as? VideoTrack
        if (video == null) {
            attached.remove(trackId)
            detach(entry)
            return reply("unavailable")
        }
        var answered = false
        // True when this call answered; false when an earlier one already had.
        val answer = { status: String ->
            val first = !answered
            if (first) {
                answered = true
                reply(status)
            }
            first
        }
        val watch = BypassWatch()
        val probe =
            VideoSink {
                when (watch.onDelivered(entry.processor.frames)) {
                    BypassWatch.Verdict.Pending -> {}
                    BypassWatch.Verdict.OnPath -> main.post {
                        endProbe(entry)
                        answer(if (attached[trackId] === entry) "ready" else "unavailable")
                    }
                    BypassWatch.Verdict.Bypassed -> main.post { bypassed(trackId, entry, answer) }
                }
            }
        entry.probe = probe
        video.addSink(probe)
        main.postDelayed(
            { answer(if (attached[trackId] === entry) "ready" else "unavailable") },
            FIRST_FRAME_TIMEOUT_MS,
        )
    }

    private fun bypassed(
        trackId: String,
        entry: Attached,
        answer: (String) -> Boolean,
    ) {
        val current = attached[trackId] === entry
        if (current) {
            attached.remove(trackId)
        }
        detach(entry)
        if (answer("unavailable") || !current) {
            return
        }
        // Applied was already returned: fail closed here, then tell the host.
        runCatching { entry.track.setEnabled(false) }
        notifyUnavailable(trackId)
    }

    /** Segmentation gave up mid-call; the track already sends black. */
    private fun gaveUp(trackId: String) {
        if (attached.containsKey(trackId)) {
            notifyUnavailable(trackId)
        }
    }

    /** Dart `webrtcTrackProcessingUnavailable`. */
    private fun notifyUnavailable(trackId: String) {
        channel?.invokeMethod("unavailable", mapOf("trackId" to trackId))
    }

    private fun endProbe(entry: Attached) {
        val probe = entry.probe ?: return
        entry.probe = null
        // The track may already be disposed by the host.
        runCatching { (entry.track.track as? VideoTrack)?.removeSink(probe) }
    }

    private fun detach(entry: Attached) {
        endProbe(entry)
        entry.track.removeProcessor(entry.processor)
        entry.processor.close()
    }

    private fun localTrack(trackId: String): LocalVideoTrack? =
        FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack

    private companion object {
        const val FIRST_FRAME_TIMEOUT_MS = 2000L
    }
}

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
        val gate = AppliedGate()
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
        attached[trackId]?.let { return request(it, it.processor.apply(args), reply) }
        val entry = Attached(track, TrackProcessor { main.post { gaveUp(trackId) } })
        val video = track.track as? VideoTrack
        val status = if (video == null) "unavailable" else entry.processor.apply(args)
        if (status != "ready") {
            entry.processor.close()
            return reply(status)
        }
        track.addProcessor(entry.processor)
        attached[trackId] = entry
        val watch = BypassWatch()
        val probe =
            VideoSink {
                val verdict = watch.onDelivered(entry.processor.frames)
                if (verdict != BypassWatch.Verdict.Pending) {
                    main.post { onVerdict(trackId, entry, verdict) }
                }
            }
        entry.probe = probe
        video?.addSink(probe)
        request(entry, status, reply)
    }

    /**
     * "ready" only once the track's first frames show the processor is on the
     * camera path ([BypassWatch]). Until then a call waits; after
     * [FIRST_FRAME_TIMEOUT_MS] it gets "unavailable" and the watch goes on.
     */
    private fun request(
        entry: Attached,
        status: String,
        reply: (String) -> Unit,
    ) {
        entry.gate.request(status, reply)
        main.postDelayed(entry.gate::timeout, FIRST_FRAME_TIMEOUT_MS)
    }

    private fun onVerdict(
        trackId: String,
        entry: Attached,
        verdict: BypassWatch.Verdict,
    ) {
        endProbe(entry)
        entry.gate.resolve(verdict)
        if (verdict != BypassWatch.Verdict.Bypassed || attached[trackId] !== entry) {
            return
        }
        // The raw camera reaches the sender: fail closed here, then tell the
        // host, which keeps or disposes the track.
        attached.remove(trackId)
        detach(entry)
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
        entry.gate.detached()
    }

    private fun localTrack(trackId: String): LocalVideoTrack? =
        FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack

    private companion object {
        const val FIRST_FRAME_TIMEOUT_MS = 2000L
    }
}

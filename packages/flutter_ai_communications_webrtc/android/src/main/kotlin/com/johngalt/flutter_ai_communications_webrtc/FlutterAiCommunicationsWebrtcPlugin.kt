package com.johngalt.flutter_ai_communications_webrtc

import android.os.Handler
import android.os.Looper
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Runs a FAC Video processor on a host flutter_webrtc local video track, in
 * place (ADR-0032). The host keeps its PeerConnection, sender, and camera.
 */
class FlutterAiCommunicationsWebrtcPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private val processors = HashMap<String, TrackProcessor>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel =
            MethodChannel(binding.binaryMessenger, "flutter_ai_communications_webrtc").also {
                it.setMethodCallHandler(this)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        synchronized(processors) {
            for ((trackId, processor) in processors) {
                localTrack(trackId)?.removeProcessor(processor)
                processor.close()
            }
            processors.clear()
        }
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
        result.success(process(trackId, args))
    }

    private fun process(
        trackId: String?,
        args: Map<String, Any?>,
    ): String {
        synchronized(processors) {
            processors.keys.filter { localTrack(it) == null }.forEach { id ->
                processors.remove(id)?.close()
            }
            val track = trackId?.let(::localTrack) ?: return "noTrack"
            if ((args["kind"] as? String ?: "none") == "none") {
                processors.remove(trackId)?.let {
                    track.removeProcessor(it)
                    it.close()
                }
                return "ready"
            }
            val processor =
                processors.getOrPut(trackId) {
                    TrackProcessor { unavailable(trackId) }.also { track.addProcessor(it) }
                }
            return processor.apply(args)
        }
    }

    /** Dart `webrtcTrackProcessingUnavailable`: this track now sends black. */
    private fun unavailable(trackId: String) {
        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("unavailable", mapOf("trackId" to trackId))
        }
    }

    private fun localTrack(trackId: String): LocalVideoTrack? =
        FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack
}

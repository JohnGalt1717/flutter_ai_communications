import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Outcome of [processWebrtcVideoTrack].
enum WebrtcTrackProcessing {
  /// The Video processor runs on every frame of the track (none: pass-through).
  applied,

  /// The processor cannot run here. The track must not carry raw video:
  /// native platforms already send black frames; the host disables the track.
  unavailable,

  /// No flutter_webrtc local video track has that id.
  noTrack,
}

/// Method channel shared with the Android, iOS, and macOS plugin classes.
@visibleForTesting
const webrtcTrackProcessingChannel = MethodChannel(
  'flutter_ai_communications_webrtc',
);

/// Runs [processor] on the host's flutter_webrtc local camera track [trackId]
/// (`MediaStreamTrack.id`), in place. Same track, same sender: no
/// replaceTrack and no renegotiation. [NoneVideoProcessor] removes it.
///
/// Fails closed: when blur or replace cannot run, the track sends black
/// frames, never the raw camera, and this returns
/// [WebrtcTrackProcessing.unavailable].
Future<WebrtcTrackProcessing> processWebrtcVideoTrack(
  String trackId,
  VideoProcessor processor,
) async {
  final none = processor is NoneVideoProcessor;
  try {
    final status = await webrtcTrackProcessingChannel.invokeMethod<String>(
      'process',
      {'trackId': trackId, 'processor': videoProcessorToMap(processor)},
    );
    return switch (status) {
      'ready' => WebrtcTrackProcessing.applied,
      'noTrack' => WebrtcTrackProcessing.noTrack,
      _ => WebrtcTrackProcessing.unavailable,
    };
  } on MissingPluginException {
    // Web, Windows, Linux: no native bridge. Pass-through needs none.
    return none
        ? WebrtcTrackProcessing.applied
        : WebrtcTrackProcessing.unavailable;
  } on PlatformException {
    return WebrtcTrackProcessing.unavailable;
  }
}

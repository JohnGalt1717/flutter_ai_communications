import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_communications/flutter_ai_communications.dart';

/// Outcome of [processWebrtcVideoTrack].
enum WebrtcTrackProcessing {
  /// The Video processor runs on every frame of the track (none: pass-through).
  applied,

  /// The processor cannot run on this track. The host keeps the track
  /// disabled (`enabled = false`): it must not carry raw video. Where the
  /// processor did attach, the track already sends black frames.
  unavailable,

  /// No flutter_webrtc local video track has that id.
  noTrack,
}

/// Method channel shared with the Android, iOS, and macOS plugin classes.
@visibleForTesting
const webrtcTrackProcessingChannel = MethodChannel(
  'flutter_ai_communications_webrtc',
);

final StreamController<String> _unavailable = StreamController.broadcast(
  onListen: () =>
      webrtcTrackProcessingChannel.setMethodCallHandler((call) async {
        if (call.method == 'unavailable') {
          final trackId = (call.arguments as Map?)?['trackId'];
          if (trackId is String) {
            _unavailable.add(trackId);
          }
        }
      }),
);

/// Android only: track ids whose processor stopped after
/// [processWebrtcVideoTrack] returned [WebrtcTrackProcessing.applied].
/// Either segmentation failed 5 times in a row (the track sends black
/// frames), or the first frames showed the processor is not on the camera
/// path (flutter_webrtc gave the host a shared or re-wrapped track); the
/// plugin then disables the track. Either way no raw frame is sent; apply a
/// processor again, or treat the video as paused. iOS and macOS never emit:
/// a frame without a mask is black or the last processed frame. Broadcast;
/// the channel handler is installed on first listen.
Stream<String> get webrtcTrackProcessingUnavailable => _unavailable.stream;

/// Runs [processor] on the host's flutter_webrtc local camera track [trackId]
/// (`MediaStreamTrack.id`), in place. Same track, same sender: no
/// replaceTrack and no renegotiation. [NoneVideoProcessor] removes it.
/// A [ReplaceVideoProcessor] bundle asset is loaded to bytes first.
///
/// Keep a new track `enabled = false` until this returns
/// [WebrtcTrackProcessing.applied], before addTrack or replaceTrack, so no
/// raw frame goes out while it is applied. On Android the answer waits for
/// the track's first frames (up to 2 s) to prove the processor is on the
/// camera path.
///
/// Fails closed: when blur or replace cannot run this returns
/// [WebrtcTrackProcessing.unavailable] and the host keeps the track
/// disabled. While applied, frames are processed, the last processed frame,
/// or black; never the raw camera.
Future<WebrtcTrackProcessing> processWebrtcVideoTrack(
  String trackId,
  VideoProcessor processor,
) async {
  final none = processor is NoneVideoProcessor;
  final resolved = await resolveVideoProcessor(processor);
  if (resolved == null) {
    return WebrtcTrackProcessing.unavailable;
  }
  try {
    final status = await webrtcTrackProcessingChannel.invokeMethod<String>(
      'process',
      {'trackId': trackId, 'processor': videoProcessorToMap(resolved)},
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

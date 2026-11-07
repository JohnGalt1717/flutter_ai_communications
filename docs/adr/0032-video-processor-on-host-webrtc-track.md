# A Video processor can run on the host's flutter_webrtc camera track

Issue #113. ADR-0018 has the host addTrack a Send track on its own PeerConnection, but a Send track is a descriptor, not a flutter_webrtc `MediaStreamTrack`. Hosts therefore open their own camera with `getUserMedia`, and the remote peer never sees FAC's blur or replace.

The Transport plugin now runs the library's own Video processor on the host's flutter_webrtc local camera track, in place: `processWebrtcVideoTrack(trackId, processor)`. flutter_webrtc 1.6.x exposes a per-track processing hook on Android (`LocalVideoTrack.addProcessor`) and on iOS and macOS (`LocalVideoTrack addProcessing:`). The plugin's native code looks the track up in flutter_webrtc's track registry and hangs FAC's processor (`AndroidVideoProcessor`, `PersonBackgroundProcessor`) on that hook. Same track and sender, so blur toggles mid-call with no replaceTrack or renegotiation. The host keeps its camera, its device picks, and its PeerConnection. The host still does not inject a processor object; it passes the `VideoProcessor` value.

## Why not FAC frames into a new flutter_webrtc source

That was the first choice (closest to ADR-0013). It needs FAC to own the camera during the call, so the host's `getUserMedia` camera and OS-default device switching go away, and on iOS and Android a second capture session fights the first. It also needs a new native track type registered in flutter_webrtc plus a Dart `MediaStreamTrack` wrapper. The per-track hook already exists and needs none of that.

## Consequences

- This bends ADR-0013 for the camera on a WebRTC call: the capture is flutter_webrtc's, the processor is FAC's. The local Video surface and Camera preview still use the Production video path.
- Fail closed. While blur or replace is requested and cannot run (no native bridge, segmentation unavailable, a frame with no mask, a conversion error), the track carries black frames, never the raw camera, and the call returns `unavailable`. Web, Windows, and Linux have no bridge yet; the host disables the track. When an applied processor gives up mid-call (Android: 5 failed segmentations in a row), the track goes black and `webrtcTrackProcessingUnavailable` emits its id so the host can tell the user.
- Frames are turned upright before segmentation and leave with rotation 0.
- Android converts each frame I420 → ARGB → I420 on the capture thread. Expect a lower frame rate than pass-through.

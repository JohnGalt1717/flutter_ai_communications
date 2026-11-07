# A Video processor can run on the host's flutter_webrtc camera track

Issue #113. ADR-0018 has the host addTrack a Send track on its own PeerConnection, but a Send track is a descriptor, not a flutter_webrtc `MediaStreamTrack`. Hosts therefore open their own camera with `getUserMedia`, and the remote peer never sees FAC's blur or replace.

The Transport plugin now runs the library's own Video processor on the host's flutter_webrtc local camera track, in place: `processWebrtcVideoTrack(trackId, processor)`. flutter_webrtc 1.6.x exposes a per-track processing hook on Android (`LocalVideoTrack.addProcessor`) and on iOS and macOS (`LocalVideoTrack addProcessing:`). The plugin's native code looks the track up in flutter_webrtc's track registry and hangs FAC's processor (`AndroidVideoProcessor`, `PersonBackgroundProcessor`) on that hook. Same track and sender, so blur toggles mid-call with no replaceTrack or renegotiation. The host keeps its camera, its device picks, and its PeerConnection. The host still does not inject a processor object; it passes the `VideoProcessor` value.

## Why not FAC frames into a new flutter_webrtc source

That was the first choice (closest to ADR-0013). It needs FAC to own the camera during the call, so the host's `getUserMedia` camera and OS-default device switching go away, and on iOS and Android a second capture session fights the first. It also needs a new native track type registered in flutter_webrtc plus a Dart `MediaStreamTrack` wrapper. The per-track hook already exists and needs none of that.

## Consequences

- This bends ADR-0013 for the camera on a WebRTC call: the capture is flutter_webrtc's, the processor is FAC's. The local Video surface and Camera preview still use the Production video path.
- Fail closed. A frame that leaves an applied processor is never raw: it is processed (blurred whole before the first mask), the last processed frame, or black (no mask, segmentation unavailable, a conversion error). When blur or replace cannot be applied the call returns `unavailable` and the host keeps the track disabled; the host keeps a new track disabled until `applied`, before addTrack or replaceTrack. Web, Windows, and Linux have no bridge yet.
- Android: flutter_webrtc runs only the processor of the registry entry that is the camera source's processor. A shared camera track (`buildSharedVideoTrack`) or an entry `mediaStreamGetTracks` replaced takes a processor and never runs it, so `process` answers `applied` only after the track's first frames went through the processor, and `unavailable` when they bypass it or none come within 2 s. A bypass seen later detaches the processor, disables the track natively, and emits `webrtcTrackProcessingUnavailable`; the host disposes that track or processes it again, never just re-enables it.
- Hosts call `processWebrtcVideoTrack` again after every camera switch; applying drops the previous person mask.
- `webrtcTrackProcessingUnavailable` is Android-only. It emits a track id when an applied processor gives up (5 failed segmentations in a row: black frames) or a late bypass disabled the track. iOS and macOS have no give-up: Vision runs on every frame, and a frame without a mask is black or the last processed frame.
- flutter_webrtc is pinned to `>=1.6.2 <1.7.0` with the webrtc-sdk it ships; the plugin reaches its internals.
- Frames are turned upright before segmentation and leave with rotation 0.
- Android converts each frame I420 → ARGB → I420 on the capture thread. Expect a lower frame rate than pass-through.

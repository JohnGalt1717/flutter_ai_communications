# flutter_ai_communications_webrtc

WebRTC **Transport plugin** for `flutter_ai_communications`.

Attach `WebrtcVideoSink` to a live Session after StartReady or `enableVideo`.
The sink yields a camera **Send track** on `localVideos` and a screen Send
track on `localScreens` while screen send is running. The host `addTrack`s
each handle separately on a PeerConnection the host constructs. This package
does not create PeerConnections. Signaling, roster, chat, and tile layout
stay in the host.

Local self-view is `Session.videoSurface` (Texture / HtmlElementView). Do not
import `RTCVideoView` for local preview. Native Production frames stay native
(ADR-0013).

A host that sends its own flutter_webrtc camera track calls
`processWebrtcVideoTrack(track.id, processor)` to run FAC's blur or replace on
that track in place (Android, iOS, macOS). When it cannot run, the track sends
black frames and the call returns `unavailable` (ADR-0032).

See `docs/host-webrtc-narrative.md`.

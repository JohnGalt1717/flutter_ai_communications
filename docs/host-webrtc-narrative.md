# Host narrative: WebRTC Transport plugin

The Communications manager does not own a PeerConnection. The host does.
`flutter_ai_communications_webrtc` attaches as a Video sink and yields a
**Send track**. The host `addTrack`s that handle on its own PeerConnection.
Local self-view stays `Session.videoSurface`. `RTCVideoView` is for inbound
streams only.

Do not attach this plugin in the lobby Session.

## Attach after Join

```text
result = await manager.start(purpose: 'meeting', settings: settings)
sink = WebrtcVideoSink()
sink.attach(session)
sink.localVideos.listen((track) {
  if (track == null) {
    // Camera-off: host removeTrack
    return
  }
  // Mute-video: track.muteVideo is true; Production path already sends black
  // frames. Same track.id until generation changes (replaceTrack).
  hostPeerConnection.addTrack(mapSendTrack(track))
})
session.capture.listen(hostPeerConnection.addAudio)  // same Capture stream
```

`mapSendTrack` is host code that turns `WebrtcSendTrack` (surface handle,
generation, Mute-video) into a flutter_webrtc `MediaStreamTrack`. This
library does not import those types. Native bind uses
`attachProductionVideoPathNative` (Session already calls it). Frames do not
copy through Dart.

## Local preview vs inbound

| Surface | Widget |
| --- | --- |
| Local send | `Session.videoSurface` Texture / HtmlElementView |
| Inbound remote | host `RTCVideoView` (or equivalent) per inbound Video surface |

Loopback proof: host adds the Send track to a loopback PeerConnection and
renders the inbound track on `RTCVideoView`. That is host code. Identity of
that loopback is not native Production-path proof.

The example's loopback meeting subsection does not construct a PeerConnection.
It lays out local Session Video surfaces (camera self-view, screen send) as
the in-call stage. `RTCVideoView` inbound waits on a native Production-path
bind (`attachProductionVideoPathNative`).

## Detach

```text
sink.detach()
session.stop()
```

Detach does not end the Session or replace the Capture stream.

## Out of this package

- Creating `RTCPeerConnection`
- Signaling, ICE, roster, chat, meeting grid
- A second camera via `getUserMedia` (that would not be the Production path)

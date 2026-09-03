# Host owns meeting fabric; this library stays the media edge

Collaborative Topic state, WebTransport/QUIC meeting sessions, document bindings, and ICE signaling are host concerns. They must not live in this repository if the library is published independently of the host product.

This library remains capture, render, catalogs, Production video path, and Video sinks. The host constructs PeerConnection and addTracks Send tracks (ADR-0018). A host may start a Communications Session only when that client enables mic, camera, or screen. Chat-only or document-only collaboration must not require a Session.

Rejected: a `flutter_ai_meeting` package in this workspace, document ops on Session, WebRTC data channels as a document bus, and Media-over-QUIC inside this library.

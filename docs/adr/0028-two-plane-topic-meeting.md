# Two planes for Topic meetings; FAC stays the media edge

A live Conversation on an `ITopic` needs authoritative collaborative state and, optionally, real-time media. Those are different failure domains.

The data plane is the MinimalWebTransport frame already used for settlement I/O, with ALPN `fulcrum-meeting` and a WebSocket fallback. All Topic ops, chat, transcripts, and ICE signaling travel there. Datagrams stay fail closed.

The media plane is WebRTC into a media worker. `flutter_ai_communications` remains the Communications manager. `flutter_ai_meeting` is the host that ADR-0018 assumed: it constructs the PeerConnection, addTracks Send tracks, and owns signaling. Session types still have no PeerConnection.

Rejected: putting document ops in Session, WebRTC data channels as the document bus, mesh-only multi-party media when a service must hear, Media-over-QUIC in v1, and SignalR RPC as the durable meeting protocol.

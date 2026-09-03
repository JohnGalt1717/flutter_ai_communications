# Understanding Brief: Topic meeting fabric

Date: 2026-09-03
Status: locked after grill. Write specs from this. Do not reopen topology.

## Goal and scope

Enable TruCom, Athena, RAPID, and SmartMone to open a live Conversation on any `ITopic` (Document, Contact, Team, Opportunity, banking object, later Project issue). Humans and AIs are the same kind of participant. Optional voice, camera, and screen. Optional live bindings for collaborative state (markdown, whiteboard, flowchart, charts, later sheet/deck/database). Server is authoritative. Lazy persist like today's DocumentHub.

This brief is the contract between:

- `flutter_ai_communications` (media edge, already shipping)
- a new Dart companion in that repo (meeting host)
- ProjectFulcrum C# twin + hub migration onto MinimalWebTransport
- product widgets that stay in Fulcrum (`Apps/shared`), not in the media library

## Key terms

**Topic**: Fulcrum `ITopic`. Durable collaborative surface. Security groups and Relationships already gate it.

**Conversation**: A thread on a Topic. Chat, transcript, grill turns, and artifacts live here.

**Meeting**: The ephemeral live roster plus open media plus open bindings for one Conversation. Starting a meeting creates a new Conversation on the Topic.

**Binding**: A logical stream keyed by Topic/document id and type. Not a second socket. Not a screen share.

**Envelope**: MinimalWebTransport frame plus a meeting wrapper `{ topicId, topicType, conversationId, bindingId, revision, payloadType, payload }`.

**Data plane**: Authoritative state and control. MinimalWebTransport streams.

**Media plane**: Mic, camera, screen, AI voice. WebRTC into a media worker.

**Media worker**: Server participant that can fan out tracks, record per speaker, transcribe onto the Conversation, attach one OpenAI Realtime session for the room, and later fork a track to a vision consumer.

**Communications Session**: Existing FAC object. At most one per app. Starts only when this client enables voice, camera, or screen.

## Settled decisions

1. FAC does not own SignalR, whiteboards, or document schemas. It stays capture, render, catalogs, Production video path, Video sinks.
2. The Dart meeting companion is the FAC host: it owns PeerConnection attach, ICE signaling over the data plane, logical binding mux, and worker session ids.
3. C# twin lives in ProjectFulcrum. Same frame, same patterns, hub handlers.
4. Data plane protocol is the existing MinimalWebTransport frame (magic `MW`). Separate ALPN from `fulcrum-settlement` (`fulcrum-meeting`).
5. Bindings: Kestrel WebTransport (web), `quic_lib` (Flutter native), `QuicPipelineClient` (C#). Same frame over WebSockets when HTTP/3 is blocked.
6. Datagrams stay fail closed. Notify and presence use streams.
7. Logical streams only. One data-plane session per live Conversation. Binding id = document/Topic id.
8. Media is WebRTC to a worker for multi-human rooms. Solo human ↔ model may stay 1:1 Realtime or host-pumped PCM with no worker.
9. No media on QUIC/WebTransport in v1.
10. Server-authoritative ops. Lazy writes. Checksum/revision like `ApplyDocumentPatch`.
11. Auth is existing bearer on the data-plane connect, then Relationship + `ITopic.Security`. Join-proof hook reserved. No ZKP in v1 ICE.
12. AI is a Conversation participant. Multi-human live voice goes through one mixer-side Realtime session. Text + tools on every Conversation from day one.
13. Transcription is Conversation messages on the data plane, not media packets.
14. Whiteboard widget and all document editors live in Fulcrum shared UI. Whiteboard and Flowchart are different document types on one scene engine. Whiteboard flow is visual only. Flowchart nodes are structural and may later drive RAPID workflows.
15. Charts are a document type. Any document may embed or inline via a display tool.
16. All Fulcrum hubs migrate onto this harness. Order: DocumentHub first, SmartMone banking hubs second, then the rest.
17. `quic_lib` is the v1 native Dart WebTransport stack. Must pass Kestrel loopback before Athena/SmartMone take a dependency.

## Non-goals / rejected

- Document ops or CRDTs inside `flutter_ai_communications` Session types
- Physical socket or PeerConnection per embedded object
- WebRTC data channels as the document bus
- Mesh-only multi-party media (worker is required once a service must hear)
- Media-over-QUIC / MoQ in v1
- SSI/ZKP as the v1 admit path
- OneNote-complete whiteboard in the first slice
- Excel, PowerPoint, and database document types in the first slice
- Cutting every hub in the same week as the first Document receipt

## Open (implementation, not topology)

- Exact media worker (LiveKit, Cloudflare Realtime, mediasoup, or in-house). Spec speaks publish/subscribe/ICE, not a vendor type.
- `quic_lib` Extended CONNECT receipt against Kestrel (gate).
- Envelope field names in code (follow this brief; do not invent a second wrapper).
- Whiteboard file format (scene JSON, versioned, server snapshot + ops). Separate short spec after DocumentHub is on the harness.

## Next action

1. Land this brief + FAC spec + ADR + plan in `flutter_ai_communications`.
2. Land the hub-migration plan in ProjectFulcrum.
3. Prove `quic_lib` ↔ Kestrel loopback with the `MW` frame and bearer.
4. Rehost DocumentHub patterns on the harness (Athena stays the UI).
5. Add Whiteboard document type + Fulcrum widget on the same binding API.
6. Stand up a media worker and attach FAC WebRTC after Join when a client enables media.
7. TruCom POC hosts a Conversation on an `ITopic` with optional voice and one collab binding.

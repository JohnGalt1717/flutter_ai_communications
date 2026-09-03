# Spec: Topic meeting fabric v1

Companion to `CONTEXT.md` (media terms stay there). Product language for Topics lives in ProjectFulcrum `CONTEXT.md`. This spec owns the wire and the Dart/C# twins.

Normative brief: `docs/meeting-UNDERSTANDING-BRIEF.md`.

## Packages

| Package | Repo | Role |
| --- | --- | --- |
| `flutter_ai_communications` | this repo | Media edge. Unchanged ADRs 0001–0027. |
| `flutter_ai_communications_webrtc` | this repo | Send tracks. Host still addTracks. |
| `flutter_ai_meeting` | this repo, new | Data-plane client, binding mux, ICE signaling, FAC host. |
| `Fulcrum.TopicMeeting` | ProjectFulcrum `Api/Libraries` | C# twin: session accept, patterns, worker control. |
| MinimalWebTransport | ProjectFulcrum | Frame, codecs, Kestrel WT, Quic pipeline. |
| Product widgets | ProjectFulcrum `Apps/shared` | Editors, whiteboard, flowchart, chat chrome. |

`flutter_ai_meeting` may import the webrtc companion. It must not put PeerConnection types into `CommunicationsManager` or `Session`.

## Planes

```text
Client
  flutter_ai_meeting
    data plane  -->  MinimalWebTransport (WT / quic_lib / WS fallback)
                        Fulcrum.TopicMeeting + existing lazy persist
    media plane -->  FAC Session + WebrtcVideoSink
                        host PeerConnection --> media worker
                        worker may attach OpenAI Realtime (one per room)
```

A Conversation with only chat and Topic bindings never starts a Communications Session.

## Data plane

### Connect

1. Client presents the existing bearer on WebTransport CONNECT (or WS upgrade).
2. Server checks Relationship + `ITopic.Security` for the requested Topic.
3. Client sends `meeting.join` with `{ topicId, topicType, conversationId? }`.
4. Empty `conversationId` means create a Conversation on that Topic and return it.
5. Server returns roster, open bindings, and a media-worker join token if media will be used.

ALPN for native QUIC: `fulcrum-meeting`. Do not reuse `fulcrum-settlement`.

### Frame

Use MinimalWebTransport frame v2 as specified in `FULCRUM/Api/BlockChain/docs/spec/minimal-webtransport.md`. Meeting patterns are UTF-8 pattern strings. Body is MessagePack on native, JSON allowed on web.

Datagram kind fails closed.

### Envelope (body wrapper)

Every meeting payload is:

```text
topicId          string
topicType        string     // Document, Contact, Team, ...
conversationId   string
bindingId        string     // usually the document/Topic id
revision         u64        // 0 if not a mutating binding
payloadType      string     // markdown.patch, whiteboard.op, chat.message, ...
payload          bytes      // codec-decoded object of that type
```

The meeting library does not interpret `payload`. Product handlers do.

### Logical bindings

One data-plane connection per live Conversation.

`binding.open` / `binding.close` / `binding.subscribe` take `{ bindingId, payloadType }`.

Ops for that binding travel as envelope messages on the same connection. They are a logical stream, not a second WT session.

### Patterns (v1)

| Pattern | Shape | Purpose |
| --- | --- | --- |
| `meeting.join` | unary | Admit + create/attach Conversation |
| `meeting.leave` | unary | Leave roster |
| `meeting.roster` | push | Participant add/remove |
| `binding.open` | unary | Open or attach a binding |
| `binding.op` | duplex | Client ops in, server-authoritative ops out |
| `binding.snapshot` | unary | Full state for late join |
| `chat.message` | duplex | Conversation messages including transcripts |
| `media.signal` | duplex | SDP/ICE for the worker |
| `media.token` | unary | Short-lived worker join token |

Reject unknown patterns.

### Authority

Server assigns the next revision. Stale client revision returns a recovery snapshot on `binding.op` (same idea as `ApplyDocumentPatch`). Lazy persist is a host/service concern, not a client flush on every ink point.

## Media plane

1. Client starts FAC Session only when this user enables mic, camera, or screen.
2. After `StartReady`, attach `WebrtcVideoSink` and add tracks to a PeerConnection created by `flutter_ai_meeting`.
3. Signaling travels on `media.signal`. ICE uses server-issued STUN/TURN.
4. The far side of the PeerConnection is the media worker, not a mesh of other humans.
5. Mute still emits silence on the Capture stream (ADR-0003, ADR-0004).
6. Screen send remains a Production video path (spec-screen-v1). It is not a binding.
7. Solo AI voice with no other humans may skip the worker and use host-pumped PCM or 1:1 Realtime. The meeting companion chooses that path from join flags.

Future vision consumers subscribe on the worker. Clients do not change.

## Native Dart binding

v1 stack: `quic_lib`.

Gate: loopback in `example/` or a `flutter_ai_meeting` test that:

- completes Extended CONNECT to Kestrel WebTransport
- sends one `MW` unary with bearer
- receives the reply
- opens a duplex `binding.op` and echoes a dummy payload
- reconnects after a server idle close

Until that receipt exists, Athena and SmartMone must not depend on `quic_lib`.

Web uses the browser `WebTransport` API. If CONNECT fails (blocked UDP), the client retries the same frame over WebSockets.

## Product document types on bindings

| payloadType | v1 | Owner |
| --- | --- | --- |
| `markdown.patch` / `markdown.full` | yes (DocumentHub cutover) | Documents service |
| `presence.cursor` | yes | same |
| `whiteboard.op` / `whiteboard.snapshot` | yes after markdown receipt | Apps/shared widget |
| `flowchart.op` / `flowchart.snapshot` | same engine, constrained graph | Apps/shared widget |
| `chart.snapshot` | later | existing AI chart tool + document type |
| `sheet.*` / `deck.*` / `database.*` | not now | — |
| `topic.patch` | after Document | generic ITopic field updates (Contact, etc.) |

Whiteboard and Flowchart share a scene format. They are different document types. Whiteboard flowchart shapes are visual only.

## Host vs library

| `flutter_ai_meeting` | Fulcrum host |
| --- | --- |
| Connect, join, mux, envelope | Topic security, persist, revisions |
| ICE + PeerConnection attach | Media worker process |
| Binding streams as bytes | Payload schemas and editors |
| FAC Session lifecycle when media on | Tile layout, chat chrome, TruCom/Athena UI |

## Non-goals

- Interpreting whiteboard bytes in FAC
- PeerConnection types on Session
- SignalR as the meeting protocol
- One physical WT session per binding
- MoQ / media on QUIC

# Plan: Topic meeting fabric (Dart companion)

**Status (2026-09-03):** Grill locked. Spec and brief landed with this plan. No implementation until `quic_lib` ↔ Kestrel receipt.
**Audience:** Agent in `JohnGalt1717/flutter_ai_communications`.
**Date:** 2026-09-03
**Source of truth:** `docs/meeting-UNDERSTANDING-BRIEF.md`, `docs/spec-meeting-fabric-v1.md`, ADR-0028.
**Fulcrum counterpart:** `FULCRUM/.agents/plans/2026-09-03-topic-meeting-and-hub-migration.md`

Ticketing: markdown under `.scratch/meeting-fabric-issues/` until a human asks for GitHub issues.

## Goal

Ship `flutter_ai_meeting` so a host can join a Conversation on an `ITopic`, mux logical bindings, and optionally start a FAC Session whose tracks go to a media worker.

This repo does not ship whiteboard widgets, DocumentHub, or the media worker binary.

## Gate

Companion is not done when a unit test parses an envelope. Done means:

- `quic_lib` (native) and browser `WebTransport` (web) each complete `meeting.join` against a recorded fixture or a local Kestrel
- WebSocket fallback speaks the same frame
- opening two bindings on one connection does not open a second socket
- media off: no Communications Session
- media on: lobby Session stop + meeting Session + `WebrtcVideoSink` attach, existing video ADRs intact
- analyzer clean on the new package

## Work order

### 00 Domain

- Add meeting terms to a companion CONTEXT or a section that does not collide with media `CONTEXT.md`.
- Do not reuse Transport, Session, or Capture stream for bindings.

### 01 Package skeleton

- `packages/flutter_ai_meeting` in the pub workspace.
- Depends on `flutter_ai_communications`, `flutter_ai_communications_webrtc`, `quic_lib`.
- No Melos.

### 02 Frame codec

- Encode/decode MinimalWebTransport frame v2 (magic `MW`).
- Envelope wrapper from the spec.
- Golden tests for MessagePack and JSON bodies.

### 03 Bindings

- Connect interface: WebTransport, `quic_lib`, WebSocket.
- `meeting.join` / leave / roster push.
- `binding.open` + duplex `binding.op` muxed by `bindingId`.

### 04 Kestrel loopback receipt

- Hard gate. Document the command and the JSON receipt path.
- Fail the ticket if Extended CONNECT or bearer does not work.

### 05 FAC interop

- Optional media flag on join.
- Start Session only when the flag is on.
- Attach webrtc sink. Signaling bytes on `media.signal` (fake worker acceptable in example).

### 06 Example slice

- Example subsection: join Topic fixture, two dummy bindings, toggle media.
- Do not build TruCom chrome here.

### 07 Docs

- Keep brief, spec, ADR, this plan current.

## Explicit non-goals

- Whiteboard renderer
- C# library (Fulcrum plan)
- SFU vendor selection in this repo
- Migrating Athena DocumentHub (Fulcrum plan)
- GitHub issues unless asked

## Risks

| Risk | Mitigation |
| --- | --- |
| `quic_lib` cannot talk to Kestrel | Receipt is a gate. WS fallback still ships. |
| Bindings become Sessions | Tests: media-off join leaves `manager.session == null` |
| Frame drift from MinimalWebTransport | Copy the field table; do not "simplify" |
| Agent puts PeerConnection on Session | ADR-0018 + ADR-0028 review |

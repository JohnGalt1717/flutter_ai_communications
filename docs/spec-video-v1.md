# Spec: Communications video v1

## Problem Statement

Hosts need Teams/Zoom-class local camera, lobby, and inbound display without
turning Session into a WebRTC client or copying 720p30 through Dart. Audio v1
already owns one Session, one Capture stream, and host-owned Transport. Video
must attach to that machine.

## Solution

The public module is the Communications manager (today’s `CommunicationsManager` until
rename). At most one Session and at most one Camera preview. Lobby is a Session
with no Transport plugin. Join is host `stop` + `start`, optionally passing
Session settings. Meeting attaches a Transport plugin (WebRTC now, WebTransport
later). The plugin owns PeerConnection/RTP; the host owns signaling, roster,
chat, and tile layout. Inbound audio enters Session playback. Each inbound
video stream is a Video surface.

Camera Endpoints and Screen sources are catalogs separate from audio Endpoints.
v1 Video processor is none (pass-through). Blur and replace are
`.agents/plans/video-processors-blur-replace.md`.

The first host is `example/`. It ships a Zoom/Teams-class lobby subsection
(device picks, permission via `start()`, mute, Join). Orchestration drives
that lobby, then join, then in-session controls. Native camera graphs stay
in the federated packages.

## User Stories

1. As a host, I want a lobby Session with no Transport plugin, so I can pick
   devices, hear a Test record, and see a local Video surface without leaking
   bytes to remotes.
2. As a host, I want Join to stop that Session and start a new one from Session
   settings, so testing cannot ride onto the wire.
3. As a user, I want mic and speaker picks in the lobby, with permission
   requested inside `start()` and blocking until the OS answers.
4. As a user, I want in-call audio device changes and a one-tap camera flip to
   be live switches, like Teams.
5. As a user, I want in-call camera settings to Camera-off the meeting (audio
   continues) and open Camera preview, so remotes see an avatar until I Apply
   or Cancel.
6. As a host, I want missing camera or camera denial to still return a live
   Session, so proctoring can fail in product code and a meeting can continue
   audio-only.
7. As a Transport plugin, I want local audio and video from the Session and to
   deliver inbound audio into Session playback, so AEC sees far-end audio.
8. As a host, I want one Video surface type (Texture id, or a view id on web)
   per local send or inbound stream, and I lay out tiles myself.
9. As a developer, I want the example lobby to be the Orchestration e2e path
   on iOS, Android, web, macOS, Windows, and Linux.

## Implementation Decisions

- Glossary: `CONTEXT.md`. ADRs 0012–0021 (0015 superseded by 0018; 0014
  superseded by 0020).
- Default requested Video Format 1280×720@30. Native Video Format is the next
  higher resolution if any, else the next lower; fps closest to the request.
- Mute-video is in-session black frames. Camera-off stops outbound video.
  Lobby has Camera-off / camera on, not Mute-video.
- v1 processor is none only.
- Screen source is specified; native capture later.
- Linux camera graph is V4L2 → Texture (in tree, PR #34 / `e6b37b4`);
  physical receipts are later. Windows Media Foundation graph is proven on
  LifeCam Studio.
- Markdown tickets in `.scratch/video-v1-issues/` and
  `.scratch/video-host-issues/`. No GitHub issues unless a human asks.

## Testing Decisions

- Fake platform adapter covers direction, lobby Session, join via settings,
  Camera-off, live `selectCamera`, Camera preview fail-closed, missing camera
  as Session status.
- Example lobby + Orchestration is the UI-to-success path. Keys on the lobby
  subsection are the e2e handles. Do not call this Marionette.
- Physical receipts: first `start()` permission, device pick, lobby → join,
  mute, Camera-off, camera flip, twenty start/stop cycles without leaking the
  camera. Loopback identity is not native proof.

## Out of Scope

- PeerConnection, signaling, roster, or meeting grid in Session.
- Blur, replace, gamma, beauty, avatars, background video (later processor
  plan).
- Screen-share native graphs (catalog is specified).
- Multi-camera simultaneous publish (camera + screen is two send paths, later).
- Library-owned landing chrome. The example is the harness, not a shipped
  product widget.

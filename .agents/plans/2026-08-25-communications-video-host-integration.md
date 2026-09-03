# Plan: Host communications video (example first)

**Status (2026-09-03):** Example lobby + Session contracts shipped. Library
tickets 04 (#46) and 12 (#48) are on `main`. Example meeting Join attaches
`WebrtcVideoSink`. Remaining host work: preference persistence in `example/`,
RTCVideoView loopback (host ticket 08), Linux camera compile + receipt.
Do not start native camera work in a host app.
**Audience:** Fresh agent working in `JohnGalt1717/flutter_ai_communications`.
**Date:** 2026-08-25
**Library source of truth:** `docs/spec-video-v1.md`, ADRs 0012–0017,
`.agents/plans/video-capture-and-sinks.md`, `.scratch/video-v1-issues/`.
**Host narrative:** `docs/host-prejoin-narrative.md`.

Ticketing for this plan is local markdown under
`.scratch/video-host-issues/`. Do **not** open GitHub issues for this work
until a human asks for them. This plan lives in this repo. It is not a
ProjectFulcrum / Apps plan.

---

## Goal

Give a host a Teams/Zoom-class landing page and in-session AV surface on top
of `flutter_ai_communications`, without turning the host into a camera plugin
and without copying production video frames through Dart.

The first host in this repo is `example/`. Product hosts copy the same API
usage; they do not copy native graphs.

The host owns:

- product chrome (Teams-like or Zoom-like; both must be possible)
- host-persisted audio Endpoint preference and Camera preference
- Transport: PeerConnection + signaling when a real call exists
- attaching the library Video sink (first: flutter_webrtc companion package)
- permission copy and all user-facing strings
- Orchestration keys on the lobby subsection and in-session pages

The library owns:

- Camera Endpoint catalog and Camera preference resolution
- Pre-join preview and Preview Texture
- one Session, including enable-video-later
- Mute-video (black frames) vs Camera-off (hardware stop)
- library-owned Video processors (none / blur / replace)
- native Production video path and Video sink provider seam

## Gate

Do not treat host video as done when a `Texture` widget shows a camera in
the example. Done means:

- one application-scoped Audio manager
- idle camera catalog + Camera preference bind work before Session
- a lobby subsection follows the host narrative (lobby is a Session)
- join stops the lobby Session and starts a meeting Session from Session settings
- mute-audio, mute-video, Camera-off, switch camera, processor, pause, stop
- host PeerConnection (or documented loopback) receives the sink track
- Orchestration can drive lobby → join → controls on at least one head
- no second camera plugin, no Dart production frame pump, no PeerConnection
  types inside Session

Library audio conformance stays on its own track. This plan must not regress
one-Session or ADR-0004 stream identity.

**Hard block:** Library tickets `01`, `02`, `04`, and `12` exist. Native
preview waits on a platform graph (`05`–`09`). Host ticket `08` (RTCVideoView
loopback / addTrack) is unblocked.

Example landing chrome may be the same work as library ticket `13`. Do not
build a second lobby. Host tickets `05`–`07` are the checklist for that
page; ticket `13` is the library-side acceptance of it.

## Product decisions (from library grill)

| Topic | Decision |
| --- | --- |
| Output seam | Native Production video path + Video surface. No Dart byte wire into WebRTC. |
| Session shape | One Session. Direction is a capability mask. Video can attach later. |
| Lobby | A Session with no Transport plugin. Join is stop + start with Session settings. |
| Camera catalog | Separate from audio Endpoints. Separate Camera preference list. No AV Pair. |
| Mute-video | In-session black frames. Not used in the lobby. |
| Camera-off | Outbound video gone. Audio continues. Host avatar. |
| Pause / stop | Pause parks audio+video. Stop ends the Session. |
| Processors | v1 none only. Blur/replace later plan. |
| Transport | Plugin owns RTP. Host owns signaling, roster, tile layout. |
| UI ownership | No library picker widgets. Example lobby is the first chrome and the Orchestration path. |
| First library platforms | iOS, Android, Web, macOS, Windows, Linux. Screen share later. Linux camera receipts remaining. |
| Tickets | Markdown files in this repo. Not GitHub issues until asked. |

## Architecture

```text
Host (example/ first)
  lobby subsection + in-call chrome, strings, Orchestration keys
        |
        v
Host wrapper (example services / view models)
  one Communications manager
  persist + bind Endpoint preference and Camera preference
  Video surface widget (unbranded)
  attach Transport plugin after join
  map Start results and Session status to UI events
        |
        v
flutter_ai_communications
  catalogs, lobby Session, meeting Session, Camera preview, native path
        |
        +-- Video surface --> Flutter Texture or web view id
        +-- Transport plugin --> flutter_ai_communications_webrtc
                                  |
                                  v
                         plugin PeerConnection / RTP
                         host signaling (out of this repo)
```

Rules that are easy to violate:

1. Do start a Session for the lobby; do not attach a Transport plugin there.
2. Do not put flutter_webrtc types in `CommunicationsManager` or Session wrappers
   beyond the sink package API.
3. Do not invent a host-side blur/replace pipeline.
4. Do not persist mid-session camera picks into Camera preference.
5. Do not create a second Audio manager. One application-scoped instance.
6. Unbranded primitives (Texture host, device list models, preference store)
   may live next to the example. Branded lobby layout stays in the page.

## Work order

Tickets live in `.scratch/video-host-issues/`.

### 1. Domain lock and first surface

Ticket `00`.

- Read `CONTEXT.md` video terms. Do not invent synonyms.
- First host surface is `example/`.
- Example owns chrome and routes. Library packages own camera graphs.

### 2. Package wiring

Ticket `01`.

- Example already depends on workspace packages. Confirm video / webrtc
  packages are wired when they exist.
- Do not vendor camera native code into `example/`.
- Analyzer clean on the touched pubspecs.

### 3. Manager and catalogs

Ticket `02`.

- Application-scoped Audio manager in the example.
- Idle `endpoints()` and `cameras()` exposed to the landing view model.
- Typed Start / preview results mapped to UI — no raw exceptions for
  expected permission failures.
- Session purpose string so already-active failures name the owner.

### 4. Preference persistence

Ticket `03`.

- Host-persisted ordered audio Endpoint preference.
- Host-persisted ordered Camera preference.
- Bind at preview and at `start()`. Mid-session picks stay ephemeral.
- Follow existing example storage if any. Do not add a new persistence
  stack without need.

### 5. Unbranded preview primitive

Ticket `04`.

- Widget that renders the Preview Texture id.
- Preview start/stop/selectCamera/setProcessor/setCameraEnabled on the
  idle manager.
- No Teams/Zoom layout in a shared helper.

### 6. Landing page

Ticket `05`. Overlaps library ticket `13`.

Follow `docs/host-prejoin-narrative.md` exactly:

- mode: audio / video / AV
- audio capture + render picks
- camera pick when mode includes video
- Preview Texture
- processor none / blur / replace
- lobby mute-audio, mute-video, Camera-off
- Join calls `start()` with current picks
- Leave-without-join stops preview only

### 7. Join, promote, enable-video-later

Ticket `06`.

- `start()` may override preview camera.
- After `StartReady`, Session owns the Texture. No flicker when camera
  and processor are unchanged.
- Audio-only join, then `enableVideo` on the same Session.
- Camera denied / restricted / no usable camera are typed results.

### 8. In-session controls

Ticket `07`.

| Control | Library call |
| --- | --- |
| Mic mute | `session.mute()` / unmute |
| Video mute | `session.muteVideo()` |
| Camera off | `session.setCameraEnabled(false)` |
| Switch camera | `session.selectCamera(id)` |
| Processor | `session.setVideoProcessor(...)` |
| Audio route | `session.selectRender(...)` |
| Pause | `session.pause()` |
| Leave | `session.stop()` |

### 9. Transport and WebRTC sink

Ticket `08`.

- Host creates and owns PeerConnection and signaling.
- Attach library flutter_webrtc sink after StartReady or enableVideo.
- AddTrack on the host PC. Do not construct PC inside the library wrapper.
- First slice may be loopback in `example/` with no product signaling.
- Detach sink on leave without leaking the camera.

### 10. Marionette and receipts

Ticket `09`.

- Drive lobby → join → mutes → Camera-off → switch → processor → leave.
- Heads follow library matrix as hardware allows.
- Tear down Flutter debug processes by numeric PID.
- Do not claim native proof from the library fake adapter alone.

### 11. Docs pass

Ticket `10`.

- Keep this plan status current.
- Keep `docs/host-prejoin-narrative.md` accurate (library ticket `14`).
- Do not duplicate the library spec.

## Implementation order

1. `00` then `01` then `02` (after or with library `01`–`02`).
2. `03` and `04` after `02`.
3. `05`–`07` after library preview (`03`) plus one native graph.
4. `08` after library sink seam + webrtc package.
5. `09`–`10` last.

Do not implement CameraX / AVFoundation / getUserMedia inside the example
beyond calling the library.

## Explicit non-goals

- Camera graphs, segmentation, or processor shaders in the host.
- PeerConnection, SFU, or signaling inside `flutter_ai_communications`
  Session types.
- Library-owned landing page widgets shipped as product chrome.
- Screen share, beauty filters, avatars, background video.
- Multi-camera simultaneous publish.
- GitHub issues for this slice.
- Any work in ProjectFulcrum for this slice.

## Risks

| Risk | Mitigation |
| --- | --- |
| Host starts before library contracts exist | Fake-backed tests only; no product preview claim |
| Second camera plugin sneaks in | Reject any `camera` / `flutter_webrtc` preview path that bypasses the manager |
| Lobby uses a Session | Tickets `04`/`05` assert idle preview |
| Mute-video implemented as Camera-off | Separate VM methods and Marionette keys |
| Dart frame pump “just for now” | Forbidden. Calibration tap is library-only and off by default |
| Preference written from in-call switch | Ephemeral select only; persistence tests |

## Files likely touched

**example/:** landing page, view model, preference store, Texture widget,
Marionette keys, permission strings, tests.

**Not touched here:** per-platform native graphs (library tickets `05`–`11`),
platform_interface contracts (library `02`), webrtc package internals
(library `12`).

## Related library tickets

| Library | Why the host cares |
| --- | --- |
| 00–02 | Types and fake contracts host tests against |
| 03 | Pre-join API the landing page calls |
| 04, 12 | Sink seam + flutter_webrtc package |
| 05–09 | Real cameras per platform |
| 10–11 | Blur / replace quality |
| 13–14 | Example + narrative this plan must not contradict |

## Grilling log (summary)

Library Q1–Q20 locked native sink + Texture, one Session, idle preview,
separate camera catalog, mute-video vs Camera-off, library processors,
provider sinks, five platforms, host narrative. This plan is the host work
that narrative implies, kept in this repository. Markdown tickets only.

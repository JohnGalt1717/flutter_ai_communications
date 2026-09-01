# Video Capture, Processors, and Sink Providers Plan

**Status (2026-09-01):** Camera graphs shipped on iOS, Android, macOS, web,
Windows, and Linux (in tree). PR #34 squash-merged to `main` as `e6b37b4`.
Windows LifeCam Studio `native_camera_test` passed. Next is Linux
`flutter build linux` plus a physical camera receipt, then Transport plugin
seam (tickets 04 / 12). See `docs/windows-linux-video-setup.md`.
**Tickets:** `.scratch/video-v1-issues/` (markdown, not GitHub issues).
**Host plan:** `.agents/plans/2026-08-25-communications-video-host-integration.md`.
**Host tickets:** `.scratch/video-host-issues/`.

## Current slice (2026-09-01)

HEAD: `e6b37b4` on `main`. Working tree clean after PR #34.

Linux remains: compile the V4L2 graph on a machine with clang/cmake/GTK/v4l
headers, then collect camera Orchestration receipts. Windows camera is
proven on JamieDesktop (Microsoft LifeCam Studio). A second Windows machine
only re-runs receipts if hardware differs. Missing/denied camera must not
fail `start()`.

### Done

- Domain: `CONTEXT.md` video terms, ADRs 0012–0021, `docs/spec-video-v1.md`
- Shared types + fake platform + `CommunicationsManager` / Session video APIs
- Lobby is a Session; Join is host `stop` + `start` with Session settings
- Native camera graphs: iOS (AVFoundation), Android (Camera2), macOS
  (AVFoundation), web (getUserMedia + HtmlElementView), Windows (Media
  Foundation → Texture), Linux (V4L2 → Texture, in tree)
- Example lobby (`lobby-enter` → pick → `lobby-join`) with self-view,
  Camera-off, Mute-video
- Orchestration e2e passed: iPhone 17 simulator, SM A176U1, macOS (audio),
  example harness Enter → Join
- Windows camera receipt: LifeCam Studio, permission granted, catalog 1 cam
  (USB / external), Texture 640×480@30, live non-black frames, Mute-video vs
  Camera-off, join via Session settings, enable-video-later (audio Capture
  stream identity kept)
- v1 processor is `none` only
- Windows/Linux audio backends already exist (WASAPI / Pulse). Audio
  Orchestration 20-cycles ran in the PR #32 / #33 window

### Not in this slice (do not block Linux receipts)

- Ticket 04 / 12: Transport plugin RTP seam and `flutter_webrtc` package
- Tickets 10–11: blur / replace processors (see
  `.agents/plans/video-processors-blur-replace.md`)
- Screen source catalog (ADR-0019)
- Physical iPhone Allow-dialog receipt
- Web Join overlay: lobby works; Join must keep a 320×220 platform view, not
  unmount a 100% HtmlElementView

### Windows and Linux remaining work

| Track | Windows | Linux |
| --- | --- | --- |
| Build / doctor | VS + C++ desktop workload | clang, cmake, ninja, GTK, Pulse/PipeWire, v4l headers |
| Audio Orchestration | 20-cycle suite already ran (`-d windows`) | 20-cycle suite already ran on WSLg (`-d linux`) |
| Example lobby | Camera list populated when a device is present | Camera list populated when `/dev/video*` exists |
| Camera graph | Done: Media Foundation → Flutter Texture (`e6b37b4`) | In tree: V4L2 → Flutter Texture. VM compile remaining |
| Camera permission | Windows privacy consent (unpackaged granted on JamieDesktop) | Device-node access (PipeWire portal is later) |
| Mute-video / Camera-off | Proven on LifeCam Studio | Same contract; unproven on hardware |
| Receipt | LifeCam Studio `native_camera_test` passed | `flutter build linux` then `native_camera_test.dart -d linux` |

Windows and Linux camera graphs match the existing Session APIs
(`enumerateCameras`, `requestCameraPermission`, `startCameraNative`,
`selectCameraNative`, `setCameraEnabledNative`, `setMuteVideoNative`). Do not
add a second camera plugin. Empty catalog when no camera is present or
permission is denied is expected, not a failed Session.

## Goal

Give host apps a Teams/Zoom-class camera stack inside `flutter_ai_communications` without turning Session into a WebRTC client. Cameras, lobby Session (no Transport plugin), Production video path, Mute-video, Camera-off, Camera preview, Video processor none in v1, Transport plugin (WebRTC). First platforms are iOS, Android, Web, macOS, Windows, and Linux.

Parity bar: a host must be able to build both a Teams-like and a Zoom-like product on this API. Missing in-call or lobby capability is a spec bug. The example lobby is the Orchestration e2e path.

Audio production work in `.agents/plans/production-audio-manager-and-real-device-conformance.md` stays on its own track. Video must not regress one-Session, one audio Capture stream, or ADR-0004 reset identity.

Host integration lives in this repository. The first host surface is `example/`. Host work does not implement camera graphs.

## Gate

Do not treat video as done when a Texture shows a camera. Done means:

- idle camera catalog and Camera preference
- lobby Session with local Video surface (processor none)
- Join as stop + start with Session settings
- Session AV lifecycle including enable-video-later
- Mute-video vs Camera-off vs pause
- native Production video path
- Transport plugin (flutter_webrtc) plus a fake in tests
- example lobby subsection + in-session AV on the six platforms, driven by Orchestration
- host narrative can be followed without a second camera plugin

Screen share stays a later plan (ADR-0019). Windows ticket 08 is done.
Linux camera compile and physical receipt remain.

## Required architecture

- One application-scoped Communications manager; at most one Session and one Camera preview.
- Separate Camera Endpoint catalog and Camera preference. No unmatched audio/video Pair.
- Lobby is a Session with no Transport plugin. Join is host stop + start with Session settings.
- Camera preview is video-only, in-call, after Camera-off. Audio continues. No in-call audio preview.
- Production video path is native per send source: capture, Video processor, Video surface, Transport plugin.
- Dart Video calibration tap is off by default.
- Session direction is a capability mask. Video attaches and detaches without replacing audio streams.
- Transport plugin owns RTP. Host owns signaling and tile layout. Session has no PeerConnection types.
- v1 Video processor is none. Blur/replace: `.agents/plans/video-processors-blur-replace.md`.
- Missing camera does not fail the Session.

## Public API sketch (host-facing)

Names follow `CONTEXT.md`. Exact types land in ticket 01.

```text
manager.cameras()
manager.bindCameraPreference(orderedIds)
lobby = await manager.start(purpose: 'lobby', direction, formats, preferences)
lobby.videoSurface
lobby.selectCamera(id)            // live; no remotes in lobby
lobby.setCameraEnabled(false)
settings = lobby.settings
await lobby.stop()
meeting = await manager.start(purpose: 'meeting', settings: settings)
attach Transport plugin
meeting.selectCamera(id)          // live flip
meeting.muteVideo() / setCameraEnabled(false)
start Camera preview only after Camera-off
meeting.pause() / stop()
```

Default Video Format: 1280×720 at 30 fps.

## Work order

### 1. Domain and contracts

Tickets 00–02.

- Glossary terms in `CONTEXT.md`
- ADRs 0012–0021
- `docs/spec-video-v1.md` and this plan
- Shared types: Camera Endpoint, Camera facing, Camera preference, Video Format, Native Video Format, Video processor, Session settings, Video surface
- Platform interface methods defaulting to unimplemented
- Fake adapter + Communications manager/Session tests for direction, lobby Session, mute-video, Camera-off, enable-video-later, processor none

Complete when fake-platform tests cover every new Start result and Session control without a physical camera.

### 2. Lobby Session

Ticket 03.

- `start(purpose: lobby)` with no Transport plugin
- Session Video surface
- Processor none
- Join is stop + start with Session settings

Complete when the example lobby subsection can show a self-view from the fake or a single native platform and Orchestration can drive enter → pick → join.

### 3. Transport plugin / video attach seam

Ticket 04.

- Attach/detach one or more sinks on Session
- Fake sink receives generation and enabled/muted/off state
- Documented native hook for real sink packages

Complete when tests prove two sinks see one path and detach does not end the Session.

### 4. Native camera graphs

Tickets 05–09 plus Linux: iOS, Android, macOS, Windows, Web, Linux.

| Platform | Graph | Receipt |
| --- | --- | --- |
| iOS | Done (`IosCameraGraph`) | iPhone 17 sim Orchestration passed |
| Android | Done (`AndroidCameraGraph`) | SM A176U1 Orchestration passed |
| macOS | Done (`MacCameraGraph`) | macOS audio Orchestration passed |
| Web | Done (getUserMedia) | Lobby driven via flutter-skill + Agent Lens |
| Windows | Done (Media Foundation → Texture, PR #34 / `e6b37b4`) | LifeCam Studio `native_camera_test` passed |
| Linux | Graph in tree (V4L2 → Texture, PR #34) | `flutter build linux` then `native_camera_test.dart -d linux` |

Each remaining graph delivers catalog, permission, negotiated Video Format, Preview Texture, camera switch, Mute-video black frames, Camera-off hardware stop, and enable-video-later.

Complete per platform only with public-seam tests plus a real-device receipt. Registration-only tests are not enough.

### 5. Video processors

Tickets 10–11.

- none always works in v1
- blur/replace: later plan, do not implement here

Complete when lobby and in-session preview show the same effect and sinks receive the processed path.

### 6. flutter_webrtc sink package

Ticket 12.

- Companion workspace package
- Binds Production video path to a MediaStreamTrack / capturer
- Host adds the track to its own PeerConnection
- No signaling in this repo

Complete when the example can attach the sink and a loopback PeerConnection shows the processed preview.

### 7. Example harness and host narrative

Tickets 13–14, plus `.scratch/video-host-issues/`.

- Example lobby subsection: mode, audio picks, camera pick, self-view, Join
- In-session: mute-audio, mute-video, Camera-off, flip camera, pause, stop
- Orchestration keys for the above; e2e drives lobby then meeting
- `docs/host-prejoin-narrative.md` kept accurate

## Ticket map

| # | Title | Blocked by |
| --- | --- | --- |
| 00 | Spec, glossary, ADRs | — |
| 01 | Shared video types | 00 |
| 02 | Session and platform-interface contracts | 01 |
| 03 | Lobby Session | 02 |
| 04 | Transport plugin video seam | 02 |
| 05–09 | iOS / Android / macOS / Windows / Web graphs | 02 — 05–09 done; Linux graph in tree, receipts remaining |
| 10 | Processors on iOS and Android | deferred — later plan |
| 11 | Processors on macOS, Windows, Web | deferred — later plan |
| 12 | flutter_webrtc Transport plugin | 04 and one native graph |
| 13 | Example lobby + in-session harness | 03 and one native graph |
| 14 | Host guide accuracy pass | 13 |

## Physical-device matrix

Primary gate on relevant video changes:

- physical iPhone, physical Android, Chrome, macOS, Windows (LifeCam Studio camera receipt on `e6b37b4`), Linux (camera receipt remaining)
- first lobby `start()` after install permission
- front/back or built-in/USB live flip
- lobby Session then join (stop + start with settings)
- audio-only start then enable video
- Mute-video vs Camera-off (lens light where the OS exposes it)
- processor none
- twenty lobby/start/stop cycles without leaking the camera

Human confirmation of blur quality is allowed. Cadence and Texture liveness should be electronic first.

## Dependency graph

1. Domain + shared types + fake Session contracts (00–02)
2. Lobby Session (03) and Transport plugin seam (04) in parallel after 02
3. Native graphs (05–09) in parallel after 02
4. Processors (10–11) later plan after at least one native graph
5. WebRTC plugin (12) after seam + one native graph
6. Example lobby + narrative (13–14) after lobby Session + one native graph; audio lobby Orchestration can start once lobby Session exists
7. User approval that Teams-like and Zoom-like hosts can be built

## Files likely touched

- `packages/flutter_ai_communications_shared` — video types
- `packages/flutter_ai_communications_platform_interface` — new methods default unimplemented
- `packages/flutter_ai_communications` — Communications manager / Session
- per-platform packages — camera graphs and processor hooks
- new `flutter_ai_communications_webrtc` workspace package
- `example/` — lobby subsection + in-session AV + Orchestration keys
- `docs/spec-video-v1.md`, `docs/host-prejoin-narrative.md`, ADRs 0012–0021

## Risks

| Risk | Mitigation |
| --- | --- |
| Dart production frame pump | ADR-0013. Calibration tap off by default |
| Lobby and meeting share a Session object | ADR-0020. stop + start with Session settings |
| Mute-video == Camera-off | ADR-0016. Separate tests |
| Host injects a processor object | ADR-0017. Selectable values only |
| Session knows flutter_webrtc | Sink package only. Ticket 12 tests |
| Audio stream identity changes | Enable-video-later tests; ADR-0004 |
| Host reimplements CameraX | Host plan forbids it; markdown tickets in this repo |

## Definition of done

- Tickets in `.scratch/video-v1-issues/` complete
- Host tickets in `.scratch/video-host-issues/` complete or explicitly deferred
- Fake-platform and public-seam tests pass
- Six-platform receipts for catalog, preview, start, mute-video, Camera-off
  (Linux camera receipt still outstanding)
- Processors work on iOS and Android at minimum; other platforms documented if delayed
- flutter_webrtc sink package attaches without Session knowing WebRTC types
- Example lobby subsection is Orchestration-drivable
- Audio ADR-0003 and ADR-0004 still hold
- No GitHub issues required for this slice unless a human asks

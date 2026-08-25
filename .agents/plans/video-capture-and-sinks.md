# Video Capture, Processors, and Sink Providers Plan

## Goal

Give host apps a Teams/Zoom-class camera stack inside `flutter_ai_communications` without turning Session into a WebRTC client. Cameras, Pre-join preview, Production video path, Mute-video, Camera-off, library-owned Video processors, and attachable Video sinks. First sink is flutter_webrtc. First platforms are iOS, Android, Web, macOS, and Windows.

Parity bar: a host must be able to build both a Teams-like and a Zoom-like product on this API. Missing in-call or lobby capability is a spec bug.

Audio production work in `.agents/plans/production-audio-manager-and-real-device-conformance.md` stays on its own track. Video must not regress one-Session, one audio Capture stream, or ADR-0004 reset identity.

## Gate

Do not treat video as done when a Texture shows a camera. Done means:

- idle camera catalog and Camera preference
- Pre-join preview with processor applied
- Session AV lifecycle including enable-video-later
- Mute-video vs Camera-off vs pause
- native Production video path
- at least one real sink provider (flutter_webrtc) plus a fake sink in tests
- example landing page + in-session AV on the five platforms
- host narrative can be followed without a second camera plugin

Linux and screen share are later plans.

## Required architecture

- One application-scoped Audio manager; at most one live Session.
- Separate Camera Endpoint catalog and Camera preference. No unmatched audio/video Pair.
- Pre-join preview is idle manager state, not a Session.
- Production video path is native: camera → Video processor → Preview Texture + every Video sink.
- Dart Video calibration tap is off by default.
- Session direction is a capability mask. Video attaches and detaches without replacing audio streams.
- Video sinks are providers. This repo does not own PeerConnection or signaling.
- Video processors: none, blur(intensity), replace(bytes or asset). Fallback to none is a warning, not a start failure.

## Work order

### 1. Domain and contracts

Tickets 00–02.

- Glossary terms in `CONTEXT.md`
- ADRs 0012–0017
- `docs/spec-video-v1.md` and this plan
- Shared types: Camera Endpoint, Camera facing, Camera preference, Video Format, Native Video Format, Video processor, sink handle
- Platform interface methods defaulting to unimplemented
- Fake adapter + AudioManager/Session tests for direction, preview, mute-video, Camera-off, enable-video-later, processor selection

Complete when fake-platform tests cover every new Start result and Session control without a physical camera.

### 2. Pre-join preview

Ticket 03.

- `startPreview` / stop on the idle manager
- Preview Texture id
- Processor applies
- Promote into Session without requiring flutter_webrtc

Complete when the example can show a lobby self-view from the fake or a single native platform.

### 3. Video sink provider seam

Ticket 04.

- Attach/detach one or more sinks on Session
- Fake sink receives generation and enabled/muted/off state
- Documented native hook for real sink packages

Complete when tests prove two sinks see one path and detach does not end the Session.

### 4. Native camera graphs

Tickets 05–09, one platform each: iOS, Android, macOS, Windows, Web.

Each ticket delivers catalog, permission, negotiated Video Format, Preview Texture, camera switch, Mute-video black frames, Camera-off hardware stop, and enable-video-later on that platform.

Web uses getUserMedia plus a documented preview surface. Insertable streams or an equivalent processor hook is acceptable if it keeps preview and sinks on one path.

Complete per platform only with public-seam tests plus a real-device or browser receipt. Registration-only tests are not enough.

### 5. Video processors

Tickets 10–11.

- none always works
- blur(intensity) on iOS and Android first, then desktop and web
- replace from bytes or asset path
- unavailable processor → none + structured warning

Complete when lobby and in-session preview show the same effect and sinks receive the processed path.

### 6. flutter_webrtc sink package

Ticket 12.

- Companion workspace package
- Binds Production video path to a MediaStreamTrack / capturer
- Host adds the track to its own PeerConnection
- No signaling in this repo

Complete when the example can attach the sink and a loopback PeerConnection shows the processed preview.

### 7. Example harness and host narrative

Tickets 13–14.

- Landing page: mode, audio picks, camera pick, preview, processor, join
- In-session: mute-audio, mute-video, Camera-off, switch camera, pause, stop
- Marionette keys for the above
- `docs/host-prejoin-narrative.md` kept accurate

## Physical-device matrix

Primary gate on relevant video changes:

- physical iPhone, physical Android, Chrome, macOS, Windows
- first preview after install permission
- front/back or built-in/USB switch
- preview then start promotion
- audio-only start then enable video
- Mute-video vs Camera-off (lens light where the OS exposes it)
- processor none / blur / replace
- twenty preview/start/stop cycles without leaking the camera

Human confirmation of blur quality is allowed. Cadence and Texture liveness should be electronic first.

## Dependency graph

1. Domain + shared types + fake Session contracts (00–02)
2. Pre-join API (03) and sink seam (04) in parallel after 02
3. Native graphs (05–09) in parallel after 02
4. Processors (10–11) after at least one native graph
5. WebRTC sink (12) after sink seam + one native graph
6. Example + narrative (13–14) after preview + one native graph; full platform matrix after 05–09
7. User approval that Teams-like and Zoom-like hosts can be built

## Definition of done

- Tickets in `.scratch/video-v1-issues/` complete
- Fake-platform and public-seam tests pass
- Five-platform receipts for catalog, preview, start, mute-video, Camera-off
- Processors work on iOS and Android at minimum; other platforms documented if delayed
- flutter_webrtc sink package attaches without Session knowing WebRTC types
- Example landing page is Marionette-drivable
- Audio ADR-0003 and ADR-0004 still hold

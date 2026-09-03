# Screen Capture and Send Plan

**Status (2026-09-03):** v1 Session API and native graphs shipped on
Windows, Linux X11, Android, and web. Squash-merged as PR #39 / `588618d`.
iOS/macOS stay fail-closed ([#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)).
Receipts on remaining heads:
[#44](https://github.com/JohnGalt1717/flutter_ai_communications/issues/44).
**Tickets:** `.scratch/screen-v1-issues/`.
**Host narrative:** `docs/host-screen-share-narrative.md`.
**Camera track:** `.agents/plans/video-capture-and-sinks.md` (do not regress).
**Video sink / Transport plugin:** tickets 04 (#46) and 12 (#48) are on `main`.

## Current slice (2026-09-03)

HEAD: `588618d` on `main` (PR #39). Domain, Session contracts, fake adapter,
example Screen send subsection, and native graphs for Windows GDI, Linux
X11, Android MediaProjection, and web `getDisplayMedia` are in tree.

### Done

- Domain: Screen source, All-displays, Screen pick, Screen preview, Share
  frame, Screen motion; ADRs 0019, 0022–0027; `docs/spec-screen-v1.md`
- Session / platform-interface / fake adapter; typed Start results
- Example in-session Screen send + loopback (`screen-share`, `screen-stop`,
  `screen-loopback`, `screen-source-*`)
- Orchestration job: `.agents/workflows/screen-send-orchestration.md`,
  `example/integration_test/native_screen_test.dart`, `/screen-send-proof`
- Windows GDI catalog, thumbs, Share frame, send Texture; JamieDesktop
  `native_screen_test` `skipped=false` (20 cycles, camera+screen, 1920×1080@5)
- Linux X11 catalog + send; Wayland catalog is one system-picker source
- Android MediaProjection + FGS; OS-stop via `MediaProjection.Callback`
- Web `getDisplayMedia` + HtmlElementView; track `ended` is source-gone
- Camera Production video path per platform (do not reuse as a screen graph)
- Video sink seam (#46) and WebrtcVideoSink Send tracks (#48)

### Shipped vs remaining (native)

| Platform | Shipped | Remaining |
| --- | --- | --- |
| Windows | GDI catalog, thumbs, Share frame, send, exclude-self | WGC production, WASAPI Include sound, WGC-border receipt note |
| Linux X11 | catalog + send | thumbs, Share frame, Pulse/PipeWire loopback, receipt |
| Linux Wayland | system-picker catalog | portal ScreenCast + PipeWire |
| Web | system-picker + `getDisplayMedia` | Chrome/Edge receipt (#44) |
| Android | MediaProjection Texture | AudioPlaybackCapture, SM-class receipt (#44) |
| macOS | ScreenCaptureKit catalog, thumbs, Share frame, send | `native_screen_test` `skipped=false` |
| iOS | system-picker + ReplayKit Broadcast | physical Broadcast receipt (#44) |

### Not in this slice

- Screen ticket 12: Transport second send path (camera + screen). Fake
  coverage does not wait on flutter_webrtc; that package is on `main` (#48).
- Blur / replace processors
- Linux camera physical receipt (camera track)

## Goal

Give host apps a Teams-class screen send inside
`flutter_ai_communications` without a library picker, without mixing
system audio into the mic Capture stream, and without replacing camera
send. First platforms are Windows, macOS, Linux, web, Android, and iOS.

Parity bar: a host must be able to build a Teams-like picker on
enumerable platforms and fall through to the OS picker elsewhere, using
one Session API. The example in-session share control is the
Orchestration e2e path.

## Gate

Do not treat screen send as done when a Texture shows a desktop. Done
means:

- idle `screenSources()` metadata (system-picker source where required)
- meeting Session: Screen pick thumbs, indicate Share frame, start/stop
- All-displays stitch on enumerable desktop
- camera send + screen send together, two local Video surfaces
- `includeSystemAudio` off by default, live toggle, not on Capture stream
- Screen motion 5 fps / 30 fps, send cap 1920×1080
- lobby and `start()` never auto-share; permission at pick or share
- source gone does not end the Session
- example picker + Orchestration on the six platforms
- fake adapter covers every new Start result and Session control

## Required architecture

- One Session. Screen send is start/stop Explicit selection (ADR-0024).
- Production video path per send source (ADR-0013). Screen path is native.
- Screen preview is pick-scoped, not that path (ADR-0025).
- Share frame is library-owned native chrome.
- System audio rides screen send (ADR-0023).
- Transport plugin pulls local camera video, local screen video, optional
  system audio, and mic Capture stream as today. Host owns signaling and
  tiles.
- Missing/denied screen does not fail the Session.

## Public API sketch (host-facing)

Names follow `CONTEXT.md`. Exact types land in ticket 01.

```text
manager.screenSources()                    // snapshot; idle or live
session.screenSourceCatalog                // live during pick and send

session.beginScreenPick() / endScreenPick()
session.screenPreview(id)                  // Screen preview handle or null
session.indicateScreenSource(id | null)    // Share frame; no send

result = await session.startScreenShare(
  id,
  includeSystemAudio: false,
  cursor: true,
  motion: false,
)
session.stopScreenShare()                  // replace = startScreenShare again
session.setIncludeSystemAudio(bool)
session.setScreenMotion(bool)
session.setScreenCursor(bool)
session.screenSurface                      // local send Video surface
session.isScreenSending
```

Lobby: `beginScreenPick` and `startScreenShare` return typed failure.
`start()` / Session settings never start screen send.

`startScreenShare` on a system-picker Screen source presents the OS picker,
then binds whatever the OS returns.

## Native backends

| Platform | Catalog | Thumbs | Share frame | Production | System audio |
| --- | --- | --- | --- | --- | --- |
| Windows | WGC items + EnumDisplayMonitors / EnumWindows; synthesize All-displays | DWM/PrintWindow, **not** WGC | Layered overlay | WGC `CreateForMonitor` / `CreateForWindow`; stitch for All-displays | WASAPI loopback |
| macOS | ScreenCaptureKit displays + windows; synthesize All-displays | SCK thumbs during pick | Overlay | `SCStream` per source; stitch All-displays | `capturesAudio` |
| Linux X11 | RandR + `_NET_CLIENT_LIST`; synthesize All-displays (root) | XComposite / XGetImage | Overlay | XComposite / XShm | Pulse/PipeWire monitor |
| Linux Wayland | One system-picker source | none | no-op | xdg-desktop-portal ScreenCast + PipeWire | PipeWire loopback (separate) |
| Web | One system-picker source | none | no-op | `getDisplayMedia` | browser checkbox / `systemAudio` hint |
| Android | One system-picker source | none | no-op | MediaProjection | AudioPlaybackCapture |
| iOS | One system-picker source | none | no-op | ReplayKit Broadcast (full device) or SCK picker | ReplayKit app audio |

Exclude the host Flutter windows from display and All-displays capture
(`WDA_EXCLUDEFROMCAPTURE` / SCK `excludingApplications` / equivalent).

## Work order

### 1. Domain and contracts

Tickets 00–02.

- Glossary and ADRs (00 done with this plan)
- Shared types: Screen source, kind (display, window, allDisplays,
  systemPicker), bounds, Screen motion
- Platform interface methods defaulting to unimplemented
- Fake adapter + Communications manager / Session tests for every
  decision in the spec

Complete when fake-platform tests cover pick, indicate, start/stop/replace,
lobby fail-closed, join-does-not-share, permission timing, system audio
isolation from Capture stream, and source-gone status without a real
display.

### 2. Enumerable desktop graphs

Tickets 04–06 (Windows, macOS, Linux X11).

- Catalog + live stream
- Screen pick thumbs without production capture chrome
- Share frame
- Production path, All-displays stitch, cursor, exclude-self
- System audio loopback

Complete per platform with public-seam tests plus a real-device receipt.
Windows receipt must include thumbs without yellow borders on every window.

### 3. OS-picker platforms

Tickets 06 (Wayland), 07–09 (web, Android, iOS).

- Catalog is one system-picker source
- `startScreenShare` presents the OS picker
- Thumbs and indicate are no-ops
- Production path + system audio where the OS allows

Complete per platform with a receipt of OS picker → local Video surface →
stop. iOS full-device share uses the Broadcast upload extension.

### 4. Example harness and Orchestration

Tickets 10–11.

- In-session Share control after Join
- Host picker grid from Screen previews; click indicates; Share calls
  `startScreenShare`
- Include sound, Screen motion, cursor toggles
- Stop share
- Orchestration keys; e2e drives join then pick then share then stop
- `docs/host-screen-share-narrative.md` kept accurate

### 5. Transport plugin second path

Ticket 12.

- Fake Transport sees camera Video surface and screen Video surface
  independently, plus optional system audio
- Real flutter_webrtc binding may share the video ticket 12 package; do
  not block fake coverage on that package

Complete when tests prove camera-off does not stop screen send and Mute
does not silence system audio.

## Ticket map

| # | Title | Blocked by | Status |
| --- | --- | --- | --- |
| 00 | Spec, glossary, ADRs | — | done |
| 01 | Shared screen types | 00 | done |
| 02 | Session and platform-interface contracts | 01 | done |
| 03 | Fake Screen pick, indicate, catalog stream | 02 | done |
| 04 | Windows screen graph | 02 | in progress (GDI; WGC/WASAPI later) |
| 05 | macOS screen graph | 02 | not started ([#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)) |
| 06 | Linux screen graph (X11 + Wayland) | 02 | in progress (X11 send; thumbs/portal later) |
| 07 | Web getDisplayMedia | 02 | in progress (graph shipped; Chrome receipt on #44) |
| 08 | Android MediaProjection | 02 | in progress (graph shipped; AudioPlaybackCapture + receipt later) |
| 09 | iOS ReplayKit / Broadcast | 02 | not started ([#43](https://github.com/JohnGalt1717/flutter_ai_communications/issues/43)) |
| 10 | Example in-session picker | 03 and one native graph | done |
| 11 | Host narrative + Orchestration keys | 10 | in progress ([#44](https://github.com/JohnGalt1717/flutter_ai_communications/issues/44); Windows automated receipt collected) |
| 12 | Transport second send path | 02 | not started (camera WebRTC Send track is #48; screen path still open) |

Frontier: 05/09 (#43) need a Mac. 04/06 remaining native gaps. 11 receipts on #44. 12 attaches screen send as a second Send track on the WebRTC plugin.

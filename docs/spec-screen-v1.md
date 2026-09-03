# Spec: Communications screen send v1

## Problem Statement

Hosts need Teams-class screen send on the same Session as camera send:
enumerate displays and windows, host-built picker with live thumbs and a
Share frame on the real window, then one Production video path for screen
that can run beside camera. Video v1 specified the Screen source catalog
and left native capture later. This slice ships capture.

## Solution

The Communications manager enumerates Screen sources. A live meeting
Session starts and stops screen send. The host draws the picker. The
library draws the Share frame on the real display or window and, during
Screen pick, yields Screen previews (thumbs). Camera send and screen send
are two Production video paths, two local Video surfaces. One local screen
send at a time.

Kinds: display, window, All-displays. Platforms omit kinds they cannot
offer. Where the OS refuses a catalog (web, Android, iOS, Linux Wayland),
the catalog is one system-picker Screen source; `startScreenShare` presents
the OS picker. Browser tabs are windows.

There is no Screen preference. `start()` never auto-shares. Lobby Session
lists metadata only; Screen pick and startScreenShare are typed failures
there. Join copies Session settings without starting screen send.

Screen permission is requested at `beginScreenPick` if the host opens
thumbs, otherwise at `startScreenShare`. Denial does not end the Session.
System audio rides screen send (`includeSystemAudio`), never the mic
Capture stream. Mute still silences only the mic.

Capture is the source’s physical pixels. Requested send size copies Teams
VBSS: that raster capped at 1920×1080 keeping aspect ratio, 5 fps default,
30 fps when Screen motion is on. Video processor on the screen path is
none.

The first host is `example/`. The in-session share picker is the
Orchestration e2e path for this slice. Native graphs stay in the federated
packages.

## User Stories

1. As a host, I want `screenSources()` metadata while idle or in lobby, so
   I can tell the user they will be able to share without capturing.
2. As a user in a meeting, I want a host picker of displays, windows, and
   All-displays with live thumbs, so I know what I am about to share.
3. As a user, I want a red Share frame on the real window or display when
   I point at it in the picker, before anything is sent, like Teams.
4. As a user, I want Share to start from that pick on the live Session, and
   Stop to end screen send, without ending the meeting or Camera-off.
5. As a user, I want camera tile and shared content at the same time.
6. As a user, I want Include sound and Optimize (Screen motion) as Teams
   does, togglable before and during send.
7. As a host on web/Android/iOS/Wayland, I want the same Session calls; the
   OS picker is the UI.
8. As a Transport plugin, I want a second local video path (and optional
   system audio) from the Session, without mixing it into mic capture.
9. As a developer, I want the example in-session picker to be the
   Orchestration path on iOS, Android, web, macOS, Windows, and Linux.

## Implementation Decisions

- Glossary: `CONTEXT.md`. ADRs 0013, 0018–0019, 0022–0027.
- Public API sketch and native backends: `.agents/plans/screen-capture-and-send.md`.
- Host picker narrative: `docs/host-screen-share-narrative.md`.
- Markdown tickets: `.scratch/screen-v1-issues/`. No GitHub issues unless a
  human asks.
- All-displays is a library stitch (ADR-0022). Losing one display rebuilds;
  losing all ends screen send, not the Session.
- Screen previews must not use a capture API that brands every window as
  shared (Windows Graphics Capture yellow border). Production send may.
- Share frame is library red. Suppress the OS capture border where the API
  allows.
- Display and All-displays capture exclude the host’s own Flutter windows.
- Cursor is on by default; live toggle.
- `includeSystemAudio` default off. Live `setIncludeSystemAudio`. Failure
  to loopback is a status warning, share stays video-only.
- DRM / FLAG_SECURE / HDCP: black frames, status warning, share stays up.
- Minimized / cloaked windows stay in the catalog; Screen preview may be
  empty; startScreenShare is legal.
- A second `startScreenShare` replaces the source. No Pause. No Mute-video
  analog for screen.
- Camera-off, Mute-video, and Camera preview do not start or stop screen
  send. `startScreenShare` is legal while Camera preview is running.
- Source gone / permission pulled: Session stays, screen send stops, Share
  frame clears, Session status reports why.
- Video v1 camera graphs and lobby Session are unchanged.

## Testing Decisions

- Fake platform adapter covers: catalog kinds, system-picker source,
  Screen pick thumbs, indicate without send, start/stop/replace, lobby
  fail-closed, join does not auto-share, permission at pick vs share,
  includeSystemAudio not on Capture stream, Camera-off independence,
  source-gone status.
- Example in-session picker + Orchestration is the UI-to-success path.
  Keys on the meeting share controls are the e2e handles.
- Physical receipts per platform: permission prompt at pick or share,
  thumbs (where enumerated), Share frame (where enumerated), start send
  with local Video surface, camera+screen together, Include sound where
  the OS can loopback, stop, twenty start/stop cycles without leaking
  capture. Loopback identity is not native proof.
- Windows receipt must show picker thumbs *without* a yellow WGC border
  on every window.

## Out of Scope

- Application as a Screen source kind (all windows of a process).
- Region / portion capture as a catalog kind.
- Pause / freeze-last-frame.
- Remote control, annotation, PowerPoint Live, Excel Live, whiteboard,
  file stages, second camera as content, computer-audio-only share.
- Zoom simultaneous multi-share. One local screen send.
- Presenter-mode compositing (host tile layout).
- Screen preference list. Auto-share on Join.
- Library-owned picker chrome.
- Blur/replace on the screen path.
- 4K send; the wire cap is 1920×1080 (ADR-0027).
- PeerConnection, signaling, roster, or meeting grid in Session.

# Spec: Communications Audio v1

## Problem Statement

Scribe’s live voice path is a tangle of `record`, `audio_session`, SoLoud, native PCM players, Hive device priority, Isolation dialogs, and SignalR. It clips first words, lies to the visualizer, breaks on iOS route changes, and cannot be reused as a Teams/Zoom-class Audio manager. Hosts need one deep Session that streams bytes, hides platform resets, and leaves Transport and preference to the app.

## Solution

A federated Flutter plugin. The host constructs an Audio manager, calls `start()` with Formats and an optional preference, and attaches a Transport to the Session’s capture and play edges. The library enumerates Endpoints, pairs hardware, runs the communications channel, applies sound floor and barge-in, and emits Isolation and Coverage events. v1 is iOS, Android, and Web.

## User Stories

1. As a host app, I want one Audio manager object, so that I do not wire capture, render, and devices myself.
2. As a host app, I want `start()` to request the microphone and wait, so that I do not guess permission timing.
3. As a host app, I want `start()` to return a typed Start result, so that denied / restricted / unavailable / already-active / failed are not exceptions.
4. As a host app, I want at most one live Session, so that two comms graphs cannot fight.
5. As a host app, I want to pass preference only at `start()`, so that my saved tree stays mine.
6. As a user in a Session, I want to pick another Endpoint or sound floor, so that I can fix this call without rewriting preference.
7. As a host app, I want handset and speakerphone as Endpoints, so that my picker is one list.
8. As a user who selects AirPods capture, I want render to follow, so that I am not on speaker while wearing them.
9. As a user who overrides render, I want that override kept until the Endpoint disappears, so that a split setup stays split.
10. As a user who pulls AirPods out, I want speakerphone, so that I am not silently on a dead headset.
11. As a user who puts AirPods back in, I want the OS-forced Pair applied and broadcast, so that the picker matches what I hear.
12. As a host Transport, I want PCM (or G.711 / Opus) byte chunks, so that SignalR and WebRTC are not library types.
13. As a visualizer, I want the same capture bytes as the Transport, so that the VOD matches the wire.
14. As a remote VAD, I want silence frames while muted, so that I do not stall when the user mutes.
15. As a user, I want mute to keep playback, so that I can still hear the agent.
16. As a user, I want pause to stop both sides without destroying the Session, so that I can resume without a new SignalR connection.
17. As a Scribe hub, I want native resets to keep the same Session streams, so that I do not lose `connectionId`.
18. As an OpenAI Realtime host, I want PCM16 mono 24 kHz by default, so that I do not transcode in the app.
19. As a Grok host, I want the documented PCM rates plus µ-law, A-law, and Opus, so that I can match the Grok session.
20. As a host, I want capture Format and playback Format to differ, so that I can send 24 kHz and play 16 kHz.
21. As a user in a lounge, I want an adaptive sound floor, so that background voices are not treated as me.
22. As a host, I want to pass a fixed sound floor, so that I can lock a known-bad car head unit.
23. As a user in a GM car that fell back to HFP, I want the floor to rise, so that the head unit’s missing cancellation is backfilled.
24. As a user who starts speaking over the agent, I want playback flushed and my first word kept, so that barge-in feels like Copilot.
25. As a host, I want a remote-VAD barge-in policy, so that I can leave interrupt to OpenAI.
26. As an iOS user with noise cancelling on, I want an Isolation event when Voice Isolation is off, so that Scribe can show its own copy.
27. As an iOS user, I want the library to open the system Isolation UI after a hold, so that the sheet actually appears.
28. As an iOS user who declines Isolation, I want the Session to continue with a raised floor, so that I am not blocked.
29. As a web user, I want `start()` to block on `getUserMedia`, so that device labels exist before the catalog is used.
30. As a web host, I want documented limits (no Isolation, no handset), so that I do not treat them as bugs.
31. As a host, I want Coverage from my hub ping plus audio-path death, so that I can park without `connectivity_plus` RTT.
32. As a user who gets a phone call, I want the Session to pause and be resumable, so that the agent does not fight the OS.
33. As a logger, I want `package:logging`, so that I can attach ISpect the way Scribe already does.
34. As a tester, I want fixture WAV/PCM in and bytes/events out, so that floor, barge-in, and mute are real tests.
35. As a developer, I want a Marionette example that looks like AI voice, so that I can drive the UI to success.
36. As a future desktop host, I want tickets for macOS, Windows, and Linux, so that the plan is complete before v1 ships.

## Implementation Decisions

- Pub workspace, federated plugin: app package, `platform_interface`, `shared`, `ios`, `android`, `web`. Desktop packages later. No Melos. Current Flutter `pubspec` / workspace / analysis conventions.
- Public module is `AudioManager` + one `Session`. Catalog works while idle.
- `StartResult` is a sealed set: `ready`, `denied`, `restricted`, `unavailable`, `alreadyActive`, `failed`. Isolation is never a start failure.
- Preference is a `start()` argument only. Session select/setSoundFloor are ephemeral.
- One capture stream; mute = silence frames; pause parks both sides; stop ends the Session.
- Internal graph is PCM16 mono at a working rate (48 kHz preferred); transcode at the edges to the OpenAI+Grok Format set. Default both edges: PCM16 LE mono 24 kHz.
- Pair by shared hardware identity. Handset and speakerphone are catalog Endpoints on iOS/Android. AirPods-out → speakerphone.
- iOS reset is a full native teardown unless in-place switch is proven. Same Session, same broadcast streams; silence during teardown (ADR-0004).
- Isolation: detect + `openIsolationSettings()` + events. Host owns strings (ADR-0005).
- Barge-in default is local flush + ~200–300 ms preroll; `BargeInPolicy.remoteVad` opts out.
- `CoverageSource` is an injected stream (`ok` / `degraded` / `lost` + reason). Default: airplane / route death. No `connectivity_plus` RTT. `lost` parks like pause.
- Phone-call audio focus emits interrupted and auto-pauses; host or OS-end resumes.
- Logging is `package:logging` only. No ISpect, no `record` / `soloud` / `flutter_recorder`.
- Permissions: first-party OS APIs; `permission_handler` only if a platform cannot request the mic.
- No user-facing library strings. Example is the AI-looking Marionette harness, not a SignalR demo.

## Testing Decisions

- Test external behaviour at `AudioManager`, `Session`, `CoverageSource`, and the platform interface. Do not assert private native steps.
- Shared DSP (floor, barge-in, pairing, transcode) is tested with fixture PCM and a fake platform adapter.
- Platform tickets add integration coverage: permission, enum, route class, Isolation detect, reset that does not end capture subscriptions.
- Example + Marionette is the UI-to-success path on iOS, Android, and web.
- A good test names a capability (“muted Session still emits silence frames at 24 kHz”) and uses fixture or OS-observable outcomes, not mocks of the implementation.

## Out of Scope

- Device-order preference persistence and UI (later package; hosts keep Hive).
- Camera, zoom, background blur.
- Shipping SignalR or WebRTC.
- ISpect as a dependency.
- User-facing localization in the library.
- Desktop implementation in v1 (tickets only).
- Matching Scribe’s public type names.

## Further Notes

Glossary: `CONTEXT.md`. Decisions: `docs/adr/0001`–`0005`. Agent rules: `AGENTS.md`.

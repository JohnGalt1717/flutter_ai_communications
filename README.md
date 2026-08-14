# flutter_ai_communications

A Flutter **Audio manager** for live duplex communications — the audio stack you would need to build a Teams- or Zoom-class client, starting with AI voice.

The host app owns the Transport (SignalR, WebRTC, or anything else), device-order preference, and product UI. This package owns capture, render, pairing, sound floor, barge-in, mute, pause, and coverage events.

**v1 platforms:** iOS, Android, Web.
**Later:** macOS, Windows, then Linux.
**Later still:** camera.
**Out of scope:** device-priority lists (apps implement that).

This repository is being built from a grilled spec ([#1](https://github.com/JohnGalt1717/flutter_ai_communications/issues/1)). The public API below is the contract. Desktop adapters are later tickets ([#13](https://github.com/JohnGalt1717/flutter_ai_communications/issues/13)–[#15](https://github.com/JohnGalt1717/flutter_ai_communications/issues/15)).

## What you get

- Enumerate capture and render **Endpoints**, including **handset** and **speakerphone** as separate items on iOS and Android
- Automatic **Pair** follow (AirPods in → both sides; AirPods out → speakerphone) with a session-only override
- Communications-channel init, AEC / NS / AGC, iOS **Isolation** detect + open-settings
- Adaptive **sound floor**, or a fixed floor the host passes in
- **Barge-in** that flushes playback and keeps a preroll of the first word (or remote-VAD-only if you opt in)
- **Mute** (playback continues, Transport gets silence) and **Pause** (both sides stop, Session stays)
- One **capture stream** — the same bytes go to the Transport, a visualizer, and a VOD tap
- **Coverage** events from an injected source plus audio-path faults
- `package:logging` you can attach to ISpect or anything else

## Install

Once the workspace packages are published (or via path):

```yaml
dependencies:
  flutter_ai_communications: ^0.1.0
```

The federated iOS / Android / Web implementations are pulled in by the app package. Declare microphone usage in the host app:

- **iOS:** `NSMicrophoneUsageDescription` (and Bluetooth usage strings if you route to headsets)
- **Android:** `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`
- **Web:** served over HTTPS / localhost so `getUserMedia` can run

## Quick start

```dart
final manager = AudioManager(
  coverageSource: myCoverageSource, // optional; default reports airplane / path death
  logger: Logger('comms'),          // optional; attach to ISpect like Scribe does
);

final result = await manager.start(
  captureFormat: AudioFormat.pcm16le(sampleRate: 24000),
  playbackFormat: AudioFormat.pcm16le(sampleRate: 24000),
  noiseCancelling: true,
  bargeIn: BargeInPolicy.local, // or BargeInPolicy.remoteVad
  preference: SessionPreference(
    captureId: savedCaptureId,
    renderId: savedRenderId,
    soundFloor: null, // adaptive; pass a value to lock a fixed floor
  ),
);

switch (result) {
  case StartReady(:final session):
    session.isolation.listen(showIsolationPromptIfNeeded);
    session.coverage.listen(parkOrResumeTransport);
    session.capture.listen(transport.send); // same bytes a visualizer should use
    transport.incoming.listen(session.play);
  case StartDenied():
    // host UI: mic permission
  case StartRestricted():
  case StartUnavailable():
  case StartAlreadyActive():
  case StartFailed(:final reason):
    // host UI
}

// Mid-session picks are ephemeral — they do not write your saved preference.
await session.selectRender(speakerphone);
await session.setSoundFloor(0.4);
await session.mute();
await session.pause();
await session.resume();
await session.stop();
```

`start()` requests microphone permission and **waits** for the OS. Isolation is never a start failure: if Voice Isolation is off, you get a ready Session plus an Isolation event.

## Formats

Capture and playback Formats are independent.

| Format | OpenAI Realtime | Grok Speech-to-Speech |
| --- | --- | --- |
| PCM16 LE mono | 24 kHz only | 8 / 16 / 22.05 / 24 / 32 / 44.1 / 48 kHz |
| G.711 µ-law / A-law | yes | 8 kHz |
| Opus | no | 24 kHz mono packets |

Default when omitted: PCM16 LE mono 24 kHz on both edges.

## Host vs library

| Library | Host |
| --- | --- |
| Session lifecycle | Transport (SignalR / WebRTC / …) |
| Endpoint catalog + Pair | Device-order preference persistence |
| Comms channel, AEC/NS/AGC | Isolation dialog copy |
| Sound floor, barge-in | Offline policy / navigation |
| Mute / pause / coverage events | ISpect (or other) log sink |

## Example

`example/` is an AI-voice debug harness (Marionette-friendly): device list, start/mute/pause, Isolation event surface, fixture loopback. It is not a SignalR client.

## Agents

Working in this repo with an agent? Start at [`AGENTS.md`](./AGENTS.md). Claude Code should start at [`CLAUDE.md`](./CLAUDE.md), which loads the same guide.

## License

See `LICENSE`.

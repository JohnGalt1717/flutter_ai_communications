# Communications Audio

The domain of a live duplex communications Session: capture, render, pairing, sound floor, barge-in, and coverage. Transport, device-order preference, and product UI live in the host app.

## Language

**Session**:
The live duplex communications context an app holds. It owns capture, render, pairing, sound floor, barge-in, mute, pause, and coverage events.
_Avoid_: engine, client, call, chat

**Audio manager**:
The public module that creates and drives a Session. The host attaches a Transport and optional Coverage source to it.
_Avoid_: engine, plugin, recorder

**Endpoint**:
One capture or render device the OS exposes, with the richest metadata the platform can give.
_Avoid_: device (alone), route (alone), input, output (as the type name)

**Pair**:
A linked capture Endpoint and render Endpoint that should move together unless the user overrides one side.
_Avoid_: match, group, set

**Route class**:
The communications role of an Endpoint: handset, speakerphone, bluetooth, wired, or car.
_Avoid_: category, type, kind

**Sound floor**:
The amplitude below which capture is treated as non-voice. May be adaptive or a host-set fixed value.
_Avoid_: noise floor, threshold, gate (the gate is the action; the floor is the value)

**Barge-in**:
User speech that interrupts playback without clipping the first word.
_Avoid_: interrupt, duck, cutoff

**Isolation**:
The iOS microphone isolation / voice-isolation mode the Session can detect. The host owns the prompt; the Session can open the system Isolation UI when asked.
_Avoid_: ANC, noise cancellation (headset hardware or OS AEC/NS)

**Coverage**:
Whether the Session can usefully continue, combining audio-path health with host-reported connectivity.
_Avoid_: offline, bad connection, airplane mode (those are Coverage reasons, not Coverage)

**Transport**:
Whatever the host uses to move PCM after this library — SignalR, WebRTC, or anything else.
_Avoid_: websocket, hub, connection

**Format**:
The encoding, sample rate, and channel layout of a Session edge — capture out or playback in. Capture and playback Formats may differ.
_Avoid_: codec (alone), rate (alone)

**Mute**:
A Session mode where the user's voice is not sent, playback continues, and the Transport still receives silence frames so remote VAD does not stall.
_Avoid_: send gate, ghost recording

**Pause**:
A Session mode where capture and playback both stop, and the Session object is kept.
_Avoid_: stop (that ends the Session), hold (internal Isolation trick)

**Noise cancelling**:
A Session option that asks the platform for AEC/NS/AGC and, on iOS, Isolation. When Isolation is off or undetectable, the Session emits Isolation events and raises the sound floor.
_Avoid_: ANC (headset hardware)

**Isolation event**:
A Session signal that Isolation is required, still off, or unavailable. The host owns every prompt string and dialog.
_Avoid_: Isolation dialog (that is host UI)

**Ephemeral selection**:
A capture Endpoint, render Endpoint, or sound floor chosen on a live Session. It does not change the preference the host passed to start.
_Avoid_: preference (that is host-owned and passed at start)

**Capture stream**:
The Session byte stream the Transport, visualizer, and VOD all subscribe to — floor-applied, mute as silence, capture Format. There is no second “pretty” tap.
_Avoid_: listen (as a distinct stream), visualizer stream (as a distinct stream)

**Start result**:
The outcome of starting a Session — success with a Session, or a typed failure such as missing permission.
_Avoid_: exception (for expected start failures)

**Barge-in policy**:
Whether barge-in is detected locally (flush playback, keep preroll) or left to the remote VAD.
_Avoid_: interrupt mode

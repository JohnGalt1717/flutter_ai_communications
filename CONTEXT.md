# Communications Audio

The domain of a communications Session: capture, render, pairing, Endpoint preference enforcement, sound floor, barge-in, and coverage. Transport, preference persistence, and product UI live in the host app.

## Language

**Session**:
The live capture-only, playback-only, or duplex communications context an app holds. It owns capture, render, pairing, sound floor, barge-in, mute, pause, and coverage events.
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

**Acoustic profile**:
The Audio manager's evidence-backed description of an Endpoint's microphone placement and available echo/noise processing, derived from native capabilities and, when necessary, a known-Endpoint registry.
_Avoid_: known device, brand rule, ANC device

**Baseline sound floor**:
The library-owned starting Sound floor policy selected from an Endpoint's Acoustic profile before adaptive measurement or an explicit user override is applied.
_Avoid_: default noise floor, device matrix

**Capture processor**:
A Session-selected policy that transforms captured frames before the single Capture stream: adaptive floor, profile-scaled floor, fixed floor, or pass-through.
_Avoid_: noise-floor mode, gate type, audio flow

**Profile confidence**:
How strongly an Acoustic profile is supported, from verified native capabilities through a known-profile match down to Route-class fallback.
_Avoid_: score, certainty

**Known-profile registry**:
The shared table of narrowly matched Endpoint family and model aliases used only when native capabilities are insufficient.
_Avoid_: device matrix, brand list, ANC list

**Barge-in**:
User speech that interrupts playback without clipping the first word.
_Avoid_: interrupt, duck, cutoff

**Isolation**:
The iOS microphone isolation / voice-isolation mode the Session can detect while noise cancelling is on. Automatic Mic Mode may use Isolation on the handset and Standard on speakerphone. The host owns the prompt; the Session can open the system Isolation UI when asked. If Isolation stays off or is unavailable, the Session raises the Sound floor.
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

**Endpoint preference**:
The host-persisted ordered list of enabled Endpoints that the Audio manager continuously resolves from most to least preferred. A host list fills capture and render independently, so a desktop webcam and a USB render Endpoint may outrank AirPods. An empty list uses platform-default complete Pairs. Persistence and editing belong to the host; live resolution and promotion belong to the Audio manager.
_Avoid_: device order, default device

**Explicit selection**:
An Endpoint selected for the current Session that temporarily suspends Endpoint preference resolution while it remains available. It expires when the Endpoint disappears or the Session ends.
_Avoid_: sticky preference, saved selection

**Desired Pair**:
The Pair selected by an Explicit selection or Endpoint preference and treated as authoritative by the Audio manager.
_Avoid_: requested route, target device

**Applied Pair**:
The Pair most recently sent to the platform for native selection.
_Avoid_: selected device, requested route

**Observed Pair**:
The Pair the platform reports is actually carrying capture and render audio.
_Avoid_: OS preference, current device

**Route convergence**:
The process of making the Observed Pair match the Desired Pair after start, reset, interruption, Endpoint change, or unwanted OS rerouting.
_Avoid_: route restore, route workaround

**Session direction**:
The active edges of a Session: capture-only, playback-only, or duplex.
_Avoid_: flow type, recorder mode, player mode

**Session purpose**:
A host-provided identifier describing which product operation owns the one live Session, used to diagnose and present an already-active failure.
_Avoid_: audio mode, feature stack

**Native Format**:
The Format a platform audio graph actually accepts after negotiation, which may differ from a Session edge Format and require conversion.
_Avoid_: requested format, backend format

**Format negotiation**:
The selection of a verified Native Format from Endpoint capabilities, preferring an exact Session edge Format and otherwise choosing the best conversion source without relying on failure-first probing when capabilities are available.
_Avoid_: format fallback, retry rate

**Conversion path**:
How a Session edge Format is related to the Native Format: identity, a single Dart converter, or a verified platform converter. Never two converters on the same edge.
_Avoid_: transcoder chain, resample mode

**Session status**:
The structured current readiness or failure state, including success, warning, or error severity, that a host maps to product-specific UI.
_Avoid_: error string, log state

**Capture stream**:
The Session byte stream the Transport, visualizer, and VOD all subscribe to — floor-applied, mute as silence, capture Format. There is no second “pretty” tap.
_Avoid_: listen (as a distinct stream), visualizer stream (as a distinct stream)

**Start result**:
The outcome of starting a Session — success with a Session, or a typed failure such as missing permission.
_Avoid_: exception (for expected start failures)

**Barge-in policy**:
Whether barge-in is detected locally (flush playback, keep preroll) or left to the remote VAD.
_Avoid_: interrupt mode

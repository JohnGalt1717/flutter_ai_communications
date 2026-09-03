# Communications

The domain of a communications Session: capture, render, pairing, cameras, screen share, Endpoint preference, Camera preference, sound floor, barge-in, coverage, and in-call Camera preview. The host owns signaling, preference persistence, tile layout, and product UI. A Transport plugin (or host-pumped Transport) moves media on the wire. Lobby is a Session whose attachments are diagnostic; join destroys it and starts a new Session.

## Language

**Session**:
The live communications context an app holds. Any combination of audio send, audio playback, camera send, screen send, and inbound video is valid, including video-only and screen-share-only. At most one Session exists at a time. Lobby is a Session with no Transport plugin; meeting is a Session with a Transport plugin. The host stops the lobby Session and starts a new meeting Session, optionally passing Session settings copied from the old one; they are not the same object.
_Avoid_: engine, client, call, chat, Setup

**Communications manager**:
The public module that creates and drives at most one Session and at most one Camera preview. The host attaches signaling, a Transport plugin or other Transport, and optional Coverage source to the Session.
_Avoid_: Audio manager, engine, plugin (the manager is not a plugin), recorder

**Endpoint**:
One capture or render audio device the OS exposes, with the richest metadata the platform can give. Missing fields are null and unused; the catalog does not shrink to a lowest-common-denominator record.
_Avoid_: device (alone), route (alone), input, output (as the type name), camera (that is Camera Endpoint)

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
The Communications manager's evidence-backed description of an Endpoint's microphone placement and available echo/noise processing, derived from native capabilities and, when necessary, a known-Endpoint registry.
_Avoid_: known device, brand rule, ANC device

**Hardware noise processing**:
Whether an Endpoint's own hardware already suppresses noise on capture, recorded per known-profile row from manufacturer evidence. It lowers a headset Baseline; it is not Isolation and not Session noise cancelling.
_Avoid_: ANC (as the type name), noise cancellation (as Isolation or OS AEC/NS)

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
The shared, file-loaded table of researched advertised-name aliases, Acoustic family, and Hardware noise processing, used when native capabilities are insufficient.
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
Whatever moves media between Session edges and the network — a host-pumped PCM path or a Transport plugin. Signaling stays host-owned.
_Avoid_: websocket, hub, connection, PeerConnection (that lives inside a Transport plugin)

**Transport plugin**:
A companion package that binds Session edges to a wire protocol. First is WebRTC (it owns PeerConnection and RTP); later WebTransport and others. It takes local audio and video from the Session, delivers inbound audio into Session playback, and yields one Video surface per inbound video stream. It does not own signaling, roster, chat, or tile layout. It attaches as a Video sink; it is not itself that type.
_Avoid_: Video sink (the Session attachment), Transport (the movement of media, not the package)

**Format**:
The encoding, sample rate, and channel layout of a Session edge — capture out or playback in. Capture and playback Formats may differ.
_Avoid_: codec (alone), rate (alone)

**Mute**:
A Session mode where the user's voice is not sent, playback continues, and the Transport still receives silence frames so remote VAD does not stall. The Session is not ended. In-call camera settings do not Mute; audio device changes are a live switch with no audio preview.
_Avoid_: send gate, ghost recording, stop (that ends the Session)

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
A capture Endpoint, render Endpoint, Camera Endpoint, Screen source, or sound floor chosen on a live Session. It does not change the preference the host persisted.
_Avoid_: preference (that is host-owned)

**Endpoint preference**:
The host-persisted ordered list of enabled Endpoints that the Communications manager continuously resolves from most to least preferred. A host list fills capture and render independently, so a desktop webcam and a USB render Endpoint may outrank AirPods. An empty list uses platform-default complete Pairs. Persistence and editing belong to the host; live resolution and promotion belong to the Communications manager.
_Avoid_: device order, default device

**Camera preference**:
The host-persisted ordered list of enabled Camera Endpoints that the Communications manager continuously resolves from most to least preferred. Independent of Endpoint preference; there is no audio/video Pair. An empty list uses facing and other metadata when present, then the first catalog entry. Persistence belongs to the host; live resolution belongs to the manager. In-session camera picks are Explicit selection and do not write this list.
_Avoid_: device order, default camera, AV preference

**Explicit selection**:
An Endpoint, Camera Endpoint, or Screen source selected for the current Session that temporarily suspends preference resolution for that side while it remains available. It expires when the device disappears or the Session ends.
_Avoid_: sticky preference, saved selection

**Desired Pair**:
The Pair selected by an Explicit selection or Endpoint preference and treated as authoritative by the Communications manager.
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
The active edges of a Session, independently combinable: audio send, audio playback, camera send, screen send, inbound video.
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
The Session byte stream — floor-applied, mute as silence, capture Format. Transport plugin, visualizer, VOD, and Test record subscribe to it. There is no second “pretty” tap. Camera preview has no Capture stream.
_Avoid_: listen (as a distinct stream), visualizer stream (as a distinct stream)

**Start result**:
The outcome of starting a Session or a Camera preview — success, or typed failure. Expected microphone permission failures when audio capture was requested are values, not exceptions. Missing camera, camera permission denied, or no matching Video Format does not fail start(); Session status reports that video is not running and why. The host decides whether that is a product failure (for example proctoring).
_Avoid_: exception (for expected start failures)

**Orchestration**:
The native proof suite that drives the example lobby (permission, device picks, mute, Join) then the meeting Session (route, capture, playback, Camera-off, receipts) on a real head.
_Avoid_: marionette

**Barge-in policy**:
Whether barge-in is detected locally (flush playback, keep preroll) or left to the remote VAD.
_Avoid_: interrupt mode

**Camera Endpoint**:
One camera the OS exposes, with the richest metadata the platform can give. Missing fields are null and unused; preference resolution uses whatever is present rather than dropping to a lowest-common-denominator record.
_Avoid_: camera device, video device, webcam (as the type name), Endpoint (that is audio)

**Mute-video**:
An in-session mode that keeps the outbound video stream alive and substitutes black frames so remotes still have a live tile. It does not exist in the lobby; lobby is Camera-off or camera on.
_Avoid_: camera-off, stop video (as Camera-off)

**Camera-off**:
Stops the outbound video stream entirely. Remotes see no video (host thumbnail / avatar). Audio continues unless also Mute. The Session is not ended. In-call Camera preview may start only after the Session is Camera-off.
_Avoid_: mute-video, stop (that ends the Session)

**Screen source**:
One screen, window, or display region the OS can capture. Distinct from a Camera Endpoint. A Session may send screen-only, camera-only, or both. An inbound presentation is an inbound video stream on a Video surface, not a Screen source in the local catalog.
_Avoid_: camera, display camera, monitor (as the type name)

**Video surface**:
A Flutter-visible surface the library gives the host for local send preview, Camera preview, or one inbound video stream. One host type; the platform handle is a Texture id on most platforms and a view/element id on web. The host lays out tiles and switches widget implementation; callers do not import `RTCVideoView` or `dart:html` for local self-view. The library does not ship a meeting grid.
_Avoid_: tile, RTCVideoView, Preview Texture (a Texture id is a handle, not the type)

**Video sink**:
A Session attachment that observes one Production video path: generation, Mute-video versus Camera-off, Video processor identity, and the local Video surface. Multiple sinks may attach. Detach does not end the Session or replace the Capture stream. A Transport plugin or disk package binds here and consumes frames natively; tests use a fake. Camera preview has no Video sink seam. Session has no PeerConnection or MediaStream types.
_Avoid_: PeerConnection, MediaStream, RTCVideoView, sink (alone)

**Video processor**:
A selected policy that transforms a send path before the local Video surface and the Transport plugin. The family is none, blur with intensity 0–100, and replace with a still image (bytes or asset). v1 implements only none (pass-through). Blur and replace are a later plan. Hosts do not inject a processor object.
_Avoid_: filter, effect, beauty

**Production video path**:
The native path for one send source (camera or screen): capture, Video processor, local Video surface, and the Transport plugin. Production frames do not copy through Dart. Each send source has its own path.
_Avoid_: Dart frame pump, pretty tap

**Video Format**:
The requested pixel size and frame rate of a video send path. Default 1280×720 at 30 fps. The graph may run a Native Video Format instead.
_Avoid_: Format (that is audio), resolution (alone)

**Native Video Format**:
The Video Format a camera or screen graph actually runs. Negotiation picks the closest mode to the request: the next higher resolution if any exists, otherwise the next lower; frame rate closest to the request, preferring at least the requested fps when tied. No matching mode means video is not running, not a failed Session.
_Avoid_: requested format, backend format (that is audio Native Format)

**Session settings**:
The start-able description of a Session: direction, Formats, Video Format, Endpoint and camera Explicit selection, preferences used, Video processor, Mute, Camera-off, purpose, and the other start arguments. Readable from a live Session and passable to a later start() after that Session is stopped. Does not include a Transport plugin, inbound Video surfaces, or live streams. The Session object is never reused.
_Avoid_: joinFromLobby, promote, clone session

**Camera preview**:
A video-only local graph for in-call camera settings. No Capture stream, no playback, no Transport plugin, no Test record. At most one. It may run beside a Session only when that Session is already Camera-off; audio on that Session continues. Starting Camera preview while the Session is still sending video is a typed failure. The host Apply/Cancel path is stop preview, then selectCamera / setCameraEnabled on the Session (or start a new Session with Session settings). There are no join/apply helper operations. Lobby self-view is the lobby Session’s Video surface, not Camera preview. In-call selectCamera without preview is a live switch; remotes see it.
_Avoid_: Setup, Session, Pre-join preview, audio preview (there is none), joinFromLobby

**Test record**:
A bounded file of the lobby Session Capture stream (Session edge Format: the PCM a host Transport would send, and that a WebRTC plugin would encode). Playback is those bytes through that same Session’s playback on the selected render Endpoint. It is a subscriber to the one Capture stream, not a second tap. There is no in-call Test record and no in-call audio preview. Video Test record is out of v1.
_Avoid_: pretty tap, RTP dump, VOD (VOD is any recording consumer; Test record is this diagnostics clip)

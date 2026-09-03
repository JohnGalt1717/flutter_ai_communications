# Production Audio Manager and Real-Device Conformance Plan

**Status (2026-09-03):** Code for issues #16–#29 is on `main`. Those issues
are **CLOSED** except #26 (`ready-for-human`: physical iPhone, physical
Android, Chrome). Do not reopen #16–#25 or #27–#29 from this file. Fieldist
is still blocked on #26.

Verified evidence (do not treat as close):

- Suite file: `example/integration_test/native_orchestration_test.dart`
  (Marionette was renamed Orchestration).
- Chrome 20-cycle + 45 capture×render receipts at commit `10f9c2c`
  (comments on #21). `devicechange` still `skipped=capability`.
- Windows exclusive audio 20-cycles: extra desktop evidence (PR #32
  comment on #26). Linux/WSLg 20-cycles ran in the PR #33 window
  (Plantronics/WASAPI on Windows; Pulse `RDPSource`/`RDPSink` on WSL).
- Acoustic-profile registry and Capture processors: implemented in shared
  + Session; physical calibration receipts still #26.
- Windows directed Sessions: PR #32; later closed by #41 (`3e1bb8d`).
- Observed emit on Windows: PR #32; #17 is closed.
- Video is a separate track (`.agents/plans/video-capture-and-sinks.md`).
  Do not close audio tickets from camera receipts.

The receipt handoff `.agents/plans/handoff-remaining-platform-signoff.md`
was written against `10f9c2c` / PR #30. Read its 2026-09-01 banner before
the historical matrix.

## Goal

Make `flutter_ai_communications` the one production audio stack used by host applications. Prove native capture, render, Endpoint selection, Format guarantees, Capture processing, reset continuity, and repeated Session lifecycle on physical iOS, physical Android, and Chrome before Fieldist integration begins.

## Gate

Fieldist integration is blocked until all relevant work below is complete, automated gates pass, required manual accessory evidence is current, machine-readable receipts are retained, and the user explicitly approves readiness.

The example application is the primary conformance harness. Synthetic loopback proves Dart stream identity only; it never satisfies native microphone, speaker, route, Format, AEC/NS/AGC, or reset acceptance.

## Required architecture

- One application-scoped `CommunicationsManager`; at most one capture-only, playback-only, or duplex `Session`.
- Product differences are edge attachments: Transport, capture sink, and playback source.
- Stable Session edges survive route change, Format renegotiation, interruption, recovery, and native reset. SignalR/WebRTC never reconnects because of native audio work.
- Application policy owns Desired Pair. Native commands produce Applied Pair; OS state produces Observed Pair. Bounded Route convergence makes Observed match Desired or reports a typed fault.
- Host persists user-scoped Endpoint preference; the Audio manager continuously resolves it.
- Explicit selection lasts only for one Session while its Endpoint remains available.
- Automatic preference requires a complete Pair. Split capture/render configurations require Explicit selection.
- Every status structurally carries `success`, `warning`, or `error` severity plus stable code, recoverability, usability, and required action.

## Work order

### 1. Public contracts

Implement issues #16, #18, #27, and #28.

- Ordered enabled Endpoint preference with deterministic defaults: Bluetooth/headset, car/projection, speakerphone, handset.
- Stable Endpoint identity and unavailable retained preference entries.
- Session direction and host-provided Session purpose.
- Structured readiness/status/fault snapshots and streams.
- Diagnostics for Desired/Applied/Observed Pair, native graph generation, capture/playback liveness, requested/Native/edge Formats, conversion path, and candidate failures.
- Optional host/platform vehicle context; core audio remains independent of CarPlay/Android for Cars entitlement.
- Optional Android `BLUETOOTH_CONNECT` enrichment with host-owned explanatory copy. Denial preserves usable conservative behavior.

Complete when fake-platform tests account for every state transition and a host cannot infer readiness from command completion.

### 2. Serialized Session lifecycle

Implement issue #22.

- One ordered state machine owns start, stop, pause, resume, Coverage, focus, Endpoint change, Format change, reset, and recovery.
- `StartAlreadyActive` is an error naming the active Session purpose.
- Interruption auto-resumes only when it parked an otherwise-active Session.
- Host-selected background policy never bypasses readiness revalidation.
- Capture and playback liveness are monitored for the Session lifetime.
- Capture or playback stall recovers below stable edges; no Transport reconnect.
- Capture sink buffering is bounded; overflow is a typed terminal recording fault.
- Host owns save/discard; manager exclusively owns native teardown.

Complete when deterministic concurrency and repeated lifecycle tests cannot leak threads, graphs, subscriptions, or stale generations.

### 3. Endpoint identity, Pairing, and Route convergence

Implement issues #17 and #20.

- Correct iOS Pair identity when capture/render UIDs differ.
- Apply and verify both capture and render selection on every platform.
- Platform-specific event-driven convergence: three application attempts within a two-second public deadline by default.
- Preference-selected failure marks a Pair unusable for that Session and walks downward; exhaustion reports `noUsablePair`.
- Explicit-selection failure never silently falls back.
- Higher-priority appearance promotes only while preference controls the Session.
- Configure native sessions to minimize automatic OS rerouting.

Complete when fake/native tests prove unwanted OS events cannot rewrite Desired Pair or create a feedback loop.

### 4. Native Format negotiation and conversion

Implement issue #23 before platform acceptance.

- Discover selected Endpoint capabilities first when reliable.
- Choose the exact promised edge Format when available; otherwise rank supported Native Formats by communications processing, fidelity, integer-ratio conversion, and cost.
- Use deterministic failure-first probing only where capability discovery is unavailable.
- Return requested, negotiated, and conversion-path information per direction.
- Renegotiate after every Pair change while preserving Session edge Format and identity.
- Prefer verified OS/native conversion when maintainable; otherwise use one shared Dart implementation. Never double-convert.
- Replace linear interpolation with stateful production-quality sample-rate conversion.
- Android must handle `AudioRecord` error -20 by selecting a verified alternative while continuing to emit backend-required PCM16 mono 24 kHz.

Complete when fixtures prove duration, sample count, frequency preservation, chunk continuity, clipping safety, and round-trip quality through public Session seams.

### 5. Acoustic profiles and Capture processors

Implement issue #29 and ADR-0010/0011.

Capture processors:

- `adaptive`: Acoustic-profile Baseline plus ambient/voice adaptation;
- `profileScaled(step)`: Baseline with deterministic step 1–10, no ambient adaptation;
- `fixed(normalizedRms)`: absolute advanced/test threshold, no hidden profile multiplier;
- `passThrough`: no floor rejection.

Rules:

- Step 5 equals Baseline; lower is more sensitive, higher rejects more.
- Seed calibration: communications headset 3, Bluetooth speaker 4, built-in/car 5, speakerphone/unknown 6, handset 8.
- Classification precedence: verified active native capabilities, high-confidence product family/model profile, conservative Route fallback.
- Shared Dart registry uses narrow aliases, platform/transport constraints, provenance, confidence, positive fixtures, and negative near-match fixtures.
- Manufacturer tokens such as Tesla require independent car/transport evidence. Do not assume display name is a Bluetooth alias.
- Unknown/low-confidence profile is diagnostic warning only and does not tighten policy.
- Pair/profile change resets adaptive history when acoustically incompatible.
- The one Capture stream is promised-Format, processor-applied, and silence-substituted for rejected/muted frames.
- Debug builds may create short, consented, local, bounded raw snapshots; release builds expose no second raw stream.
- Research a suitably licensed maintained Bluetooth capability database before building the registry. If none is suitable, keep the versioned registry and reproducible provenance process. Telemetry/database ingestion is future work.

Complete when fixture and physical tests prove background rejection, user speech preservation, playback echo leakage, and simultaneous speech during playback for representative routes.

### 6. Platform correctness

Implement issues #19–#21 and #24–#25.

- Android: capture running order, capture Endpoint application, capabilities, Format negotiation, Bluetooth enrichment, graph recovery.
- iOS: deterministic Pairing, available/observed routes, route enforcement, Isolation flow, interruption/reset, Format negotiation.
- Web: `deviceId` capture constraints, `setSinkId` render selection where supported, `devicechange`, capability outcomes, playback scheduling.
- Complete Isolation/noise-cancelling contract and continuous streamed playback queue.

Complete only after each adapter has public-seam tests plus physical/browser evidence; registration-only tests are insufficient.

### 7. Example conformance harness

Implement issues #18 and #26.

Expose stable Marionette keys/actions for:

- endpoint catalog and preference ordering;
- Desired/Applied/Observed Pair;
- Session direction/purpose/lifecycle;
- requested/Native/edge Formats and conversion path;
- status severity/code/action;
- capture frame cadence, RMS, and stall recovery;
- playback accepted/queued/rendered/flushed/stalled progress;
- reset generation and stable stream identity;
- Acoustic profile, Baseline, processor, active floor, and confidence;
- evidence receipt generation.

The harness must never skip a native failure by substituting loopback.

## Physical-device matrix

### Automated primary gate on relevant changes

Physical iPhone, physical Android, and Chrome:

- first Session after install;
- handset ↔ speakerphone;
- preference fallback and promotion;
- Explicit Pair and split capture/render selection;
- Format exact match and fallback/transcoding;
- capture/playback stall recovery;
- interruption and background/resume;
- twenty consecutive start/capture/playback/stop cycles;
- stable Session/Transport edges through route and Format reset;
- structured success/warning/error statuses.

Chrome additionally tests every available capture × render combination and `devicechange`.

### Manual secondary gate

AirPods, generic Bluetooth, CarPlay, and Android Auto require audible and metadata confirmation. Existing evidence remains valid until code affecting Endpoint identity/Pairing, preference, route policy/convergence, graph setup/reset, Format negotiation/conversion, focus, or lifecycle changes; relevant changes invalidate it immediately.

### Human challenge minimization

Use frame cadence, Observed Pair, playback progress, fixtures, and electronic echo metrics first. Ask for human sound/output confirmation only where no reliable electronic oracle exists.

## Evidence receipt

Generate a machine-readable receipt containing:

- commit;
- package/platform/OS/hardware/accessory;
- permission/capability context;
- requested, Native, working, and edge Formats;
- Endpoint catalog, profile confidence, and Pair transitions;
- processor and Baseline;
- cycle count and liveness metrics;
- statuses/faults/recoveries;
- manual confirmations.

Receipts stay out of source control. Retain approved baselines in an artifact location and summarize them when shipping.

## Dependency graph

1. Contracts/status/preferences (#16, #18, #27, #28)
2. Serialized lifecycle (#22)
3. Identity/Pairing/convergence (#17, #20)
4. Format negotiation/conversion (#23)
5. Acoustic profiles/processors (#29)
6. Platform fixes (#19–#21, #24–#25)
7. Harness and physical conformance (#26)
8. Explicit user approval
9. Fieldist worktree integration may begin

Tests accompany every step; they are not deferred to the harness phase.

## Definition of done

- Relevant issues #16–#29 are complete.
- Unit, public-seam, fake-platform, adapter, and browser tests pass.
- Physical iPhone, physical Android, and Chrome receipts pass without skipped native failures.
- Impact-triggered accessory receipts are current.
- Docs/example teach one application-scoped manager and directed Sessions.
- User explicitly approves Fieldist integration readiness.

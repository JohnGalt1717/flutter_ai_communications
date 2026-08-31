# Handoff: remaining ticket sign-off and platform receipts

Hand this file to the next agent. Do not reopen the “unplug USB” path. USB staying attached is the Mac proof, not a blocker.

Read first: `CONTEXT.md`, `AGENTS.md`, this file, then the ADRs for the area you touch (`0006`, `0007`, `0004`). Load `device-marionette` and `device-permission-prompts` before any exclusive drive. Load `tdd` / `dart-add-unit-test` before product edits.

## Mission

Finish native Session proof on the remaining platforms and only then close hardware tickets that the receipts actually satisfy.

Definition of done for this handoff:

- Exclusive native suite passes on **macOS with USB Audio still attached**.
- Exclusive native suite passes on **Chrome**, then **Windows**, then **Linux**.
- Each pass writes a host receipt under `/tmp/flutter_ai_communications_receipts/<commit>-<platform>-<device>.json` with the real git commit, not `unknown`.
- PR #30 gets a comment per platform. Hardware issues stay open until their own close bar is met.
- #17 / #19 / #20 / #26 are **not** closed from a single platform receipt.

Fieldist integration stays blocked until #26’s required matrix is clean: physical iPhone, physical Android, and Chrome. Desktop receipts are required to “roll the rest of the platforms”; they do not by themselves close #26.

## Hard rules

- One exclusive Flutter process. From `example/`:

  ```text
  pushd /Users/jameshancock/Repos/flutter_ai_communications/example
  flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/native_marionette_test.dart \
    -d <id>
  ```

- Never `flutter test` at the workspace root. Never wrap the registered adapter in loopback.
- Command completion is not observation. Desired ≠ Applied ≠ Observed.
- Isolation is not a suite gate. Mic Allow is a `StartReady` gate.
- Do not add Patrol mid-receipt.
- Do not start a second `flutter drive` / `flutter run`. If a leftover exists, kill it first.
- Do not close #17, #19, #20, or #26 without the matching receipt. Comment the path and the pass/fail summary.
- Working tree has uncommitted adapter/harness work on top of HEAD `10f9c2c84c5642c9050cbf30d24b209212630774`. Receipts must stamp the commit that actually ran. If you land product fixes, re-run the exclusive suite on the new HEAD.

## Current matrix

HEAD at last exclusive runs: `10f9c2c84c5642c9050cbf30d24b209212630774` on `production-audio-manager-device-conformance`. PR #30.

| Target | Id | Receipt | Status |
| --- | --- | --- | --- |
| Android phone | `R5GL63B3GWV` | `…-android-R5GL63B3GWV.json` | Pass. Do not re-run unless you change Android product code. |
| iPhone | `00008150-000664981A38401C` | `…-ios-00008150-000664981A38401C.json` | Pass. Capability-gated AirPods / interruption rows still open on #20 / #26. |
| iPad | `00008110-000E24912E63A01E` | `…-ios-00008110-000E24912E63A01E.json` | Pass. Speaker-only catalog; `speakerHandset` skipped. |
| Pixel Tablet AVD | `emulator-5554` | `…-android-emulator-5554.json` | Pass. Speaker-only built-ins; virtual wired listed; `speakerHandset` skipped. |
| macOS | `macos` | `…-macos-JamesMaroMax598-blocked.json` | **Not signed off.** Preference selected USB. Observed later matched. Capture frames live, RMS 0. |
| Chrome | `chrome` | none | **Not run.** Compile path is now web-safe. Drive was started then killed. |
| Windows | remoting later | none | **Not run.** Observed emit + unit test now in the working tree. Exclusive `-d windows` still requires remoting. |
| Linux | remoting later | none | **Not run.** Observed emit + unit test now in the working tree. Exclusive `-d linux` still requires remoting. |

Do not treat the blocked macOS file as a pass.

## Preference and switching — learn this before touching Mac

Use glossary terms. Do not say “device order”, “default device”, or “OS preference”.

### Who owns what

- Host persists and edits `EndpointPreference`. Persistence is out of scope here.
- `CommunicationsManager.bindPreference` stores the bound list and **ends** a live Session. Next `start()` uses that list.
- `SessionPreference.endpoints` at `start()` overrides the bound list for that start only when non-empty.
- `SessionPreference.captureId` / `renderId` are an **Explicit selection** for this Session only.
- `Session.select` is ephemeral. It must not write the host list. A later `start()` must come back under preference control.

### Default walk order

`EndpointPreference.platformDefault` walks complete Pairs in this Route-class order:

1. `bluetooth`
2. `wired`
3. `car`
4. `speakerphone`
5. `handset`

On this Mac, Generic USB Audio is `wired`. Built-in MacBook mic/speakers are `speakerphone`. **USB must win.** That first exclusive Desired/Applied pair was correct:

- capture `AppleUSBAudioEngine:Generic:USB Audio:1141200:1`
- render `AppleUSBAudioEngine:Generic:USB Audio:1141200:2`

Do not bind the suite to speakerphone to dodge USB. Do not unplug USB to make the suite pass. The product claim is: attached higher-priority hardware is selected and actually carries audio.

### Resolution rules

Implemented in `PreferenceResolver` / `Session`:

- Empty preference → platform default from the live catalog.
- Walk enabled entries top to bottom. Missing ids stay in the list (`unresolvedIds`) and are never guessed from display name.
- Disabled entries are skipped by automatic resolution; they remain valid for Explicit selection.
- Automatic resolution requires a **complete Pair** for the requested Session direction. Capture-only USB with no render mate is skipped; the walk continues.
- Explicit selection wins while those Endpoints remain in the catalog. Split capture/render is kept and is not completed from preference.
- If the explicit Endpoint disappears, the override expires and the Session returns to preference immediately.
- While `preferenceControlled == true`, a newly appeared higher-priority complete Pair promotes.
- If a preference-selected Pair fails Route convergence, mark that `pairId` unusable for this Session and walk downward. Exhaustion is `noUsablePair` / `StartUnavailable`.
- If an Explicit selection fails convergence, do **not** silently walk. Report the fault.
- OS route events update **Observed** only. They must not rewrite Desired. Command completion must not update Observed.

### What “switch” means

Three values, always:

- **Desired** — resolver output.
- **Applied** — last `startNative` / `selectEndpoints` command.
- **Observed** — what the platform reports is actually bound.

Route convergence: up to three application attempts inside `Session.convergenceDeadline` (two seconds). Then fail or walk as above.

Native reset must keep the same `Session` and the same broadcast `capture` stream (ADR-0004).

## Mac leftover — this is the product bug

USB was selected. That is not the bug.

### Already fixed in the working tree

macOS used to leave `lastObservedRoute` empty (platform default). First exclusive fail:

```text
desired=…USB…:1 / …USB…:2
applied=…USB…:1 / …USB…:2
observed=null/null
```

Adapter now emits Observed after successful `startNative` and after `selectEndpoints` when running. Unit test “start and select report Observed from bound native devices” passed (`packages/flutter_ai_communications_macos`, 6 tests). That code is **uncommitted**.

### Still failing on hardware

Second exclusive fail, USB still attached:

```text
capture stayed dead frames=807 rms=0.0 status=ready
```

Status `ready` means Observed was accepted as Desired. The graph produced hundreds of frames. RMS stayed 0. Preference did its job. Capture on the selected USB Endpoint did not.

Suite gate in `example/integration_test/native_marionette_test.dart`: `captureFrameCount > 1` **and** `recentRms > 0` within 8s. Silent frames fail. That gate stays.

### Likely causes, in investigation order

Inspect before editing. Do not assume “USB is silent hardware”.

1. **`AudioQueueSetProperty(aqcd)` status is ignored.** `_bindDevice` never checks the OSStatus. `observed` then falls back to selected / default UID, so Observed can **lie** that the queue is on USB while the queue is still on the built-in device, or on a USB device opened with a rejected format.
2. **Hardcoded Native Format.** `writePcm16` is PCM16 LE mono 24 kHz. Many USB interfaces are stereo 44.1/48 kHz. If bind “succeeds” and the device still emits zeros, negotiate a supported Native Format and convert at the edge (ADR-0008 / #23). Identity 24 kHz mono is the Session edge promise, not a license to ignore device capabilities.
3. **In-place bind without restart.** `select()` only sets CurrentDevice. Some USB devices need the queue rebuilt after bind. `start()` binds then starts; prove whether start-time bind actually sticks (`AudioQueueGetProperty(aqcd)` vs fallback).
4. **Pair / UID mismatch.** Catalog ids are full Core Audio UIDs (`…:1` / `…:2`). Pair identity is `applePairId` on normalized name (`usb audio`). That pairing is correct if both sides share the name. Confirm enumerate is not advertising an output-only UID as capture, or collapsing two USB boxes (Generic USB Audio vs Realtek USB2.0 Audio) into one Pair.
5. **Channel / scope.** `_collect` keeps a device if it has streams in `inpt` / `outp`. Confirm the capture UID has a real input stream and that the queue is not reading a dead output-only node.
6. **TCC / first-start Allow.** Permission was granted enough to produce frames. Do not treat this as a permission skip.

Unusable-Pair walk is **not** the first move. Walking away from USB because RMS is 0 hides the bind/format bug and contradicts “USB hooked up should work”. Only mark the Pair unusable after bind/format/Observed are honest and the OS still cannot open that Endpoint.

### Mac completion criterion

Exclusive `-d macos` all-tests-passed with USB still listed in `system_profiler SPAudioDataType`, receipt stamped with the running commit, `nativeFailuresSkipped: false`, Desired/Applied/Observed = the USB Pair (or a honestly higher bluetooth Pair if one appears), `recentRms > 0`, 20 cycles, new Session `preferenceControlled: true`. Then PR comment. Then stop Mac work.

## Ticket sign-off map

All of #16–#29 are still **OPEN**. PR #30 implements a large slice in code; hardware tickets stay open until receipts exist. Do not close from “the PR body says implemented”.

| Issue | Close only when | Now |
| --- | --- | --- |
| #16 preference policy | Fake-platform tests cover start, explicit, disappear, higher-priority appear, new-Session reset. Docs no longer call ordering host-only. | Code exists (`EndpointPreference`, `PreferenceResolver`, `bindPreference`). Keep open until those tests are clearly green on the landed commit and Mac/Chrome prove live promotion/fallback. |
| #17 Observed convergence | Fake-platform transient route tests + native adapters emit enough Observed state + no select/event loop. Physical receipts show Observed = Desired. | Fake path likely present. macOS / Windows / Linux emit are in the working tree (unit-tested). Exclusive Observed=Desired still unproven on Mac USB, Chrome, Windows, Linux. **Do not close.** |
| #18 diagnostics | Fake tests + Marionette keys for Desired/Applied/Observed, frames, RMS, preferenceControlled, generation. | Suite already asserts these. Keep open until Chrome/desktop also expose them. |
| #19 Android capture apply | Physical Android: running order, selected capture applied, 20 cycles, Observed both sides. | Phone + tablet receipts exist. Bluetooth / interruption still capability-gated. **Do not close** until the issue’s Bluetooth/handset rows are either proven or recorded `skipped=capability` on a device that lacks them. |
| #20 iOS Pair identity | Physical iPhone: AirPods one Pair despite UID split, speaker ↔ handset, first Session honors preference, explicit stays, 20 cycles. | iPhone 20-cycle receipt exists. AirPods / interruption still need capability-gated rows. **Do not close.** |
| #21 web selection | Chrome: every available capture × render, `devicechange` promote/fallback, explicit blocks promote, streams survive reset, typed `sinkId` unsupported. | Policy unit tests exist. **No Chrome receipt.** This is the next signed-off ticket after Mac. |
| #22 lifecycle | Deterministic concurrency tests; no leaked graph/thread/generation. | Code present. Not this handoff’s first job unless a drive exposes a leak. |
| #23 Formats | Fixture + native negotiation; Android -20 path; no double convert. | Mac USB silence may force this on Core Audio. Do not expand scope past the failing Endpoint. |
| #24 Isolation | iOS detect / open / continue-with-raised-floor. Isolation is not a suite gate. | Do not block Mac/Chrome/desktop on this. |
| #25 playback schedule | Continuous queue; flush zeros queued. | Suite already requires `playbackAccepted > 0`. Not a close of #25 by itself. |
| #26 Marionette suite | Required matrix: physical iPhone, physical Android, Chrome. Capability-gated accessory rows recorded. Receipts with `nativeFailuresSkipped: false`. | Phone/tablet/iPhone/iPad 20-cycle rows exist. **Chrome missing.** Desktop is extra. **Do not close.** |
| #27 / #28 / #29 | Directed Sessions, structured status, acoustic profiles. | Out of this receipt handoff unless a failing drive forces a contract change. |
| #1 spec | Living spec. Leave open. | Leave open. |

Close comment shape, when a ticket is actually done: receipt path, commit, device id, catalog summary, Desired/Applied/Observed, cycle count, what was skipped as capability, what is still open.

## Ordered work for the next agent

Stop at the first red exclusive drive. Do not start the next platform while one Flutter process is live.

### 0. Inventory

- `git status` / `git rev-parse HEAD`.
- `pgrep -lf 'flutter_tools.snapshot (drive|run|test)'` must be empty.
- `flutter devices`. Use the **id** column.
- Confirm USB still present if you are about to run Mac.

Complete when you can name HEAD, the exclusive slot is free, and you know which device id you will drive.

### 1. Make Mac USB capture actually live

Keep USB attached. Prove bind + format + honest Observed.

Minimum product bar:

- `AudioQueueSetProperty` / `GetProperty` statuses are checked.
- Observed is the bound UID, never the requested UID on bind failure.
- If 24 kHz mono is not a Native Format for that Endpoint, negotiate and convert once at the edge.
- Unit tests on the macOS adapter cover: bind success reports that UID; bind failure does not report that UID; select of USB then speakerphone then USB updates Observed; a stereo/48k device still emits non-zero PCM at the Session edge.

Then one exclusive `-d macos`. On pass: stamp receipt with HEAD, `gh pr comment 30`, do not close tickets.

Complete when the Mac completion criterion above is true.

### 2. Chrome (#21 + #26 required row)

Web host helpers already exist:

- `example/integration_test/native_marionette_host.dart` (web stub)
- `example/integration_test/native_marionette_host_io.dart` (io)

The suite no longer imports `dart:io` directly. Commit those files before calling Chrome done if they are still untracked.

Run exclusive `-d chrome` only after Mac is finished or explicitly parked. First `start()` blocks on `getUserMedia` — that is the permission gate. Do not kill the drive for a browser prompt; wait or ask the human once.

Issue 26 Chrome extras still required after the 20-cycle suite:

- every available capture × render combination
- `devicechange` during Session (promote while preference-controlled; explicit blocks promote; disconnect expires explicit)
- typed sink unsupported where `AudioContext.sinkId` is missing

If the current suite does not cover those rows, add capability-gated cases. Do not skip native failure by wrapping loopback.

Complete when a Chrome receipt exists, commit ≠ `unknown` (stamp on the host if the web stub writes `unknown`), PR commented, #21 still open until the extra rows are in that receipt or a follow-up receipt.

### 3. Windows, then Linux

Same exclusive suite. Remoting is expected. This Mac has no `windows` / `linux` Flutter devices.

Observed emit is **already in the working tree** (uncommitted). Do not re-port it.

- Windows: `lastObservedRoute` / `osRouteChanges` after successful `startNative` and after `selectEndpoints` while running. `WasapiWindows.observed` reports the **opened** Endpoint id (`IMMDevice.getId()`), not the requested id. Default-communications fallback must not claim the requested id. Unit test “start and select report Observed from bound native devices” passed (5 tests).
- Linux: same adapter emit. `PulseBackend.observed` is the selected `_captureId` / `_renderId` (Pulse opens those ids; there is no separate bound-UID query yet). Unit test passed (5 tests).
- If a remoted exclusive fail is `observed=null/null`, the tree you drove is missing this commit. Do not “fix” by wrapping loopback.

Do Windows before Linux. One exclusive process per host.

Complete when each has a pass receipt and a PR comment. Do not close #17 from desktop-only Observed work; #17 also needs the mobile receipts already on disk plus no remaining adapter that silently returns empty Observed if that adapter is in the v1/desktop ship set.

### 4. Ticket comments, not mass-close

After the three remaining platforms have receipts:

- Comment #26 with the full receipt table. Leave it open until Chrome extras and capability-gated AirPods/Bluetooth/interruption rows are either proven or recorded.
- Comment #21 with the Chrome receipt.
- Comment #17 with Mac/Windows/Linux Observed emit + existing mobile receipts. Close only if every shipping adapter emits Observed and fake-platform loop tests are green.
- Leave #19 / #20 open until their accessory rows are honest.
- Do not close #16–#18, #22–#25, #27–#29 from this handoff unless you separately execute their acceptance lists.

## Platform recipes

Always `pushd` into `example/`. Grant mic after the binary exists (`device-permission-prompts` / `grant-device-permissions.sh`).

| Platform | Device id | Grant | Notes |
| --- | --- | --- | --- |
| macOS | `macos` | TCC already granted if frames arrive | USB must stay. `Failed to foreground app; open returned 1` did not block VM attach last time. |
| Chrome | `chrome` | First `getUserMedia` prompt | Host receipt may need a manual stamp if `hostGitCommit()` is `unknown`. |
| Windows | the remoted `windows` id | OS mic privacy | Observed emit already landed in the working tree. Drive the remoted host; do not re-port emit. |
| Linux | the remoted linux id | Pulse/PipeWire access | Same emit as Windows. Pulse Observed is the selected id until a bound-UID query exists. |

Receipt copy: suite prints `NATIVE_MARIONETTE_RECEIPT {json}` and writes under the device temp dir. Copy to `/tmp/flutter_ai_communications_receipts/<commit>-<platform>-<device>.json`.

## Working tree the next agent inherits

Uncommitted / untracked that matter for receipts:

- macOS Observed emit (`flutter_ai_communications_macos.dart`, `core_audio_backend.dart`, `core_audio_ffi.dart`, `audio_backend.dart`, unit test)
- Windows Observed emit (`flutter_ai_communications_windows.dart`, `wasapi_backend.dart`, `wasapi_windows.dart` `_openDevice` / opened-id Observed, unit test)
- Linux Observed emit (`flutter_ai_communications_linux.dart`, `audio_backend.dart`, `pulse_backend.dart`, unit test)
- Android catalog honesty (no handset without earpiece)
- iOS route-policy / plugin edits
- `example/integration_test/native_marionette_test.dart` + web/io host split
- `.agents/workflows/real-device-marionette.md`, permission skill/workflow
- this handoff plan

Land or at least keep these in the tree you drive. A receipt on HEAD without the Observed emit is the first Mac fail again.

## What “ready to roll” is not

- Not: unplug USB so speakerphone passes.
- Not: `bindPreference` to speakerphone for the suite.
- Not: close #26 after Mac + Chrome 20-cycles if Chrome combination / `devicechange` rows never ran.
- Not: interactive `flutter run` + Marionette taps. That path does not close hardware issues.
- Not: `echo_loopback_test.dart`. Digital identity only.
- Not: starting web while Mac is still red, unless the human explicitly parks Mac.

## First command for the next agent

```text
pgrep -lf 'flutter_tools.snapshot (drive|run|test)' || echo 'slot free'
git rev-parse HEAD
flutter devices
system_profiler SPAudioDataType | rg -n 'USB|Built-in|Default Input|Default Output'
```

Then fix Mac USB capture with USB still attached. Then Chrome. Then Windows. Then Linux.

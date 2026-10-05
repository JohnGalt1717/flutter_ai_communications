# Interactive iOS / macOS receipts

Walk the **human-audible** and **catalog-observation** rows that unit tests
and `native_orchestration_test` cannot close. The agent drives the example
(flutter-skill + Agent Lens). The human plugs accessories, listens, and
taps OS sheets.

Automated mic/route cycles: [real-device-orchestration.md](real-device-orchestration.md).
Screen send: [screen-send-orchestration.md](screen-send-orchestration.md).
Endpoint preference unplug: [endpoint-preference-orchestration.md](endpoint-preference-orchestration.md).

Human wizard (optional second terminal):
`bash .agents/workflows/interactive-ios-macos.sh [macos|ios|both]`

## Load first

`device-agent-lens`, `device-permission-prompts`, `fac-os-sheets` when an
Allow / Isolation / Screen Recording sheet appears. Read `CONTEXT.md`
(Session, Pair, Desired / Applied / Observed, Isolation, Explicit
selection) and issues **#26**, **#92**, **#100**. Follow-up live proof:
**#93** (iOS detach).

## Issues this job covers

| Issue | State | iOS / macOS rows |
| --- | --- | --- |
| #26 | open, `ready-for-human` | Physical iPhone speakerphone ↔ handset, AirPods before/during, explicit pick, interruption, Isolation, human loopback prove. macOS 20-cycle already receipted; re-run optional. |
| #92 | open, `ready-for-human` | macOS #89 AirPods-after-start + mid-Session switch. iPhone #88 idle catalog + live list refresh. |
| #100 | open, `ready-for-human` | Mac execution of #92 A2/A3. Optional pci built-in Pair smoke (C). Android A1 / video B are **out of this job**. |
| #93 | open, `ready-for-agent` | Manual: hot restart while catalog observation is held; idle must not leave a voice session. |
| #94 / #95 | open, `ready-for-agent` | Code tickets. Do not treat this job as their implementation. Live proof only after those land. |

#44 screen send already has `skipped=false` on macOS and physical iOS.
Do not reopen it here.

Simulator and wireless-only iPhone are **not** physical handset proof.
Prefer USB for James’s iPhone (`00008150-000664981A38401C`). Media Room
iPad (`00008110-000E24912E63A01E`) is not the #26 iPhone matrix.

## Discover

```text
flutter devices
```

Use the **id** column.

| Label | Typical id | This job |
| --- | --- | --- |
| macOS | `macos` | #89 / #92 A2 / #100 C |
| James’s iPhone | `00008150-000664981A38401C` | #88 / #92 A3 / #26 remaining |
| iPhone simulator | any `*-****-****` sim | skip — not physical |
| SM A176U1 | `R5GL63B3GWV` | skip — Android job |

If `macos` is missing, stop the macOS half. If no **USB** iPhone, run
catalog/AirPods rows on wireless only with `notes` saying wireless, and
leave speakerphone ↔ handset unmarked.

## Split of responsibility

| Who | Does |
| --- | --- |
| Agent | `flutter run`, Agent Lens attach, flutter-skill inspect/tap/screenshot, read Desired/Applied/Observed, run native suites, comment receipts |
| Human | AirPods in/out, USB plug, listen for which speaker is live, tap **Allow**, Isolation sheet, phone-call interruption, background the app |
| Appium | OS sheets only (`fac-os-sheets`). Never Flutter keys |

Never uninstall the iOS example. `flutter run` over the existing install.

## Launch

Workspace `dart analyze` must be clean (`dart-run-static-analysis`).

macOS (VM port 50000):

```text
cd example && flutter run -d macos --vm-service-port=50000
```

iPhone (different port if macOS is still up):

```text
cd example && flutter run -d 00008150-000664981A38401C --vm-service-port=50001
```

Pin the printed `ws://127.0.0.1:<port>/<token>=/ws`. Agent Lens
`discover_apps` / `connect`. Drive keys below. First `start()` on
physical iOS: keep the process and wait for **Allow**.

## Keys

| Key | Use |
| --- | --- |
| `lobby-enter` / `lobby-join` / `lobby-leave` | Lobby → meeting → idle |
| `endpoint-<id>` | Explicit pick (render first, then capture override) |
| `desired-capture` `desired-render` `applied-*` `observed-*` | Pair convergence |
| `preference-controlled` | `true` until Explicit pick |
| `capture-frames` `capture-rms` `playback-progress` | Live capture / play |
| `mute` `pause` `prove` `stop` | Meeting bar |
| `echo-proof` | Host loopback identity (not native proof) |
| `open-isolation` `isolation` | iOS Isolation Open |
| `pref-capture-<render>-<capture>` `pref-apply` `pref-use-current` | USB+Brio compose |
| `status` `status-code` | Start / fault |

## Row matrix

Record every row as `pass`, `fail`, `skipped=capability`, or
`skipped=not-run`. Comment the receipt path on the issue in the
**Issue** column.

### macOS

| Row id | Issue | Human does | Agent asserts |
| --- | --- | --- | --- |
| `macos-pci-builtin` | #100 C | nothing extra | Built-in mic + speakers share one `built-in` Pair (pci transport) |
| `macos-airpods-start` | #92 A2 / #89 | AirPods default output in macOS Sound settings | After `lobby-enter` → `lobby-join`, playback still on AirPods; Desired = Applied = Observed; `capture-rms` live |
| `macos-mid-session-switch` | #92 A2 / #89 | Pick built-in or USB in the Endpoints list | Route sticks after engine rebind; audible on the new render |
| `macos-unplug-brio` | preference job | Unplug Brio after USB+Brio Apply | Render stays USB; capture walks to next listed mic |
| `macos-prove` | #26 | Listen / confirm `echo-proof` | Tap `prove`; identity is host loopback, not analog |
| `macos-native-20` | #26 | wait | `cd example && flutter test integration_test/native_orchestration_test.dart -d macos` |

### iPhone

| Row id | Issue | Human does | Agent asserts |
| --- | --- | --- | --- |
| `ios-idle-catalog` | #92 A3 / #88 | Tap `lobby-leave` first (the example auto-enters lobby). AirPods (and CarPlay if in a car) with **no** Session | Catalog lists accessory capture/render. A2DP-only is render-only |
| `ios-speaker-handset` | #26 | Hold to ear vs speaker | Both directions; Desired = Applied = Observed on each |
| `ios-airpods-before` | #26 | AirPods connected, then Join | Pair is AirPods both sides |
| `ios-airpods-during` | #26 | Disconnect then reconnect during Session | Out → speakerphone; in → AirPods; Capture stream object unchanged |
| `ios-live-catalog-refresh` | #92 A3 / #88 | Stay in meeting; agent re-opens Endpoints | Playback does **not** stop; Session stays |
| `ios-explicit` | #26 | — | Tap `endpoint-*` render; `preference-controlled` false; Observed converges |
| `ios-interruption` | #26 | Incoming call or Siri; then return | Pause / interrupted; resume keeps the same Session |
| `ios-isolation` | #26 | Isolation sheet | Tap `open-isolation`; decline still leaves Session ready |
| `ios-prove` | #26 | — | Tap `prove`; `echo-proof` updates |
| `ios-detach` | #93 | — | Catalog on, Agent Lens hot restart; idle has no lingering voice session |
| `ios-native-20` | #26 | Allow if prompted | `flutter test integration_test/native_orchestration_test.dart -d <udid>` on **USB** |
| `ios-carplay` / `ios-generic-bt` | #26 | accessory | `skipped=capability` unless hardware is present |

## Sequence

1. Setup: commit SHA, `flutter devices`, accessories on hand.
2. macOS rows in table order (skip `macos-unplug-brio` without USB+Brio).
3. Stop the macOS `flutter run` before the iPhone run if they share a
   machine, or keep distinct VM ports.
4. iPhone rows in table order. Speakerphone ↔ handset only on USB
   physical iPhone.
5. Write
   `/tmp/flutter_ai_communications_receipts/<commit>-interactive-ios-macos.json`
   (the wizard does this). Screenshot keys on fail.
6. Comment #92 with A2/A3 rows, #26 with remaining iPhone rows, #100
   with the Mac pass. Close a ticket only when every required box on
   that ticket is `pass` or an accepted `skipped=capability`.

## Fail closed

Observed ≠ Desired after the human heard the wrong speaker, catalog
missing AirPods while they are connected, live list refresh tearing
down the Session, Isolation Open crashing start, or substituting
loopback identity for a native route row: stop, file or comment the
issue, leave the row `fail`.

Do not mark #26 or #92 done without the matching comment + receipt
path.

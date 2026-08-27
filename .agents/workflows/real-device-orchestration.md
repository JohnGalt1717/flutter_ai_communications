# Real-device Orchestration

Execute native Session proof on physical iOS and Android. Loopback identity is a different path.

Interactive MCP (debug session → VM service URI → tap harness keys / `get_logs`) is the `device-agent-lens` skill. This file is the receipt job. Do not mix them.

## Load first

`tdd`, then `flutter-add-integration-test`. Read `CONTEXT.md` and issue #26.

## Discover

From the repo root:

```text
flutter devices
```

Use the **id** column, not the display name.

| Label | Typical id | OS |
| --- | --- | --- |
| Media Room (iPad mini) | `00008110-000E24912E63A01E` | iOS |
| SM A176U1 | `R5GL63B3GWV` | Android |

If either id is missing, stop. Wireless iPhones and simulators are not this workflow.

iPad `developerModeStatus: disabled`: try `/usr/bin/devmodectl single -v 00008110-000E24912E63A01E` first. If it prints `Failed to arm: Device has a passcode set`, the human must remove the passcode or flip Settings → Privacy & Security → Developer Mode. Do not retry `flutter test` / `flutter run` until `/usr/bin/devmodectl list` shows `enabled`.

## Grant microphone

Load `device-permission-prompts` and run [grant-device-permissions.md](grant-device-permissions.md). Android grant is after the APK exists. Physical iOS: first `start()` shows Allow — keep the exclusive process and wait for the human tap. Isolation Open is host UI; do not block the suite on it.

## Run

From `example/`. Never `flutter test` at the workspace root.

```text
cd example
flutter test integration_test/native_orchestration_test.dart -d 00008110-000E24912E63A01E
flutter test integration_test/native_orchestration_test.dart -d R5GL63B3GWV
```

Drive form (same assertions):

```text
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/native_orchestration_test.dart \
  -d <device-id>
```

`integration_test/echo_loopback_test.dart` is digital identity after `Session.play`. It does not satisfy #26.

## Pass

Every case must:

- return `StartReady` (not skip on permission)
- emit capture frames with live RMS
- accept playback (`playbackAccepted` increments)
- keep the same `Session.capture` object through select/reset
- leave `manager.session == null` after stop
- start the next Session from preference, not the prior explicit pick
- write a receipt under `/tmp/flutter_ai_communications_receipts/`

Built-in cases: first Session, speakerphone ↔ handset when both exist, explicit select, twenty start/capture/play/stop cycles.

Capability-gated (run when the catalog has the Endpoint; otherwise record `skipped=capability`): Bluetooth before/during Session, interruption, Chrome `devicechange`.

## Receipt

Machine-readable, out of source control. File name:

```text
/tmp/flutter_ai_communications_receipts/<commit>-<platform>-<device>.json
```

Must include commit, platform, OS, hardware, permission, catalog, Desired/Applied/Observed, Formats, cycle count, statuses, Isolation state, and whether native failures were skipped (must be false).

The suite prints `NATIVE_ORCHESTRATION_RECEIPT {json}` on the host log and writes the same JSON under the device `Directory.systemTemp`. Copy the printed JSON to the host artifact location.

## Close hardware issues only with receipts

Do not close #17, #19, #20, or #26 without the matching receipt. Comment the receipt path and the pass/fail summary.

## Fail closed

Permission denied, dead capture, Observed ≠ Desired after the convergence deadline, replaced Capture stream, leftover native graph, or a skip that substituted loopback: stop and file or comment the hardware issue. Do not mark the matrix done.

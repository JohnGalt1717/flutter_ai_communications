---
name: device-marionette
description: Start a Flutter debug session on a physical device, extract the VM service URI, connect Marionette MCP, and drive the example harness (tap keys, read diagnostics, get_logs). Use when the user asks to Marionette a device, hook DebugMCP, get a VM service / observatory URI, script Start/Mute/Pause on iPad or Android, make get_logs work, or recover a stale session by killing flutter run and restarting.
---

# Device debug → Marionette

Interactive MCP path. Receipts and the native suite stay in [real-device-marionette.md](../../workflows/real-device-marionette.md).

## Do not confuse these sockets

| Socket | What it is | Enough for Marionette? |
| --- | --- | --- |
| Dart Tooling Daemon (DTD) | IDE process. `dtd listDtdUris` / `connect` | No |
| Flutter Driver / `widget_inspector` | Official Flutter MCP | No |
| **VM service** `ws://127.0.0.1:PORT/ws` | Printed by `flutter run` / a Dart debug session | **Yes** |

DTD `listConnectedApps` can *discover* an already-running debug app. It does not replace `mcp_marionette-mc_connect`.

## Preconditions

1. Example has `marionette_flutter` + `marionette_logging`. `main()` calls `MarionetteBinding.ensureInitialized(MarionetteConfiguration(logCollector: LoggingLogCollector()))` in debug. Tests must not call this `main()` (single-binding rule).
2. Marionette MCP tools are enabled. If `connect` is missing, activate the Marionette tool group first.
3. Library stays on `package:logging`. Do **not** add ISpect to any `packages/` pubspec. `get_logs` is `LoggingLogCollector` in **example only**.
4. Loopback wrap in `example/lib/main.dart` is the interactive harness. It is **not** native proof. Do not close #17 / #19 / #20 / #26 from this path.

## 1. Discover the device id

```text
flutter devices
```

Use the **id** column.

| Label | id |
| --- | --- |
| Media Room (iPad mini) | `00008110-000E24912E63A01E` |
| SM A176U1 | `R5GL63B3GWV` |

If the id is missing, stop. Wireless iPhones and simulators are out of this skill.

iOS: confirm before retrying a failed `flutter run`:

```text
xcrun devicectl device info details --device 00008110-000E24912E63A01E
```

If `developerModeStatus: disabled` and `ddiServicesAvailable: false`, do **not** loop `flutter run`. Host enable first:

```text
/usr/bin/devmodectl list
/usr/bin/devmodectl single -v 00008110-000E24912E63A01E
```

Verified 2026-08-24 on Media Room: `devmodectl` finds the iPad, establishes a secure session, then **Failed to arm: Device has a passcode set**. `devicectl device info lockState` can still report `passcodeRequired: false` / `unlockedSinceBoot: true` — that only means the screen is unlocked, not that no passcode is configured. A configured passcode blocks host enable. Then the human must either remove the passcode and re-run `devmodectl single`, or flip Settings → Privacy & Security → Developer Mode → Restart → Turn On. Do not retry `flutter run` until `/usr/bin/devmodectl list` shows `enabled`.

```text
.agents/workflows/enable-ipad-developer-mode.sh
```

When status becomes `enabled`, do **not** rediscover the hookup. Run:

```text
.agents/workflows/resume-ipad-marionette.sh
```

That script exits `2` while Developer Mode is off. On `0` it is `flutter run -d 00008110-000E24912E63A01E` in `example/`. Parse the printed `?uri=ws://…` and `mcp_marionette-mc_connect`. Disconnect the Android Marionette session first (one connection at a time).

Permission sheets (Android `pm grant`, iOS simulator `simctl privacy`, physical Allow, Mac Automation) are the `device-permission-prompts` skill and [grant-device-permissions.md](../../workflows/grant-device-permissions.md). Android grant is **after** the first `flutter run` install, not before.

## 2. Start a debug session (pick one)

Prefer **A**. Use **B** when a matching `.vscode/launch.json` configuration exists.

### A. `flutter run` (canonical URI)

From `example/`, background:

```text
cd example && flutter run -d <device-id>
```

Wait until the console prints a DevTools / VM line. Extract the `ws://…` URI.

Verified on SM A176U1 (`flutter run` 2026-04-22):

```text
A Dart VM Service on SM A176U1 is available at:
http://127.0.0.1:51810/M4jw-VrDv6Q=/
The Flutter DevTools debugger and profiler on SM A176U1 is available at:
http://127.0.0.1:51810/M4jw-VrDv6Q=/devtools/?uri=ws://127.0.0.1:51810/M4jw-VrDv6Q=/ws
```

Connect with the `?uri=` value: `ws://127.0.0.1:51810/M4jw-VrDv6Q=/ws`.

Convert:

- DevTools `?uri=ws://HOST:PORT/AUTH/ws` → use that `ws://` value (preferred)
- `http://127.0.0.1:PORT/AUTH/` → `ws://127.0.0.1:PORT/AUTH/ws`
- already `ws://…` → use as-is

`flutter run` also starts a **DTD** on a neighboring port (here `ws://127.0.0.1:51809/…`). That is not the Marionette URI. Do not invent a port.

### B. DebugMCP

`.vscode/launch.json` configurations:

- `example (Media Room iPad)`
- `example (SM A176U1)`

Call `mcp_debugmcp_start_debugging` with:

- `fileFullPath`: `/Users/jameshancock/Repos/flutter_ai_communications/example/lib/main.dart`
- `workingDirectory`: `/Users/jameshancock/Repos/flutter_ai_communications/example`
- `configurationName`: the matching configuration

Then read the debug console / `flutter run` equivalent output for the same `ws://` URI. If DebugMCP starts the app but does not print a URI, fall back to A, or `dtd listConnectedApps` after the app is running and convert that VM service URI to `ws://`.

Do not use DebugMCP breakpoints as a substitute for Marionette. DebugMCP is how you *launch* and inspect Dart; Marionette is how you *tap the UI*.

## 3. Connect Marionette

```text
mcp_marionette-mc_connect  uri=ws://127.0.0.1:PORT/…
```

Failure modes:

| Symptom | Cause | Fix |
| --- | --- | --- |
| connect missing | MCP group disabled | activate Marionette tools |
| version mismatch | app lacks `marionette_flutter` binding | rebuild / hot **restart** after adding the binding |
| connection refused | used DTD URI or stale port | re-read the current `flutter run` line |
| no interactive elements | connected to the wrong isolate / splash | wait for first frame, then `get_interactive_elements` |
| `Sentinel kind: Collected` | isolate died (hot restart / kill) and Marionette still holds the old extension | §4a — do not retry taps |

One Marionette connection at a time. `disconnect` before switching devices.

## 4. Drive the harness

Prefer **keys**, not visible text.

| Key | Meaning |
| --- | --- |
| `start` | `AudioManager.start()` (permission prompt may block) |
| `mute` / `pause` / `stop` | Session controls |
| `prove` | Loopback echo identity — **not** native proof |
| `desired-*` / `applied-*` / `observed-*` | Route triad |
| `capture-frames` / `capture-rms` | Live capture |
| `pipeline-log` | On-screen `PipelineLog` tail |
| `isolation` | Isolation event (iOS) |

Sequence for an interactive smoke:

1. `get_interactive_elements`
2. `tap` key `start`
3. If iOS shows the microphone Allow sheet, load `device-permission-prompts`. Isolation Open is not that sheet.
4. Re-read elements: `status` is ready (or `routeConverging` while Observed settles), `capture-frames` / `capture-rms` when the live row is on screen
5. `get_logs` — must include `PipelineLog` lines (`pipeline.start.requested`, isolation, route). If logs say no collector, the binding was not installed; hot **restart**, not reload.
6. After Start, the control row can scroll off a phone viewport. `scroll_to` key `mute` (or `start`) before tapping Mute / Pause / Stop.

Verified 2026-04-22 on SM A176U1: Start → `pipeline.permission … granted` → Mute → `pipeline.session.mute muted=true` in `get_logs`. This is the loopback-wrapped harness.

## 4a. Reset after code changes or a stale session

Pick the cheapest reset that actually returns **idle home**. Verified on SM A176U1 2026-08-24.

| Want | Tool | What it does | Marionette connection |
| --- | --- | --- | --- |
| Apply UI-only Dart | `mcp_marionette-mc_hot_reload` | Keeps Session, mute, logs | Stays up |
| New run from `main()` | `mcp_marionette-mc_hot_restart` | Idle home, Start enabled, `get_logs` empty | Stays up |
| Same, via Dart MCP | `mcp_dart_and_flut_hot_restart` | Same reset | **Dies** — `Sentinel: Collected` until disconnect + reconnect **same** URI |
| End Session only | tap `stop` | `pipeline.session.stopped`; endpoint list still showing; logs remain | Stays up. **Not** a new run. |
| Stale / Sentinel / hung isolate | kill `flutter run`, relaunch | New VM service URI | Must `disconnect`, then `connect` the **new** `?uri=` |

Home means: `status` = `idle`, `start` enabled, `mute`/`pause`/`stop` disabled, `get_logs` empty. If `get_interactive_elements` returns `Sentinel kind: Collected`, stop tapping.

### Prefer Marionette `hot_restart`

Use this after code changes or to start a new run on a live connection. Do **not** use Dart-MCP `hot_restart` while Marionette is connected — it orphans the extension.

### Kill and relaunch when restart is not enough

Triggers: Sentinel, connect refused on the old URI, `hot_restart` failed, or the isolate is wedged after a binding / `main()` edit.

1. `mcp_marionette-mc_disconnect`
2. Find the host process (not the app PID on the phone):

```text
ps -ax -o pid,ppid,command | rg 'flutter_tools.snapshot run -d R5GL63B3GWV'
```

3. `kill <pid>` and wait until `ps -p <pid>` is gone. SIGKILL only if it is still alive after a few seconds.
4. Relaunch from **example/**, never the workspace root (`Target file "lib/main.dart" not found`):

```text
cd /Users/jameshancock/Repos/flutter_ai_communications/example && flutter run -d R5GL63B3GWV
```

5. Parse the **new** `?uri=ws://…`. The previous port/token is dead.
6. `mcp_marionette-mc_connect` with that URI. Confirm idle home before tapping `start`.

Verified 2026-08-24: killed PID 28937 (`dead after 2s`), relaunched, connected `ws://127.0.0.1:58864/kSyXapTA7IU=/ws`, home was idle with empty logs.

## 5. Logging rules

- Library: `package:logging` only. `PipelineLog.loggerName`.
- Example: `LoggingLogCollector` → Marionette `get_logs`.
- Do not add ISpect to the library or the example. ISpect is not what `get_logs` reads.
- `debugPrint` without a collector does **not** satisfy `get_logs`.

## 6. When to leave this skill

Need machine receipts, twenty cycles, or to close hardware issues? Stop tapping and run [real-device-marionette.md](../../workflows/real-device-marionette.md). Interactive Start on the loopback-wrapped harness is not #26.

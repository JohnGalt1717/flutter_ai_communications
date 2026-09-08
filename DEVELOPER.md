# Developing this package

For **agents** and humans who will run the example, index the graph, and
collect device receipts. Host-app install stays in [README.md](README.md).

## First-time machine

1. Flutter stable (Dart 3), Xcode, Android SDK, Node.js 22+.
2. Export `ANDROID_HOME` (and `JAVA_HOME`) in the **system/user environment**
   so Appium MCP inherits it. Do **not** put a machine path in `.mcp.json`.
3. Install [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp):

   ```text
   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
   ```

4. Install Appium MCP and its optional docs pack (never pulled unless you
   install it yourself):

   ```text
   npm install -g appium-mcp @appium/mcp-documentation
   ```

5. Restart the coding agent so `.mcp.json` loads.
6. Generate the graph index if `.codebase-memory/graph.db.zst` is missing
   (agents must do this themselves — see below).

`.mcp.json` already wires `codebase-memory-mcp`, `appium-mcp`,
`flutter_agent_lens`, and `flutter-skill`. It does **not** set
`ANDROID_HOME`. Export that in the shell/profile (macOS:
`~/Library/Android/sdk` is typical). Restart the agent so Appium MCP
inherits it. If `select_device` reports SDK root `/path/to/android/sdk`,
the variable is unset in the MCP process.

## Codebase memory

Graph tools (`search_graph`, `trace_path`, `get_architecture`) beat grep
for callers, packages, and impact. The project name is derived from the
repo path. Confirm with `list_projects`; do not hard-code a machine path.

### Generate / refresh the index

If `.codebase-memory/graph.db.zst` does not exist, or after a session that
changed a lot of code, run a full index with persistence:

- MCP: `index_repository` with `repo_path` = this repo, `mode` = `full`,
  `persistence` = `true`
- CLI: `codebase-memory-mcp cli index_repository '{"repo_path":"."}'`

That writes `.codebase-memory/graph.db.zst`. The file is gitignored (it
rewrites as a full blob). Teammates generate it locally. `index_status`
must report `status: ready` before you trust graph answers.

Agents: if `list_projects` is empty or `index_status` is not ready, index
before exploring. Re-index at the end of a session that landed native or
Dart structural changes.

## Device stack

| Surface | Tool |
| --- | --- |
| Launch / attach / VM URI / logs | `flutter_agent_lens` |
| Flutter UI (keys `lobby-enter`, `screen-share`, …) | `flutter-skill` |
| OS sheets (mic Allow, MediaProjection, ReplayKit, TCC, nearby devices) | Appium MCP (`fac-os-sheets`) |
| Pre-grant Android mic/camera after APK exists | `.agents/workflows/grant-device-permissions.sh` |
| Force Android OS sheets to appear | `adb uninstall com.example.flutter_ai_communications` then `flutter run`; Appium `autoGrantPermissions: false` |
| iOS hardware retry | `flutter run` over the existing install. **Never uninstall** — that re-prompts developer trust. |

Do **not** use Appium to tap Flutter widgets. Do **not** use flutter-skill
to tap a system sheet. Load `device-agent-lens` then `fac-os-sheets` for a
receipt run.

Appium sessions that attach to an already-running `flutter run` must set
`appium:autoLaunch` false, `appium:noReset` true, and
`appium:dontStopAppOnReset` true so the Dart VM stays up. Presets live in
[`.appium.capabilities.json`](.appium.capabilities.json). Pass `appium:udid`
at session create from `flutter devices` (this lab’s known ids live in
`device-agent-lens`). iOS WDA signing values in the capability preset and
[`.appium.wda.xcconfig`](.appium.wda.xcconfig) are this repository’s
Development team. Other contributors override `appium:xcodeOrgId` at
session create.

## Example harness

```text
cd example
flutter run -d R5GL63B3GWV --vm-service-port=50005
```

Pin the printed `ws://127.0.0.1:<port>/<token>=/ws`. Screen receipts:
`.agents/workflows/screen-send-orchestration.md`. Audio receipts:
`.agents/workflows/real-device-orchestration.md`.

## Tests

`flutter test` from a **package** dir, never the workspace root. Native
suites: `example/integration_test/native_screen_test.dart` and
`native_orchestration_test.dart`.

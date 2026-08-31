---
name: device-agent-lens
description: Attach/debug a physical Flutter device with flutter_agent_lens (discover, VM URI, logs, breakpoints, evaluate) and drive the UI with flutter-skill (inspect, tap, type, scroll, screenshot). Use when the user asks to Agent Lens a device, use flutter-skill, get a ws:// URI without VS Code debug, or replace Marionette/DebugMCP.
---

# Device Agent Lens + flutter-skill

No VS Code debug session. No Marionette. No DebugMCP.

| Tool | Role |
| --- | --- |
| **flutter_agent_lens** | Launch/attach, discover apps, `ws://` URI, console logs, breakpoints, evaluate, hot reload/restart |
| **flutter-skill** | See and drive the UI: inspect, tap, type, scroll, screenshot |

## Preconditions

1. Example `main()` calls `FlutterSkillBinding.ensureInitialized()` in debug only.
2. MCP servers configured: `flutter_agent_lens` (`flutter-agent-lens`) and `flutter-skill` (`flutter-skill server`).
3. Devices connected (`flutter devices`). Known ids:
   - James’s iPhone → `00008150-000664981A38401C`
   - SM A176U1 → `R5GL63B3GWV`
4. Permission sheets: `device-permission-prompts` / grant workflow.

## Launch (no IDE debug)

Prefer Agent Lens / flutter-skill launch over `workbench.action.debug.*`.
Do **not** use VS Code debug configurations.

`.mcp.json` starts flutter-skill with the Dart executable, not a shell wrapper:

```json
"flutter-skill": {
  "command": "flutter_skill",
  "args": ["server"]
}
```

Launch the app with the flutter-skill MCP `launch_app` tool (`project_path` = `example/`, `device_id` = chrome / ios / android id, `extra_args` include `--vm-service-port=50000`). Or:

```text
cd example && flutter run -d <device-id> --vm-service-port=50000
```

Capture the printed `ws://127.0.0.1:<port>/<token>=/ws`. Then:

1. flutter_agent_lens `discover_apps` with `workspace_root` = example path, `autoConnect: true`
2. Or flutter_agent_lens `connection` `connect` with that `ws://…/ws` and `workspace_root`
3. Drive UI with flutter-skill MCP `inspect`, `tap`, `screenshot` (keys: `lobby-enter`, `lobby-join`, `mute`, `pause`)

If `inspect` is empty after taps, Agent Lens `hot_restart` usually restores the semantics tree. Binding order in `example/lib/main.dart` must be `WidgetsFlutterBinding.ensureInitialized()` then `FlutterSkillBinding.ensureInitialized()`.

## Split of responsibility

- **Start / attach / logs / breakpoints / evaluate / hot reload** → Agent Lens
- **Tap Start/Mute/Pause, pick endpoints, screenshots** → flutter-skill
- **Mic Allow sheet** → human (physical) or `device-permission-prompts`

## Do not

- Start a VS Code debug configuration for this path.
- Add `marionette_flutter` / `marionette_logging` back to `example/`.
- Treat loopback wrap in `example/lib/main.dart` as native proof.
- Rely on flutter-skill auto-discover when two devices (or iproxy) are live — pin the URI.
- Launch a second device on the default `--vm-service-port=50000` while another session holds it.

## Recovery

If discover finds nothing: confirm the app is still running in debug/profile, reconnect Agent Lens to DTD if needed, then `discover_apps` again. Kill stale `flutter run` only if the process is hung — do not uninstall the app.

Port conflict (`Address already in use …:50000`): relaunch with `--vm-service-port=<free>` and reconnect to the new `ws://`.

---
name: device-marionette
description: Deprecated. Redirects to device-agent-lens. Use when the user says Marionette, DebugMCP, or asks for the old VM-service tap/get_logs path — load device-agent-lens instead.
---

# Deprecated: use `device-agent-lens`

Marionette / DebugMCP are **removed** from the example harness.

| Old | New |
| --- | --- |
| `marionette_flutter` / `MarionetteBinding` | `flutter_skill` / `FlutterSkillBinding` |
| Marionette MCP tap / `get_logs` | **flutter-skill** for UI; **flutter_agent_lens** for attach/logs/breakpoints |
| VS Code debug for VM URI | `dart run flutter_skill launch . -d <id>` (no IDE debug) |

Load and follow [device-agent-lens](../device-agent-lens/SKILL.md).

Receipt workflows (native suite, permission grants) remain under:

- [real-device-marionette.md](../../workflows/real-device-marionette.md)
- [device-permission-prompts](../device-permission-prompts/SKILL.md)

Do **not** re-add `marionette_flutter` or `marionette_logging` to `example/`.

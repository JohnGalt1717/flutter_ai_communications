# Agent guide

Functional Teams/Zoom-class communications for Flutter. The host owns signaling, preference persistence, tile layout, and product UI. This repo is the Communications manager.

## Read first

1. `CONTEXT.md` — glossary. Use those terms; do not revive the `_Avoid_` list.
2. `docs/adr/` — every ADR in the area you are touching.
3. `docs/agents/domain.md` — when to load domain docs.
4. `docs/agents/issue-tracker.md` — GitHub Issues via `gh`.
5. `docs/agents/triage-labels.md` — triage vocabulary.
6. `.agents/workflows/` — how to run a named job (device matrix, receipts).

If a term is missing from `CONTEXT.md`, stop and add it with `/domain-modeling` before inventing a synonym.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues; use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical labels `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository using root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.

## Layout

Pub workspace (Dart 3 `workspace:` / `resolution: workspace`), federated Flutter plugin:

```text
packages/flutter_ai_communications/                    # Communications manager
packages/flutter_ai_communications_platform_interface/
packages/flutter_ai_communications_shared/             # pairing, floor, barge-in, transcode
packages/flutter_ai_communications_ios/
packages/flutter_ai_communications_android/
packages/flutter_ai_communications_web/
packages/flutter_ai_communications_macos/
packages/flutter_ai_communications_windows/
packages/flutter_ai_communications_linux/
example/                                               # AI-voice agent harness (flutter-skill + agent_lens)
```

Do not add Melos.

Follow current Flutter federated-plugin and pub-workspace conventions (`pubspec.yaml`, shared analysis options, path/`workspace` resolution). Native C DSP, if any, uses Native Assets hooks (`dart-setup-ffi-assets`, `dart-use-ffigen`) inside the non-web packages that need it — not a root FFI stub.

## Skills to load

Load the skill before the work it covers:

| Work | Skill |
| --- | --- |
| Domain terms, `CONTEXT.md`, ADRs | `domain-modeling` |
| Interface / seam shape | `codebase-design` |
| Tests | `tdd`, then `dart-add-unit-test` / `flutter-add-widget-test` / `flutter-add-integration-test` |
| Native C / hooks / bindings | `dart-setup-ffi-assets`, `dart-use-ffigen` |
| Dart 3 constructors / switches | `dart-use-primary-constructors`, `dart-use-pattern-matching` |
| Analyze | Dart MCP / `mcp_dart_and_flut_analyze_files` — not routine `dart analyze` |
| This file or a skill | `writing-for-agents` |
| Grill / plan | `grill-with-docs` (`grilling` + `domain-modeling`) |
| Attach/debug via flutter_agent_lens; UI drive via flutter-skill | `device-agent-lens` |
| Mic / OS permission sheets, `pm grant`, `simctl privacy`, first-start Allow | `device-permission-prompts` |
| Physical iOS/Android native receipts | `.agents/workflows/real-device-orchestration.md` |
| Ship PR → CI → Copilot review → squash-merge | `/ship-pr-review-loop` |

## Non-negotiables

- One live Session per Communications manager, plus at most one Camera preview. `start()` returns a `StartResult`; expected failures are values, not thrown exceptions. Missing camera or failed screen send does not fail the Session.
- Permission blocks until the OS answers. Microphone (and camera when camera send is on) is requested inside `start()`. Screen recording is requested inside `beginScreenPick` or `startScreenShare`, never Session `start()`.
- One capture stream: Transport, visualizer, and VOD see the same bytes. Mute emits silence frames. System audio on screen send is not that stream.
- Native reset must not replace the Session or its broadcast streams (ADR-0004).
- Isolation is an event. No user-facing strings in the library (ADR-0005).
- No `record`, `flutter_recorder`, or `flutter_soloud`. No ISpect dependency; log with `package:logging`.
- Device-order preference persistence is host-owned. Camera is in scope (catalog, Session video, Camera preview, Transport plugin). Screen send is in scope: catalog, Screen pick, Share frame, native Production video path. Spec: `docs/spec-screen-v1.md`.

## Testing

Test at public seams (`CommunicationsManager` / today's `CommunicationsManager`, `Session`, `CoverageSource`, platform interface). Prefer a fake platform adapter over mocks of internals. Fixture PCM/WAV in, assert bytes and events out. The example is the AI-voice agent harness for iOS, Android, web, macOS, Windows, and Linux — not a SignalR demo. Its lobby subsection is the Orchestration e2e path (permission, device picks, Join).

Physical iOS, Android, and Chrome: follow `.agents/workflows/real-device-orchestration.md` (receipts) and `device-agent-lens` (flutter_agent_lens + flutter-skill). `flutter test` from a package dir. Loopback identity is not native proof.

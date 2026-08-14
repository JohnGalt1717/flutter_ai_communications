# Agent guide

Functional Teams/Zoom-class communications audio for Flutter. The host owns Transport, device-order preference, and product UI. This repo is the Audio manager.

## Read first

1. `CONTEXT.md` — glossary. Use those terms; do not revive the `_Avoid_` list.
2. `docs/adr/` — every ADR in the area you are touching.
3. `docs/agents/domain.md` — when to load domain docs.
4. `docs/agents/issue-tracker.md` — GitHub Issues via `gh`.
5. `docs/agents/triage-labels.md` — triage vocabulary.

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
packages/flutter_ai_communications/                    # AudioManager
packages/flutter_ai_communications_platform_interface/
packages/flutter_ai_communications_shared/             # pairing, floor, barge-in, transcode
packages/flutter_ai_communications_ios/
packages/flutter_ai_communications_android/
packages/flutter_ai_communications_web/
packages/flutter_ai_communications_macos/
example/                                               # Marionette AI-voice harness
```

Desktop remaining: `windows`, `linux`. Do not add Melos.

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

## Non-negotiables

- One live Session per Audio manager. `start()` returns a `StartResult`; expected failures are values, not thrown exceptions.
- Permission is requested inside `start()` and blocks until the OS answers.
- One capture stream: Transport, visualizer, and VOD see the same bytes. Mute emits silence frames.
- Native reset must not replace the Session or its broadcast streams (ADR-0004).
- Isolation is an event. No user-facing strings in the library (ADR-0005).
- No `record`, `flutter_recorder`, or `flutter_soloud`. No ISpect dependency; log with `package:logging`.
- Device-order preference is host-owned and out of scope. Camera is out of scope.

## Testing

Test at public seams (`AudioManager`, `Session`, `CoverageSource`, platform interface). Prefer a fake platform adapter over mocks of internals. Fixture PCM/WAV in, assert bytes and events out. The example is the Marionette harness for iOS, Android, web, and macOS — not a SignalR demo.

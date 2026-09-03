# Screen send Orchestration

Prove native screen send on a real head through the example harness. Audio
loopback identity is a different path and is not this receipt.

Interactive MCP (launch → VM service → tap keys / screenshot) is the
`device-agent-lens` skill. This file is the receipt job. Do not mix them
with `.agents/workflows/real-device-orchestration.md` (mic/route matrix).

Apple native graphs are issue #43. Empty catalog or `skipped=none` on
iOS/macOS is expected until that issue lands — not a pass.

## Load first

`device-agent-lens`, then `device-permission-prompts` if a Screen Recording
or MediaProjection sheet will appear. Read `CONTEXT.md`, `docs/spec-screen-v1.md`,
and issue #44.

## Two proofs

| Proof | Command / tools | Counts as native graph |
| --- | --- | --- |
| Automated Session seam | `flutter test integration_test/native_screen_test.dart -d <id>` from `example/` | yes |
| Host chrome | flutter-skill on `example/` `lib/main.dart` (keys below) | no — Texture/HtmlElementView appearing is host wiring; pair with the automated receipt |

Unattended `native_screen_test` **does not** call `startScreenShare` on a
system-picker catalog (web, Android, iOS, Wayland). That would hang on the
OS picker. Those platforms finish share through flutter-skill with a human
tap on the OS sheet, then the same assertions.

## Discover

From the repo root:

```text
flutter devices
```

Use the **id** column.

| Label | Typical id | Catalog | Share |
| --- | --- | --- | --- |
| Windows desktop | `windows` | display, window, All-displays | automated |
| Linux X11 | `linux` | display, window, All-displays | automated |
| Linux Wayland | `linux` | one system-picker source | flutter-skill + portal |
| Chrome | `chrome` | one system-picker source | flutter-skill + getDisplayMedia |
| SM A176U1 | `R5GL63B3GWV` | one system-picker source | flutter-skill + MediaProjection |
| macOS | `macos` | display, window, All-displays | automated |
| James’s iPhone | `00008150-000664981A38401C` | one system-picker source | flutter-skill + Broadcast; wireless/sim not proof |

If the requested id is missing, stop. Wireless iPhones and simulators are
not iOS Broadcast proof.

## Automated run

From `example/`. Never `flutter test` at the workspace root.

```text
cd example
flutter test integration_test/native_screen_test.dart -d windows
flutter test integration_test/native_screen_test.dart -d linux
```

The suite must not wrap `LoopbackCommunicationsPlatform`. It asserts:

- idle `screenSources()` metadata
- lobby `beginScreenPick` / `startScreenShare` are typed failures
- `start()` never auto-shares
- enumerable share yields a local Video surface
- camera send and screen send are two handles when a camera exists
- Camera-off does not stop screen send
- Include sound may stay off (status warning); share stays video-only
- twenty start/stop cycles keep the same Capture stream
- `manager.session == null` after stop

`skipped=none` (empty catalog) and `skipped=os-picker` (system-picker only)
are receipts, not passes.

## flutter-skill drive (host chrome + OS picker)

Launch the example with flutter-skill `launch_app` (`project_path` =
`example/`, `device_id` = the id above, `extra_args` include
`--vm-service-port=50000`) or:

```text
cd example && flutter run -d <device-id> --vm-service-port=50000
```

Attach with flutter_agent_lens. Drive with flutter-skill inspect / tap /
scroll / screenshot.

Keys (do not collide with lobby audio keys):

| Key | When |
| --- | --- |
| `lobby-enter` | idle → lobby Session |
| `lobby-join` | lobby → meeting Session (required before Share) |
| `screen-session` | idle shortcut to a meeting Session |
| `screen-source-*` | indicate a source (enumerable) |
| `screen-share` | `startScreenShare`; OS picker runs here on system-picker platforms |
| `screen-stop` | `stopScreenShare` |
| `screen-sound` / `screen-motion` / `screen-cursor` | live toggles |
| `screen-loopback` | local send Video surface (Texture or HtmlElementView) |
| `screen-status` | last ScreenShare result text in the host |

Sequence:

1. `lobby-enter` → `lobby-join` (or `screen-session` from idle).
2. Scroll to Screen send. Screenshot catalog.
3. Enumerable: tap `screen-source-*`, confirm Share frame on the real
   window/display, screenshot thumbs (`screen-preview-*`).
4. Tap `screen-share`. On OS-picker platforms wait for the human to pick
   a display/window/tab in the OS sheet.
5. Assert `screen-loopback` is a live surface, not `Not sharing`.
6. If a camera is on, `self-view` stays up (two Production paths).
7. Toggle Include sound / Optimize / Cursor.
8. `screen-stop`. Loopback returns to `Not sharing`. Session stays.
9. Repeat share/stop once more. Screenshot.

Windows picker thumbs must not show a yellow Graphics Capture border on
every window.

## Receipt

Machine-readable, out of source control. File name:

```text
<temp>/flutter_ai_communications_receipts/<commit>-<platform>-<device>-screen.json
```

The automated suite prints `NATIVE_ORCHESTRATION_RECEIPT {json}` and writes
the same JSON under the device `Directory.systemTemp`. Copy it to the host
artifact location.

Must include commit, platform, OS, hardware, catalog kinds, whether lobby
was blocked, shared source id/kind, camera+screen, Include sound applied,
cycle count, and `skipped` (`false` / `none` / `os-picker`). Flutter-skill
runs attach screenshots of catalog, Share frame (enumerable), loopback, and
stop.

## Fail closed

Permission denied that ends the Session, missing screen surface after a
successful OS pick, camera handle reused as the screen handle, Capture
stream replaced across screen start/stop, leftover native graph after stop,
or treating `skipped=none` / `skipped=os-picker` / loopback identity as a
native pass: stop and comment issue #44. Do not mark the matrix done.

Close #44 only with a `skipped=false` receipt per shipped graph (Windows,
Linux X11, Android, web today; macOS and iOS after #43).

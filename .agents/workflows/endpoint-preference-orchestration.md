# Endpoint preference Orchestration

Prove Endpoint preference as ordered render rows with capture lists. Loopback
identity is a different path. Screen send is a different workflow.

Interactive MCP (debug session → VM service URI → tap harness keys) is the
`device-agent-lens` skill plus flutter-skill. This file is the receipt job
and the permutation matrix.

## Load first

`tdd`, `device-agent-lens`. Read `CONTEXT.md` **Endpoint preference** /
**Explicit selection**, ADR-0029, and this matrix.

## What is covered where

| Permutation | Unit (`PreferenceResolver`) | Session (`session_contracts_test`) | Harness UI + widget test | Native receipt | flutter-skill unplug |
| --- | --- | --- | --- | --- | --- |
| Empty list → platform-default complete Pairs | yes | yes | Apply empty draft | empty start | no |
| USB+Brio row outranks AirPods | yes | yes | capture chip + Apply | `native_orchestration_desktop_preference_test` | no |
| Capture list fallback (Brio gone, speakers stay) | yes | yes | n/a (needs unplug) | no | **yes — desktop** |
| Skip row when listed captures all gone | yes | yes | n/a | no | yes if USB row is `[Brio]` only |
| Same mic on many render rows | yes | no (resolver is enough) | chip on two rows | no | optional |
| Disabled render row / capture slot | yes | no | enable switch | no | no |
| Explicit render auto-completes from the row | yes | yes | live Endpoints list | desktop explicit USB test | no |
| Explicit render does not steal from another row | yes | skip-row Session test | n/a | no | unplug Brio with `[Brio]` only |
| Unlisted unpaired render + capture-only walk | yes | no | tap USB before Apply | no | yes |
| Capture-only ignores missing render | yes | yes | n/a | no | no |
| Playback-only ignores capture lists | yes | yes | n/a | no | no |
| Select capture keeps render | yes | yes | tap capture Endpoint | no | no |
| Select render clears capture override | yes | yes | tap render after capture | no | no |
| Lock live (Explicit both) blocks Brio return | yes (override flags) | yes | `pref-lock` | no | **yes — desktop** |
| Unusable combo walks next capture then next row | yes | preference walk downward | n/a | OS mismatch existing | no |
| New Session ignores prior Explicit | n/a | yes | Leave + Enter lobby | native-orchestration_test | no |
| bindPreference ends Session | n/a | yes | `pref-apply` | no | no |
| Catalog grouping complete vs unpaired | `EndpointCatalogGroups` | n/a | editor rows | n/a | n/a |

Catalog updates are OS device notifications on every head (iOS route
change, Android AudioDeviceCallback, web `devicechange`, Windows
`IMMNotificationClient`, Pulse subscribe, macOS Core Audio listeners).
There is no two-second catalog poll.

Remote control of the example cannot unplug USB hardware. Catalog-change
permutations that need disappearance are Session unit tests plus the
flutter-skill unplug cases below.

## Automated (no device)

From the repo:

```text
cd packages/flutter_ai_communications_shared
dart test test/endpoint_preference_test.dart

cd packages/flutter_ai_communications
flutter test test/session_contracts_test.dart

cd example
flutter test test/preference_editor_test.dart test/harness_test.dart
```

Never `flutter test` at the workspace root.

## Native desktop receipt

Requires a Brio-class capture Endpoint and a USB render Endpoint in the
catalog, plus AirPods or another complete Pair below.

From `example/`:

```text
flutter test integration_test/native_orchestration_desktop_preference_test.dart -d windows
```

Cases:

1. Preference-controlled USB+Brio above AirPods (Observed matches Desired).
2. Explicit `select(renderId: usb)` auto-completes Brio from that row.

Capability missing: fail the suite (this is a desktop proof, not
`skipped=capability`).

## flutter-skill drive (host chrome)

Keys on `example/lib/main.dart` and `preference_editor.dart`:

| Key | Action |
| --- | --- |
| `preference-editor` | Section |
| `pref-capture-<renderId>-<captureId>` | Toggle that capture on that render row |
| `pref-row-enable-<renderId>` | Enable/disable the row |
| `pref-row-up-<renderId>` / `pref-row-down-<renderId>` | Reorder draft |
| `pref-apply` | `bindPreference` (ends a live Session) |
| `pref-reset` | Empty draft (platform default) |
| `pref-lock` | Explicit both current ids |
| `pref-bound-count` | Draft row count |
| `endpoint-<id>` | Live Explicit pick (output-first, then capture override) |
| `preference-controlled` | `true` / `false` |
| `desired-capture` / `desired-render` | Desired Pair |
| `desired-capture-override` | Capture departed from auto-complete |
| `lobby-enter` / `lobby-join` / `lobby-leave` | Lobby |

### Compose USB+Brio (idle)

1. Idle. Scroll to `preference-editor`.
2. Tap `pref-capture-<usbRenderId>-<brioId>`.
3. Optionally tap `pref-capture-<usbRenderId>-<airpodsInId>` as fallback.
4. Tap `pref-apply`. Status `preference-bound`.
5. `lobby-enter`. Assert `desired-render` is USB, `desired-capture` is Brio,
   `preference-controlled` is `true`.

### Unplug fallback (desktop, human)

After compose + Enter lobby:

1. Unplug Brio.
2. Assert `desired-render` still USB and `desired-capture` is the next listed
   capture (AirPods mic if that chip was selected).
3. Plug Brio back. Assert capture returns to Brio unless `pref-lock` was tapped
   while on the fallback mic.

### Lock

On the fallback mic (Brio unplugged): tap `pref-lock`. Plug Brio back.
`desired-capture` stays the locked mic. `desired-capture-override` is `true`
once Brio is first on the list again.

### Live split

`endpoint-<usb-out>` then `endpoint-<airpods-in>`: render USB, capture AirPods
mic, `preference-controlled` false. Do not tap capture first if you want the
output auto-complete.

## Fail closed

Preference-controlled Observed ≠ Desired after convergence, Apply that did not
bind, or a skip that substituted loopback: stop. Unplug cases without a
human/device: record as not run, do not mark the matrix done.

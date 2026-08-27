---
name: device-permission-prompts
description: Grant OS permission prompts during Flutter debug and Agent Lens / flutter-skill device runs. Use when start() hangs on a microphone Allow dialog, Android pm grant, iOS simctl privacy, physical-device TCC, Mac Automation, Patrol grantPermissionWhenInUse, or XCTest addUIInterruptionMonitor.
---

# Device permission prompts

`start()` requests permission and **blocks until the OS answers**. The dialog is a system sheet (SpringBoard / package installer / TCC), not Flutter UI. flutter-skill, Agent Lens, `integration_test`, and `widget_inspector` cannot tap it.

Receipts stay in [real-device-orchestration.md](../../workflows/real-device-orchestration.md). The grant job is [grant-device-permissions.md](../../workflows/grant-device-permissions.md).

## Pick a lane

| Surface | Lane | Agent action |
| --- | --- | --- |
| Android phone / emulator / tablet | `adb pm grant` after the APK exists | Run [grant-device-permissions.sh](../../workflows/grant-device-permissions.sh) |
| iOS / iPadOS **simulator** | `xcrun simctl privacy … grant microphone` | Same script |
| Physical iPhone / iPad | First `start()` shows Allow. Later runs reuse TCC | Tell the human to tap **Allow**. Isolation Open is not this prompt |
| Host Mac controlling Xcode | Privacy & Security → Automation | Tell the human to allow Terminal / VS Code / dart to control Xcode |
| Future native-dialog suite | Patrol `$.platform.mobile.grantPermissionWhenInUse()` | See Patrol below. Do not add Patrol during an exclusive receipt run |

Done when `start()` returns `StartReady` (or the grant command exits 0 and the next `start()` will not show a sheet).

## Android

Install first. `Failure [package not found]` means the APK is not on the device.

```text
.agents/workflows/grant-device-permissions.sh R5GL63B3GWV
```

That is `adb -s <id> shell pm grant com.example.flutter_ai_communications android.permission.RECORD_AUDIO`. Confirm with `adb -s <id> shell dumpsys package com.example.flutter_ai_communications | rg RECORD_AUDIO`.

## iOS Simulator

```text
.agents/workflows/grant-device-permissions.sh <simulator-udid>
```

That is `xcrun simctl privacy <udid> grant microphone com.example.flutterAiCommunications`. `applesimutils --setPermissions` is the same idea. Both are **simulator-only**. They do not write TCC on a physical device.

Reset (next `start()` will prompt again):

```text
xcrun simctl privacy <udid> reset microphone com.example.flutterAiCommunications
```

## Physical iOS / iPadOS

There is no `devicectl` / `simctl` grant for microphone on hardware. XCTest `addUIInterruptionMonitor` and Appium `autoAcceptAlerts` run only inside an XCUITest / WebDriverAgent process. `flutter drive`, `flutter test integration_test/…`, flutter-skill, and Agent Lens are not that process.

1. Keep the exclusive `flutter drive` / `flutter run` alive.
2. Ask the human: tap **Allow** on the microphone sheet. Isolation Open is host UI — leave it; it is not a suite gate.
3. Wait for `StartReady`. Later installs that keep the same bundle id reuse TCC. A delete/reinstall resets it.

Wireless Local Network is a different sheet (debug VM). Grant that too if `flutter run` cannot discover the Dart VM.

## Host Mac Automation

When the log says `You may be prompted to give access to control Xcode`, the sheet is on the **Mac**, not the device. Grant once: System Settings → Privacy & Security → Automation → allow the launching app (Terminal, VS Code, dart) to control Xcode. Without it, install hangs at `The Dart VM Service was not discovered after 60 seconds`.

## Patrol

Patrol is the Dart API that *does* tap a live native permission sheet (`$.platform.mobile.grantPermissionWhenInUse()`, `grantPermissionOnlyThisTime()`, `denyPermission()`). It needs `patrol` + `patrol_cli`, native XCUITest / instrumentation setup, `patrol test` (not `flutter drive`), and English (US) on iOS.

Do **not** add Patrol, change the example runner, or start a second Flutter process while an exclusive receipt is in flight. Record the gap and keep the human-Allow lane. Adding Patrol is a separate change after the exclusive suite finishes.

## Isolation

iOS Isolation Open (`AVCaptureDevice.showSystemUserInterface(.microphoneModes)`) is host UI. The native suite must not block on it. Microphone Allow is the only permission gate for `StartReady`.

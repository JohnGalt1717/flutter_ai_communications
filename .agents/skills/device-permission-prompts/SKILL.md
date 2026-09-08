---
name: device-permission-prompts
description: Grant OS permission prompts during Flutter debug and Agent Lens / flutter-skill device runs. Use when start() hangs on a microphone Allow dialog, Android pm grant, iOS simctl privacy, physical-device TCC, Mac Automation, Patrol grantPermissionWhenInUse, or XCTest addUIInterruptionMonitor. Live sheets that need a tap go through fac-os-sheets (Appium).
---

# Device permission prompts

`start()` requests permission and **blocks until the OS answers**. The dialog is a system sheet (SpringBoard / package installer / TCC), not Flutter UI. flutter-skill, Agent Lens, `integration_test`, and `widget_inspector` cannot tap it.

Receipts stay in [real-device-orchestration.md](../../workflows/real-device-orchestration.md). The grant job is [grant-device-permissions.md](../../workflows/grant-device-permissions.md).

## Pick a lane

| Surface | Lane | Agent action |
| --- | --- | --- |
| Android phone / emulator / tablet | `adb pm grant` after the APK exists | Run [grant-device-permissions.sh](../../workflows/grant-device-permissions.sh) |
| iOS / iPadOS **simulator** | `xcrun simctl privacy … grant microphone` | Same script |
| Live OS sheet (mic Allow, MediaProjection, ReplayKit, TCC, nearby devices) | Appium attach | Load [fac-os-sheets](../fac-os-sheets/SKILL.md). Do not adb-tap Start on the home picker. |
| Physical iPhone / iPad when Appium WDA is not signed | First `start()` shows Allow. Later runs reuse TCC | Tell the human to tap **Allow**. Isolation Open is not this prompt |
| Host Mac controlling Xcode | Privacy & Security → Automation | Tell the human to allow Terminal / VS Code / dart to control Xcode |

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

There is no `simctl` grant for microphone on hardware. flutter-skill cannot tap the sheet. Appium XCUITest (`fac-os-sheets`, `autoAcceptAlerts`) can, once WDA is signed via `appium_prepare_ios_real_device`.

If WDA is not signed: keep the exclusive `flutter run` alive and ask the human to tap **Allow**. Isolation Open is host UI — leave it.

Wireless Local Network is a different sheet (debug VM). Grant that too if `flutter run` cannot discover the Dart VM.

**Do not uninstall** `com.example.flutterAiCommunications` on hardware. Deleting the app clears developer trust; the next install asks to re-approve the developer account. Retry with `flutter run` over the existing install. `ideviceinstaller -U`, `devicectl device uninstall`, and Xcode “Delete App” are the same mistake.

## Host Mac Automation

When the log says `You may be prompted to give access to control Xcode`, the sheet is on the **Mac**, not the device. Grant once: System Settings → Privacy & Security → Automation → allow the launching app (Terminal, VS Code, dart) to control Xcode. Without it, install hangs at `The Dart VM Service was not discovered after 60 seconds`.

## Patrol

Patrol is the Dart API that *does* tap a live native permission sheet (`$.platform.mobile.grantPermissionWhenInUse()`, `grantPermissionOnlyThisTime()`, `denyPermission()`). It needs `patrol` + `patrol_cli`, native XCUITest / instrumentation setup, `patrol test` (not `flutter drive`), and English (US) on iOS.

Do **not** add Patrol, change the example runner, or start a second Flutter process while an exclusive receipt is in flight. Record the gap and keep the human-Allow lane. Adding Patrol is a separate change after the exclusive suite finishes.

## Isolation

iOS Isolation Open (`AVCaptureDevice.showSystemUserInterface(.microphoneModes)`) is host UI. The native suite must not block on it. Microphone Allow is the only permission gate for `StartReady`.

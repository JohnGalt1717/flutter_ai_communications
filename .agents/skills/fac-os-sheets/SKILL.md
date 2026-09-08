---
name: fac-os-sheets
description: Tap OS permission and screen-share sheets with Appium MCP while flutter-skill drives the example. Use when start() hangs on Allow, MediaProjection, ReplayKit Broadcast picker, ScreenCaptureKit TCC, nearby-devices, or any system dialog flutter-skill cannot see.
---

# OS sheets (Appium)

Flutter UI → `device-agent-lens` / flutter-skill. **This skill is only the
system dialog** (SpringBoard, SystemUI, TCC, MediaProjection, ReplayKit).

Keep the exclusive `flutter run` / `flutter drive` alive. Appium must
**attach**, not relaunch.

## Setup once per device

1. `select_device` with `platform` android|ios and `deviceUdid` (SM A176U1
   `R5GL63B3GWV`; iPhone 17 sim `4A99E018-E415-496E-BE37-5BC143084B6B`;
   iOS sim also needs `iosDeviceType=simulator`).
2. iOS **simulator**: `prepare_ios_simulator` then pass `capabilitiesHint`
   into create. If WDA “launched but did not become ready”, do not create a
   session — iOS sheets stay blocked until WDA answers. iOS **hardware**
   (James’s iPhone `00008150-000664981A38401C`): create XCUITest with
   `appium:xcodeOrgId=3RQSQYAB58`, `appium:xcodeSigningId=Apple Development`,
   `appium:updatedWDABundleId=com.example.flutterAiCommunications.wda`,
   `appium:xcodeConfigFile` = [`.appium.wda.xcconfig`](../../../.appium.wda.xcconfig),
   `appium:allowProvisioningUpdates=true`. Do not wait for a human to pick a
   profile. `appium_prepare_ios_real_device` is optional; there is no
   wildcard `*` profile. macOS TCC: `platform=general` + Mac2.
3. `appium_session_management` `action=create` with that platform. Do **not**
   invent `http://localhost:4723`. Omit `remoteServerUrl` (embedded drivers).
   Merge [`.appium.capabilities.json`](../../../.appium.capabilities.json)
   plus `appium:udid`. Required: `autoLaunch=false`, `noReset=true`,
   `dontStopAppOnReset=true`, `skipUninstall=true`.
4. iOS: if the phone shows **Automation is running**, WDA is in front —
   `appium_app_lifecycle` `activate` `com.example.flutterAiCommunications`.
   Do **not** activate while a ReplayKit sheet is up — that dismisses it.
   After **Start Sharing**, activate the example, then `action=delete` the
   Appium session within a minute so WDA does not linger. Never uninstall
   the example.

To **exercise** OS sheets on Android, uninstall the package first
(`adb uninstall com.example.flutter_ai_communications`) so runtime
permissions reset. Do **not** run `grant-device-permissions.sh` and set
`appium:autoGrantPermissions` false on that session. After the sheets
are proven, `pm grant` is still the fast lane for receipts that are not
about the dialog.

Never uninstall the **iOS** example on hardware to reset sheets. That
clears developer trust and forces a developer-account re-approve.
`flutter run` over the existing install. Android uninstall is Android-only.

## Tap the sheet

1. `appium_alert` `action=get_text`. If a standard alert, `accept` with
   `buttonLabel` Allow (mic, camera, nearby devices, Wireless Local Network).
2. Else `appium_get_page_source` and find by **accessibility id** then **id**,
   then platform-native. `appium_find_element` → `appium_gesture` `tap`.
3. Android MediaProjection (not an alert):
   - Title contains “Share your screen”
   - Prefer **Share one app** (entire screen backgrounds the app and can
     drop the debug VM). Tap **Next**.
   - Pick `flutter_ai_communications_example`. Tap **Start**.
4. iOS ReplayKit (SpringBoard, not the Flutter app): tap **Start Sharing**
   (iOS 27) or **Start Broadcast**. Prefer the extension row
   `AI Communications Screen`. Isolation Open is host UI — leave it.
5. macOS Screen Recording TCC: Allow this time / this app.

Done when flutter-skill `screen-status` is `sharing` or `start()` returned
`StartReady`. Delete the Appium session when the receipt run ends
(`action=delete`) so the UiAutomator2 / WDA process does not linger.

## Fail closed

If `select_device` says the SDK root is `/path/to/android/sdk`, `ANDROID_HOME`
is unset in the Appium MCP process. It must come from the **user environment**,
not `.mcp.json`. Restart the agent after exporting it. Do not invent
`http://localhost:4723`.

If Appium would kill `flutter run`, stop and use
[device-permission-prompts](../device-permission-prompts/SKILL.md) human
Allow instead of fighting the session.

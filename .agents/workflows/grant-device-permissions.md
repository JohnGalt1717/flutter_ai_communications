# Grant device permissions

Pre-grant or first-tap the OS microphone sheet so `CommunicationsManager.start()` can return `StartReady`. Companion to [real-device-orchestration.md](real-device-orchestration.md). Process lives in the `device-permission-prompts` skill.

## Load first

`device-permission-prompts`. Read `CONTEXT.md` if a permission term is missing.

## Discover

```text
flutter devices
```

Use the **id** column. Pass that id to the script. Do not start a second Flutter process while an exclusive suite is already targeting a device.

## Grant

After the example app is installed (Android `pm list packages` shows `com.example.flutter_ai_communications`; iOS simulator or device has the Runner):

```text
.agents/workflows/grant-device-permissions.sh <device-id>
```

| Exit | Meaning |
| --- | --- |
| `0` | Host grant applied (Android `pm grant` or simulator `simctl privacy`) |
| `2` | Physical iOS / unknown surface — human must tap **Allow** on the device (and Mac Automation if Xcode control was denied) |
| `1` | Device missing, package not installed yet, or the grant command failed |

Android: install (`flutter run` / `flutter drive`) **then** grant. Simulator: grant can precede `start()`. Physical iOS: the script always exits `2`; keep the exclusive process and wait for the human tap.

## Isolation

Isolation Open is not this job. Do not treat an Isolation sheet as a failed grant.

## Pass

`start()` returns `StartReady`. Receipts still require `permission: granted` and `nativeFailuresSkipped: false`.

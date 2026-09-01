# Windows and Linux: camera receipts

**As of 2026-09-01.** HEAD `e6b37b4` on `main` (PR #34). Camera graphs are
in tree on all six platforms. Empty `cameras()` when no device is present
or permission is denied is unavailable video, not `StartFailed`.

| Platform | Graph | Receipt |
| --- | --- | --- |
| iOS | AVFoundation | iPhone 17 sim Orchestration |
| Android | Camera2 | SM A176U1 Orchestration |
| macOS | AVFoundation | graph + audio Orchestration |
| Web | getUserMedia | lobby via flutter-skill |
| Windows | Media Foundation → Texture | LifeCam Studio `native_camera_test` on `e6b37b4` |
| Linux | V4L2 → Texture | compile + physical receipt remaining |

Use a Linux machine to **build the example and collect a camera
Orchestration receipt**. A second Windows machine only re-runs camera
receipts if hardware differs from JamieDesktop / LifeCam Studio.

Audio Orchestration 20-cycles already ran on Windows (PR #32 / #33) and
Linux/WSLg (PR #33). Those are not camera receipts.

## What is already done (do not re-litigate)

- `CommunicationsManager`, one Session, lobby Session, Join = stop + start
  with Session settings
- Shared video types, platform camera methods, fake-platform tests
- Native camera graphs: iOS, Android, macOS, web, Windows, Linux (in tree)
- Example keys: `lobby-enter`, `lobby-join`, `mute`, `camera-off`,
  `mute-video`, `self-view`
- Orchestration passed on iPhone 17 sim and SM A176U1
- Windows camera: permission granted, catalog, 640×480@30 Texture, live
  non-black frames, Mute-video vs Camera-off, join via Session settings,
  enable-video-later (LifeCam Studio)
- v1 Video processor is `none` only
- Missing/denied camera does not fail `start()`

## Shared machine setup

1. Clone this repo. Flutter SDK must match `environment.sdk` in the
   workspace `pubspec.yaml` (Dart 3.13+).
2. `flutter pub get` at the repo root.
3. `flutter doctor` must show the desktop toolchain OK.
4. First `start()` shows the OS mic prompt. Grant it. Camera prompt appears
   when the lobby Session includes camera send.
5. From `example/`:

```text
flutter test integration_test/native_orchestration_test.dart -d <device-id>
flutter test integration_test/native_camera_test.dart -d <device-id>
flutter run -d <device-id>
```

Lobby drive: `lobby-enter` → pick endpoints → `lobby-join` → mute / End.

Receipts write under the platform temp directory (Linux/macOS:
`/tmp/flutter_ai_communications_receipts/`; Windows: `%TEMP%\flutter_ai_communications_receipts\`).
Copy the `NATIVE_ORCHESTRATION_RECEIPT` / `NATIVE_CAMERA_*` JSON.

## Windows (camera receipt already collected)

1. Enable Developer Mode. Install Visual Studio with **Desktop development
   with C++** and the Windows 10/11 SDK.
2. `flutter devices` lists `windows`.
3. Re-run only if hardware differs from Microsoft LifeCam Studio on
   JamieDesktop:

```text
cd example
flutter test integration_test/native_camera_test.dart -d windows
flutter test integration_test/native_orchestration_test.dart -d windows
flutter run -d windows
```

4. Enter lobby. Mic permission is requested inside `start()`. Camera
   permission is requested when the lobby Session includes camera send.
   Empty `cameras()` still means unavailable video, not a failed Session.
5. Join, mute, End. Camera receipt must show catalog, Texture, live frames,
   Mute-video vs Camera-off, join via Session settings, enable-video-later.

Unpackaged Win32 has no Store webcam sheet; desktop camera access is the
Windows privacy grant.

## Linux (compile + camera receipt remaining)

1. Install `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`,
   `liblzma-dev`, PulseAudio or PipeWire, and `v4l-utils`.
2. `flutter devices` lists `linux`.
3. Compile first, then receipts:

```text
cd example
flutter build linux --debug
flutter test integration_test/native_camera_test.dart -d linux
flutter test integration_test/native_orchestration_test.dart -d linux
flutter run -d linux
```

4. Camera list is populated when `/dev/video*` capture nodes exist.
   Empty `cameras()` still means unavailable video, not a failed Session.
5. PipeWire camera portal is not this slice. Device-node access only.

### What to send back from Linux

- OS version, `flutter --version`, device id (`linux`)
- `flutter build linux` success
- Mic permission result
- `cameras()` empty: yes/no
- `native_camera_test` output (permission, catalog, Texture, frames)
- Orchestration receipt JSON
- Confirmation that lobby `start()` succeeded with or without a camera

## Camera graph contract (already in the federated packages)

Implement in the federated packages, not in `example/`. Match iOS/Android
contracts in ADR-0012, ADR-0013, ADR-0021. Do not add a second camera
plugin.

Public seam (already on `FlutterAiCommunicationsPlatform`):

- `enumerateCameras`
- `requestCameraPermission`
- `startCameraNative` / `stopCameraNative`
- `selectCameraNative`
- `setCameraEnabledNative` (Camera-off)
- `setMuteVideoNative` (black frames, graph stays up)
- `lastVideoSurface` (Texture id) and `lastNativeVideoFormat`

Missing camera or denied permission → Session still `StartReady`,
`videoUnavailableReason` set.

### Windows (ticket `.scratch/video-v1-issues/08-windows-camera.md`)

Done on `e6b37b4`. Capture is Media Foundation Source Reader → Flutter
`TextureRegistry`. Mute-video substitutes black frames; Camera-off stops
the device.

### Linux (ticket `.scratch/video-v1-issues/linux-camera.md`)

Capture is V4L2 (`/dev/video*`) STREAMING nodes (YUYV / NV12 / RGB24 /
BGR24) → `FlPixelBufferTexture`. Same Mute-video / Camera-off /
enable-video-later contracts. Do not require a camera to pass audio
Orchestration.

### Camera receipt (after the graph compiles on that machine)

- `cameras()` non-empty
- lobby self-view Texture
- live camera switch when more than one camera exists
- Mute-video vs Camera-off (lens / LED if the OS exposes it)
- Join stop + start keeps audio stream identity
- twenty lobby/start/stop cycles without leaking the camera
- screenshot of lobby self-view

## Do not do on these machines

- Do not add Melos, `flutter_recorder`, `flutter_soloud`, or a second camera
  plugin
- Do not put PeerConnection types on Session
- Do not implement blur/replace processors
- Do not treat empty `cameras()` as Orchestration failure
- Do not copy production frames through Dart (ADR-0013)
- Do not re-implement the Windows Media Foundation graph; it is on `main`

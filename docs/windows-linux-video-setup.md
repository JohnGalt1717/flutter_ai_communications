# Windows and Linux: build, audio receipts, then camera graphs

**As of 2026-08-31.** iOS, Android, macOS, and web camera graphs are in this
repo. Windows and Linux already have **audio** backends (WASAPI / Pulse).
Camera graphs are in tree (Windows Media Foundation, Linux V4L2). Empty
`cameras()` still happens when no device is present or permission is
denied; that is unavailable video, not `StartFailed`.

Use a second Windows machine and a Linux machine for two tracks, in order:

1. **Receipts (do this first):** build the example, run audio Orchestration,
   drive the lobby. Empty camera list is expected.
2. **Camera graphs (ticket work on those machines):** implement the native
   Production video path against the existing Session APIs.

## What is already done (do not re-litigate)

- `CommunicationsManager`, one Session, lobby Session, Join = stop + start
  with Session settings
- Shared video types, platform camera methods, fake-platform tests
- Native camera graphs: iOS, Android, macOS, web
- Example keys: `lobby-enter`, `lobby-join`, `mute`, `camera-off`,
  `mute-video`, `self-view`
- Orchestration passed on iPhone 17 sim and SM A176U1
- v1 Video processor is `none` only
- Missing/denied camera does not fail `start()`

## Shared machine setup

1. Clone this repo. Flutter SDK must match `environment.sdk` in the
   workspace `pubspec.yaml` (Dart 3.13+).
2. `flutter pub get` at the repo root.
3. `flutter doctor` must show the desktop toolchain OK.
4. First `start()` shows the OS mic prompt. Grant it. Camera prompt appears
   only after a camera graph exists.
5. From `example/`:

```text
flutter test integration_test/native_orchestration_test.dart -d <device-id>
flutter test integration_test/native_camera_test.dart -d <device-id>
flutter run -d <device-id>
```

Lobby drive: `lobby-enter` → pick endpoints → `lobby-join` → mute / End.

Receipts write under the platform temp directory (Linux/macOS:
`/tmp/flutter_ai_communications_receipts/`; Windows: `%TEMP%\flutter_ai_communications_receipts\`).
Copy the `NATIVE_ORCHESTRATION_RECEIPT` JSON.

## Track 1 — audio / lobby receipts (ready now)

### Windows machine

1. Enable Developer Mode. Install Visual Studio with **Desktop development
   with C++** and the Windows 10/11 SDK.
2. `flutter devices` lists `windows`.
3. Run:

```text
cd example
flutter test integration_test/native_orchestration_test.dart -d windows
flutter run -d windows
```

4. Enter lobby. Mic permission is requested inside `start()`. Camera
   permission is requested when the lobby Session includes camera send.
   Empty `cameras()` still means unavailable video, not a failed Session.
5. Join, mute, End, confirm 20 start/stop cycles in the Orchestration
   receipt.

### Linux machine

1. Install `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`,
   `liblzma-dev`, PulseAudio or PipeWire, and `v4l-utils` (for later camera
   work).
2. `flutter devices` lists `linux`.
3. Run:

```text
cd example
flutter test integration_test/native_orchestration_test.dart -d linux
flutter run -d linux
```

4. Camera list is populated when `/dev/video*` capture nodes exist.
   Empty `cameras()` still means unavailable video, not a failed Session.

### What to send back from track 1

- OS version, `flutter --version`, device id (`windows` / `linux`)
- Mic permission result
- `cameras()` empty: yes/no
- Orchestration receipt JSON
- Confirmation that lobby `start()` succeeded with no camera

## Track 2 — camera graphs (in tree; receipts remaining)

Implement in the federated packages, not in `example/`. Match iOS/Android
contracts in ADR-0012, ADR-0013, ADR-0021.

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

- Capture: Media Foundation or `Windows.Media.Capture`
- Preview: Flutter `TextureRegistry` (same Video surface kind as iOS/Android)
- Permission: Windows camera privacy consent; typed `CameraPermission`
- Catalog: built-in and external; unplug falls back only when Camera
  preference controls the pick
- Mute-video: black frames on the Texture; Camera-off stops the device
- Enable-video-later on an existing audio Session without replacing
  `Session.capture`

### Linux

- Capture: V4L2 (`/dev/video*`), PipeWire camera portal where that is the
  distro default
- Preview: Flutter Texture (GTK embedder)
- Permission: portal prompt or device-node access; typed `CameraPermission`
- Same Mute-video / Camera-off / enable-video-later contracts
- Do not require a camera to pass audio Orchestration

### Camera receipt (after the graph exists)

- `cameras()` non-empty
- lobby self-view Texture
- live camera switch
- Mute-video vs Camera-off (lens / LED if the OS exposes it)
- Join stop + start keeps audio stream identity
- twenty lobby/start/stop cycles without leaking the camera
- screenshot of lobby self-view

## Do not do on these machines

- Do not add Melos, `flutter_recorder`, `flutter_soloud`, or a second camera
  plugin
- Do not put PeerConnection types on Session
- Do not implement blur/replace processors
- Do not treat empty `cameras()` as Orchestration failure until track 2 lands
- Do not copy production frames through Dart (ADR-0013)

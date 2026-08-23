# Bluetooth and car Endpoint identity

## Conclusion

General audio-route APIs do not provide trustworthy Bluetooth manufacturer/model identity.

- iOS exposes a descriptive `portName`, a port-scoped `uid`, and a `portType`. `.carAudio` identifies a car-audio route but is not documented as proof of an active CarPlay session.
- Android exposes a human-readable `productName`, internal device `id`, generic audio `type`, and API 28+ device-specific `address`. It has no Android Auto/car audio device type and no manufacturer/model field.
- Neither platform documents its audio-route display name as the Bluetooth advertised name or user-selected alias.
- CarPlay and Android Auto connection state belongs to their separate car-framework lifecycle APIs, when the app is entitled/eligible to use them.

Therefore Acoustic profile matching must prefer verified native capabilities and route metadata. A known-profile registry may use narrowly constrained names only as fallback. Vehicle manufacturer tokens such as `Tesla` are not reliable by themselves; use them only with independent car/transport evidence and physical metadata receipts.

## iOS

`AVAudioSessionPortDescription` exposes:

- `portName`: descriptive display name;
- `uid`: system-assigned unique identifier for the port;
- `portType`: including Bluetooth HFP/A2DP/LE and `carAudio`;
- optional data sources and channel descriptions.

It does not expose a separate manufacturer, model, Bluetooth address, or arbitrary Bluetooth profile list. The `uid` must not be parsed as undocumented accessory identity.

Sources:

- [AVAudioSessionPortDescription](https://developer.apple.com/documentation/avfaudio/avaudiosessionportdescription)
- [AVAudioSession.Port](https://developer.apple.com/documentation/avfaudio/avaudiosession/port)
- [carAudio](https://developer.apple.com/documentation/avfaudio/avaudiosession/port/caraudio)
- [AVAudioSessionDataSourceDescription](https://developer.apple.com/documentation/avfaudio/avaudiosessiondatasourcedescription)
- [CPTemplateApplicationScene](https://developer.apple.com/documentation/carplay/cptemplateapplicationscene)

## Android

`AudioDeviceInfo` exposes:

- `productName`: human-readable device name;
- `id`: internal audio device ID;
- `type`: Bluetooth SCO/A2DP/BLE, USB, bus, wired, built-in, and other generic types;
- API 28+ `address`: device-specific address/parameters, not guaranteed to be a Bluetooth MAC address;
- supported sample rates, encodings, and channel capabilities.

It does not expose Android Auto state, manufacturer, or model. `BluetoothDevice` separately exposes name, local alias, address, class, and UUID information, but Android documents no universal mapping from `AudioDeviceInfo` to `BluetoothDevice`. Access to Bluetooth identity generally requires `BLUETOOTH_CONNECT` on API 31+.

Android Auto/projection state is separately represented by Android for Cars `CarConnection`, not by `AudioDeviceInfo`.

Sources:

- [AudioDeviceInfo](https://developer.android.com/reference/android/media/AudioDeviceInfo)
- [AudioProfile](https://developer.android.com/reference/android/media/AudioProfile)
- [BluetoothDevice.getAlias](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#getAlias())
- [BluetoothDevice.getName](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#getName())
- [BluetoothClass.Device.AUDIO_VIDEO_CAR_AUDIO](https://developer.android.com/reference/android/bluetooth/BluetoothClass.Device#AUDIO_VIDEO_CAR_AUDIO)
- [CarConnection](https://developer.android.com/reference/androidx/car/app/connection/CarConnection)

## Current package forwarding

The current package forwards only:

- common `Endpoint`: `id`, display `name`, `routeClass`, capture flag, and `pairId`;
- iOS: `uid`, `portName`, route class derived from `portType`, and the same `uid` as `pairId`;
- Android: internal `id`, `productName`, route class derived from `type`, and `address` or ID as `pairId`.

It does not forward iOS data sources/channels, Android sample-rate/encoding/channel capabilities, confidence/provenance, verified AEC/NS/AGC state, Bluetooth alias/class, or car-framework connection state.

Relevant source:

- `packages/flutter_ai_communications_shared/lib/src/endpoint.dart`
- `packages/flutter_ai_communications_ios/ios/flutter_ai_communications_ios/Sources/flutter_ai_communications_ios/FlutterAiCommunicationsPlugin.swift`
- `packages/flutter_ai_communications_android/android/src/main/kotlin/com/johngalt/flutter_ai_communications/FlutterAiCommunicationsPlugin.kt`

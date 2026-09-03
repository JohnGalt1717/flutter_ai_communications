# Changelog

## 0.0.1

* iOS, macOS, web, and Linux `startNative` report the Native Format the graph actually opened. Session conversion uses that report instead of assuming the requested edge Format.
* iOS speakerphone ↔ handset `selectEndpoints` applies the port override on the live graph and does not restart the engine. Accessory input changes may still rebuild.
* Web render selection closes and reopens `AudioContext` so a live pick and the next Session apply the Desired sink. Observed render is the applied sink, never the requested id.
* Federated Audio manager workspace with iOS, Android, Web, macOS, Windows, and Linux adapters.
* Android adapter migrates to built-in Kotlin (AGP 9).
* iOS adapter is Swift Package Manager only. There is no CocoaPods podspec.
* iOS and Android catalogs advertise handset only when a receiver/earpiece exists.
* iOS Isolation reads `AVCaptureDevice.preferredMicrophoneMode`.
* iOS speakerphone and handset enable VoiceProcessingIO, stay Session-mono, and do not pin a built-in data source. Isolation follows the active Mic Mode so Automatic on speakerphone is required, not on.
* iOS playback buffers match the player connection (Session mono), not the stereo mixer.
* iOS capture EventChannel payloads hop to the platform thread.
* Exclusive native Orchestration suite passed on physical iOS, physical Android, macOS, Windows, and Linux (WSLg). Chrome exclusive also passed.
* macOS production duplex uses one native AVAudioEngine. Isolation is unavailable, so the Session raises the Sound floor.
* Isolation refuse / missing / unavailable raises the adaptive Sound floor after the host prompt.
* Host Endpoint preference fills capture and render independently so a webcam plus USB render can outrank AirPods.

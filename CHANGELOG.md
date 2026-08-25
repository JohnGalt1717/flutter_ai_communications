# Changelog

## 0.0.1

* Federated Audio manager workspace with iOS, Android, Web, macOS, Windows, and Linux adapters.
* Android adapter migrates to built-in Kotlin (AGP 9).
* iOS adapter is Swift Package Manager only. There is no CocoaPods podspec.
* iOS and Android catalogs advertise handset only when a receiver/earpiece exists.
* iOS Isolation reads `AVCaptureDevice.preferredMicrophoneMode`.
* iOS speakerphone and handset enable VoiceProcessingIO, stay Session-mono, and do not pin a built-in data source. Isolation follows the active Mic Mode so Automatic on speakerphone is required, not on.
* iOS playback buffers match the player connection (Session mono), not the stereo mixer.
* iOS capture EventChannel payloads hop to the platform thread.
* Exclusive native Marionette suite passed on physical iOS, physical Android, and macOS. Chrome exclusive also passed. Windows and Linux exclusive drives are still outstanding.
* macOS production duplex uses one native AVAudioEngine. Isolation is unavailable, so the Session raises the Sound floor.
* Isolation refuse / missing / unavailable raises the adaptive Sound floor after the host prompt.
* Host Endpoint preference fills capture and render independently so a webcam plus USB render can outrank AirPods.

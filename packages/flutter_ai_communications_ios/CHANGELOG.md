# Changelog

## 0.0.1

* Initial iOS adapter stub.
* Ships as Swift Package Manager only. There is no CocoaPods podspec.
* Catalog advertises handset only when a receiver exists (iPad stays speaker).
* Isolation reads `AVCaptureDevice.preferredMicrophoneMode` (iOS 15+).
* Playback buffers match the player connection (Session mono), not the stereo mixer.
* Capture EventChannel payloads hop to the platform thread.

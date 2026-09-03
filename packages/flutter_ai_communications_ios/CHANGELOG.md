# Changelog

## 0.0.1

* Speakerphone ↔ handset selection applies `overrideOutputAudioPort` on the live graph; the engine is not restarted. Accessory picks may still rebuild.
* Initial iOS adapter stub.
* Ships as Swift Package Manager only. There is no CocoaPods podspec.
* Catalog advertises handset only when a receiver exists (iPad stays speaker).
* Isolation reads `AVCaptureDevice.preferredMicrophoneMode` (iOS 15+).
* Speakerphone and handset enable VoiceProcessingIO after playback is attached.
* Capture and playback stay Session-mono; built-in Front/Bottom data sources are not pinned while Isolation is available.
* Isolation follows the active Mic Mode so Automatic on speakerphone is required, not on.
* Playback buffers match the player connection (Session mono), not the stereo mixer.
* Capture EventChannel payloads hop to the platform thread.

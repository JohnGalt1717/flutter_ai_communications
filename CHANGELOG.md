# Changelog

## 0.0.1

* Federated Audio manager workspace with iOS, Android, Web, macOS, Windows, and Linux adapters.
* Android adapter migrates to built-in Kotlin (AGP 9).
* iOS adapter is Swift Package Manager only. There is no CocoaPods podspec.
* iOS and Android catalogs advertise handset only when a receiver/earpiece exists.
* iOS Isolation reads `AVCaptureDevice.preferredMicrophoneMode`.
* iOS playback buffers match the player connection (Session mono), not the stereo mixer.
* iOS capture EventChannel payloads hop to the platform thread.
* Exclusive native Marionette suite passed on physical iOS, physical Android, and macOS. Chrome exclusive also passed. Windows and Linux exclusive drives are still outstanding.
* macOS Core Audio reports Observed from the bound UID and transcodes Native Format to PCM16 LE mono 24 kHz.
* Host Endpoint preference fills capture and render independently so a webcam plus USB render can outrank AirPods.

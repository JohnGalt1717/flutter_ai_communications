# Echo e2e

Host Transport that proves each platform can stream, pick an Endpoint,
stream again, and keep the same Session capture stream.

The library does not own Transport. `EchoTransport` lives in the example.

## What “byte for byte” means

Analog speaker → microphone cannot be bit-identical (SRC, AEC,
room, gain). The host adds a **Loopback Pair**. `Session.play`
still hits the real adapter; after that adapter accepts the
frame, the same bytes are published as capture. That is the
echo the other end would receive.

1. **Unit identity** — fake adapter, fixture injected or played.
   `example/test/echo_transport_test.dart`. CI.

2. **Live identity** — real adapter on a device / emulator.
   `Session.play` still hits that adapter. After it accepts the
   frame, the host Loopback Pair publishes the same bytes as
   capture. Select another Endpoint, select Loopback again, play
   a second fixture, match again. `Session.capture` must be the
   same object. Analog start/permission may fail on a simulator;
   the Loopback Pair still starts so identity can be proven.
   `example/integration_test/echo_loopback_test.dart`.

Adaptive sound floor and local barge-in rewrite capture. The
digital tests start with `soundFloor: 0` and
`BargeInPolicy.remoteVad` so identity is the Transport edge, not
the floor.

## Fixture

`example/assets/voice_band_24k.wav` — PCM16 LE mono 24 kHz, peak
below full scale. Regenerated with:

```text
cd example && dart run tool/write_fixture.dart
```

## Commands

Digital (any host):

```text
flutter test example/test/echo_transport_test.dart
```

Live device / emulator:

```text
cd example
flutter test integration_test/echo_loopback_test.dart -d <device>
```

Or:

```text
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/echo_loopback_test.dart -d <device>
```

Grant the microphone. On macOS the host app already has
`NSMicrophoneUsageDescription` and `audio-input`. On Chrome,
allow the mic prompt once.

### Chrome / ChromeDriver on macOS

Homebrew’s `chromedriver` cask is unsigned. Gatekeeper will
quarantine it (`killed: chromedriver`). It also tracks the
latest Chrome major, which can be newer than the installed
browser.

Use Chrome-for-Testing that matches
`Google Chrome --version`, not the Homebrew cask:

```text
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
# pick the same version from
# https://googlechromelabs.github.io/chrome-for-testing/
curl -fsSL -o /tmp/chromedriver.zip \
  'https://storage.googleapis.com/chrome-for-testing-public/<VERSION>/mac-arm64/chromedriver-mac-arm64.zip'
unzip -o /tmp/chromedriver.zip -d /tmp
install -m 755 /tmp/chromedriver-mac-arm64/chromedriver "$HOME/.local/bin/chromedriver"
xattr -d com.apple.quarantine "$HOME/.local/bin/chromedriver"
```

If macOS still blocks it:

1. **System Settings → Privacy & Security** — Open Anyway.
2. Or right-click the binary → Open, then Open.
3. Do **not** leave Homebrew 152 installed if Chrome is 151.

Then:

```text
"$HOME/.local/bin/chromedriver" --port=4444 --allowed-origins='*'
cd example
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/echo_loopback_test.dart -d chrome
```

## Heads

| Head | Digital | Live |
| --- | --- | --- |
| macOS | CI | This machine |
| iOS | CI | Simulator or device |
| Android | CI | Emulator or device |
| web | CI | Chrome |
| Windows | CI | Parallels |
| Linux | CI | Parallels |

Orchestration **Prove** plays the fixture on the Loopback Pair and
shows whether capture was identical.

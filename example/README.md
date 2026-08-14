# flutter_ai_communications_example

AI-voice Marionette harness for the federated Audio manager.

Drive **Start → Mute → Pause → Isolation event** from the widget test
(`flutter test` in this package) or by running the app on iOS, Android, web,
macOS, Windows, or Linux.

The visualizer plots the same capture stream the Transport would send. There is
no SignalR. Web, macOS, Windows, and Linux have no Isolation and no handset
Endpoint — those are documented limits, not bugs.

Echo Transport (`lib/echo/`) is the host stand-in. A Loopback Pair taps
`Session.play` after the real adapter accepts the fixture so capture can
be compared byte for byte. Analog speaker → microphone is not that path;
see `docs/echo-e2e.md`.

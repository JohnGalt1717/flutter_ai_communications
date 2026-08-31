# flutter_ai_communications_example

AI-voice agent harness for the federated Audio manager.

Drive **Enter lobby → pick devices → Join → Mute → Pause** from the widget
test (`flutter test` in this package) or by running the app on iOS, Android,
web, macOS, Windows, or Linux.

The **Lobby** subsection is a Session with no Transport (no Echo). Join stops
it and starts a meeting Session, then attaches Echo Transport. Orchestration
e2e uses that path.

Debug-mode runs initialize `FlutterSkillBinding` so **flutter-skill** can
tap/type/scroll the UI. Use **flutter_agent_lens** to discover/attach to the
VM service, read console logs, set breakpoints, and evaluate expressions.
That binding is skipped under `flutter test`.

The visualizer plots the same capture stream the Transport would send. There is
no SignalR. Web, macOS, Windows, and Linux have no Isolation and no handset
Endpoint — those are documented limits, not bugs.

Echo Transport (`lib/echo/`) is the host stand-in. A Loopback Pair taps
`Session.play` after the real adapter accepts the fixture so capture can
be compared byte for byte. Analog speaker → microphone is not that path;
see `docs/echo-e2e.md`.

Windows and Linux camera receipts on other machines: `docs/windows-linux-video-setup.md`.

# One capture stream is the wire

Scribe has a separate visualizer path that does not match what is sent. Transport, visualizer, and VOD all subscribe to the same Session capture stream: capture Format, sound floor applied, Mute as silence frames. A second “pretty” tap would reintroduce the bug. Playback is a separate Format and may differ from capture.

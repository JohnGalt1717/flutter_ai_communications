# One capture stream is the wire

Scribe has a separate visualizer path that does not match what is sent. Transport, visualizer, and VOD all subscribe to the same Session capture stream: capture Format, sound floor applied, Mute as silence frames. A second “pretty” tap would reintroduce the bug. Playback is a separate Format and may differ from capture.

Server-side interview mux forks the inbound WebRTC tracks that correspond to this Capture stream plus the camera Send track and the screen Send track into one fMP4/CMAF with separate tracks. FAC does not write a local interview file. System audio on screen send is a separate audio track in that file, never mixed into this stream. There is no rawer mic for later server denoise; the archive is what the room heard.

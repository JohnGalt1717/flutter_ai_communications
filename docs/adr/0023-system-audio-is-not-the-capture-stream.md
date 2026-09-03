# System audio rides screen send, not the Capture stream

ADR-0003 keeps one mic Capture stream for Transport, visualizer, and VOD, with Mute as silence. Computer sound is a share option (Teams Include sound), looped back from the OS, and must not mix into that stream or barge-in, Isolation, and Mute break. `includeSystemAudio` is a flag on startScreenShare / setIncludeSystemAudio. Mute still silences only the mic. Platforms that cannot loopback share video-only and report it on Session status.

# 12 — Transport second send path

**What to build:** A Transport plugin (fake first) takes camera send and
screen send as two paths, plus optional system audio, without mixing
system audio into the mic Capture stream.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started. Camera WebRTC Send track shipped in #48.
Screen send is still a second local Production path to attach.

- [ ] Fake Transport observes camera Video surface and screen Video
      surface independently
- [ ] Mute silences Capture stream only
- [ ] Camera-off does not remove the screen path
- [ ] includeSystemAudio off means no system-audio edge
- [ ] Real flutter_webrtc binding may share video ticket 12; fake
      coverage does not wait on that package

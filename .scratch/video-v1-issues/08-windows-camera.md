# 08 — Windows camera graph

**What to build:** On Windows, the host can enumerate cameras, honor Camera preference fallback, show a Preview Texture, Mute-video, Camera-off, and enable video later on the same Session.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** graph landed and proven on Microsoft LifeCam Studio (USB,
facing=external, Native Video Format 640×480@30). Suite:
`example/integration_test/native_camera_test.dart -d windows`.

- [x] External cameras appear in the catalog (USB facing)
- [x] Unplug falls back when preference controls the pick (manager)
- [x] Explicit camera selection does not silently fall back
- [x] Permission denial is a typed result
- [x] Physical receipt: catalog, Texture, Mute-video, Camera-off, join
      settings, enable-video-later (LifeCam Studio, JamieDesktop)
- [x] Permission `granted`; native stream `frames>=8` and `liveFrames>=8`
      (non-black pixels, not a Dart byte tap)

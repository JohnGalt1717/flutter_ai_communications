# Linux camera graph

**What to build:** On Linux, the host can enumerate cameras, honor Camera
preference fallback, show a Preview Texture, Mute-video, Camera-off, and
enable video later on the same Session.

**Blocked by:** 02 — Session and platform-interface video contracts

**Status:** graph in tree for a Linux VM. Dart adapter tests pass on any
host. Native V4L2 + Flutter Texture still needs a Linux compile and a
physical receipt (`docs/windows-linux-video-setup.md`).

- [x] Dart CameraBackend + MethodChannel wiring
- [x] V4L2 capture → Flutter Texture (YUYV / NV12 / RGB24 / BGR24, STREAMING nodes)
- [ ] `flutter build linux` on a machine with clang/cmake/GTK/v4l headers
- [ ] `flutter test integration_test/native_camera_test.dart -d linux`
- [ ] External cameras appear in the catalog
- [ ] Permission denial is a typed result (device-node EACCES)
- [ ] Physical receipt: catalog, Preview Texture, Mute-video vs Camera-off

PipeWire camera portal is not this slice. Device-node access only.
Do not add a second camera plugin. Empty `cameras()` is not `StartFailed`.

# 01 — Shared video types

**What to build:** Hosts and platform adapters share Camera Endpoint, Camera facing, Camera preference, Video Format, Native Video Format, and Video processor types (`none`, blur with intensity, replace from bytes or asset path) without importing flutter_webrtc.

**Blocked by:** 00 — Video spec, glossary, and ADRs

**Status:** done (2026-09-01). Types live in `flutter_ai_communications_shared`.

- [x] Types live in the shared package and use glossary names
- [x] Default Video Format is 1280×720 at 30 fps
- [x] Processor types are selectable values, not a host-injected strategy object
- [x] Unit tests cover equality, defaults, and invalid intensity / empty background

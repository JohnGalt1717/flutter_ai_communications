# 01 — Shared screen types

**What to build:** Hosts and platform adapters share Screen source, Screen
source kind, and Screen motion without importing flutter_webrtc or
platform capture types.

**Blocked by:** 00 — Screen spec, glossary, and ADRs

**Status:** done (2026-09-03)

- [x] Types live in `flutter_ai_communications_shared` and use glossary
      names
- [x] Kind is display, window, allDisplays, systemPicker
- [x] Screen source carries id, name, kind, physical bounds; missing
      fields are null
- [x] Browser tab is not a kind
- [x] Unit tests cover equality, defaults, and All-displays as a kind

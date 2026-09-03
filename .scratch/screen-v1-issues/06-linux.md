# 06 — Linux screen graph (X11 + Wayland)

**What to build:** X11 enumerates displays and windows and captures
without a portal picker. Wayland is one system-picker source via
xdg-desktop-portal ScreenCast + PipeWire. Same Session API.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** in progress. X11 catalog + send in #39. Thumbs, Share frame,
and Wayland portal ScreenCast in this slice. Pulse/PipeWire Include
sound later.

- [x] X11: window list, All-displays, XGetImage send
- [x] X11 thumbs and Share frame
- [x] Wayland: catalog is one system-picker source; thumbs and indicate
      are no-ops
- [x] Wayland portal ScreenCast (async picker; PipeWire frame pull still
      a follow-up when libpipewire is present)
- [ ] System audio from Pulse/PipeWire monitor, not mixed into mic
      Capture stream
- [ ] Receipt: X11 host picker path and/or Wayland portal path on #44

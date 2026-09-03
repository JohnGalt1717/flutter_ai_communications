# 06 — Linux screen graph (X11 + Wayland)

**What to build:** X11 enumerates displays and windows and captures
without a portal picker. Wayland is one system-picker source via
xdg-desktop-portal ScreenCast + PipeWire. Same Session API.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** in progress (PR #39). X11 catalog + send. Thumbs, Share
frame, Wayland portal, and loopback later.

- [x] X11: RandR + window list, All-displays, XGetImage send
- [ ] X11 thumbs and Share frame
- [x] Wayland: catalog is one system-picker source; thumbs and indicate
      are no-ops
- [ ] Wayland portal ScreenCast + PipeWire
- [ ] System audio from Pulse/PipeWire monitor, not mixed into mic
      Capture stream
- [ ] Receipt: X11 host picker path and/or Wayland portal path on #44

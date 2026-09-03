# 06 — Linux screen graph (X11 + Wayland)

**What to build:** X11 enumerates displays and windows and captures
without a portal picker. Wayland is one system-picker source via
xdg-desktop-portal ScreenCast + PipeWire. Same Session API.

**Blocked by:** 02 — Session and platform-interface screen contracts

**Status:** not started

- [ ] X11: RandR + window list, All-displays from the virtual screen,
      thumbs, Share frame, XComposite/XShm send
- [ ] Wayland: catalog is one system-picker source; Start() shows the
      portal; thumbs and indicate are no-ops
- [ ] System audio from Pulse/PipeWire monitor, not mixed into mic
      Capture stream
- [ ] Receipt: X11 host picker path and/or Wayland portal path documented
      for the machine under test

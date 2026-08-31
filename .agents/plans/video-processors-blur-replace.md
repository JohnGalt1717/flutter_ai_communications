# Plan stub: blur and replace Video processors

**Status:** Later. Do not implement in the v1 camera slice.
**Depends on:** native Production video path and Camera preview shipping with processor `none` only.
**Glossary:** `CONTEXT.md` **Video processor**. ADR-0017.

## Why this is separate

v1 must not block cameras, lobby Session, Transport plugins, or Camera preview on person segmentation. The selectable family is already named so hosts do not invent a processor object: none, blur(intensity 0–100), replace(still bytes or asset). v1 implements **none** (pass-through). This plan is the rest.

## v1 (not this plan)

- Processor type exists. The only valid production value is `none`.
- Selecting blur or replace in v1 is either unimplemented (structured warning, stay on none) or not exposed by the example.
- Camera preview and Session send the unprocessed Production video path.
- Host UIs may still show None / Some / Lots as labels; they must not assume blur runs.

## Later work (this plan)

1. **Blur** on iOS and Android first, then macOS, Windows, Web. Intensity is 0–100. Host chrome maps None/Some/Lots to 0 / 50 / 100. Intensity changes apply without restarting the Session. Camera preview and the Transport plugin see the same processed path.
2. **Replace** with a still image (bytes or asset path), not a video loop. Empty or invalid still fails that set-processor call, keeps the previous processor, does not kill Session or Camera preview.
3. Unavailable native segmentation → none + structured warning, not a start failure.
4. Human confirmation of blur quality is allowed. Cadence and Video surface liveness stay electronic.

## Out of this plan

- Gamma, exposure, zoom, beauty, avatars, background *video*.
- Host-injected processor objects.
- Shipping blur/replace as a v1 gate.

## Tickets

Not opened. When this plan is scheduled, split mobile vs desktop/web the way `video-capture-and-sinks.md` tickets 10–11 did, after at least one native camera graph is real.

## Gate

Done when lobby Session self-view, in-call Camera preview, and the Transport plugin all show the same blur or replace, and `none` remains the fallback.

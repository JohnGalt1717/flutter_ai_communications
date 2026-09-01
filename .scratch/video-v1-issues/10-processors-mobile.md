# 10 — Video processors on iOS and Android

**What to build:** On iOS and Android, a host can select none, blur with intensity, or replace with bytes or an asset path in Pre-join preview and in Session. Preview and sinks show the same processed path. If the processor cannot run, the Session stays up with none and a structured warning.

**Blocked by:** 05 — iOS camera graph; 06 — Android camera graph; 03 — Pre-join preview

**Status:** deferred (2026-09-01). Later plan `.agents/plans/video-processors-blur-replace.md`. Native graphs exist; do not start blur/replace in v1.

- [ ] none / blur / replace are selectable mid-preview and mid-session
- [ ] Intensity changes are visible without restarting the Session
- [ ] Missing background bytes fail the set-processor call without killing capture
- [ ] Unavailable processor is not a Start failure

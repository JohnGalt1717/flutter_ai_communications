# macOS screen pick is a host picker, not SCContentSharingPicker

macOS 14+ ScreenCaptureKit ships `SCContentSharingPicker`. We still enumerate with `SCShareableContent`, draw the host picker, and run send on `SCStream` (ADR-0025). Revisit if product drops Teams-style Indicate / Share frame on Mac, or Apple requires the system picker for store distribution.

**Why not the system picker today**

- Indicate and Share frame exist *before* send. The OS sheet has no hover-indicate; its chrome is the UI.
- Enumerable desktop is one host API (Windows, macOS, Linux X11): `beginScreenPick`, Screen previews, Include sound / Screen motion / cursor in the host dialog.
- All-displays is a library stitch (ADR-0022), not an SC picker item.
- Replace source with `startScreenShare(newId)` without opening a new OS sheet.
- Using `SCContentSharingPicker` would make macOS an OS-picker platform: one `systemPicker` catalog row, no Screen previews, no Share frame.

Send and thumbs stay ScreenCaptureKit (`SCStream`, `SCScreenshotManager`). Only the *chooser* is host-owned.

**Mac App Store / TCC (not a documented reject)**

Apple documents the system picker as the *recommended* chooser, not a store requirement. `SCShareableContent` + `SCStream` remain public APIs. Guideline 2.5.1 has not been applied as “must present `SCContentSharingPicker`.” Zoom, Teams, and Chrome still ship custom pickers.

What you *do* get on macOS 15+ when you enumerate instead of presenting the picker: a TCC alert that the app is bypassing the system private window picker, plus periodic re-approval. DTS’s workaround for that alert is the system picker, or `com.apple.developer.persistent-content-capture` for VNC-class apps. Interview / meeting hosts are not that entitlement. Pre-14 `CGWindowListCreateImage` thumbs are the deprecated path that triggers the older “may collect detailed information” alert; keep `SCScreenshotManager` on 14+.

Revisit store risk if Review starts citing 2.5.1 against custom catalogs, or if a future OS drops programmatic `SCShareableContent` for sandboxed App Store apps.

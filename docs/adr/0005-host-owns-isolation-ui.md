# Isolation is an event, not a dialog

When noise cancelling is on, the Session detects iOS Isolation and can open the system microphone-mode UI (using an internal hold so the sheet appears). It does not ship user-facing strings or a dialog. The host handles Isolation events with its own localized copy. If Isolation stays off or is undetectable, the Session still starts, emits the event, and raises the sound floor.

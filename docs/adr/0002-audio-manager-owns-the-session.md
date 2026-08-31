# The host holds signaling and preference persistence; this library is the Communications manager

Scribe's `AiChatAudioEngine` mixed SignalR, Hive preference persistence, Isolation dialogs, and audio. Each host application owns one long-lived Communications manager with at most one live Session, owns signaling, tile layout, and UI, and persists Endpoint preference and Camera preference. A Transport plugin or host-pumped Transport moves media. The Communications manager continuously enforces the supplied preferences; Explicit selection remains Session-scoped and never writes back.

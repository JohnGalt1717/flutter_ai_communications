# The host holds Transport and preference persistence; this library is the Audio manager

Scribe's `AiChatAudioEngine` mixed SignalR, Hive preference persistence, Isolation dialogs, and audio. Each host application owns one long-lived Audio manager with at most one live Session, attaches Transport or local media edges, persists Endpoint preference, and owns UI. The Audio manager continuously enforces the supplied Endpoint preference; Explicit selection remains Session-scoped and never writes back.

# The host holds Transport and preference; this library is the Audio manager

Scribe's `AiChatAudioEngine` mixed SignalR, Hive device-priority, Isolation dialogs, and audio. The public module here is a long-lived Audio manager with at most one live Session. The host passes preference at `start()`, attaches a Transport to the capture stream, and owns UI. Mid-session Endpoint and sound-floor picks are ephemeral and must not write back. Device-order preference is explicitly out of scope.

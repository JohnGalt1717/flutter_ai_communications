# Negotiate Native Formats and convert at Session edges

Every platform inspects Endpoint capabilities and selects the promised Session edge Format when available, otherwise choosing the best verified Native Format; failure-first candidate probing is only a fallback when capabilities cannot be discovered. When the Native Format differs, the Audio manager inserts stateful streaming conversion so Transport and local sinks always receive the declared edge Format without replacing the Session or its streams.

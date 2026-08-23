# The Audio manager enforces Endpoint preference

The host owns persistence and UI for an ordered, enabled Endpoint preference, but the Audio manager continuously resolves and applies it. An Explicit selection overrides that order only for one Session while its Endpoint remains available; disappearance expires the override, and every new Session returns to Endpoint preference.

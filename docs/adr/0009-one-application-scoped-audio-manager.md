# One application-scoped Audio manager

Each host application constructs one Audio manager for its lifetime and permits at most one capture-only, playback-only, or duplex Session. Product features differ only by attached Transport, capture sink, or playback source; competing starts are explicit error states rather than a reason to create another native audio stack.

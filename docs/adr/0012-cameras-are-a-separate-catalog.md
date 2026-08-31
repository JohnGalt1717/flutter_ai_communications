# Cameras are a separate catalog from audio Endpoints

Audio Endpoints pair capture with render and carry Route-class, Isolation, and acoustic-profile behavior. Cameras are a single-selection list with facing metadata and no unmatched audio/video Pair. Mixing them into one Endpoint catalog would force fake pairIds and break preference resolution. Camera Endpoints live in their own catalog and Camera preference list, independent of Endpoint preference. Mid-session camera picks are Explicit selection and do not write Camera preference.

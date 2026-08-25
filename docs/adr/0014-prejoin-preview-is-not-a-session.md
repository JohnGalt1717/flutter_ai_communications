# Pre-join preview is idle manager state, not a Session

Teams- and Zoom-class hosts need device selection and a live Preview Texture before the conversation exists. Using a live Session for that lobby would occupy the one-Session slot, invent mute-as-silence and Coverage semantics with no Transport, and force a teardown on join. Pre-join preview lives on the Audio manager while idle. Processors apply. Join starts a Session and may promote the same camera, Video Format, and Video processor. The host may override the camera at start and again mid-session.

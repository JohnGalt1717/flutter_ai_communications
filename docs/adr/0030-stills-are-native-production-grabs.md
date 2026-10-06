# Stills are native Production-path grabs; screen is a second Send track

Interview mux is server-side: a media worker forks that participant's inbound WebRTC tracks (mic Capture stream, camera Send track, screen Send track) into one fMP4/CMAF with separate tracks when MediaRecord is on and retention is enabled. FAC does not write a local interview file, does not stitch camera and screen, and does not own a PeerConnection. The WebRTC Transport plugin yields a screen Send track beside the camera Send track so the host addTracks them separately. The server never sees a PIP.

Stills (`captureStill` / `captureScreenStill`) are one native JPEG/PNG grab of the matching Production path after Isolation / Video processor — the same frame the Send track encodes. They fail closed when that path is not running. They are the realtime vision path (requested or capped, not a 30 fps pump), including when retention is off. The control plane carries start, stop, artifact id, and discrete stills; it does not carry media bytes otherwise.

## Considered Options

Client MP4, client re-encode, compositing camera and screen, continuous JPEG on the bus, and PeerConnection inside FAC are out of this library.

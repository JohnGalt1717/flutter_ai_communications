# Video sinks are providers on one production path

The library does not own PeerConnection, signaling, or disk files. Hosts attach one or more Video sinks to the Production video path: first a flutter_webrtc track bridge, later WebTransport and a disk recorder for training capture. Every sink sees the same processed frames. The Dart API stays Transport-agnostic. The native capturer hook is documented so a sink package can bind without forking Session.

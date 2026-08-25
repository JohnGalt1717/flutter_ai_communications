# The production video path stays native

Audio can cross the Dart boundary as PCM chunks. Video at 720p30 cannot: copying frames through EventChannel into Dart and back into an encoder loses the Teams/Zoom thermal and latency race. The Production video path is native: camera, Video processor, Preview Texture, and Video sinks. A Dart byte tap exists only as a Video calibration tap, off by default, never the wire into WebRTC.

# The production video path stays native and is per send source

Audio can cross the Dart boundary as PCM chunks. Video at 720p30 cannot: copying frames through EventChannel into Dart and back into an encoder loses the Teams/Zoom thermal and latency race. Each send source (camera, screen) has its own native Production video path: capture, Video processor, local Video surface, Transport plugin. A Dart byte tap exists only as a calibration tap, off by default, never the wire into a Transport plugin.

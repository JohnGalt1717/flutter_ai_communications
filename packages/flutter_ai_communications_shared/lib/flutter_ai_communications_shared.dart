/// Shared pairing, sound floor, barge-in, and transcode types.
library;

export 'src/acoustic_profile.dart';
export 'src/apple_pair_id.dart';
export 'src/bluetooth_identity.dart';
export 'src/known_profile_registry.dart';
export 'src/audio_format.dart';
export 'src/audio_transcoder.dart';
export 'src/capture_processor.dart';
export 'src/conversion_path.dart';
export 'src/format_negotiator.dart';
export 'src/barge_in.dart';
export 'src/endpoint.dart';
export 'src/endpoint_preference.dart';
export 'src/pairing.dart';
export 'src/playback_timeline.dart';
export 'src/sound_floor.dart';
export 'src/voice_metrics.dart';

/// Placeholder so older workspace tests still resolve.
const String sharedPackageName = 'flutter_ai_communications_shared';

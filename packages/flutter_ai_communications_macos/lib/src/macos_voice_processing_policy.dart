/// Voice-processing graph policy for the macOS adapter.
///
/// Isolation is unavailable on macOS. The Session still prompts via
/// Isolation events and raises the Sound floor when Isolation is missing.
/// AEC still needs one duplex AVAudioEngine: separate AudioQueues recreate
/// the Scribe speaker leak because capture never receives the rendered
/// playback reference.
final class MacosVoiceProcessingPolicy {
  /// Creates a policy.
  const MacosVoiceProcessingPolicy();

  /// Capture tap and playback player must live on one AVAudioEngine.
  static const usesSingleDuplexEngine = true;

  /// Player connects to this engine's mixer/output, never a second graph.
  static const playbackMustShareCaptureEngine = true;

  /// Mixer output is the VPIO echo reference. Connect it on the same engine.
  static const mixerMustConnectToOutputOnSameEngine = true;

  /// Isolation cannot be detected or opened on macOS.
  static const isolationState = 'unavailable';

  /// Attach playback, then enable VoiceProcessingIO, then tap.
  static const engineStartSteps = <String>[
    'attachPlayback',
    'enableVoiceProcessing',
    'installCaptureTap',
    'startEngine',
  ];

  /// Disable VoiceProcessingIO before stopping the engine.
  static const mustDisableVoiceProcessingBeforeEngineStop = true;

  /// Noise cancelling asks the platform for VoiceProcessingIO.
  static bool shouldEnableVoiceProcessing(bool noiseCancelling) =>
      noiseCancelling;
}

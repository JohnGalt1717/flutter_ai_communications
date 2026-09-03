/// Graph policy for the iOS adapter.
///
/// Session edges are PCM16 LE mono. The mixer is often stereo, so connecting
/// the player and scheduling playback from the mixer format crashes:
/// `_outputFormat.channelCount == buffer.format.channelCount`.
public enum IosGraphPolicy {
    /// Capture EventChannel payloads must hop to Flutter's platform thread.
    public static let captureEventsRequirePlatformThread = true

    /// Player connection stays Session-mono even when the mixer is stereo.
    public static func playerConnectionChannelCount(mixerOutputChannels: Int) -> Int {
        1
    }

    /// Scheduled buffers must match the player connection, not the mixer.
    public static func playbackBufferChannelCount(
        playerConnectionChannels: Int,
        mixerOutputChannels: Int
    ) -> Int {
        playerConnectionChannels > 0 ? playerConnectionChannels : 1
    }

    /// Native Format the engine actually opened. Not the requested edge Format.
    public static func nativeFormatMap(
        sampleRate: Double,
        channels: Int = 1
    ) -> [String: Any] {
        let rate = sampleRate > 0 ? Int(sampleRate.rounded()) : 24_000
        let ch = channels > 0 ? channels : 1
        return [
            "encoding": "pcm16le",
            "sampleRate": rate,
            "channels": ch,
        ]
    }
}

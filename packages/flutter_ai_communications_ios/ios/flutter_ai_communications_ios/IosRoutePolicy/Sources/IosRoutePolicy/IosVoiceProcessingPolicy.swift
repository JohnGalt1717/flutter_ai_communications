/// Voice-processing and Isolation policy for the iOS adapter.
///
/// Isolation is an iOS microphone-mode the user can set. It is only available
/// when VoiceProcessingIO is active. Speakerphone and handset both need that
/// graph: without it the Session hears playback, which is the Scribe speaker
/// leak. Automatic Mic Mode on iOS 18+ uses Isolation on the receiver and
/// Standard on speakerphone, so Isolation state must read the active mode, not
/// only the preferred mode.
public enum IosVoiceProcessingPolicy {
    public enum EngineStartStep: Equatable, Sendable {
        case attachPlayback
        case enableVoiceProcessing
        case installCaptureTap
        case startEngine
    }

    public enum MicrophoneMode: Equatable, Sendable {
        case unknown
        case standard
        case voiceIsolation
        case wideSpectrum
        case automatic
    }

    /// VoiceProcessingIO teardown on iOS 18+ can crash if the engine stops first.
    public static let mustDisableVoiceProcessingBeforeEngineStop = true

    /// Enabling VPIO or starting the engine can reset a speaker override
    /// back to the receiver. Re-apply the Desired Pair after both.
    public static let mustReapplyRouteAfterVoiceProcessing = true

    /// Capture tap and playback player must live on one AVAudioEngine.
    /// Scribe's speaker leak was record_ios capture vs a second player engine:
    /// VPIO never saw the rendered reference, so speakerphone heard itself.
    public static let usesSingleDuplexEngine = true

    /// Player connects to this engine's mixer/output, never a second graph.
    public static let playbackMustShareCaptureEngine = true

    /// Mixer output is the VPIO echo reference. Connect it on the same engine.
    public static let mixerMustConnectToOutputOnSameEngine = true

    /// `.defaultToSpeaker` pins the route to speaker even with a headset
    /// attached and is not how speakerphone is selected. Use a port override.
    public static let sessionCategoryIncludesDefaultToSpeaker = false

    public static func shouldEnableVoiceProcessing(
        noiseCancelling: Bool,
        routeClass: String
    ) -> Bool {
        guard noiseCancelling else { return false }
        switch routeClass {
        case "speakerphone", "handset", "bluetooth", "wired", "car":
            return true
        default:
            return true
        }
    }

    public static func engineStartSteps(voiceProcessing: Bool) -> [EngineStartStep] {
        if voiceProcessing {
            return [.attachPlayback, .enableVoiceProcessing, .installCaptureTap, .startEngine]
        }
        return [.attachPlayback, .installCaptureTap, .startEngine]
    }

    /// VPIO capture is Session-mono. When it is off, still tap Session-mono so
    /// the Capture stream stays PCM16 LE mono.
    public static func captureTapChannelCount(
        voiceProcessingEnabled: Bool,
        inputNodeChannels: Int
    ) -> Int {
        if voiceProcessingEnabled, inputNodeChannels > 0 {
            return inputNodeChannels
        }
        return 1
    }

    public static func preferredInputChannelCount(voiceProcessing: Bool) -> Int {
        1
    }

    public static func preferredOutputChannelCount(voiceProcessing: Bool) -> Int {
        1
    }

    public static func shouldPreferBuiltInMic(selectedCaptureId: String?) -> Bool {
        selectedCaptureId == "speaker-in" || selectedCaptureId == "handset-in"
    }

    /// Speakerphone ↔ handset is a port override on the live graph.
    /// Accessory input/output changes may rebuild.
    public static func shouldRebuildGraph(
        previousCaptureId: String?,
        previousRenderId: String?,
        nextCaptureId: String?,
        nextRenderId: String?
    ) -> Bool {
        let previousBuiltin =
            isBuiltinPortId(previousCaptureId) && isBuiltinPortId(previousRenderId)
        let nextBuiltin = isBuiltinPortId(nextCaptureId) && isBuiltinPortId(nextRenderId)
        return !(previousBuiltin && nextBuiltin)
    }

    public static func isBuiltinPortId(_ id: String?) -> Bool {
        switch id {
        case "speaker-in", "speaker-out", "speakerphone-out", "handset-in", "handset-out":
            return true
        default:
            return false
        }
    }

    /// Pinning Front/Bottom/Back while VPIO is on fights Isolation's array
    /// processing and is the Scribe channel bug. Let the OS pick the array.
    public static func shouldPinBuiltinDataSource(noiseCancelling: Bool) -> Bool {
        false
    }

    public static func isolationState(
        noiseCancelling: Bool,
        isolationApiAvailable: Bool,
        preferredMode: MicrophoneMode,
        activeMode: MicrophoneMode?,
        voiceProcessingEnabled: Bool,
        routeClass: String = "speakerphone"
    ) -> String {
        guard isolationApiAvailable else { return "unavailable" }
        let observed = observedMode(preferredMode: preferredMode, activeMode: activeMode)
        let isolated = isVoiceIsolation(
            observed: observed,
            routeClass: routeClass
        )
        guard noiseCancelling else {
            return isolated && voiceProcessingEnabled ? "on" : "off"
        }
        guard voiceProcessingEnabled else { return "required" }
        return isolated ? "on" : "required"
    }

    /// Automatic Mic Mode uses Isolation on the receiver and Standard on
    /// speakerphone. Read the active mode when present; otherwise assume that
    /// Apple mapping so speakerphone still reports Isolation required.
    private static func isVoiceIsolation(
        observed: MicrophoneMode,
        routeClass: String
    ) -> Bool {
        switch observed {
        case .voiceIsolation:
            return true
        case .automatic:
            return routeClass == "handset"
        case .standard, .wideSpectrum, .unknown:
            return false
        }
    }

    private static func observedMode(
        preferredMode: MicrophoneMode,
        activeMode: MicrophoneMode?
    ) -> MicrophoneMode {
        activeMode ?? preferredMode
    }
}

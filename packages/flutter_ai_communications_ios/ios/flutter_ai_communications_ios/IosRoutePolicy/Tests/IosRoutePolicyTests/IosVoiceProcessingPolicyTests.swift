import Testing
@testable import IosRoutePolicy

@Test func noiseCancellingEnablesVoiceProcessingOnSpeakerphoneAndHandset() {
    #expect(
        IosVoiceProcessingPolicy.shouldEnableVoiceProcessing(
            noiseCancelling: true,
            routeClass: "speakerphone"
        )
    )
    #expect(
        IosVoiceProcessingPolicy.shouldEnableVoiceProcessing(
            noiseCancelling: true,
            routeClass: "handset"
        )
    )
}

@Test func noiseCancellingOffDoesNotEnableVoiceProcessing() {
    #expect(
        IosVoiceProcessingPolicy.shouldEnableVoiceProcessing(
            noiseCancelling: false,
            routeClass: "speakerphone"
        ) == false
    )
}

@Test func voiceProcessingGraphAttachesPlaybackBeforeEnablingAndTapping() {
    #expect(
        IosVoiceProcessingPolicy.engineStartSteps(voiceProcessing: true) == [
            .attachPlayback,
            .enableVoiceProcessing,
            .installCaptureTap,
            .startEngine,
        ]
    )
}

@Test func graphWithoutVoiceProcessingStillAttachesPlaybackBeforeTap() {
    #expect(
        IosVoiceProcessingPolicy.engineStartSteps(voiceProcessing: false) == [
            .attachPlayback,
            .installCaptureTap,
            .startEngine,
        ]
    )
}

@Test func voiceProcessingMustBeDisabledBeforeEngineStop() {
    #expect(IosVoiceProcessingPolicy.mustDisableVoiceProcessingBeforeEngineStop)
}

@Test func speakerOverrideMustBeReappliedAfterVoiceProcessing() {
    #expect(IosVoiceProcessingPolicy.mustReapplyRouteAfterVoiceProcessing)
}

@Test func captureAndPlaybackShareOneDuplexEngine() {
    #expect(IosVoiceProcessingPolicy.usesSingleDuplexEngine)
    #expect(IosVoiceProcessingPolicy.playbackMustShareCaptureEngine)
    #expect(IosVoiceProcessingPolicy.mixerMustConnectToOutputOnSameEngine)
}

@Test func captureTapFollowsVoiceProcessedNodeChannelCount() {
    #expect(
        IosVoiceProcessingPolicy.captureTapChannelCount(
            voiceProcessingEnabled: true,
            inputNodeChannels: 1
        ) == 1
    )
}

@Test func captureTapStaysSessionMonoWhenVoiceProcessingIsOff() {
    #expect(
        IosVoiceProcessingPolicy.captureTapChannelCount(
            voiceProcessingEnabled: false,
            inputNodeChannels: 2
        ) == 1
    )
}

@Test func sessionEdgesPreferMonoWhenVoiceProcessingIsOn() {
    #expect(IosVoiceProcessingPolicy.preferredInputChannelCount(voiceProcessing: true) == 1)
    #expect(IosVoiceProcessingPolicy.preferredOutputChannelCount(voiceProcessing: true) == 1)
}

@Test func speakerphoneDoesNotUseDefaultToSpeakerCategoryOption() {
    #expect(IosVoiceProcessingPolicy.sessionCategoryIncludesDefaultToSpeaker == false)
}

@Test func builtinSpeakerAndHandsetPreferBuiltInMicWithoutPinningADataSource() {
    #expect(IosVoiceProcessingPolicy.shouldPreferBuiltInMic(selectedCaptureId: "speaker-in"))
    #expect(IosVoiceProcessingPolicy.shouldPreferBuiltInMic(selectedCaptureId: "handset-in"))
    #expect(
        IosVoiceProcessingPolicy.shouldPreferBuiltInMic(selectedCaptureId: "airpods-in") == false
    )
    #expect(
        IosVoiceProcessingPolicy.shouldPinBuiltinDataSource(noiseCancelling: true) == false
    )
}

@Test func isolationIsOnOnlyWhenActiveModeIsVoiceIsolation() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: true,
            preferredMode: .automatic,
            activeMode: .voiceIsolation,
            voiceProcessingEnabled: true
        ) == "on"
    )
}

@Test func speakerphoneAutomaticMicModeIsNotIsolation() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: true,
            preferredMode: .automatic,
            activeMode: .standard,
            voiceProcessingEnabled: true,
            routeClass: "speakerphone"
        ) == "required"
    )
}

@Test func speakerphoneAutomaticWithoutActiveModeIsStillRequired() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: true,
            preferredMode: .automatic,
            activeMode: nil,
            voiceProcessingEnabled: true,
            routeClass: "speakerphone"
        ) == "required"
    )
}

@Test func handsetAutomaticWithoutActiveModeUsesIsolation() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: true,
            preferredMode: .automatic,
            activeMode: nil,
            voiceProcessingEnabled: true,
            routeClass: "handset"
        ) == "on"
    )
}

@Test func preferredVoiceIsolationWithoutActiveReadingIsOn() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: true,
            preferredMode: .voiceIsolation,
            activeMode: nil,
            voiceProcessingEnabled: true
        ) == "on"
    )
}

@Test func isolationIsRequiredWhenVoiceProcessingFailedToEnable() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: true,
            preferredMode: .voiceIsolation,
            activeMode: .voiceIsolation,
            voiceProcessingEnabled: false
        ) == "required"
    )
}

@Test func isolationIsUnavailableWhenTheApiIsMissing() {
    #expect(
        IosVoiceProcessingPolicy.isolationState(
            noiseCancelling: true,
            isolationApiAvailable: false,
            preferredMode: .unknown,
            activeMode: nil,
            voiceProcessingEnabled: true
        ) == "unavailable"
    )
}

@Test func speakerphoneHandsetPickDoesNotRebuildTheGraph() {
    #expect(
        IosVoiceProcessingPolicy.shouldRebuildGraph(
            previousCaptureId: "speaker-in",
            previousRenderId: "speaker-out",
            nextCaptureId: "handset-in",
            nextRenderId: "handset-out"
        ) == false
    )
    #expect(
        IosVoiceProcessingPolicy.shouldRebuildGraph(
            previousCaptureId: "handset-in",
            previousRenderId: "handset-out",
            nextCaptureId: "speaker-in",
            nextRenderId: "speaker-out"
        ) == false
    )
}

@Test func accessoryInputChangeMayRebuildTheGraph() {
    #expect(
        IosVoiceProcessingPolicy.shouldRebuildGraph(
            previousCaptureId: "speaker-in",
            previousRenderId: "speaker-out",
            nextCaptureId: "airpods-in",
            nextRenderId: "airpods-out"
        )
    )
    #expect(
        IosVoiceProcessingPolicy.shouldRebuildGraph(
            previousCaptureId: "airpods-in",
            previousRenderId: "airpods-out",
            nextCaptureId: "speaker-in",
            nextRenderId: "speaker-out"
        )
    )
}

@Test func selectingTheSameAccessoryDoesNotRebuildTheGraph() {
    #expect(
        IosVoiceProcessingPolicy.shouldRebuildGraph(
            previousCaptureId: "airpods-in",
            previousRenderId: "airpods-out",
            nextCaptureId: "airpods-in",
            nextRenderId: "airpods-out"
        ) == false
    )
}

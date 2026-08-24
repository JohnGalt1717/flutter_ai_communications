import Testing
@testable import IosRoutePolicy

@Test func padWithoutReceiverDoesNotAdvertiseHandset() {
    let catalog = IosRoutePolicy.builtinEndpoints(hasReceiver: false)
    #expect(catalog.map(\.id) == ["speaker-in", "speaker-out"])
    #expect(catalog.contains { $0.pairId == "handset" } == false)
}

@Test func phoneWithReceiverAdvertisesHandsetAndSpeaker() {
    let catalog = IosRoutePolicy.builtinEndpoints(hasReceiver: true)
    #expect(
        catalog.map(\.id) == [
            "handset-in",
            "handset-out",
            "speaker-in",
            "speaker-out",
        ]
    )
}

@Test func nativeSuiteSkipsHandsetSwitchWhenReceiverIsAbsent() {
    #expect(IosRoutePolicy.shouldAdvertiseHandset(hasReceiver: false) == false)
    #expect(IosRoutePolicy.shouldAdvertiseHandset(hasReceiver: true) == true)
}

@Test func padDetectsNoReceiverFromSpeakerRouteAndNonPhoneIdiom() {
    #expect(
        IosRoutePolicy.hasReceiver(
            currentOutputIsReceiver: false,
            idiomIsPhone: false
        ) == false
    )
}

@Test func phoneKeepsReceiverEvenWhileSpeakerIsActive() {
    #expect(
        IosRoutePolicy.hasReceiver(
            currentOutputIsReceiver: false,
            idiomIsPhone: true
        ) == true
    )
}

@Test func receiverPortIsEnoughEvenOnNonPhoneIdiom() {
    #expect(
        IosRoutePolicy.hasReceiver(
            currentOutputIsReceiver: true,
            idiomIsPhone: false
        ) == true
    )
}

@Test func padSpeakerRouteObservesSpeakerPair() {
    let ids = IosRoutePolicy.catalogIds(
        outputRouteClass: "speakerphone",
        accessoryPairId: "speakerphone"
    )
    #expect(ids.capture == "speaker-in")
    #expect(ids.render == "speaker-out")
}

@Test func phoneReceiverRouteObservesHandsetPair() {
    let ids = IosRoutePolicy.catalogIds(
        outputRouteClass: "handset",
        accessoryPairId: "handset"
    )
    #expect(ids.capture == "handset-in")
    #expect(ids.render == "handset-out")
}

@Test func accessoryRouteObservesPairedIds() {
    let ids = IosRoutePolicy.catalogIds(
        outputRouteClass: "bluetooth",
        accessoryPairId: "airpods"
    )
    #expect(ids.capture == "airpods-in")
    #expect(ids.render == "airpods-out")
}

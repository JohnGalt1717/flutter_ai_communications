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
    #expect(ids.capture == nil)
    #expect(ids.render == "airpods-out")
}

@Test func a2dpOutputWithBuiltinMicDoesNotInventAccessoryCapture() {
    let ids = IosRoutePolicy.catalogIds(
        output: IosObservedPort(
            routeClass: "bluetooth",
            pairId: "airpods",
            portType: "BluetoothA2DP"
        ),
        input: IosObservedPort(
            routeClass: "handset",
            pairId: "handset",
            portType: "MicrophoneBuiltIn"
        )
    )
    #expect(ids.capture == "handset-in")
    #expect(ids.render == "airpods-out")
}

@Test func hfpOutputWithHfpInputObservesPairedAccessoryIds() {
    let ids = IosRoutePolicy.catalogIds(
        output: IosObservedPort(
            routeClass: "bluetooth",
            pairId: "airpods",
            portType: "BluetoothHFP"
        ),
        input: IosObservedPort(
            routeClass: "bluetooth",
            pairId: "airpods",
            portType: "BluetoothHFP"
        )
    )
    #expect(ids.capture == "airpods-in")
    #expect(ids.render == "airpods-out")
}

@Test func outputOnlyPathWithNoInputsLeavesCaptureNil() {
    let ids = IosRoutePolicy.catalogIds(
        output: IosObservedPort(
            routeClass: "bluetooth",
            pairId: "airpods",
            portType: "BluetoothA2DP"
        ),
        input: nil
    )
    #expect(ids.capture == nil)
    #expect(ids.render == "airpods-out")
}

@Test func speakerphoneOutputWithBuiltinMicStillObservesSpeakerCapture() {
    let ids = IosRoutePolicy.catalogIds(
        output: IosObservedPort(
            routeClass: "speakerphone",
            pairId: "speakerphone",
            portType: "Speaker"
        ),
        input: IosObservedPort(
            routeClass: "handset",
            pairId: "handset",
            portType: "MicrophoneBuiltIn"
        )
    )
    #expect(ids.capture == "speaker-in")
    #expect(ids.render == "speaker-out")
}

@Test func hfpPortIsHeadsetFormFactor() {
    #expect(IosRoutePolicy.formFactor(portType: "BluetoothHFP") == "headset")
}

@Test func carAudioPortIsCarFormFactor() {
    #expect(IosRoutePolicy.formFactor(portType: "CarAudio") == "car")
}

@Test func a2dpPortStaysUnknownUntilANameOrClassMatch() {
    #expect(IosRoutePolicy.formFactor(portType: "BluetoothA2DP") == "unknown")
}

@Test func builtinHandsetRouteIsHandsetFormFactor() {
    #expect(IosRoutePolicy.formFactor(routeClass: "handset") == "handset")
    #expect(IosRoutePolicy.formFactor(routeClass: "speakerphone") == "unknown")
}

@Test func hfpLeAndHeadsetMicAreCaptureCapable() {
    #expect(IosRoutePolicy.isCaptureCapableAccessory(portType: "BluetoothHFP"))
    #expect(IosRoutePolicy.isCaptureCapableAccessory(portType: "BluetoothLE"))
    #expect(IosRoutePolicy.isCaptureCapableAccessory(portType: "HeadsetMic"))
}

@Test func a2dpHeadphonesAndCarAudioAreNotCaptureCapable() {
    #expect(IosRoutePolicy.isCaptureCapableAccessory(portType: "BluetoothA2DP") == false)
    #expect(IosRoutePolicy.isCaptureCapableAccessory(portType: "Headphones") == false)
    #expect(IosRoutePolicy.isCaptureCapableAccessory(portType: "CarAudio") == false)
}

@Test func hardwarePairTokenStripsTscoAndTaclSuffixes() {
    let base = "AA:BB:CC:DD:EE:FF"
    #expect(IosRoutePolicy.hardwarePairToken(uid: "\(base)-tsco") == base)
    #expect(IosRoutePolicy.hardwarePairToken(uid: "\(base)-tacl") == base)
    #expect(
        IosRoutePolicy.hardwarePairToken(uid: "\(base)-tsco")
            == IosRoutePolicy.hardwarePairToken(uid: "\(base)-tacl")
    )
}

@Test func hardwarePairTokenKeepsDistinctAddressesApart() {
    let left = IosRoutePolicy.hardwarePairToken(uid: "AA:BB:CC:DD:EE:FF-tsco")
    let right = IosRoutePolicy.hardwarePairToken(uid: "11:22:33:44:55:66-tacl")
    #expect(left != right)
    #expect(IosRoutePolicy.hardwarePairToken(uid: "plain-uid") == "plain-uid")
}

@Test func receiverRouteStillMarksSpeakerphoneAsBuiltinOsDefault() {
    #expect(
        IosRoutePolicy.builtinIsOsDefault(
            routeClass: "speakerphone",
            isCapture: true,
            inputPortType: "MicrophoneBuiltIn",
            outputPortType: "Receiver"
        )
    )
    #expect(
        IosRoutePolicy.builtinIsOsDefault(
            routeClass: "speakerphone",
            isCapture: false,
            inputPortType: "MicrophoneBuiltIn",
            outputPortType: "Receiver"
        )
    )
    #expect(
        IosRoutePolicy.builtinIsOsDefault(
            routeClass: "handset",
            isCapture: false,
            inputPortType: "MicrophoneBuiltIn",
            outputPortType: "Receiver"
        ) == false
    )
}

@Test func speakerRouteMarksSpeakerphoneAsBuiltinOsDefault() {
    #expect(
        IosRoutePolicy.builtinIsOsDefault(
            routeClass: "speakerphone",
            isCapture: false,
            inputPortType: "MicrophoneBuiltIn",
            outputPortType: "Speaker"
        )
    )
}

@Test func accessoryRouteDoesNotMarkSpeakerphoneAsOsDefault() {
    #expect(
        IosRoutePolicy.builtinIsOsDefault(
            routeClass: "speakerphone",
            isCapture: false,
            inputPortType: "BluetoothHFP",
            outputPortType: "BluetoothHFP"
        ) == false
    )
    #expect(
        IosRoutePolicy.builtinIsOsDefault(
            routeClass: "speakerphone",
            isCapture: true,
            inputPortType: "BluetoothHFP",
            outputPortType: "BluetoothHFP"
        ) == false
    )
}

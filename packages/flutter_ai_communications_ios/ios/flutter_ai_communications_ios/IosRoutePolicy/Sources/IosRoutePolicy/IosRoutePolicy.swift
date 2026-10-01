/// Catalog and observe policy for the iOS adapter.
///
/// Handset is only an Endpoint when a receiver exists. iPad has a speaker
/// and a mic, not an earpiece, so advertising handset makes Observed diverge
/// from Desired after a speaker-handset switch.
public struct IosCatalogEndpoint: Equatable, Sendable {
    public let id: String
    public let name: String
    public let routeClass: String
    public let isCapture: Bool
    public let pairId: String

    public init(
        id: String,
        name: String,
        routeClass: String,
        isCapture: Bool,
        pairId: String
    ) {
        self.id = id
        self.name = name
        self.routeClass = routeClass
        self.isCapture = isCapture
        self.pairId = pairId
    }
}

public enum IosRoutePolicy {
    public static func shouldAdvertiseHandset(hasReceiver: Bool) -> Bool {
        hasReceiver
    }

    /// A receiver is present when the current route is the earpiece, or the
    /// idiom is phone (iPhone still has a receiver while speaker is active).
    public static func hasReceiver(
        currentOutputIsReceiver: Bool,
        idiomIsPhone: Bool
    ) -> Bool {
        currentOutputIsReceiver || idiomIsPhone
    }

    public static func builtinEndpoints(hasReceiver: Bool) -> [IosCatalogEndpoint] {
        var items: [IosCatalogEndpoint] = []
        if shouldAdvertiseHandset(hasReceiver: hasReceiver) {
            items.append(
                IosCatalogEndpoint(
                    id: "handset-in",
                    name: "Handset",
                    routeClass: "handset",
                    isCapture: true,
                    pairId: "handset"
                )
            )
            items.append(
                IosCatalogEndpoint(
                    id: "handset-out",
                    name: "Handset",
                    routeClass: "handset",
                    isCapture: false,
                    pairId: "handset"
                )
            )
        }
        items.append(
            IosCatalogEndpoint(
                id: "speaker-in",
                name: "Speakerphone",
                routeClass: "speakerphone",
                isCapture: true,
                pairId: "speakerphone"
            )
        )
        items.append(
            IosCatalogEndpoint(
                id: "speaker-out",
                name: "Speakerphone",
                routeClass: "speakerphone",
                isCapture: false,
                pairId: "speakerphone"
            )
        )
        return items
    }

    public static func catalogIds(
        outputRouteClass: String?,
        accessoryPairId: String
    ) -> (capture: String?, render: String?) {
        switch outputRouteClass {
        case "speakerphone":
            return ("speaker-in", "speaker-out")
        case "handset":
            return ("handset-in", "handset-out")
        case nil:
            return (nil, nil)
        default:
            return ("\(accessoryPairId)-in", "\(accessoryPairId)-out")
        }
    }

    /// Native form factor from AVAudioSession port type. Unknown A2DP stays
    /// name-based; HFP is a headset and carAudio is a car head unit.
    public static func formFactor(portType: String) -> String {
        switch portType {
        case "BluetoothHFP", "BluetoothLE":
            return "headset"
        case "CarAudio":
            return "car"
        case "Receiver":
            return "handset"
        default:
            return "unknown"
        }
    }

    /// Built-in handset is the earpiece. Speakerphone is not a Bluetooth speaker.
    public static func formFactor(routeClass: String) -> String {
        routeClass == "handset" ? "handset" : "unknown"
    }

    /// Input ports that may appear as capture Endpoints (issue #88).
    public static func isCaptureCapableAccessory(portType: String) -> Bool {
        switch portType {
        case "BluetoothHFP", "BluetoothLE", "HeadsetMic":
            return true
        default:
            return false
        }
    }

    /// Hardware pair token: strip trailing -tsco / -tacl from a port uid (issue #90/#88).
    public static func hardwarePairToken(uid: String) -> String {
        if uid.hasSuffix("-tsco") { return String(uid.dropLast(5)) }
        if uid.hasSuffix("-tacl") { return String(uid.dropLast(5)) }
        return uid
    }
}

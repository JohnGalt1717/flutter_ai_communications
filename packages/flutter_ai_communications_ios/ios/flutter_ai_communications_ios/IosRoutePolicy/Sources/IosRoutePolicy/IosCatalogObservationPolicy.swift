/// Catalog-observation ownership when the Flutter engine detaches (issue #93).
public struct IosCatalogObservationRelease: Equatable, Sendable {
    public let depth: Int
    public let ownsSession: Bool
    public let deactivate: Bool

    public init(depth: Int, ownsSession: Bool, deactivate: Bool) {
        self.depth = depth
        self.ownsSession = ownsSession
        self.deactivate = deactivate
    }
}

public enum IosCatalogObservationPolicy {
    /// Engine detach: drop observation bookkeeping. Deactivate the
    /// AVAudioSession only when observation owns it and no Session is running.
    public static func releaseForDetach(
        ownsSession: Bool,
        running: Bool
    ) -> IosCatalogObservationRelease {
        IosCatalogObservationRelease(
            depth: 0,
            ownsSession: false,
            deactivate: !running && ownsSession
        )
    }
}

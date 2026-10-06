import Testing
@testable import IosRoutePolicy

@Test func detachWhileIdleAndOwningSessionDeactivatesAndClearsDepth() {
    let plan = IosCatalogObservationPolicy.releaseForDetach(
        ownsSession: true,
        running: false
    )
    #expect(plan.depth == 0)
    #expect(plan.ownsSession == false)
    #expect(plan.deactivate == true)
}

@Test func detachWhileSessionRunningLeavesCallSessionActive() {
    let plan = IosCatalogObservationPolicy.releaseForDetach(
        ownsSession: true,
        running: true
    )
    #expect(plan.depth == 0)
    #expect(plan.ownsSession == false)
    #expect(plan.deactivate == false)
}

@Test func detachWithoutOwnershipDoesNotDeactivate() {
    let plan = IosCatalogObservationPolicy.releaseForDetach(
        ownsSession: false,
        running: false
    )
    #expect(plan.depth == 0)
    #expect(plan.ownsSession == false)
    #expect(plan.deactivate == false)
}

import Testing
@testable import IosRoutePolicy

@Test func playbackBufferUsesPlayerConnectionNotMixerWhenCountsDiverge() {
    #expect(
        IosGraphPolicy.playbackBufferChannelCount(
            playerConnectionChannels: 1,
            mixerOutputChannels: 2
        ) == 1
    )
}

@Test func playbackBufferKeepsStereoWhenPlayerIsStereo() {
    #expect(
        IosGraphPolicy.playbackBufferChannelCount(
            playerConnectionChannels: 2,
            mixerOutputChannels: 2
        ) == 2
    )
}

@Test func playerConnectionStaysSessionMonoWhenMixerIsStereo() {
    #expect(IosGraphPolicy.playerConnectionChannelCount(mixerOutputChannels: 2) == 1)
}

@Test func unsetPlayerConnectionFallsBackToSessionMono() {
    #expect(
        IosGraphPolicy.playbackBufferChannelCount(
            playerConnectionChannels: 0,
            mixerOutputChannels: 2
        ) == 1
    )
}

@Test func captureEventsMustHopToThePlatformThread() {
    #expect(IosGraphPolicy.captureEventsRequirePlatformThread)
}

import Testing
@testable import TideBarCore

@Test func windowKnowledgeAggregatesKnownInstances() {
    let result = WindowKnowledge<Int>.aggregate([
        .known([]),
        .known([1, 2]),
        .known([3]),
    ])

    #expect(result == .known([1, 2, 3]))
}

@Test func windowKnowledgeBecomesUnknownWhenAnyInstanceIsUnknown() {
    let result = WindowKnowledge<Int>.aggregate([
        .known([1]),
        .unknown,
    ])

    #expect(result == .unknown)
}

@Test func finderRequiresKnownWindowsAndForbidsTermination() {
    let behavior = AppBehavior.resolve(for: AppIdentity("com.apple.Finder"))

    #expect(!behavior.isVisible(isPinned: true, isRunning: true, knownWindowCount: nil))
    #expect(!behavior.isVisible(isPinned: true, isRunning: true, knownWindowCount: 0))
    #expect(behavior.isVisible(isPinned: true, isRunning: true, knownWindowCount: 1))
    #expect(!behavior.isVisible(isPinned: true, isRunning: false, knownWindowCount: 1))
    #expect(!behavior.canTerminate)
}

@Test func standardAppsKeepPinnedAndRunningVisibility() {
    let behavior = AppBehavior.resolve(for: AppIdentity("com.example.app"))

    #expect(behavior.isVisible(isPinned: true, isRunning: false, knownWindowCount: nil))
    #expect(behavior.isVisible(isPinned: false, isRunning: true, knownWindowCount: nil))
    #expect(!behavior.isVisible(isPinned: false, isRunning: false, knownWindowCount: 0))
    #expect(behavior.canTerminate)
}

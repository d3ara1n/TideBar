import Testing
@testable import TideBarCore

@Test func identityIgnoresASCIICase() {
    #expect(AppIdentity("com.apple.Finder") == AppIdentity("com.apple.finder"))
    #expect(AppIdentity("COM.Example.App").bundleIdentifier == "com.example.app")
}

@Test func pinnedAndRunningCaseVariantsComposeAsOneApp() {
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: ["com.apple.Finder"],
        runningApps: [RunningAppDescription(bundleIdentifier: "com.apple.finder", processIdentifier: 10)]
    )

    #expect(result.count == 1)
    #expect(result[0].identity == AppIdentity("com.apple.finder"))
    #expect(result[0].pinnedBundleIdentifier == "com.apple.Finder")
    #expect(result[0].runningInstances.map(\.processIdentifier) == [10])
}

@Test func duplicatePinnedVariantsKeepFirstPositionAndLocator() {
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: ["com.example.First", "COM.EXAMPLE.FIRST", "com.example.Second"],
        runningApps: []
    )

    #expect(result.map(\.identity) == [AppIdentity("com.example.first"), AppIdentity("com.example.second")])
    #expect(result.map(\.pinnedBundleIdentifier) == ["com.example.First", "com.example.Second"])
}

@Test func multipleProcessesWithOneIdentityComposeAsOneApp() {
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: [],
        runningApps: [
            RunningAppDescription(bundleIdentifier: "com.example.App", processIdentifier: 20),
            RunningAppDescription(bundleIdentifier: "com.example.app", processIdentifier: 21),
        ]
    )

    #expect(result.count == 1)
    #expect(result[0].runningInstances.map(\.processIdentifier) == [20, 21])
}

@Test func pinnedAppsPrecedeUnpinnedRunningApps() {
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: ["com.example.Pinned"],
        runningApps: [
            RunningAppDescription(bundleIdentifier: "com.example.Running", processIdentifier: 30),
            RunningAppDescription(bundleIdentifier: "com.example.Pinned", processIdentifier: 31),
        ]
    )

    #expect(result.map(\.identity) == [AppIdentity("com.example.pinned"), AppIdentity("com.example.running")])
    #expect(result[0].isPinned)
    #expect(result[0].isRunning)
    #expect(!result[1].isPinned)
    #expect(result[1].isRunning)
}

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

@Test func sameBundleDifferentApplicationPathsComposeAsSeparateApps() {
    let result = AppListComposer.compose(
        pinnedApplications: [],
        runningApps: [
            RunningAppDescription(bundleIdentifier: "com.example.App", processIdentifier: 20, applicationPath: "/Applications/Foo.app"),
            RunningAppDescription(bundleIdentifier: "com.example.App", processIdentifier: 21, applicationPath: "/Users/test/Applications/Foo.app"),
        ]
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.identity == AppIdentity("com.example.app") })
    #expect(Set(result.map(\.itemIdentity.applicationPath)) == Set(["/Applications/Foo.app", "/Users/test/Applications/Foo.app"]))
}


@Test func bareExecutableInstancesGroupByPathIdentity() {
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: [],
        runningApps: [
            RunningAppDescription(executablePath: "/Users/x/proj/bin/Debug/App", processIdentifier: 20),
            RunningAppDescription(executablePath: "/users/x/proj/bin/Debug/app", processIdentifier: 21),
        ]
    )

    #expect(result.count == 1)
    #expect(result[0].runningInstances.count == 2)
    #expect(result[0].pinnedBundleIdentifier == nil)
}

@Test func distinctBareExecutablesComposeAsSeparateApps() {
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: [],
        runningApps: [
            RunningAppDescription(executablePath: "/Users/x/Debug/App", processIdentifier: 20),
            RunningAppDescription(executablePath: "/Users/x/Release/App", processIdentifier: 21),
        ]
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { !$0.isPinned })
}

@Test func bareExecutablePathIdentityNeverCollidesWithBundleIdentity() {
    // 路径身份以 / 起步，bundle identifier 不含路径分隔符，二者天然不碰撞
    let result = AppListComposer.compose(
        pinnedBundleIdentifiers: ["com.example.app"],
        runningApps: [
            RunningAppDescription(executablePath: "/tmp/com.example.app", processIdentifier: 30),
        ]
    )

    #expect(result.count == 2)
    #expect(result[0].isPinned && result[0].runningInstances.isEmpty)
    #expect(!result[1].isPinned && result[1].runningInstances.count == 1)
}

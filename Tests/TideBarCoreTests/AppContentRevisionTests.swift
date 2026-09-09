import Testing
@testable import TideBarCore

private func revision(processIdentifier: Int32 = 10,
                      isPinned: Bool = false,
                      isHidden: Bool = false,
                      canTerminate: Bool = true,
                      badge: BadgeValue? = nil,
                      windows: WindowKnowledge<WindowContentRevision> = .known([])) -> AppContentRevision {
    AppContentRevision(identity: AppIdentity("com.example.app"),
                       name: "Example",
                       applicationPath: "/Applications/Example.app",
                       isPinned: isPinned,
                       preferredProcessIdentifier: processIdentifier,
                       processIdentifiers: [processIdentifier],
                       isHidden: isHidden,
                       canTerminate: canTerminate,
                       badge: badge,
                       windows: windows)
}

@Test func processReplacementChangesAppContentRevision() {
    #expect(revision(processIdentifier: 10) != revision(processIdentifier: 11))
}

@Test func pinStateChangeChangesAppContentRevision() {
    #expect(revision(isPinned: true) != revision(isPinned: false))
}

@Test func hiddenStateChangeChangesAppContentRevision() {
    #expect(revision(isHidden: true) != revision(isHidden: false))
}

@Test func capabilityChangeChangesAppContentRevision() {
    #expect(revision(canTerminate: true) != revision(canTerminate: false))
}

@Test func badgeChangeChangesAppContentRevision() {
    #expect(revision(badge: nil) != revision(badge: .count(3)))
    #expect(revision(badge: .count(3)) != revision(badge: .count(4)))
    #expect(revision(badge: .count(3)) != revision(badge: .dot))
}

@Test func windowContentChangeChangesAppContentRevision() {
    let first = WindowContentRevision(ownerProcessIdentifier: 10,
                                      elementIdentifier: 100,
                                      title: "First",
                                      document: nil,
                                      isMinimized: false,
                                      screenID: 1)
    let second = WindowContentRevision(ownerProcessIdentifier: 10,
                                       elementIdentifier: 100,
                                       title: "Second",
                                       document: nil,
                                       isMinimized: false,
                                       screenID: 1)

    let replacement = WindowContentRevision(ownerProcessIdentifier: 10,
                                            elementIdentifier: 101,
                                            title: "First",
                                            document: nil,
                                            isMinimized: false,
                                            screenID: 1)

    #expect(revision(windows: .known([first])) != revision(windows: .known([second])))
    #expect(revision(windows: .known([first])) != revision(windows: .known([replacement])))
    #expect(revision(windows: .unknown) != revision(windows: .known([])))
}

@Test func screenAssignmentChangeChangesAppContentRevision() {
    let builtin = WindowContentRevision(ownerProcessIdentifier: 10,
                                         elementIdentifier: 100,
                                         title: "First",
                                         document: nil,
                                         isMinimized: false,
                                         screenID: 1)
    let external = WindowContentRevision(ownerProcessIdentifier: 10,
                                          elementIdentifier: 100,
                                          title: "First",
                                          document: nil,
                                          isMinimized: false,
                                          screenID: 2)
    #expect(revision(windows: .known([builtin])) != revision(windows: .known([external])))
}

@Test func processOrderDoesNotChangeAppContentRevision() {
    let first = AppContentRevision(identity: AppIdentity("com.example.app"),
                                   name: "Example",
                                   applicationPath: nil,
                                   isPinned: false,
                                   preferredProcessIdentifier: 10,
                                   processIdentifiers: [10, 11],
                                   isHidden: false,
                                   canTerminate: true,
                                   badge: nil,
                                   windows: .known([]))
    let second = AppContentRevision(identity: AppIdentity("com.example.app"),
                                    name: "Example",
                                    applicationPath: nil,
                                    isPinned: false,
                                    preferredProcessIdentifier: 10,
                                    processIdentifiers: [11, 10],
                                    isHidden: false,
                                    canTerminate: true,
                                    badge: nil,
                                    windows: .known([]))

    #expect(first == second)
}

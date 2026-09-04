import Testing
@testable import TideBarCore

private let firstApp = AppIdentity("com.example.first")
private let secondApp = AppIdentity("com.example.second")

@Test func persistentSessionDoesNotExpire() {
    let session = BarSessionState(mode: .persistent,
                                   displayID: 1,
                                   openedBySession: true,
                                   firstApplication: firstApp,
                                   now: 10,
                                   timeout: 0.9)
    #expect(session.isPersistent)
    #expect(!session.isExpired(at: 100))
    #expect(session.selectedApplication == firstApp)
}

@Test func switcherSessionExpiresAtIdleDeadline() {
    let session = BarSessionState(mode: .switcher,
                                   displayID: 1,
                                   openedBySession: true,
                                   firstApplication: firstApp,
                                   now: 10,
                                   timeout: 0.9)
    #expect(!session.isExpired(at: 10.89))
    #expect(session.isExpired(at: 10.9))
}

@Test func switcherTouchExtendsDeadline() {
    var session = BarSessionState(mode: .switcher,
                                  displayID: 1,
                                  openedBySession: true,
                                  firstApplication: firstApp,
                                  now: 10,
                                  timeout: 0.9)
    session.touch(now: 10.5, timeout: 0.9)
    #expect(!session.isExpired(at: 11.3))
    #expect(session.isExpired(at: 11.4))
}

@Test func sessionForwardsWindowNavigation() {
    var session = BarSessionState(mode: .switcher,
                                  displayID: 1,
                                  openedBySession: true,
                                  firstApplication: firstApp)
    let entered = session.enterWindows(for: firstApp, firstWindowIdentifier: 22)
    #expect(entered)
    #expect(session.level == .windows(firstApp))
    #expect(session.selectedWindowIdentifier == 22)
}

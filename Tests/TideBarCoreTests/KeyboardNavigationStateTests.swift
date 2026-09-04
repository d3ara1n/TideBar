import Testing
@testable import TideBarCore

private let editor = AppIdentity("com.example.editor")
private let browser = AppIdentity("com.example.browser")

@Test func enteringApplicationsSelectsFirstApplication() {
    var state = KeyboardNavigationState()
    let entered = state.enterApplications(displayID: 7, firstApplication: editor)
    #expect(entered)
    #expect(state.level == .applications)
    #expect(state.focusedDisplayID == 7)
    #expect(state.selectedApplication == editor)
}

@Test func escapeClosesWindowsBeforeApplications() {
    var state = KeyboardNavigationState()
    _ = state.enterApplications(displayID: 7, firstApplication: editor)
    let entered = state.enterWindows(for: editor, firstWindowIdentifier: 42)
    #expect(entered)
    let escapedWindows = state.escape()
    #expect(escapedWindows)
    #expect(state.level == .applications)
    #expect(state.selectedWindowIdentifier == nil)
    let escapedApplications = state.escape()
    #expect(!escapedApplications)
    #expect(state.level == .inactive)
}

@Test func missingApplicationClearsState() {
    var state = KeyboardNavigationState()
    _ = state.enterApplications(displayID: 7, firstApplication: editor)
    state.clearSelectionIfMissing(applications: [browser], windowIdentifiers: nil)
    #expect(state.level == .inactive)
    #expect(state.focusedDisplayID == nil)
}

@Test func missingWindowMovesSelectionToAvailableWindow() {
    var state = KeyboardNavigationState()
    _ = state.enterApplications(displayID: 7, firstApplication: editor)
    let entered = state.enterWindows(for: editor, firstWindowIdentifier: 42)
    #expect(entered)
    state.clearSelectionIfMissing(applications: [editor], windowIdentifiers: [43, 44])
    #expect(state.selectedWindowIdentifier == 43)
}

@Test func unknownWindowsClearWindowSelectionWithoutInvalidActivation() {
    var state = KeyboardNavigationState()
    _ = state.enterApplications(displayID: 7, firstApplication: editor)
    let entered = state.enterWindows(for: editor, firstWindowIdentifier: 42)
    #expect(entered)
    state.clearSelectionIfMissing(applications: [editor], windowIdentifiers: nil)
    #expect(state.level == .windows(editor))
    #expect(state.selectedWindowIdentifier == nil)
}

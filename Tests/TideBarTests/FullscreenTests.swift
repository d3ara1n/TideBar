import CoreGraphics
import Testing
@testable import TideBar

private let builtin = FullscreenDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 1710, height: 1112))
private let belowNotch = CGRect(x: 0, y: 38, width: 1710, height: 1074)

@Test func fullscreenAndMaximizedWindowsWithIdenticalFramesFollowAXState() {
    let visible = VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)
    for fullscreen in [true, false] {
        let states = FullscreenResolver.resolve(displays: [builtin], visibleWindows: [visible],
            windowsByPID: [100: [AXFullscreenWindow(frame: belowNotch, isFullscreen: fullscreen)]])
        #expect(states[1] == (fullscreen ? .fullscreen : .windowed))
    }
}

@Test func splitViewDoesNotRequireAWindowToCoverTheDisplay() {
    let tile = CGRect(x: 0, y: 38, width: 850, height: 1074)
    let states = FullscreenResolver.resolve(displays: [builtin],
        visibleWindows: [VisibleFullscreenWindow(id: 10, pid: 100, frame: tile)],
        windowsByPID: [100: [AXFullscreenWindow(frame: tile, isFullscreen: true)]])
    #expect(states[1] == .fullscreen)
}

@Test func fullscreenWindowInAnotherSpaceDoesNotAffectVisibleWindowOfSameProcess() {
    let normal = CGRect(x: 50, y: 70, width: 900, height: 600)
    let states = FullscreenResolver.resolve(displays: [builtin],
        visibleWindows: [VisibleFullscreenWindow(id: 10, pid: 100, frame: normal)],
        windowsByPID: [100: [AXFullscreenWindow(frame: normal, isFullscreen: false),
                             AXFullscreenWindow(frame: belowNotch, isFullscreen: true)]])
    #expect(states[1] == .windowed)
}

@Test func indistinguishableWindowsAcrossSpacesRemainUnknown() {
    let states = FullscreenResolver.resolve(displays: [builtin],
        visibleWindows: [VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)],
        windowsByPID: [100: [AXFullscreenWindow(frame: belowNotch, isFullscreen: false),
                             AXFullscreenWindow(frame: belowNotch, isFullscreen: true)]])
    #expect(states[1] == .unknown)
}

@Test func unreadableUnmatchedAndUnsupportedWindowsRemainUnknown() {
    let visible = [VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)]
    let candidates: [[AXFullscreenWindow]] = [
        [],
        [AXFullscreenWindow(frame: belowNotch, isFullscreen: nil)],
        [AXFullscreenWindow(frame: nil, isFullscreen: true)],
        [AXFullscreenWindow(frame: CGRect(x: 30, y: 30, width: 900, height: 600), isFullscreen: false)],
    ]
    for windows in candidates {
        #expect(FullscreenResolver.resolve(displays: [builtin], visibleWindows: visible,
                                            windowsByPID: [100: windows])[1] == .unknown)
    }
}

@Test func confirmedFullscreenWinsOverAnUnreadableCompanionWindowInEitherOrder() {
    let first = VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)
    let second = VisibleFullscreenWindow(id: 20, pid: 200, frame: CGRect(x: 20, y: 50, width: 300, height: 300))
    for visible in [[first, second], [second, first]] {
        let states = FullscreenResolver.resolve(displays: [builtin], visibleWindows: visible,
            windowsByPID: [100: [AXFullscreenWindow(frame: belowNotch, isFullscreen: true)]])
        #expect(states[1] == .fullscreen)
    }
}

@Test func fullscreenIsAssignedToItsDisplayInGlobalTopLeftCoordinates() {
    let external = FullscreenDisplay(id: 2, bounds: CGRect(x: -1920, y: -300, width: 1920, height: 1080))
    let states = FullscreenResolver.resolve(displays: [builtin, external],
        visibleWindows: [VisibleFullscreenWindow(id: 10, pid: 100, frame: external.bounds)],
        windowsByPID: [100: [AXFullscreenWindow(frame: external.bounds, isFullscreen: true)]])
    #expect(states[1] == .windowed)
    #expect(states[2] == .fullscreen)

    // 跨屏的少量溢出不能让同一窗口同时抑制两块屏幕。
    let spanning = CGRect(x: -1800, y: 0, width: 1900, height: 700)
    #expect(FullscreenResolver.display(for: spanning, in: [builtin, external])?.id == 2)
}

@Test func windowMatchingUsesPIDAndAllowsOnlyCoordinateRounding() {
    let rounded = CGRect(x: 0.5, y: 38.5, width: 1709.5, height: 1073.5)
    let visible = [VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)]
    #expect(FullscreenResolver.resolve(displays: [builtin], visibleWindows: visible,
        windowsByPID: [100: [AXFullscreenWindow(frame: rounded, isFullscreen: true)]])[1] == .fullscreen)
    #expect(FullscreenResolver.resolve(displays: [builtin], visibleWindows: visible,
        windowsByPID: [200: [AXFullscreenWindow(frame: belowNotch, isFullscreen: true)]])[1] == .unknown)
}

@Test func movingAWindowOnAnotherDisplayDoesNotInvalidateFullscreen() {
    let external = FullscreenDisplay(id: 2, bounds: CGRect(x: 1710, y: 0, width: 1920, height: 1080))
    let fullscreen = VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)
    let moving = VisibleFullscreenWindow(id: 20, pid: 200,
                                         frame: CGRect(x: 1800, y: 20, width: 900, height: 700))
    let moved = VisibleFullscreenWindow(id: 20, pid: 200,
                                        frame: moving.frame.offsetBy(dx: 30, dy: 0))
    let states = FullscreenResolver.resolve(displays: [builtin, external],
        visibleWindows: [fullscreen, moving],
        windowsByPID: [100: [AXFullscreenWindow(frame: belowNotch, isFullscreen: true)],
                       200: [AXFullscreenWindow(frame: moving.frame, isFullscreen: false)]],
        currentVisibleWindows: [fullscreen, moved])
    #expect(states[1] == .fullscreen)
    #expect(states[2] == .unknown)
}

@Test func spaceSwitchDuringSamplingCannotPublishTheDepartedFullscreenWindow() {
    let states = FullscreenResolver.resolve(displays: [builtin],
        visibleWindows: [VisibleFullscreenWindow(id: 10, pid: 100, frame: belowNotch)],
        windowsByPID: [100: [AXFullscreenWindow(frame: belowNotch, isFullscreen: true)]],
        currentVisibleWindows: [])
    #expect(states[1] == .unknown)
}

@Test func changingSpaceClearsConfirmationAndRejectsAnInFlightSnapshot() {
    var observations = FullscreenObservations()
    let oldGeneration = observations.generation
    let acceptedInitial = observations.record([1: .fullscreen], at: 10, generation: oldGeneration)
    #expect(acceptedInitial)
    observations.invalidate(clearConfirmed: true)
    #expect(observations.state(on: 1, at: 10.1, gracePeriod: 2) == .unknown)
    let acceptedStale = observations.record([1: .fullscreen], at: 10.2, generation: oldGeneration)
    #expect(!acceptedStale)
    #expect(observations.state(on: 1, at: 10.2, gracePeriod: 2) == .unknown)
    let acceptedCurrent = observations.record([1: .windowed], at: 10.3, generation: observations.generation)
    #expect(acceptedCurrent)
    #expect(observations.state(on: 1, at: 10.3, gracePeriod: 2) == .windowed)
}

@Test func resamplingWithinTheSameSpaceKeepsOnlyTheOriginalGracePeriod() {
    var observations = FullscreenObservations()
    observations.record([1: .fullscreen], at: 10, generation: observations.generation)
    observations.invalidate(clearConfirmed: false)
    observations.record([1: .unknown], at: 11, generation: observations.generation)
    #expect(observations.state(on: 1, at: 11, gracePeriod: 2) == .fullscreen)
    #expect(observations.state(on: 1, at: 12.1, gracePeriod: 2) == .unknown)
}

@Test func transientFailuresHaveABoundedGracePeriodAndSuccessRecoversImmediately() {
    var observation = FullscreenObservation()
    #expect(observation.state(at: 10, gracePeriod: 2) == .unknown)
    observation.record(.fullscreen, at: 10)
    observation.record(.unknown, at: 11)
    #expect(observation.state(at: 11, gracePeriod: 2) == .fullscreen)
    observation.record(.unknown, at: 12)
    #expect(observation.state(at: 12.1, gracePeriod: 2) == .unknown)
    observation.record(.windowed, at: 12.2)
    #expect(observation.state(at: 12.2, gracePeriod: 2) == .windowed)
    observation.record(.fullscreen, at: 12.3)
    #expect(observation.state(at: 12.3, gracePeriod: 2) == .fullscreen)
}

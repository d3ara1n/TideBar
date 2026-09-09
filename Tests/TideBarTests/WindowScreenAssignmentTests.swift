import CoreGraphics
import Testing
@testable import TideBar

private let builtin = FullscreenDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 1710, height: 1112))
private let external = FullscreenDisplay(id: 2, bounds: CGRect(x: 1710, y: 0, width: 1920, height: 1080))

@Test func activeWindowFollowsLargestIntersection() {
    let onBuiltin = CGRect(x: 100, y: 100, width: 800, height: 600)
    #expect(WindowScreenAssignment.resolve(frame: onBuiltin, isMinimized: false,
                                           displays: [builtin, external], previous: 2) == 1)
    let spanningMostlyExternal = CGRect(x: 1700, y: 0, width: 1900, height: 700)
    #expect(WindowScreenAssignment.resolve(frame: spanningMostlyExternal, isMinimized: false,
                                           displays: [builtin, external], previous: 1) == 2)
}

@Test func minimizedWindowKeepsLastKnownAssignmentRegardlessOfFrame() {
    let frame = CGRect(x: 0, y: 0, width: 500, height: 400)
    #expect(WindowScreenAssignment.resolve(frame: frame, isMinimized: true,
                                           displays: [builtin, external], previous: 2) == 2)
    #expect(WindowScreenAssignment.resolve(frame: nil, isMinimized: true,
                                           displays: [builtin, external], previous: 1) == 1)
    #expect(WindowScreenAssignment.resolve(frame: frame, isMinimized: true,
                                           displays: [builtin, external], previous: nil) == nil)
}

@Test func unreadableOrOffscreenFrameKeepsPreviousAssignment() {
    #expect(WindowScreenAssignment.resolve(frame: nil, isMinimized: false,
                                           displays: [builtin, external], previous: 2) == 2)
    let offscreen = CGRect(x: -3000, y: -3000, width: 400, height: 300)
    #expect(WindowScreenAssignment.resolve(frame: offscreen, isMinimized: false,
                                           displays: [builtin, external], previous: 1) == 1)
    #expect(WindowScreenAssignment.resolve(frame: offscreen, isMinimized: false,
                                           displays: [builtin, external], previous: nil) == nil)
}

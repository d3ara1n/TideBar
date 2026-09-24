/// TideBar 键盘会话的呈现模式。
import Foundation

public enum BarSessionMode: Equatable, Sendable {
    /// ⌥Space 建立的持久会话；只由显式操作结束。
    case persistent
    /// ⌥Tab 建立的临时切换会话；空闲超时后提交当前选择。
    case switcher
}

/// 统一描述快捷键会话的生命周期与导航状态。
///
/// AppKit 层只负责把状态变化映射到面板副作用；本模型不持有窗口或 AX 对象。
public struct BarSessionState: Equatable, Sendable {
    public private(set) var mode: BarSessionMode
    public let displayID: UInt32
    public let openedBySession: Bool
    public private(set) var navigation: KeyboardNavigationState
    public private(set) var deadline: TimeInterval?

    public init(mode: BarSessionMode,
                displayID: UInt32,
                openedBySession: Bool,
                firstApplication: AppIdentity?,
                now: TimeInterval? = nil,
                timeout: TimeInterval? = nil) {
        self.mode = mode
        self.displayID = displayID
        self.openedBySession = openedBySession
        var navigation = KeyboardNavigationState()
        _ = navigation.enterApplications(displayID: displayID, firstApplication: firstApplication)
        self.navigation = navigation
        if mode == .switcher, let now, let timeout {
            self.deadline = now + timeout
        } else {
            self.deadline = nil
        }
    }

    public init(mode: BarSessionMode,
                displayID: UInt32,
                openedBySession: Bool,
                firstApplication: ApplicationItemIdentity?,
                now: TimeInterval? = nil,
                timeout: TimeInterval? = nil) {
        self.mode = mode
        self.displayID = displayID
        self.openedBySession = openedBySession
        var navigation = KeyboardNavigationState()
        _ = navigation.enterApplications(displayID: displayID, firstApplication: firstApplication)
        self.navigation = navigation
        if mode == .switcher, let now, let timeout {
            self.deadline = now + timeout
        } else {
            self.deadline = nil
        }
    }

    public var level: KeyboardNavigationLevel { navigation.level }
    public var selectedApplication: AppIdentity? { navigation.selectedApplication }
    public var selectedItem: ApplicationItemIdentity? { navigation.selectedItem }
    public var selectedWindowIdentifier: Int? { navigation.selectedWindowIdentifier }
    public var isPersistent: Bool { mode == .persistent }
    public var isSwitcher: Bool { mode == .switcher }

    public func isExpired(at now: TimeInterval) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    public mutating func touch(now: TimeInterval, timeout: TimeInterval) {
        guard mode == .switcher else { return }
        deadline = now + timeout
    }

    public mutating func selectApplication(_ identity: AppIdentity,
                                            now: TimeInterval? = nil,
                                            timeout: TimeInterval? = nil) {
        navigation.selectApplication(identity)
        if let now, let timeout { touch(now: now, timeout: timeout) }
    }

    public mutating func selectApplication(_ item: ApplicationItemIdentity,
                                            now: TimeInterval? = nil,
                                            timeout: TimeInterval? = nil) {
        navigation.selectApplication(item)
        if let now, let timeout { touch(now: now, timeout: timeout) }
    }

    @discardableResult
    public mutating func enterWindows(for identity: AppIdentity,
                                      firstWindowIdentifier: Int?,
                                      now: TimeInterval? = nil,
                                      timeout: TimeInterval? = nil) -> Bool {
        let entered = navigation.enterWindows(for: identity, firstWindowIdentifier: firstWindowIdentifier)
        if entered, let now, let timeout { touch(now: now, timeout: timeout) }
        return entered
    }

    @discardableResult
    public mutating func enterWindows(for item: ApplicationItemIdentity,
                                      firstWindowIdentifier: Int?,
                                      now: TimeInterval? = nil,
                                      timeout: TimeInterval? = nil) -> Bool {
        let entered = navigation.enterWindows(for: item, firstWindowIdentifier: firstWindowIdentifier)
        if entered, let now, let timeout { touch(now: now, timeout: timeout) }
        return entered
    }

    public mutating func selectWindow(_ identifier: Int?,
                                     now: TimeInterval? = nil,
                                     timeout: TimeInterval? = nil) {
        navigation.selectWindow(identifier)
        if let now, let timeout { touch(now: now, timeout: timeout) }
    }

    /// 返回是否仍处于键盘会话；窗口层先退回应用层，应用层再结束会话。
    @discardableResult
    public mutating func escape() -> Bool {
        navigation.escape()
    }

    public mutating func reconcile(applications: Set<AppIdentity>,
                                   windowIdentifiers: Set<Int>?) {
        navigation.clearSelectionIfMissing(applications: applications,
                                           windowIdentifiers: windowIdentifiers)
    }

    public mutating func reconcile(items: Set<ApplicationItemIdentity>,
                                   windowIdentifiers: Set<Int>?) {
        navigation.clearSelectionIfMissing(items: items, windowIdentifiers: windowIdentifiers)
    }
}

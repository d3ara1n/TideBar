/// 键盘导航当前层级。
public enum KeyboardNavigationLevel: Equatable, Sendable {
    case inactive
    case applications
    case windows(AppIdentity)
}

/// 键盘导航的纯状态模型；不持有 AppKit/AX 对象，便于在模型变化后安全修正选择。
public struct KeyboardNavigationState: Equatable, Sendable {
    public private(set) var level: KeyboardNavigationLevel = .inactive
    public private(set) var focusedDisplayID: UInt32?
    public private(set) var selectedApplication: AppIdentity?
    public private(set) var selectedWindowIdentifier: Int?

    public init() {}

    @discardableResult
    public mutating func enterApplications(displayID: UInt32, firstApplication: AppIdentity?) -> Bool {
        focusedDisplayID = displayID
        level = .applications
        selectedApplication = firstApplication
        selectedWindowIdentifier = nil
        return firstApplication != nil
    }

    public mutating func selectApplication(_ identity: AppIdentity) {
        level = .applications
        selectedApplication = identity
        selectedWindowIdentifier = nil
    }

    @discardableResult
    public mutating func enterWindows(for identity: AppIdentity, firstWindowIdentifier: Int?) -> Bool {
        guard selectedApplication == identity || selectedApplication == nil else { return false }
        level = .windows(identity)
        selectedApplication = identity
        selectedWindowIdentifier = firstWindowIdentifier
        return firstWindowIdentifier != nil
    }

    public mutating func selectWindow(_ identifier: Int?) {
        guard case .windows = level else { return }
        selectedWindowIdentifier = identifier
    }

    /// 返回是否仍处于键盘模式。潮涌层先退回应用层，应用层再完全退出。
    @discardableResult
    public mutating func escape() -> Bool {
        switch level {
        case .inactive:
            return false
        case .applications:
            reset()
            return false
        case .windows:
            level = .applications
            selectedWindowIdentifier = nil
            return true
        }
    }

    public mutating func reset() {
        level = .inactive
        focusedDisplayID = nil
        selectedApplication = nil
        selectedWindowIdentifier = nil
    }

    public mutating func clearSelectionIfMissing(
        applications: Set<AppIdentity>,
        windowIdentifiers: Set<Int>?
    ) {
        guard let selectedApplication else {
            reset()
            return
        }
        guard applications.contains(selectedApplication) else {
            reset()
            return
        }
        if case .windows = level {
            guard let windowIdentifiers else {
                selectedWindowIdentifier = nil
                return
            }
            if let selectedWindowIdentifier, !windowIdentifiers.contains(selectedWindowIdentifier) {
                self.selectedWindowIdentifier = windowIdentifiers.sorted().first
            }
        }
    }
}

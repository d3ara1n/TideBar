import AppKit

/// 系统 Dock 接管、快照、恢复和指纹校验。仅修改 com.apple.dock 的用户偏好域。
@MainActor
final class DockController {
    enum State: Equatable {
        case notEnabled
        case takeover
        case drifted
        case manualRecoveryRequired
        case failed(DockFailure)
    }

    private enum Key: String, CaseIterable {
        case autohide
        case autohideDelay = "autohide-delay"
        case autohideTimeModifier = "autohide-time-modifier"
        case noBouncing = "no-bouncing"
        case tilesize
        case magnification
        case largesize
        case mineffect
    }

    private enum StoredValue: Codable, Equatable {
        case bool(Bool)
        case integer(Int)
        case real(Double)
        case string(String)

        init?(object: Any) {
            if let value = object as? Bool {
                self = .bool(value)
            } else if let value = object as? NSNumber {
                switch String(cString: value.objCType) {
                case "c", "B": self = .bool(value.boolValue)
                case "f", "d": self = .real(value.doubleValue)
                default: self = .integer(value.intValue)
                }
            } else if let value = object as? Int {
                self = .integer(value)
            } else if let value = object as? Double {
                self = .real(value)
            } else if let value = object as? String {
                self = .string(value)
            } else {
                return nil
            }
        }

        var object: Any {
            switch self {
            case .bool(let value): return value
            case .integer(let value): return value
            case .real(let value): return value
            case .string(let value): return value
            }
        }
    }

    private struct Snapshot: Codable {
        let version: Int
        let createdAt: Date
        let values: [String: StoredValue]
    }

    static let shared = DockController()
    private static let domain = "com.apple.dock"
    private static let snapshotKey = "tidebar.dockSnapshot"
    private static let target: [Key: StoredValue] = [
        .autohide: .bool(true),
        .autohideDelay: .real(1000),
        .autohideTimeModifier: .real(0),
        .noBouncing: .bool(true),
        .tilesize: .integer(16),
        .magnification: .bool(false),
        .largesize: .integer(16),
        .mineffect: .string("scale"),
    ]

    private let defaults = RuntimeEnvironment.defaults
    private(set) var state: State = .notEnabled {
        didSet { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }
    static let didChange = Notification.Name("TideBar.dockStateDidChange")
    private init() {}

    func start() {
        guard RuntimeEnvironment.isProduction else {
            state = .notEnabled
            return
        }
        checkStatus()
    }

    /// 仅在设置界面或用户主动操作时检查，不常驻轮询。
    func checkStatus() {
        guard RuntimeEnvironment.isProduction,
              AppConfiguration.shared.isTakeoverEnabled else {
            state = .notEnabled
            return
        }
        guard snapshotData() != nil else {
            state = .manualRecoveryRequired
            return
        }
        state = fingerprintMatches() ? .takeover : .drifted
    }

    func applyTakeover() {
        guard RuntimeEnvironment.isProduction else {
            state = .notEnabled
            return
        }
        guard !AppConfiguration.shared.isTakeoverEnabled else {
            checkStatus()
            return
        }
        do {
            try saveSnapshot()
            try writeTargetValues()
            guard restartDock(), fingerprintMatches() else { throw DockError.verificationFailed }
            AppConfiguration.shared.isTakeoverEnabled = true
            state = .takeover
            NSLog("TideBar Dock takeover enabled")
        } catch {
            state = .failed(dockFailure(error, log: "TideBar Dock takeover failed"))
            try? restoreSnapshot()
            _ = restartDock()
        }
    }

    func restore() {
        guard RuntimeEnvironment.isProduction else {
            state = .notEnabled
            return
        }
        guard snapshotData() != nil else {
            state = .manualRecoveryRequired
            return
        }
        do {
            try restoreSnapshot()
            guard restartDock() else { throw DockError.restartFailed }
            AppConfiguration.shared.isTakeoverEnabled = false
            state = .notEnabled
            defaults.removeObject(forKey: Self.snapshotKey)
            NSLog("TideBar Dock settings restored")
        } catch {
            state = .failed(dockFailure(error, log: "TideBar Dock restore failed"))
        }
    }

    /// 用户在设置界面明确触发的修复操作。
    func repair() {
        guard RuntimeEnvironment.isProduction,
              AppConfiguration.shared.isTakeoverEnabled else {
            state = .notEnabled
            return
        }
        guard snapshotData() != nil else {
            state = .manualRecoveryRequired
            return
        }
        guard !fingerprintMatches() else {
            state = .takeover
            return
        }
        do {
            try writeTargetValues()
            guard restartDock(), fingerprintMatches() else { throw DockError.verificationFailed }
            state = .takeover
            NSLog("TideBar Dock takeover repaired by user")
        } catch {
            state = .failed(dockFailure(error, log: "TideBar Dock takeover repair failed"))
        }
    }

    func snapshotExists() -> Bool { snapshotData() != nil }

    /// 统一失败入态与日志；不在操作阶段固化用户界面的语言。
    private func dockFailure(_ error: Error, log context: String) -> DockFailure {
        if let dockError = error as? DockError {
            NSLog("%@: %@", context, dockError.logDescription)
            return .configuration(dockError)
        }
        NSLog("%@: %@", context, String(describing: error))
        return .system(error.localizedDescription)
    }

    private var appID: CFString { Self.domain as CFString }

    /// 通过 app-level CFPreferences 读取 Dock 偏好，读前刷新 cfprefsd 缓存。
    private func readValue(for key: Key) -> StoredValue? {
        CFPreferencesAppSynchronize(appID)
        guard let value = CFPreferencesCopyAppValue(key.rawValue as CFString, appID) else { return nil }
        return StoredValue(object: value)
    }

    private func saveSnapshot() throws {
        var values: [String: StoredValue] = [:]
        for key in Key.allCases {
            if let value = readValue(for: key) {
                values[key.rawValue] = value
            }
        }
        let snapshot = Snapshot(version: 1, createdAt: Date(), values: values)
        defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.snapshotKey)
    }

    private func restoreSnapshot() throws {
        guard let data = snapshotData(), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        for key in Key.allCases {
            setValue(snapshot.values[key.rawValue], for: key)
        }
        try synchronize()
    }

    private func writeTargetValues() throws {
        for (key, value) in Self.target {
            setValue(value, for: key)
        }
        try synchronize()
    }

    private func setValue(_ value: StoredValue?, for key: Key) {
        let propertyList = value.map { $0.object as CFPropertyList }
        CFPreferencesSetAppValue(key.rawValue as CFString, propertyList, appID)
    }

    private func synchronize() throws {
        guard CFPreferencesAppSynchronize(appID) else {
            throw DockError.synchronizeFailed
        }
    }

    private func fingerprintMatches() -> Bool {
        Self.target.allSatisfy { key, expected in
            guard let actual = readValue(for: key) else { return false }
            return valuesMatch(actual, expected)
        }
    }

    private func valuesMatch(_ actual: StoredValue, _ expected: StoredValue) -> Bool {
        switch (actual, expected) {
        case (.bool(let a), .bool(let b)): return a == b
        case (.bool(let a), .integer(let b)): return a == (b != 0)
        case (.bool(let a), .real(let b)): return a == (abs(b) > 0.0001)
        case (.integer(let a), .bool(let b)): return (a != 0) == b
        case (.real(let a), .bool(let b)): return (abs(a) > 0.0001) == b
        case (.string(let a), .string(let b)): return a == b
        case (.integer(let a), .integer(let b)): return a == b
        case (.real(let a), .real(let b)): return abs(a - b) < 0.0001
        case (.integer(let a), .real(let b)): return abs(Double(a) - b) < 0.0001
        case (.real(let a), .integer(let b)): return abs(a - Double(b)) < 0.0001
        default: return false
        }
    }

    private func snapshotData() -> Data? { defaults.data(forKey: Self.snapshotKey) }

    /// Dock 没有公开的重载偏好 API；结束当前 Dock 进程后由 launchd 自动拉起。
    private func restartDock() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.domain
        ).first else {
            return false
        }
        return dock.forceTerminate()
    }
}

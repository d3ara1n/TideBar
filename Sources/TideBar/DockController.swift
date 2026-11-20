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

    enum Key: String, CaseIterable {
        case autohide
        case autohideDelay = "autohide-delay"
        case autohideTimeModifier = "autohide-time-modifier"
        case noBouncing = "no-bouncing"
        case mineffect
    }

    enum StoredValue: Codable, Equatable {
        case bool(Bool)
        case integer(Int)
        case real(Double)
        case string(String)

        init?(object: Any) {
            if let value = object as? NSNumber {
                if CFGetTypeID(value) == CFBooleanGetTypeID() {
                    self = .bool(value.boolValue)
                } else {
                    switch String(cString: value.objCType) {
                    case "f", "d": self = .real(value.doubleValue)
                    default: self = .integer(value.intValue)
                    }
                }
            } else if let value = object as? String {
                self = .string(value)
            } else {
                return nil
            }
        }

        func matches(_ other: StoredValue) -> Bool {
            switch (self, other) {
            case (.integer(let integer), .real(let real)), (.real(let real), .integer(let integer)):
                return Double(integer) == real
            default:
                return self == other
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

    struct Snapshot: Codable {
        static let currentVersion = 2
        let version: Int
        let createdAt: Date
        let values: [String: StoredValue]
        var needsDockReload: Bool? // 缺省兼容没有此字段的快照

        /// 只回收仍等于旧接管值的偏好；用户自行改过的值保持不动。
        func legacyAppearanceRestoration(read: (String) -> StoredValue?) -> [(key: String, value: StoredValue?)] {
            guard version == 1 else { return [] }
            let legacyValues: [String: StoredValue] = [
                "tilesize": .integer(16), "magnification": .bool(false), "largesize": .integer(16),
            ]
            return legacyValues.compactMap { key, takeoverValue in
                guard let current = read(key), current.matches(takeoverValue) else { return nil }
                let original = values[key]
                if let original, current.matches(original) { return nil }
                return (key, original)
            }
        }

        func checkpointLegacyAppearance(restore: () throws -> Void,
                                        save: (Snapshot) throws -> Void) throws -> Snapshot {
            guard version == 1 else { return self }
            let checkpoint = Snapshot(version: Self.currentVersion, createdAt: createdAt,
                                      values: values.filter { Key(rawValue: $0.key) != nil },
                                      needsDockReload: true)
            try restore()
            // 偏好同步后即交还外观管理权；后续只重试重载，不再写外观。
            try save(checkpoint)
            return checkpoint
        }

        func reloadDockIfNeeded(reload: () throws -> Void, save: (Snapshot) throws -> Void) throws {
            guard needsDockReload == true else { return }
            try reload()
            var completed = self
            completed.needsDockReload = nil
            try save(completed)
        }
    }

    static let shared = DockController()
    private static let domain = "com.apple.dock"
    private static let snapshotKey = "tidebar.dockSnapshot"
    static let target: [Key: StoredValue] = [
        .autohide: .bool(true),
        .autohideDelay: .real(1000),
        .autohideTimeModifier: .real(0),
        .noBouncing: .bool(true),
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

    /// 启动、打开设置或用户主动检查时调用；除一次性快照迁移外只读，不轮询。
    func checkStatus() {
        guard RuntimeEnvironment.isProduction,
              AppConfiguration.shared.isTakeoverEnabled else {
            state = .notEnabled
            return
        }
        guard let snapshot = loadSnapshot() else {
            state = .manualRecoveryRequired
            return
        }
        do {
            try migrateSnapshotIfNeeded(snapshot)
            state = fingerprintMatches() ? .takeover : .drifted
        } catch {
            state = .failed(dockFailure(error, log: "TideBar Dock snapshot migration failed"))
        }
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
            if let snapshot = loadSnapshot() { try? restoreSnapshot(snapshot) }
            _ = restartDock()
        }
    }

    func restore() {
        guard RuntimeEnvironment.isProduction else {
            state = .notEnabled
            return
        }
        guard let snapshot = loadSnapshot() else {
            state = .manualRecoveryRequired
            return
        }
        do {
            let checkpoint = try checkpointLegacyAppearance(snapshot)
            try restoreSnapshot(checkpoint)
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
        checkStatus()
        guard state == .drifted else { return }
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
    private func readValue(for key: String) -> StoredValue? {
        CFPreferencesAppSynchronize(appID)
        guard let value = CFPreferencesCopyAppValue(key as CFString, appID) else { return nil }
        return StoredValue(object: value)
    }

    private func saveSnapshot() throws {
        var values: [String: StoredValue] = [:]
        for key in Key.allCases {
            if let value = readValue(for: key.rawValue) {
                values[key.rawValue] = value
            }
        }
        let snapshot = Snapshot(version: Snapshot.currentVersion, createdAt: Date(), values: values)
        try saveSnapshot(snapshot)
    }

    private func saveSnapshot(_ snapshot: Snapshot) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.snapshotKey)
    }

    private func migrateSnapshotIfNeeded(_ snapshot: Snapshot) throws {
        let checkpoint = try checkpointLegacyAppearance(snapshot)
        try checkpoint.reloadDockIfNeeded(reload: {
            guard restartDock() else { throw DockError.restartFailed }
            NSLog("TideBar reloaded Dock after releasing legacy appearance settings")
        }, save: saveSnapshot)
    }

    private func checkpointLegacyAppearance(_ snapshot: Snapshot) throws -> Snapshot {
        try snapshot.checkpointLegacyAppearance(restore: {
            for (key, value) in snapshot.legacyAppearanceRestoration(read: readValue) {
                setValue(value, for: key)
            }
            try synchronize()
        }, save: saveSnapshot)
    }

    private func restoreSnapshot(_ snapshot: Snapshot) throws {
        for key in Key.allCases {
            setValue(snapshot.values[key.rawValue], for: key.rawValue)
        }
        try synchronize()
    }

    private func writeTargetValues() throws {
        for (key, value) in Self.target {
            setValue(value, for: key.rawValue)
        }
        try synchronize()
    }

    private func setValue(_ value: StoredValue?, for key: String) {
        let propertyList = value.map { $0.object as CFPropertyList }
        CFPreferencesSetAppValue(key as CFString, propertyList, appID)
    }

    private func synchronize() throws {
        guard CFPreferencesAppSynchronize(appID) else {
            throw DockError.synchronizeFailed
        }
    }

    private func fingerprintMatches() -> Bool {
        Self.target.allSatisfy { key, expected in
            readValue(for: key.rawValue)?.matches(expected) == true
        }
    }

    private func snapshotData() -> Data? { defaults.data(forKey: Self.snapshotKey) }

    private func loadSnapshot() -> Snapshot? {
        guard let data = snapshotData(),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              (1...Snapshot.currentVersion).contains(snapshot.version) else { return nil }
        return snapshot
    }

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

import AppKit

/// TideBar 的持久化配置。系统 Dock 的原始值由 DockController 单独快照。
@MainActor
final class AppConfiguration {
    enum Mode: String {
        case floating
        case takeover
    }

    static let shared = AppConfiguration()
    static let didChange = Notification.Name("TideBar.configurationDidChange")

    private let defaults = UserDefaults.standard
    private let modeKey = "tidebar.mode"
    private let pinnedKey = "tidebar.pinned"
    private let onboardingKey = "tidebar.onboardingCompleted"

    private init() {}

    var mode: Mode {
        get { Mode(rawValue: defaults.string(forKey: modeKey) ?? "floating") ?? .floating }
        set {
            guard mode != newValue else { return }
            defaults.set(newValue.rawValue, forKey: modeKey)
            notifyChange()
        }
    }

    var pinnedBundleIDs: [String] {
        get { defaults.stringArray(forKey: pinnedKey) ?? [] }
        set {
            defaults.set(newValue, forKey: pinnedKey)
            notifyChange()
        }
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        set { defaults.set(newValue, forKey: onboardingKey) }
    }

    var isTakeoverEnabled: Bool { mode == .takeover }

    func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

extension Layout {
    static var offsetY: CGFloat {
        if UserDefaults.standard.string(forKey: "tidebar.mode") == AppConfiguration.Mode.takeover.rawValue {
            return 0
        }
        let raw = UserDefaults.standard.double(forKey: "tidebar.offsetY")
        return raw > 0 ? raw : 140
    }
}

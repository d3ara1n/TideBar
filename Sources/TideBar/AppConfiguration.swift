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
    private let offsetYKey = "tidebar.offsetY"
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

    /// 固定项 bundle id 列表；未设置时为 nil（AppRegistry 以默认固定项兜底）
    var pinnedBundleIDs: [String]? {
        get { defaults.stringArray(forKey: pinnedKey) }
        set {
            defaults.set(newValue, forKey: pinnedKey)
            notifyChange()
        }
    }

    /// 贴底偏移：接管态贴底；悬浮测试态为可调值（缺省 140pt）
    var verticalOffset: CGFloat {
        if mode == .takeover { return 0 }
        let raw = defaults.double(forKey: offsetYKey)
        return raw > 0 ? raw : 140
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

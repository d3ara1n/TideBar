import AppKit
import TideBarCore

/// TideBar 的持久化配置。系统 Dock 的原始值由 DockController 单独快照。
@MainActor
final class AppConfiguration {
    enum Mode: String {
        case floating
        case takeover
    }

    static let shared = AppConfiguration()
    static let didChange = Notification.Name("TideBar.configurationDidChange")
    static let pinnedDidChange = Notification.Name("TideBar.pinnedAppsDidChange")
    static let defaultPinnedBundleIDs = ["com.apple.Finder", "com.apple.Safari", "com.apple.mail",
                                         "com.apple.Notes", "com.apple.Music", "com.apple.Terminal"]

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

    /// 固定项 bundle id 列表；未设置时使用内建默认值。
    var pinnedBundleIDs: [String]? {
        get { defaults.stringArray(forKey: pinnedKey) }
        set {
            defaults.set(newValue, forKey: pinnedKey)
            NotificationCenter.default.post(name: Self.pinnedDidChange, object: self)
        }
    }

    var effectivePinnedBundleIDs: [String] {
        pinnedBundleIDs ?? Self.defaultPinnedBundleIDs
    }

    /// 固定操作保留系统提供的原始 bundle identifier；身份比较仍忽略 ASCII 大小写。
    func setPinned(_ pinned: Bool, bundleIdentifier: String) {
        let identity = AppIdentity(bundleIdentifier)
        var bundleIdentifiers = effectivePinnedBundleIDs
        let contains = bundleIdentifiers.contains { AppIdentity($0) == identity }

        if pinned {
            guard !contains else { return }
            bundleIdentifiers.append(bundleIdentifier)
        } else {
            guard contains else { return }
            bundleIdentifiers.removeAll { AppIdentity($0) == identity }
        }
        pinnedBundleIDs = bundleIdentifiers
    }

    /// 贴底偏移：接管态贴底；悬浮测试态为可调值（缺省 140pt）
    var verticalOffset: CGFloat {
        if mode == .takeover { return 0 }
        guard defaults.object(forKey: offsetYKey) != nil else { return 140 }
        return defaults.double(forKey: offsetYKey)
    }

    /// 设置悬浮模式贴底偏移（0–300pt）
    func setFloatingOffset(_ value: CGFloat) {
        let clamped = min(max(value, 0), 300)
        guard clamped != verticalOffset else { return }
        defaults.set(clamped, forKey: offsetYKey)
        notifyChange()
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

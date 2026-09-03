import AppKit
import TideBarCore

enum ApplicationTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// TideBar 的持久化配置。系统 Dock 的原始值由 DockController 单独快照。
@MainActor
final class AppConfiguration {
    static let shared = AppConfiguration()
    static let didChange = Notification.Name("TideBar.configurationDidChange")
    static let pinnedDidChange = Notification.Name("TideBar.pinnedAppsDidChange")
    static let appearanceDidChange = Notification.Name("TideBar.appearanceDidChange")

    /// 默认固定常用应用；Finder 不在此列，由窗口模型在存在可用窗口时自然出现。
    static let defaultPinnedBundleIDs = [
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.Notes",
        "com.apple.Music",
        "com.apple.Terminal",
    ]

    private let defaults = UserDefaults.standard
    private let enabledKey = "tidebar.enabled"
    private let pinnedKey = "tidebar.pinned"
    private let onboardingKey = "tidebar.onboardingCompleted"
    private let appearanceKey = "tidebar.appearance"
    private init() {}

    /// TideBar 是否负责系统 Dock 的可见入口。正式产品只有启用与停用两种运行状态。
    var isTakeoverEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set {
            guard isTakeoverEnabled != newValue else { return }
            defaults.set(newValue, forKey: enabledKey)
            notifyChange()
        }
    }

    /// 整个应用使用的外观；未设置或值无效时跟随系统。
    var appearance: ApplicationTheme {
        get {
            guard let rawValue = defaults.string(forKey: appearanceKey),
                  let value = ApplicationTheme(rawValue: rawValue) else { return .system }
            return value
        }
        set {
            guard appearance != newValue else { return }
            defaults.set(newValue.rawValue, forKey: appearanceKey)
            NotificationCenter.default.post(name: Self.appearanceDidChange, object: self)
        }
    }

    /// 固定项 bundle id 列表；未设置时使用内建默认值。
    private(set) var pinnedBundleIDs: [String]? {
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

    func movePinned(from offsets: IndexSet, to destination: Int) {
        var values = effectivePinnedBundleIDs
        let moving = offsets.sorted().map { values[$0] }
        for index in offsets.sorted(by: >) {
            values.remove(at: index)
        }
        let adjustedDestination = destination - offsets.filter { $0 < destination }.count
        values.insert(contentsOf: moving, at: min(max(adjustedDestination, 0), values.count))
        pinnedBundleIDs = values
    }

    func restoreDefaultPinned() {
        pinnedBundleIDs = nil
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        set { defaults.set(newValue, forKey: onboardingKey) }
    }

    func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

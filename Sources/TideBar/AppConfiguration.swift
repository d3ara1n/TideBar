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
    static let layoutDidChange = Notification.Name("TideBar.layoutDidChange")
    static let behaviorDidChange = Notification.Name("TideBar.behaviorDidChange")

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
    private let iconSizeKey = "tidebar.iconSize"
    private let tidelineBrightnessKey = "tidebar.tidelineBrightness"
    private let animationKey = "tidebar.animation"
    private let reducedMotionKey = "tidebar.reducedMotion"
    private let fullscreenBehaviorKey = "tidebar.fullscreenBehavior"
    private let switcherDelayKey = "tidebar.shortcut.switcherDelay"
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

    var iconSize: IconSizePreset {
        get { stored(iconSizeKey, default: .standard) }
        set {
            guard iconSize != newValue else { return }
            defaults.set(newValue.rawValue, forKey: iconSizeKey)
            NotificationCenter.default.post(name: Self.layoutDidChange, object: self)
        }
    }

    var tidelineBrightness: TideLineBrightness {
        get { stored(tidelineBrightnessKey, default: .automatic) }
        set {
            guard tidelineBrightness != newValue else { return }
            defaults.set(newValue.rawValue, forKey: tidelineBrightnessKey)
            NotificationCenter.default.post(name: Self.appearanceDidChange, object: self)
        }
    }

    var animation: AnimationPreset {
        get { stored(animationKey, default: .standard) }
        set {
            guard animation != newValue else { return }
            defaults.set(newValue.rawValue, forKey: animationKey)
            NotificationCenter.default.post(name: Self.behaviorDidChange, object: self)
        }
    }

    var reducedMotion: ReducedMotionPreference {
        get { stored(reducedMotionKey, default: .automatic) }
        set {
            guard reducedMotion != newValue else { return }
            defaults.set(newValue.rawValue, forKey: reducedMotionKey)
            NotificationCenter.default.post(name: Self.behaviorDidChange, object: self)
        }
    }

    var fullscreenBehavior: FullscreenBehavior {
        get { stored(fullscreenBehaviorKey, default: .lineOnly) }
        set {
            guard fullscreenBehavior != newValue else { return }
            defaults.set(newValue.rawValue, forKey: fullscreenBehaviorKey)
            NotificationCenter.default.post(name: Self.behaviorDidChange, object: self)
        }
    }

    var switcherCommitDelay: Double {
        get {
            let value = defaults.double(forKey: switcherDelayKey)
            return value > 0 ? min(max(value, 0.2), 5.0) : 0.9
        }
        set {
            let value = min(max(newValue, 0.2), 5.0)
            guard abs(switcherCommitDelay - value) > 0.001 else { return }
            defaults.set(value, forKey: switcherDelayKey)
            NotificationCenter.default.post(name: Self.behaviorDidChange, object: self)
        }
    }

    func restoreDefaultSwitcherDelay() {
        defaults.removeObject(forKey: switcherDelayKey)
        NotificationCenter.default.post(name: Self.behaviorDidChange, object: self)
    }

    private func stored<Value: RawRepresentable>(_ key: String, default fallback: Value) -> Value where Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key), let value = Value(rawValue: rawValue) else {
            return fallback
        }
        return value
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

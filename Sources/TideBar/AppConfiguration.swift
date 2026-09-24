import AppKit
import TideBarCore

enum ApplicationTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

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
    static let pinnedDidChange = PinnedItemStore.didChange
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

    private let defaults = RuntimeEnvironment.defaults
    private let enabledKey = "tidebar.enabled"
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
        get { stored(fullscreenBehaviorKey, default: .clickToExpand) }
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

    /// 应用观测消费带资源位置的固定应用投影；旧记录没有 bookmark 时才退化为 bundle-only。
    var effectivePinnedApplications: [PinnedApplicationDescription] {
        PinnedItemStore.shared.applicationDescriptions
    }

    func setPinned(_ pinned: Bool, bundleIdentifier: String) {
        do { try PinnedItemStore.shared.setPinned(pinned, bundleIdentifier: bundleIdentifier) }
        catch { ItemErrors.report(error) }
    }

    func movePinned(from offsets: IndexSet, to destination: Int) {
        do { try PinnedItemStore.shared.move(from: offsets, to: destination) }
        catch { ItemErrors.report(error) }
    }

    func restoreDefaultPinned() {
        do { try PinnedItemStore.shared.restoreDefaults() }
        catch { ItemErrors.report(error) }
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        set { defaults.set(newValue, forKey: onboardingKey) }
    }

    func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

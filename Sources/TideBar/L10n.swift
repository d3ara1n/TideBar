import SwiftUI

/// 用户可选的应用语言。词条按 `.lproj` 子 bundle 提供，应用内切换不依赖系统 preferred localization。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// 语言名按自身语言显示（English、简体中文不随界面语言翻译），仅「跟随系统」项走词条。
    @MainActor var displayName: String {
        switch self {
        case .system: L10n.string("language.system", table: .labels)
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

/// 词条表。每个功能域一对 `Resources/<lproj>/<Table>.strings`，key 命名以域内前缀分层。
enum L10nTable: String {
    case onboarding = "Onboarding"
    case settings = "Settings"
    case menus = "Menus"
    case runtime = "Runtime"
    case labels = "Labels"
}

/// 应用内语言切换核心：按用户偏好解析实际 localization（「跟随系统」时 zh 前缀归 zh-Hans，其余归 en），
/// 从 Bundle.module 加载对应 `.lproj` 子 bundle，全部文案查找显式指定该 bundle。
///
/// 语言变化同时发布 `objectWillChange` 与 `languageDidChange` 通知：
/// SwiftUI 根视图持有本对象，整树随语言重算；AppKit 处订阅通知重建文案。
@MainActor
final class L10nManager: ObservableObject {
    static let shared = L10nManager()
    static let languageDidChange = Notification.Name("TideBar.languageDidChange")

    private let defaults: UserDefaults
    private let languageKey = "tidebar.language"

    @Published private(set) var language: AppLanguage

    /// 实际生效的 localization code（"en" / "zh-Hans"）。
    private(set) var localization: String

    /// 当前语言的词条 bundle。查找与刷新都以它为准，不使用系统自动命中。
    private(set) var bundle: Bundle

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.language = stored
        let code = Self.resolve(stored)
        self.localization = code
        self.bundle = Self.loadBundle(code)
    }

    /// 切换语言并持久化；语言未变化时静默返回。
    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        defaults.set(newLanguage.rawValue, forKey: languageKey)

        let code = Self.resolve(newLanguage)
        guard code != localization else { return }
        localization = code
        bundle = Self.loadBundle(code)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.languageDidChange, object: self)
    }

    private static func resolve(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    private static func loadBundle(_ code: String) -> Bundle {
        // SPM 会把 lproj 目录名规范化为小写（zh-Hans → zh-hans），而 path(forResource:)
        // 按精确名匹配，故精确名查不到时按小写回查。
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj")
                ?? Bundle.module.path(forResource: code.lowercased(), ofType: "lproj"),
              let lproj = Bundle(path: path) else {
            NSLog("L10n: missing localization %@ in module bundle", code)
            return Bundle.module
        }
        return lproj
    }
}

/// 词条查找门面。文案在视图/菜单构建时求值；语言切换后的更新由视图随
/// `L10nManager` 重算、AppKit 处随 `languageDidChange` 重建完成。
@MainActor
enum L10n {
    static var bundle: Bundle { L10nManager.shared.bundle }

    /// 查词条；缺条目时原样返回 key，让缺失在界面上可见。
    static func string(_ key: String, table: L10nTable) -> String {
        bundle.localizedString(forKey: key, value: key, table: table.rawValue)
    }

    /// 带格式化参数的词条查找，词条内用 `%1$@` 等位置占位。
    static func string(_ key: String, table: L10nTable, arguments: CVarArg...) -> String {
        let value = bundle.localizedString(forKey: key, value: key, table: table.rawValue)
        return String(format: value, arguments: arguments)
    }
}

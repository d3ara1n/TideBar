import Observation
import SwiftUI

/// 语言偏好与实际词条语言分别保留：跟随系统和显式选择同一语言仍是不同的选中项。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    func displayName(in localization: Localization) -> String {
        switch self {
        case .system: localization.string("language.system", table: .labels)
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

enum L10nTable: String, CaseIterable, Sendable {
    case onboarding = "Onboarding"
    case settings = "Settings"
    case menus = "Menus"
    case runtime = "Runtime"
    case labels = "Labels"
}

/// 一次语言选择的不可变快照。视图读取环境中的快照，AppKit 在展示时读取管理器的当前快照。
/// 词条查找不读取全局状态，保存快照即可保证同一批文案使用同一种语言。
struct Localization: Equatable, Sendable {
    let language: AppLanguage
    let code: String
    let bundle: Bundle

    var locale: Locale { Locale(identifier: code) }

    init(language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = language
        switch language {
        case .english: code = "en"
        case .simplifiedChinese: code = "zh-Hans"
        case .system:
            code = (preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh-Hans" : "en"
        }
        bundle = Self.loadBundle(code)
    }

    func string(_ key: String, table: L10nTable) -> String {
        bundle.localizedString(forKey: key, value: key, table: table.rawValue)
    }

    func string(_ key: String, table: L10nTable, arguments: CVarArg...) -> String {
        String(format: string(key, table: table), locale: locale, arguments: arguments)
    }

    private static func loadBundle(_ code: String) -> Bundle {
        // SPM 将 lproj 目录名规范化为小写；同时支持保留标准语言代码大小写的资源包。
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj")
                ?? Bundle.module.path(forResource: code.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            NSLog("TideBar L10n missing localization %@ in module bundle", code)
            return Bundle.module
        }
        return bundle
    }
}

/// 单一语言真值。选择、实际语言和 bundle 一次替换，通知发布时状态已完整可读。
@MainActor
@Observable
final class L10nManager {
    static let shared = L10nManager(defaults: RuntimeEnvironment.defaults)
    static let languageDidChange = Notification.Name("TideBar.languageDidChange")
    private static let languageKey = "tidebar.language"

    private(set) var current: Localization
    private let preferredLanguages: () -> [String]
    private let persistLanguage: (AppLanguage) -> Void

    init(language: AppLanguage,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
         persistLanguage: @escaping (AppLanguage) -> Void = { _ in }) {
        self.preferredLanguages = preferredLanguages
        self.persistLanguage = persistLanguage
        current = Localization(language: language, preferredLanguages: preferredLanguages())
    }

    private convenience init(defaults: UserDefaults) {
        let language = defaults.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.init(language: language, persistLanguage: {
            defaults.set($0.rawValue, forKey: Self.languageKey)
        })
    }

    /// 控件绑定直接读写真值；计算属性的读取仍通过 current 参与 Observation。
    var language: AppLanguage {
        get { current.language }
        set {
            guard newValue != current.language else { return }
            let next = Localization(language: newValue, preferredLanguages: preferredLanguages())
            persistLanguage(newValue)
            current = next
            NotificationCenter.default.post(name: Self.languageDidChange, object: self)
        }
    }
}

extension EnvironmentValues {
    @Entry var l10n = Localization(language: .system)
}

/// 每个 hosting root 使用同一入口注入语言环境；更新环境不改变子视图 identity 与本地 State。
struct LocalizedContent<Content: View>: View {
    @State private var manager: L10nManager
    private let content: Content

    init(manager: L10nManager = .shared, @ViewBuilder content: () -> Content) {
        _manager = State(initialValue: manager)
        self.content = content()
    }

    var body: some View {
        content
            .environment(manager)
            .environment(\.l10n, manager.current)
            .environment(\.locale, manager.current.locale)
    }
}

/// ForEach 的元素只携带稳定词条 key；实际标签独立读取环境，不依赖父视图重算枚举闭包。
struct LocalizedText: View {
    @Environment(\.l10n) private var l10n
    let key: String
    let table: L10nTable

    init(_ key: String, table: L10nTable) {
        self.key = key
        self.table = table
    }

    var body: some View {
        Text(l10n.string(key, table: table))
    }
}

/// 两个窗口共用语言选择与写入路径；语言名按自身语言显示。
struct LanguagePicker: View {
    @Environment(L10nManager.self) private var manager
    var title: String? = nil

    var body: some View {
        @Bindable var manager = manager
        Picker(selection: $manager.language) {
            ForEach(AppLanguage.allCases) { language in
                LanguageName(language: language).tag(language)
            }
        } label: {
            if let title { Text(title) }
        }
        .pickerStyle(.menu)
    }
}

private struct LanguageName: View {
    @Environment(\.l10n) private var l10n
    let language: AppLanguage

    var body: some View {
        Text(language.displayName(in: l10n))
    }
}

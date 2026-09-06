import Foundation
import Observation
import SwiftUI
import Testing
import TideBarCore
@testable import TideBar

// 这些测试覆盖语言真值、Observation 发布和真实词条资源；原生 Picker 的显示刷新仍需 GUI 验收。
@Test func systemLanguageResolutionKeepsPreferenceDistinctFromTranslation() {
    let system = Localization(language: .system, preferredLanguages: ["zh-Hans-CN", "en"])
    let explicit = Localization(language: .simplifiedChinese, preferredLanguages: ["en"])
    #expect(system.code == "zh-Hans")
    #expect(system.language == .system)
    #expect(system != explicit)
    #expect(Localization(language: .system, preferredLanguages: []).code == "en")
    #expect(Localization(language: .system, preferredLanguages: ["fr", "zh-Hans"]).code == "en")
    #expect(Localization(language: .english, preferredLanguages: ["zh-Hans"]).code == "en")
}

@Test func resourceBundlesContainMatchingKeysAndResolveEveryEntry() throws {
    let english = Localization(language: .english)
    let chinese = Localization(language: .simplifiedChinese)
    #expect(english.bundle.bundleURL.lastPathComponent == "en.lproj")
    #expect(chinese.bundle.bundleURL.lastPathComponent.lowercased() == "zh-hans.lproj")

    for table in L10nTable.allCases {
        let en = try entries(in: english, table: table)
        let zh = try entries(in: chinese, table: table)
        #expect(!en.isEmpty)
        #expect(Set(en.keys) == Set(zh.keys))
        for (localization, entries) in [(english, en), (chinese, zh)] {
            for (key, value) in entries {
                #expect(!value.isEmpty)
                #expect(localization.string(key, table: table) == value)
            }
        }
    }
    #expect(english.string("missing.test.key", table: .labels) == "missing.test.key")
}

@Test @MainActor func switchingPublishesSelectionEvenWhenResolvedLanguageIsUnchanged() {
    var persisted: [AppLanguage] = []
    let manager = L10nManager(language: .system, preferredLanguages: { ["en"] },
                              persistLanguage: { persisted.append($0) })
    let probe = ChangeProbe()
    let bridge = MainThreadBridge { probe.count += 1 }
    withObservationTracking {
        _ = manager.current
    } onChange: {
        bridge()
    }

    let before = manager.current
    @Bindable var bindable = manager
    $bindable.language.wrappedValue = .english
    #expect($bindable.language.wrappedValue == .english)
    #expect(probe.count == 1)
    #expect(manager.current.language == .english)
    #expect(manager.current.code == before.code)
    #expect(manager.current != before)
    #expect(persisted == [.english])

    manager.language = .english
    #expect(persisted == [.english])
    manager.language = .system
    #expect(manager.current.language == .system)
    #expect(persisted == [.english, .system])
}

@Test @MainActor func appKitNotificationSeesCompleteLanguageSnapshot() {
    let manager = L10nManager(language: .english)
    let probe = SnapshotProbe()
    let bridge = MainThreadBridge { probe.snapshots.append(manager.current) }
    let token = NotificationCenter.default.addObserver(
        forName: L10nManager.languageDidChange, object: manager, queue: .main
    ) { _ in bridge() }
    defer { NotificationCenter.default.removeObserver(token) }

    let original = manager.current
    manager.language = .simplifiedChinese
    #expect(probe.snapshots.count == 1)
    #expect(probe.snapshots.first?.language == .simplifiedChinese)
    #expect(probe.snapshots.first?.string("theme.light", table: .labels) == "亮色")
    // 已保存快照不能随单例或 manager 的后续变化而改变。
    #expect(original.string("theme.light", table: .labels) == "Light")
    manager.language = .simplifiedChinese
    #expect(probe.snapshots.count == 1)
}

@Test @MainActor func everyPreferenceLabelCanFollowRepeatedLanguageChanges() {
    let manager = L10nManager(language: .english)
    let keys = ApplicationTheme.allCases.map(\.titleKey)
        + IconSizePreset.allCases.map(\.titleKey)
        + TideLineBrightness.allCases.map(\.titleKey)
        + AnimationPreset.allCases.map(\.titleKey)
        + ReducedMotionPreference.allCases.map(\.titleKey)
        + FullscreenBehavior.allCases.map(\.titleKey)
    let english = keys.map { manager.current.string($0, table: .labels) }
    manager.language = .simplifiedChinese
    let chinese = keys.map { manager.current.string($0, table: .labels) }
    for (index, key) in keys.enumerated() {
        #expect(english[index] != key)
        #expect(chinese[index] != key)
        #expect(english[index] != chinese[index])
    }
    manager.language = .english
    #expect(keys.map { manager.current.string($0, table: .labels) } == english)
    #expect(AppLanguage.system.displayName(in: manager.current) == "Follow System")
    #expect(AppLanguage.english.displayName(in: manager.current) == "English")
    #expect(AppLanguage.simplifiedChinese.displayName(in: manager.current) == "简体中文")
}

@Test func dockFailureIsLocalizedAtPresentationWithoutTranslatingSystemErrors() {
    let english = Localization(language: .english)
    let chinese = Localization(language: .simplifiedChinese)
    let failure = DockFailure.configuration(.verificationFailed)
    #expect(failure.message(in: english) == "Couldn't verify Dock configuration")
    #expect(failure.message(in: chinese) == "Dock 配置验证失败")
    let parameterized = DockFailure.configuration(.unsupportedValue("autohide"))
    #expect(parameterized.message(in: english) == "Couldn't save Dock preference: autohide")
    #expect(parameterized.message(in: chinese) == "Dock 配置项无法保存：autohide")
    let system = DockFailure.system("System-provided error")
    #expect(system.message(in: english) == system.message(in: chinese))
}

private func entries(in localization: Localization, table: L10nTable) throws -> [String: String] {
    let url = try #require(localization.bundle.url(forResource: table.rawValue, withExtension: "strings"))
    let data = try Data(contentsOf: url)
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

@MainActor private final class ChangeProbe {
    var count = 0
}

@MainActor private final class SnapshotProbe {
    var snapshots: [Localization] = []
}

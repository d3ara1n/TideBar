import AppKit
@testable import TideBar
@testable import TideBarCore
import Testing

/// 复现用户流程：栏内把 widget 拖到最前（reorder 提交）→ 设置页添加新 widget（追加写入），
/// 验证排序不回退。使用独立 defaults 域，不碰真实用户数据。
@MainActor
final class WidgetOrderingTests {
    private func makeStore(records: [PinnedItemRecord]) throws -> PinnedItemStore {
        let suiteName = "widget-ordering-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let data = try JSONEncoder().encode(PinnedItemDocument(records: records))
        defaults.set(data, forKey: "tidebar.pinnedItems.v1")
        return PinnedItemStore(defaults: defaults)
    }

    @Test func dragToFrontThenAddWidgetKeepsOrder() throws {
        let finder = try ItemReferences.application("com.apple.finder")
        let zen = try ItemReferences.application("app.zen-browser.zen")
        let widgetRef = try WidgetReferences.applicationLauncher(displayName: "音乐")
        let records = [
            PinnedItemRecord(id: .application(AppIdentity("com.apple.finder")), kind: .application,
                             reference: finder, fallbackName: "Finder"),
            PinnedItemRecord(id: .application(AppIdentity("app.zen-browser.zen")), kind: .application,
                             reference: zen, fallbackName: "Zen"),
            PinnedItemRecord(id: .resource(), kind: .widget, reference: widgetRef, fallbackName: "音乐")
        ]
        let store = try makeStore(records: records)
        let widgetID = records[2].id
        let registry = ItemRegistry(store: store)
        registry.start()

        // 栏内拖 widget 到最前（等价 registry.reorder 的提交路径）
        try registry.reorder(widgetID, before: records[0].id)
        #expect(store.records.map(\.id) == [widgetID, records[0].id, records[1].id])

        // 设置页添加新 widget：追加到尾部
        let newWidget = PinnedItemRecord(id: .resource(), kind: .widget,
                                         reference: try WidgetReferences.applicationLauncher(displayName: "新"),
                                         fallbackName: "新")
        try store.replace(store.records + [newWidget])

        // 展开态所见顺序（只看固定项；临时运行应用在本测试进程会真实追加到尾部）
        let expected: [ItemID] = [widgetID, records[0].id, records[1].id, newWidget.id]
        let pinnedOrder = registry.entries.map(\.id).filter { expected.contains($0) }
        #expect(pinnedOrder == expected)
    }
}

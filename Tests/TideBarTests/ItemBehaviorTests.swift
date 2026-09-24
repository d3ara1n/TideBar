import AppKit
import Testing
import TideBarCore
@testable import TideBar

/// 无 URL、路径或进程的行为，直接处理引用；用于约束未来 widget 的接入自由。
@MainActor
private struct ReferenceOnlyBehavior: ItemBehaviorProviding {
    let sink: ReferenceSink
    let capabilities: ItemCapabilities = [.receive]
    func presentation(for record: PinnedItemRecord) -> ItemPresentation {
        ItemPresentation(name: record.fallbackName, icon: NSImage(), isAvailable: true)
    }
    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal? {
        ItemReceiveProposal(operation: .generic) {
            sink.received = references
            sink.target = target
        }
    }
}

@MainActor private final class ReferenceSink {
    var received: [ItemReference] = []
    var target: ItemReference?
}

@Test @MainActor func receiverCanConsumeReferencesWithoutResolvingAnything() throws {
    let source = ItemReference(scheme: "widget-event", payload: Data([1]))
    let target = ItemReference(scheme: "widget-state", payload: Data([2]))
    let sink = ReferenceSink()
    let behavior = ReferenceOnlyBehavior(sink: sink)
    let proposal = try #require(behavior.receive([source], at: target))
    #expect(sink.received.isEmpty)
    try proposal.execute()
    #expect(sink.received == [source])
    #expect(sink.target == target)
    #expect(!behavior.capabilities.contains(.open))
}

/// 潮涌体能力矩阵：应用与目录提供，文件条目的伪预览体是下一阶段目标。
@Test @MainActor func surgeBodyCapabilityFollowsKind() throws {
    #expect(ItemBehaviors.provider(for: .application)?.capabilities.contains(.surgeBody) == true)
    #expect(ItemBehaviors.provider(for: .directory)?.capabilities.contains(.surgeBody) == true)
    #expect(ItemBehaviors.provider(for: .file)?.capabilities.contains(.surgeBody) == false)
    let reference = try WidgetReferences.applicationLauncher(displayName: "Test")
    let record = PinnedItemRecord(id: .resource(), kind: .widget,
                                  reference: reference, fallbackName: "Test")
    #expect(ItemBehaviors.provider(for: record)?.capabilities.contains(.surgeBody) == true)
}

/// barArtwork 必须经 any 存在类型动态派发到 widget 实现：
/// 若只是 extension 默认实现（非 requirement），栏内会静默退回通用占位图标。
@Test @MainActor func widgetBarArtworkDispatchesThroughExistential() throws {
    let apps = try [ItemReferences.application("com.apple.finder")]
    let reference = try WidgetReferences.applicationLauncher(displayName: "Test", applications: apps)
    let record = PinnedItemRecord(id: .resource(), kind: .widget,
                                  reference: reference, fallbackName: "Test")
    let entry = ItemEntry(id: record.id, kind: record.kind, reference: record.reference,
                          name: "Test", icon: NSImage(), preferredBarWidth: nil,
                          isPinned: true, content: .reference(isAvailable: true))
    let artwork = ItemBehaviors.provider(for: record)?.barArtwork(for: entry)
    #expect(artwork != nil)
    #expect(artwork is ApplicationLauncherTileView)
}

/// 自绘悬停的 artwork（usesSharedHoverEffects=false）经 any 存在类型调用时，
/// 特性开关与高亮转发都必须动态派发到实现，否则静默退回共享特效/无反馈。
@Test @MainActor func widgetArtworkHighlightDispatchesThroughExistential() throws {
    let reference = try WidgetReferences.applicationLauncher(displayName: "Test")
    let record = PinnedItemRecord(id: .resource(), kind: .widget,
                                  reference: reference, fallbackName: "Test")
    let entry = ItemEntry(id: record.id, kind: record.kind, reference: record.reference,
                          name: "Test", icon: NSImage(), preferredBarWidth: nil,
                          isPinned: true, content: .reference(isAvailable: true))
    let tile = try #require(ItemBehaviors.provider(for: record)?.barArtwork(for: entry) as? ApplicationLauncherTileView)
    let artwork: AnyBarArtwork = tile
    #expect(artwork.usesSharedHoverEffects == false)
    tile.frame = NSRect(x: 0, y: 0, width: 52, height: 52)
    tile.layoutSubtreeIfNeeded()
    artwork.setHighlightState(hovered: true, selected: false)
    #expect(tile.highlightOpacity == 1)
    artwork.setHighlightState(hovered: false, selected: true)
    #expect(tile.highlightOpacity == 1)
    artwork.setHighlightState(hovered: false, selected: false)
    #expect(tile.highlightOpacity == 0)
}

/// 自绘 widget 不复用通用图标遮罩，拖拽接收/拒绝反馈也必须经 artwork 自己绘制。
@Test @MainActor func widgetArtworkDragFeedbackDispatchesThroughExistential() throws {
    let reference = try WidgetReferences.applicationLauncher(displayName: "Test")
    let record = PinnedItemRecord(id: .resource(), kind: .widget,
                                  reference: reference, fallbackName: "Test")
    let entry = ItemEntry(id: record.id, kind: record.kind, reference: record.reference,
                          name: "Test", icon: NSImage(), preferredBarWidth: nil,
                          isPinned: true, content: .reference(isAvailable: true))
    let tile = try #require(ItemBehaviors.provider(for: record)?.barArtwork(for: entry) as? ApplicationLauncherTileView)
    let artwork: AnyBarArtwork = tile
    tile.frame = NSRect(x: 0, y: 0, width: 52, height: 52)
    tile.layoutSubtreeIfNeeded()

    artwork.setDragFeedback(.receiving)
    #expect(tile.dragFeedbackOpacity == 0.30)
    artwork.setDragFeedback(.rejected)
    #expect(tile.dragFeedbackOpacity == 0.38)
    artwork.setDragFeedback(.idle)
    #expect(tile.dragFeedbackOpacity == 0)
}

@Test @MainActor func applicationLauncherAcceptsAppsAndRejectsOtherReferences() throws {
    let target = try WidgetReferences.applicationLauncher(displayName: "Test")
    let record = PinnedItemRecord(id: .resource(), kind: .widget,
                                  reference: target, fallbackName: "Test")
    let behavior = try #require(ItemBehaviors.provider(for: record))
    let application = try ItemReferences.application("com.apple.finder")
    let other = ItemReference(scheme: "file-url", payload: Data("file:///tmp/not-an-app.txt".utf8))

    #expect(behavior.receive([application], at: target) != nil)
    #expect(behavior.receive([other], at: target) == nil)
}

@Test @MainActor func applicationLauncherDeduplicatesByBundleLocation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TideBarTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let firstURL = try makeTestApplication(at: root.appendingPathComponent("Applications/Foo.app"),
                                           bundleIdentifier: "dev.test.same")
    let secondURL = try makeTestApplication(at: root.appendingPathComponent("Downloads/Foo.app"),
                                            bundleIdentifier: "dev.test.same")
    let first = try ItemReferences.application("dev.test.same", url: firstURL)
    let sameLocation = try ItemReferences.application("dev.test.same", url: firstURL)
    let second = try ItemReferences.application("dev.test.same", url: secondURL)

    #expect(ItemReferences.sameApplicationLocation(first, sameLocation))
    #expect(!ItemReferences.sameApplicationLocation(first, second))

    let additions = ApplicationLauncherWidgetSupport.uniqueAdditions(
        current: [first],
        incoming: [first, second, sameLocation]
    )
    #expect(additions == [second])
}

private func makeTestApplication(at url: URL, bundleIdentifier: String) throws -> URL {
    let contents = url.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info = [
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": "Test"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return url
}

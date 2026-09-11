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

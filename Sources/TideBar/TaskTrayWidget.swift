import AppKit
import TideBarCore

extension WidgetReferences {
    static func taskTray(displayName: String) throws -> ItemReference {
        let payload = WidgetPayload(type: .taskTray, displayName: displayName,
                                    configuration: try JSONEncoder().encode(TaskTrayConfiguration()))
        return ItemReference(scheme: "widget", payload: try JSONEncoder().encode(payload))
    }

    static func taskTrayConfiguration(for reference: ItemReference) -> TaskTrayConfiguration? {
        guard let payload = payload(for: reference), payload.type == .taskTray else { return nil }
        return try? JSONDecoder().decode(TaskTrayConfiguration.self, from: payload.configuration)
    }

    @MainActor
    static func saveTaskTrayDefault(_ recipe: TaskTrayRecipe, instanceID: UUID) throws {
        var records = PinnedItemStore.shared.records
        guard let index = records.firstIndex(where: {
            payload(for: $0.reference)?.instanceID == instanceID
        }), var payload = payload(for: records[index].reference), payload.type == .taskTray else {
            throw ItemFailure("item.error.changed")
        }
        payload.configuration = try JSONEncoder().encode(TaskTrayConfiguration(defaultRecipe: recipe))
        records[index].reference = ItemReference(scheme: "widget", payload: try JSONEncoder().encode(payload))
        try PinnedItemStore.shared.replace(records)
    }

    @MainActor
    static func taskTrayDefault(instanceID: UUID) -> TaskTrayRecipe? {
        guard let record = PinnedItemStore.shared.records.first(where: {
            payload(for: $0.reference)?.instanceID == instanceID
        }) else { return nil }
        return taskTrayConfiguration(for: record.reference)?.defaultRecipe
    }
}

@MainActor
struct TaskTrayWidgetBehavior: ItemBehaviorProviding {
    let capabilities: ItemCapabilities = [.receive, .surgeBody]

    func presentation(for record: PinnedItemRecord) -> ItemPresentation {
        let name = WidgetReferences.payload(for: record.reference)?.displayName ?? record.fallbackName
        return ItemPresentation(name: name,
                                icon: NSImage(systemSymbolName: "tray.and.arrow.down.fill",
                                              accessibilityDescription: name) ?? NSImage(),
                                isAvailable: WidgetReferences.taskTrayConfiguration(for: record.reference) != nil)
    }

    func barArtwork(for entry: ItemEntry) -> AnyBarArtwork? { TaskTrayTileView(entry: entry) }

    func surgeBody(for entry: ItemEntry, on screen: NSScreen) async -> AnySurgeBody? {
        guard let payload = WidgetReferences.payload(for: entry.reference),
              let configuration = WidgetReferences.taskTrayConfiguration(for: entry.reference) else { return nil }
        return TaskTraySurgeView(instanceID: payload.instanceID, configuration: configuration)
    }

    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal? {
        guard let payload = WidgetReferences.payload(for: target),
              let configuration = WidgetReferences.taskTrayConfiguration(for: target),
              let urls = try? references.map(ItemReferences.fileURL), !urls.isEmpty,
              configuration.defaultRecipe.map({ recipe in
                  urls.allSatisfy { TaskTrayWorker.accepts($0, recipe: recipe) }
              }) ?? true else { return nil }
        return ItemReceiveProposal(operation: .copy) {
            // 默认值在预览与提交之间变化时拒绝，不能执行另一个动作。
            guard PinnedItemStore.shared.records.contains(where: {
                WidgetReferences.payload(for: $0.reference)?.instanceID == payload.instanceID
            }), WidgetReferences.taskTrayDefault(instanceID: payload.instanceID) == configuration.defaultRecipe else {
                throw ItemFailure("item.error.changed")
            }
            let currentURLs = try references.map(ItemReferences.fileURL)
            try TaskTrayStore.shared.receive(currentURLs, instanceID: payload.instanceID,
                                             recipe: configuration.defaultRecipe)
        }
    }

    static func hoverName(for entry: ItemEntry) -> String {
        guard let configuration = WidgetReferences.taskTrayConfiguration(for: entry.reference) else { return entry.name }
        let operation = configuration.defaultRecipe.map { TaskTrayText.operation($0.operation) }
            ?? TaskTrayText.string("tray.chooseOperation")
        return "\(entry.name) · \(operation)"
    }
}

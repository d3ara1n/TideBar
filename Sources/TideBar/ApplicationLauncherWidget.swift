import AppKit
import TideBarCore

/// 应用收藏夹小工具的引用编解码。实例数据完全封装在 widget record 的 payload 内。
enum WidgetReferences {
    static func payload(for reference: ItemReference) -> WidgetPayload? {
        guard reference.scheme == "widget" else { return nil }
        return try? JSONDecoder().decode(WidgetPayload.self, from: reference.payload)
    }

    static func applicationLauncher(displayName: String,
                                    applications: [ItemReference] = []) throws -> ItemReference {
        let configuration = ApplicationLauncherConfiguration(applications: applications)
        let configurationData = try JSONEncoder().encode(configuration)
        let payload = WidgetPayload(type: .applicationLauncher,
                                    displayName: displayName,
                                    configuration: configurationData)
        return ItemReference(scheme: "widget", payload: try JSONEncoder().encode(payload))
    }

    /// 新实例的默认名跟随当前界面语言；创建后由用户改名接管。
    @MainActor
    static func defaultApplicationLauncherName() -> String {
        L10nManager.shared.current.string("widgets.applicationLauncher", table: .settings)
    }

    static func applicationLauncherConfiguration(for reference: ItemReference) -> ApplicationLauncherConfiguration? {
        guard let payload = payload(for: reference), payload.type == .applicationLauncher else { return nil }
        return try? JSONDecoder().decode(ApplicationLauncherConfiguration.self, from: payload.configuration)
    }

    static func replacing(_ reference: ItemReference,
                          displayName: String? = nil,
                          applications: [ItemReference]? = nil) throws -> ItemReference {
        guard let payload = payload(for: reference) else { throw ItemFailure("item.error.reference") }
        let old = try JSONDecoder().decode(ApplicationLauncherConfiguration.self, from: payload.configuration)
        let nextConfiguration = ApplicationLauncherConfiguration(applications: applications ?? old.applications)
        let next = WidgetPayload(instanceID: payload.instanceID, type: payload.type,
                                 displayName: displayName ?? payload.displayName,
                                 configuration: try JSONEncoder().encode(nextConfiguration))
        return ItemReference(scheme: "widget", payload: try JSONEncoder().encode(next))
    }
}

@MainActor
private struct ApplicationLauncherWidgetBehavior: ItemBehaviorProviding {
    let capabilities: ItemCapabilities = [.receive, .surgeBody]

    func presentation(for record: PinnedItemRecord) -> ItemPresentation {
        let payload = WidgetReferences.payload(for: record.reference)
        let name = payload?.displayName ?? record.fallbackName
        let icon = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: name)
            ?? NSWorkspace.shared.icon(for: .application)
        return ItemPresentation(name: name, icon: icon,
                                isAvailable: payload?.type == .applicationLauncher)
    }

    /// 栏内展示为内容缩略网格（2x2），与应用条目同族，沿用共享悬停特效。
    func barArtwork(for entry: ItemEntry) -> AnyBarArtwork? {
        ApplicationLauncherTileView(entry: entry)
    }

    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal? {
        let appReferences = references.compactMap { reference -> ItemReference? in
            if ItemReferences.applicationLocator(reference) != nil { return reference }
            guard let record = try? ItemReferences.record(for: reference), record.kind == .application else { return nil }
            return record.reference
        }
        // 提案只做无副作用校验；提交时按实例定位最新记录再合并，避免用陈旧引用覆盖内容。
        guard !appReferences.isEmpty,
              appReferences.count == references.count,
              let targetInstance = WidgetReferences.payload(for: target)?.instanceID,
              WidgetReferences.applicationLauncherConfiguration(for: target) != nil else { return nil }
        return ItemReceiveProposal(operation: .copy) {
            guard let record = PinnedItemStore.shared.records.first(where: {
                WidgetReferences.payload(for: $0.reference)?.instanceID == targetInstance
            }), let current = WidgetReferences.applicationLauncherConfiguration(for: record.reference) else {
                throw ItemFailure("item.error.changed")
            }
            var identities = Set(current.applications.compactMap {
                ItemReferences.applicationLocator($0).map { AppIdentity($0.bundleIdentifier) }
            })
            let additions = appReferences.filter { reference in
                guard let locator = ItemReferences.applicationLocator(reference) else { return false }
                return identities.insert(AppIdentity(locator.bundleIdentifier)).inserted
            }
            guard !additions.isEmpty else { return }
            let latest = try WidgetReferences.replacing(record.reference,
                                                        applications: current.applications + additions)
            var records = PinnedItemStore.shared.records
            guard let index = records.firstIndex(where: { $0.id == record.id }) else {
                throw ItemFailure("item.error.changed")
            }
            records[index].reference = latest
            try PinnedItemStore.shared.replace(records)
        }
    }

    func surgeBody(for entry: ItemEntry, on screen: NSScreen) async -> AnySurgeBody? {
        guard WidgetReferences.payload(for: entry.reference)?.type == .applicationLauncher else { return nil }
        return ApplicationLauncherSurgeView(reference: entry.reference, screen: screen)
    }
}

@MainActor
extension ItemBehaviors {
    static func widgetProvider(for record: PinnedItemRecord) -> (any ItemBehaviorProviding)? {
        guard let payload = WidgetReferences.payload(for: record.reference) else { return nil }
        switch payload.type {
        case .applicationLauncher: return ApplicationLauncherWidgetBehavior()
        }
    }
}

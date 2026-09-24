import Foundation
import TideBarCore

/// 通用固定存储：只保存引用和顺序，不执行任何资源操作。
@MainActor
final class PinnedItemStore {
    static let shared = PinnedItemStore()
    static let didChange = Notification.Name("TideBar.pinnedItemsDidChange")
    private static let key = "tidebar.pinnedItems.v1"
    private static let legacyKey = "tidebar.pinned"

    private let defaults: UserDefaults
    private(set) var records: [PinnedItemRecord] = []
    private(set) var loadError: Error?

    init(defaults: UserDefaults = RuntimeEnvironment.defaults) {
        self.defaults = defaults
        do {
            if let object = defaults.object(forKey: Self.key) {
                guard let data = object as? Data else { throw ItemFailure("item.error.storage") }
                let document = try JSONDecoder().decode(PinnedItemDocument.self, from: data)
                guard document.version == 1,
                      Set(document.records.map(\.id)).count == document.records.count else {
                    throw ItemFailure("item.error.storage")
                }
                records = try Self.normalizedApplicationRecords(document.records)
                if records != document.records {
                    let migrated = try JSONEncoder().encode(PinnedItemDocument(records: records))
                    defaults.set(migrated, forKey: Self.key)
                }
            } else if defaults.object(forKey: Self.legacyKey) != nil {
                guard let ids = defaults.stringArray(forKey: Self.legacyKey) else { throw ItemFailure("item.error.storage") }
                records = try Self.applicationRecords(ids)
                // 先完整写入新格式，保留旧键作为迁移来源；显式空数组不是默认列表。
                let data = try JSONEncoder().encode(PinnedItemDocument(records: records))
                defaults.set(data, forKey: Self.key)
            } else {
                records = try Self.applicationRecords(AppConfiguration.defaultPinnedBundleIDs)
            }
        } catch {
            loadError = error
            NSLog("TideBar pinned item storage unavailable; original data preserved: %@", String(describing: error))
        }
    }

    private static func applicationRecords(_ ids: [String]) throws -> [PinnedItemRecord] {
        var seen = Set<ItemID>()
        return try ids.compactMap { bundleID in
            let id = ItemID.application(AppIdentity(bundleID))
            guard seen.insert(id).inserted else { return nil }
            return PinnedItemRecord(id: id, kind: .application,
                                    reference: try ItemReferences.application(bundleID), fallbackName: bundleID)
        }
    }

    private static func normalizedApplicationRecords(_ records: [PinnedItemRecord]) throws -> [PinnedItemRecord] {
        var seen = Set<ItemID>()
        return try records.compactMap { record in
            var normalized = record
            if record.kind == .application,
               let locator = ItemReferences.applicationLocator(record.reference),
               let bookmark = locator.bookmark,
               let url = ItemReferences.applicationURL(record.reference) {
                normalized = PinnedItemRecord(
                    id: .application(ApplicationItemIdentity(
                        bundleIdentifier: locator.bundleIdentifier,
                        applicationPath: url.standardizedFileURL.resolvingSymlinksInPath().path
                    )),
                    kind: record.kind,
                    reference: ItemReference(
                    scheme: "application",
                    payload: try JSONEncoder().encode(ItemReferences.ApplicationLocator(
                        bundleIdentifier: locator.bundleIdentifier,
                        bookmark: bookmark
                    ))
                    ),
                    fallbackName: record.fallbackName
                )
            }
            guard seen.insert(normalized.id).inserted else {
                if normalized.kind == .application {
                    NSLog("TideBar duplicate application location collapsed during migration: %@", normalized.id.rawValue)
                    return nil
                }
                throw ItemFailure("item.error.storage")
            }
            return normalized
        }
    }

    var applicationBundleIdentifiers: [String] {
        records.compactMap { $0.kind == .application ? ItemReferences.applicationLocator($0.reference)?.bundleIdentifier : nil }
    }

    var applicationDescriptions: [PinnedApplicationDescription] {
        records.compactMap { record in
            guard record.kind == .application,
                  let locator = ItemReferences.applicationLocator(record.reference) else { return nil }
            return PinnedApplicationDescription(
                bundleIdentifier: locator.bundleIdentifier,
                applicationPath: locator.bookmark == nil ? nil : ItemReferences.applicationURL(record.reference)?.path
            )
        }
    }

    func reconcileApplicationLocations() throws {
        var updated: [PinnedItemRecord] = []
        var seen = Set<ItemID>()
        for record in records {
            var candidate = record
            if record.kind == .application,
               let locator = ItemReferences.applicationLocator(record.reference),
               locator.bookmark != nil,
               let url = ItemReferences.applicationURL(record.reference) {
                candidate = PinnedItemRecord(
                    id: .application(ApplicationItemIdentity(
                        bundleIdentifier: locator.bundleIdentifier,
                        applicationPath: url.path
                    )),
                    kind: record.kind,
                    reference: record.reference,
                    fallbackName: record.fallbackName
                )
            }
            guard seen.insert(candidate.id).inserted else {
                guard candidate.kind == .application else {
                    throw ItemFailure("item.error.storage")
                }
                NSLog("TideBar duplicate application location collapsed: %@", candidate.id.rawValue)
                continue
            }
            updated.append(candidate)
        }
        if updated != records {
            try replace(updated)
        }
    }

    func replace(_ records: [PinnedItemRecord]) throws {
        guard loadError == nil else { throw ItemFailure("item.error.storage") }
        guard Set(records.map(\.id)).count == records.count else { throw ItemFailure("item.error.storage") }
        guard records != self.records else { return }
        let data = try JSONEncoder().encode(PinnedItemDocument(records: records))
        defaults.set(data, forKey: Self.key)
        self.records = records
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func setPinned(_ pinned: Bool, bundleIdentifier: String) throws {
        let id = ItemID.application(AppIdentity(bundleIdentifier))
        if pinned {
            guard !records.contains(where: { $0.id == id }) else { return }
            try replace(records + Self.applicationRecords([bundleIdentifier]))
        } else {
            try remove([id])
        }
    }

    func remove(_ ids: Set<ItemID>) throws { try replace(records.filter { !ids.contains($0.id) }) }

    func move(from offsets: IndexSet, to destination: Int) throws {
        guard offsets.allSatisfy({ records.indices.contains($0) }), (0...records.count).contains(destination) else { return }
        let moving = offsets.sorted().map { records[$0] }
        var result = records.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let index = destination - offsets.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: index)
        try replace(result)
    }

    func restoreDefaults() throws {
        let result = try Self.applicationRecords(AppConfiguration.defaultPinnedBundleIDs)
        // 只有用户明确恢复默认值才允许覆盖无法读取的文档。
        let data = try JSONEncoder().encode(PinnedItemDocument(records: result))
        defaults.set(data, forKey: Self.key)
        loadError = nil
        records = result
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// 固定项目页的“恢复默认”只重置普通应用，保留 widget 实例及其独立配置。
    func restoreDefaultApplicationsPreservingWidgets() throws {
        guard loadError == nil else {
            try restoreDefaults()
            return
        }
        let widgets = records.filter { $0.kind == .widget }
        let applications = try Self.applicationRecords(AppConfiguration.defaultPinnedBundleIDs)
        try replace(applications + widgets)
    }
}

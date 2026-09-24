import AppKit
import TideBarCore

/// 通用条目只保留通用展示；应用状态作为独立的关联内容，不扩散到文件或未来 widget。
@MainActor
struct ItemEntry: Identifiable {
    enum Content {
        case application(AppEntry)
        case reference(isAvailable: Bool)
    }
    let id: ItemID
    let kind: ItemKind
    let reference: ItemReference
    let name: String
    let icon: NSImage
    let preferredBarWidth: CGFloat?
    let isPinned: Bool
    let content: Content

    var application: AppEntry? {
        if case .application(let app) = content { return app }
        return nil
    }
    var isAvailable: Bool {
        if case .reference(let available) = content { return available }
        return true
    }
    var capabilities: ItemCapabilities { ItemBehaviors.provider(for: self)?.capabilities ?? [] }
    /// 是否提供长按潮涌体（触发门槛查能力，不问条目内容）
    var canSurge: Bool { capabilities.contains(.surgeBody) }
    var canPin: Bool { isPinned || application?.bundleIdentifier != nil }
    var badge: BadgeValue? { application?.badge }

    func primaryClick() {
        if let application { application.primaryClick(); return }
        guard capabilities.contains(.open), let behavior = ItemBehaviors.provider(for: self) else { return }
        Task {
            do { try await behavior.open(reference) }
            catch { ItemErrors.report(error) }
        }
    }
    func reveal() {
        if let url = application?.applicationURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        do { try ItemBehaviors.provider(for: self)?.reveal(reference) }
        catch { ItemErrors.report(error) }
    }
    func sameContent(as other: Self) -> Bool {
        id == other.id && kind == other.kind && reference == other.reference && name == other.name
            && preferredBarWidth == other.preferredBarWidth
            && isPinned == other.isPinned && isAvailable == other.isAvailable
            && application?.contentRevision == other.application?.contentRevision && icon.isEqual(other.icon)
    }
}

/// 固定引用与运行应用的组合；应用观测和窗口动作仍由 AppRegistry 独立承担。
@MainActor
final class ItemRegistry {
    let applications = AppRegistry()
    private let store: PinnedItemStore
    private(set) var entries: [ItemEntry] = []
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var presentations: [PinnedItemRecord: ItemPresentation] = [:]
    private var sessionOrder: [ItemID] = []
    private var usesSessionOrder = false
    private var isRefreshing = false
    /// 临时项移除仅隐藏当前运行实例；新运行实例或重启 TideBar 后自然恢复。
    private var dismissed: [ApplicationItemIdentity: Set<pid_t>] = [:]
    private var lastPinnedOrder: [ItemID] = []
    private var committingOrder = false

    init(store: PinnedItemStore = .shared) {
        self.store = store
    }

    func start() {
        applications.onChange = { [weak self] in self?.rebuild() }
        applications.start()
        observer = NotificationCenter.default.addObserver(forName: PinnedItemStore.didChange,
                                                          object: store, queue: .main) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.refresh() }.call()
        }
        rebuild()
        if let error = store.loadError { ItemErrors.report(error) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        presentations.removeAll()
        var records = store.records
        for index in records.indices {
            let refreshed: ItemReference?
            if records[index].kind == .application {
                refreshed = try? ItemReferences.refreshApplicationBookmark(records[index].reference)
            } else {
                refreshed = try? ItemReferences.refreshBookmark(records[index].reference)
            }
            if let refreshed {
                records[index].reference = refreshed
            }
        }
        if records != store.records {
            do { try store.replace(records) }
            catch { NSLog("TideBar bookmark refresh could not be saved: %@", String(describing: error)) }
        }
        do { try store.reconcileApplicationLocations() }
        catch { NSLog("TideBar application identity reconciliation failed: %@", String(describing: error)) }
        applications.refresh()
        rebuild()
    }

    private func rebuild() {
        let records = store.records
        let pinnedIDs = records.map(\.id)
        if pinnedIDs != lastPinnedOrder, !committingOrder {
            sessionOrder = []
            usesSessionOrder = false
        }
        lastPinnedOrder = pinnedIDs
        let apps = Dictionary(uniqueKeysWithValues: applications.entries.map { (ItemID.application($0.id), $0) })
        var result: [ItemEntry] = []
        for record in records {
            if let app = apps[record.id], record.kind == .application {
                result.append(entry(for: app, record: record))
            } else {
                let presentation = presentations[record] ?? ItemBehaviors.presentation(for: record)
                presentations[record] = presentation
                result.append(ItemEntry(id: record.id, kind: record.kind, reference: record.reference,
                                        name: presentation.name, icon: presentation.icon,
                                        preferredBarWidth: presentation.preferredBarWidth, isPinned: true,
                                        content: .reference(isAvailable: presentation.isAvailable)))
            }
        }
        let liveIDs = Set(applications.entries.map(\.itemIdentity))
        dismissed = dismissed.filter { liveIDs.contains($0.key) }
        for app in applications.entries {
            let id = ItemID.application(app.id)
            if pinnedIDs.contains(id) { dismissed.removeValue(forKey: app.itemIdentity); continue }
            if let hiddenPIDs = dismissed[app.itemIdentity] {
                let current = Set(app.runningAppsByPID.keys)
                if !current.isEmpty, current.isSubset(of: hiddenPIDs) { continue }
                dismissed.removeValue(forKey: app.itemIdentity)
            }
            result.append(entry(for: app, record: nil))
        }
        let available = Set(result.map(\.id))
        if !usesSessionOrder { sessionOrder = result.map(\.id) }
        sessionOrder = sessionOrder.filter { available.contains($0) }
        sessionOrder += result.map(\.id).filter { !sessionOrder.contains($0) }
        let ranks = Dictionary(uniqueKeysWithValues: sessionOrder.enumerated().map { ($0.element, $0.offset) })
        result.sort { ranks[$0.id, default: 0] < ranks[$1.id, default: 0] }
        let changed = entries.count != result.count || !zip(entries, result).allSatisfy { $0.sameContent(as: $1) }
        entries = result
        if changed { onChange?() }
    }

    private func entry(for app: AppEntry, record: PinnedItemRecord?) -> ItemEntry {
        let reference = record?.reference
            ?? app.bundleIdentifier.flatMap { try? ItemReferences.application($0, url: app.applicationURL) }
            ?? ItemReference(scheme: "running-process", payload: Data(app.identity.description.utf8))
        return ItemEntry(id: .application(app.id), kind: .application, reference: reference,
                         name: app.name, icon: app.icon, preferredBarWidth: nil,
                         isPinned: record != nil, content: .application(app))
    }

    func setPinned(_ pinned: Bool, for id: ItemID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        do {
            if pinned, let app = entry.application, let bundleID = app.bundleIdentifier,
               !store.records.contains(where: { $0.id == id }) {
                let record = PinnedItemRecord(id: id, kind: .application,
                                              reference: try ItemReferences.application(bundleID, url: app.applicationURL),
                                              fallbackName: entry.name)
                try store.replace(store.records + [record])
            } else if !pinned {
                try store.remove([id])
            }
        } catch { ItemErrors.report(error) }
    }

    func remove(_ id: ItemID) throws {
        guard let item = entries.first(where: { $0.id == id }) else { return }
        if item.isPinned {
            try store.remove([id])
        } else if let app = item.application {
            dismissed[app.itemIdentity] = Set(app.runningAppsByPID.keys)
            rebuild()
        }
    }

    func reorder(_ id: ItemID, before anchor: ItemID?) throws {
        guard let order = ItemOrdering.moving([id], before: anchor, in: entries.map(\.id)) else {
            throw ItemFailure("item.error.changed")
        }
        let oldOrder = sessionOrder
        let wasUsingSessionOrder = usesSessionOrder
        sessionOrder = order
        usesSessionOrder = true
        let pinnedByID = Dictionary(uniqueKeysWithValues: store.records.map { ($0.id, $0) })
        committingOrder = true
        defer { committingOrder = false }
        do { try store.replace(order.compactMap { pinnedByID[$0] }) }
        catch { sessionOrder = oldOrder; usesSessionOrder = wasUsingSessionOrder; throw error }
        NSLog("TideBar item reorder committed: %@ before %@", id.rawValue,
              anchor?.rawValue ?? "<end>")
        rebuild()
    }

    /// 插入动作解释外部引用；一次校验、一次持久化。重复资源复用原条目身份。
    func insert(_ references: [ItemReference], before anchor: ItemID?) throws {
        guard !references.isEmpty else { return }
        let current = entries.map(\.id)
        if let anchor, !current.contains(anchor) { throw ItemFailure("item.error.changed") }
        let (records, inserted) = try ItemPinOperation.prepare(references, existing: store.records)
        // 落在临时项之前也有稳定的展示锚点；固定持久化只保存固定项的相对顺序。
        let all = current + inserted.filter { !current.contains($0) }
        guard let order = ItemOrdering.moving(inserted, before: anchor, in: all) else { throw ItemFailure("item.error.changed") }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let oldOrder = sessionOrder
        let wasUsingSessionOrder = usesSessionOrder
        sessionOrder = order
        usesSessionOrder = true
        committingOrder = true
        defer { committingOrder = false }
        do { try store.replace(order.compactMap { byID[$0] }) }
        catch { sessionOrder = oldOrder; usesSessionOrder = wasUsingSessionOrder; throw error }
        rebuild()
    }
}

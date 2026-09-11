import AppKit
import TideBarCore

/// 持有引用拖拽会话；来源权限、目标意图与资源操作分离，source 不依赖按钮存活。
@MainActor
final class ItemDragCoordinator: NSObject, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.dearain.TideBar.item-reference")
    var onBegin: (() -> Void)?
    var onMovement: (() -> Void)?
    var onSessionChange: (() -> Void)?
    var allowsRemovalAt: ((NSPoint) -> Bool)?
    private let registry: ItemRegistry

    @MainActor
    private final class Session {
        let token = UUID().uuidString
        let itemID: ItemID
        let startTimestamp: TimeInterval
        let wasPinned: Bool
        let originalPIDs: Set<pid_t>
        var invalidated = false
        var committed = false
        init(item: ItemEntry, event: NSEvent) {
            itemID = item.id
            startTimestamp = event.timestamp
            wasPinned = item.isPinned
            originalPIDs = Set(item.application?.runningAppsByPID.keys.map { $0 } ?? [])
        }
    }
    private struct Proposal {
        let operation: NSDragOperation
        let execute: () throws -> Void
    }
    private var active: Session?
    private weak var targetView: TideBarView?
    private var preview: Proposal?
    private var previewIntent: ItemDropIntent?
    private var previewTargetReference: ItemReference?
    private var previewSourceOperations: NSDragOperation = []
    private var externalCache: (sequence: Int, changeCount: Int, references: [ItemReference])?
    private var committedSequence: Int?
    var isDragging: Bool { active != nil }
    var liftedItemID: ItemID? {
        guard let active, !active.invalidated, !active.committed else { return nil }
        return active.itemID
    }

    init(registry: ItemRegistry) { self.registry = registry }

    func begin(from button: ItemIconButton, event: NSEvent) -> Bool {
        guard active == nil, button.window != nil else { return false }
        let state = Session(item: button.entry, event: event)
        let writer = NSPasteboardItem()
        guard writer.setString(state.token, forType: Self.pasteboardType) else { return false }
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(NSRect(x: button.bounds.midX - Layout.iconSize / 2,
                                     y: button.bounds.midY - Layout.iconSize / 2,
                                     width: Layout.iconSize, height: Layout.iconSize), contents: button.dragPreviewImage())
        active = state
        onBegin?()
        let session = button.beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        return true
    }

    func invalidate(reason: String) {
        if active != nil || previewIntent != nil {
            NSLog("TideBar item drag invalidated: %@", reason)
        }
        active?.invalidated = true
        if let targetView { exit(targetView) }
        externalCache = nil
        onSessionChange?()
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // 在原生会话开始时确定策略，不依赖结束回调与系统回位动画的先后顺序。
        session.animatesToStartingPositionsOnCancelOrFail = false
        onSessionChange?()
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication && active?.invalidated == false ? [.private, .copy] : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        if active?.invalidated == false { onMovement?() }
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        guard let state = active else { return }
        defer {
            active = nil
            onSessionChange?()
        }
        if let targetView { exit(targetView) }
        // 原生 source 结束时 currentEvent 可能是 Pressure 或其他事件；不猜测原因。
        let evidence: ItemDragEndEvidence
        if let event = NSApp.currentEvent, event.timestamp >= state.startTimestamp {
            if event.type == .leftMouseUp { evidence = .mouseReleased }
            else if event.type == .keyDown, event.keyCode == 53 { evidence = .cancelled }
            else { evidence = .unknown }
        } else { evidence = .unknown }
        guard evidence.permitsRemoval(accepted: state.committed,
                                      invalidated: state.invalidated,
                                      outsideBar: allowsRemovalAt?(screenPoint) == true,
                                      leftButtonStillDown: NSEvent.pressedMouseButtons & 1 != 0) else {
            if evidence == .unknown { NSLog("TideBar item drag removal cancelled: no confirmed mouse release") }
            return
        }
        guard let latest = registry.entries.first(where: { $0.id == state.itemID }),
              latest.isPinned == state.wasPinned else { return }
        // 小工具实例删除需经设置页确认；栏内拖出只回位，不做删除。
        guard latest.kind != .widget else { return }
        if !state.wasPinned,
           Set(latest.application?.runningAppsByPID.keys.map { $0 } ?? []) != state.originalPIDs { return }
        do {
            try registry.remove(state.itemID)
        } catch { ItemErrors.report(error) }
    }

    func update(_ sender: any NSDraggingInfo, in view: TideBarView) -> NSDragOperation {
        if targetView !== view {
            targetView?.setDropFeedback(nil)
            preview = nil
            previewIntent = nil
            targetView = view
        }
        guard let payload = payload(for: sender) else { view.setDropFeedback(nil); return [] }
        let location = view.dropLocation(for: sender)
        let intent = routedIntent(payload, at: location)
        let latestTarget = targetReference(for: intent)
        // 在同一目标内移动不重复查询 Launch Services 或文件系统；提交时强制重验。
        if previewIntent != intent || previewTargetReference != latestTarget
            || previewSourceOperations != sender.draggingSourceOperationMask {
            previewIntent = intent
            previewTargetReference = latestTarget
            previewSourceOperations = sender.draggingSourceOperationMask
            preview = proposal(for: intent, allowed: sender.draggingSourceOperationMask)
        }
        view.setDropFeedback(intent, accepted: preview != nil)
        guard let preview, sender.draggingSourceOperationMask.contains(preview.operation) else { return [] }
        return preview.operation
    }

    func canPerform(_ sender: any NSDraggingInfo, in view: TideBarView) -> Bool {
        validatedProposal(sender, in: view) != nil
    }

    func perform(_ sender: any NSDraggingInfo, in view: TideBarView) -> Bool {
        guard committedSequence != sender.draggingSequenceNumber,
              let proposal = validatedProposal(sender, in: view) else {
            NSLog("TideBar item drop rejected: sequence=%ld previewIntent=%@",
                  sender.draggingSequenceNumber,
                  previewIntent.map { String(describing: $0) } ?? "nil")
            return false
        }
        do {
            try proposal.execute()
            committedSequence = sender.draggingSequenceNumber
            if isInternal(sender) { active?.committed = true }
            exit(view)
            onSessionChange?()
            return true
        } catch {
            exit(view)
            ItemErrors.report(error)
            return false
        }
    }

    func exit(_ view: TideBarView) {
        view.setDropFeedback(nil)
        guard targetView === view else { return }
        targetView = nil
        preview = nil
        previewIntent = nil
        previewTargetReference = nil
        previewSourceOperations = []
    }

    func ended(_ sender: any NSDraggingInfo, in view: TideBarView) {
        exit(view)
        if externalCache?.sequence == sender.draggingSequenceNumber { externalCache = nil }
    }

    /// 潮涌小工具专用接收：只接受应用引用，不参与栏内重排。
    func widgetDropOperation(_ sender: any NSDraggingInfo, target: ItemEntry) -> NSDragOperation {
        guard target.kind == .widget, target.capabilities.contains(.receive),
              let references = widgetApplicationReferences(for: sender),
              let receiver = ItemBehaviors.provider(for: target),
              receiver.receive(references, at: target.reference) != nil else { return [] }
        return .copy
    }

    func performWidgetDrop(_ sender: any NSDraggingInfo, target: ItemEntry) -> Bool {
        guard let references = widgetApplicationReferences(for: sender),
              let receiver = ItemBehaviors.provider(for: target),
              let proposal = receiver.receive(references, at: target.reference) else { return false }
        do { try proposal.execute(); registry.refresh(); return true }
        catch { ItemErrors.report(error); return false }
    }

    private func widgetApplicationReferences(for sender: any NSDraggingInfo) -> [ItemReference]? {
        if let payload = payload(for: sender) {
            if case .internalItem(let sourceID) = payload,
               let source = registry.entries.first(where: { $0.id == sourceID }),
               source.kind == .application,
               let bundleIdentifier = source.application?.bundleIdentifier,
               let reference = try? ItemReferences.application(bundleIdentifier) {
                return [reference]
            }
            if case .externalReferences(let references) = payload {
                let converted = references.compactMap { reference -> ItemReference? in
                    if ItemReferences.applicationLocator(reference) != nil { return reference }
                    guard let record = try? ItemReferences.record(for: reference), record.kind == .application else { return nil }
                    return record.reference
                }
                return converted.count == references.count && !converted.isEmpty ? converted : nil
            }
        }
        return nil
    }

    private func validatedProposal(_ sender: any NSDraggingInfo, in view: TideBarView) -> Proposal? {
        guard targetView === view, view.isExpandedState, view.window?.isVisible == true,
              let payload = payload(for: sender) else { return nil }
        let intent = routedIntent(payload, at: view.dropLocation(for: sender))
        // 模型或几何变化不能把用户看到的意图替换成另一个操作。
        guard intent == previewIntent, preview != nil else { return nil }
        return proposal(for: intent, allowed: sender.draggingSourceOperationMask)
    }

    private func proposal(for intent: ItemDropIntent, allowed: NSDragOperation) -> Proposal? {
        switch intent {
        case .reorder(let id, let anchor):
            guard active?.itemID == id, active?.invalidated == false, allowed.contains(.private),
                  ItemOrdering.moving([id], before: anchor, in: registry.entries.map(\.id)) != nil else { return nil }
            return Proposal(operation: .private) { [registry] in
                try registry.reorder(id, before: anchor)
            }
        case .insert(let references, let anchor):
            let operation: NSDragOperation = allowed.contains(.link) ? .link : .copy
            guard allowed.contains(operation), ItemPinOperation.accepts(references) else { return nil }
            return Proposal(operation: operation) { [registry] in
                try registry.insert(references, before: anchor)
            }
        case .deliver(let references, let id):
            guard let item = registry.entries.first(where: { $0.id == id }),
                  item.isAvailable, item.capabilities.contains(.receive),
                  let receiver = ItemBehaviors.provider(for: item),
                  let receive = receiver.receive(references, at: item.reference),
                  allowed.contains(receive.operation) else { return nil }
            return Proposal(operation: receive.operation) { [registry] in
                defer { registry.refresh() }
                try receive.execute()
            }
        case .deliverItem(let sourceID, let targetID):
            guard let source = registry.entries.first(where: { $0.id == sourceID }),
                  source.kind == .application,
                  let target = registry.entries.first(where: { $0.id == targetID }),
                  target.kind == .widget,
                  target.capabilities.contains(.receive),
                  let bundleIdentifier = source.application?.bundleIdentifier,
                  let appReference = try? ItemReferences.application(bundleIdentifier),
                  let receiver = ItemBehaviors.provider(for: target),
                  let receive = receiver.receive([appReference], at: target.reference),
                  allowed.contains(receive.operation) else { return nil }
            return Proposal(operation: receive.operation) { [registry] in
                defer { registry.refresh() }
                try receive.execute()
            }
        }
    }

    private func targetReference(for intent: ItemDropIntent) -> ItemReference? {
        let id: ItemID
        switch intent {
        case .deliver(_, let target), .deliverItem(_, let target): id = target
        default: return nil
        }
        return registry.entries.first(where: { $0.id == id })?.reference
    }

    private func routedIntent(_ payload: ItemDragPayload, at location: ItemDropLocation) -> ItemDropIntent {
        if case .internalItem(let sourceID) = payload,
           let targetID = location.target,
           let source = registry.entries.first(where: { $0.id == sourceID }),
           source.kind == .application,
           let target = registry.entries.first(where: { $0.id == targetID }),
           target.kind == .widget {
            return .deliverItem(sourceID, to: targetID)
        }
        return ItemDropIntent.route(payload, at: location)
    }
    private func isInternal(_ sender: any NSDraggingInfo) -> Bool {
        guard let active, let source = sender.draggingSource as? ItemDragCoordinator, source === self else { return false }
        return sender.draggingPasteboard.string(forType: Self.pasteboardType) == active.token
    }
    private func payload(for sender: any NSDraggingInfo) -> ItemDragPayload? {
        if sender.draggingPasteboard.types?.contains(Self.pasteboardType) == true {
            guard isInternal(sender), let active, !active.invalidated else { return nil }
            return .internalItem(active.itemID)
        }
        let board = sender.draggingPasteboard
        if let cache = externalCache, cache.sequence == sender.draggingSequenceNumber,
           cache.changeCount == board.changeCount { return .externalReferences(cache.references) }
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        let references = urls.map(ItemReferences.externalFile)
        externalCache = (sender.draggingSequenceNumber, board.changeCount, references)
        return .externalReferences(references)
    }
}

import AppKit
import TideBarCore

struct ItemListUpdate {
    let hasInsertions: Bool
    let hasRemovals: Bool
    let removalDuration: TimeInterval

    static let none = ItemListUpdate(hasInsertions: false, hasRemovals: false, removalDuration: 0)
}

@MainActor
final class ItemRowView: NSView {
    var onBeginDrag: ((ItemIconButton, NSEvent) -> Bool)? {
        didSet {
            for button in buttons { button.onBeginDrag = onBeginDrag }
        }
    }
    var onLaunch: ((ItemEntry) -> Void)?
    var onUserLaunch: (() -> Void)?
    var onSetHidden: ((ApplicationItemIdentity, Bool) -> Void)?
    var onTerminate: ((ApplicationItemIdentity) -> Bool)?
    var onSetPinned: ((ItemID, Bool) -> Void)?
    var onSurge: ((ItemEntry, NSRect) -> Void)?
    var onRemoveWidget: ((ItemEntry) -> Void)? {
        didSet {
            for button in buttons { button.onRemoveWidget = onRemoveWidget }
        }
    }
    var onMenuSessionChange: ((Bool) -> Void)? {
        didSet {
            for button in buttons { button.onMenuSessionChange = onMenuSessionChange }
        }
    }
    private var buttons: [ItemIconButton] = []
    /// 离场项保留到动画结束，避免列表真值先删除导致视图瞬间消失。
    private var departingButtons: [ItemID: ItemIconButton] = [:]
    private var departureTokens: [ItemID: Int] = [:]
    var onPreviewWidthChange: (() -> Void)?
    private let placeholder = ItemDragPlaceholder()
    private var preview: ItemDragPreview = .none
    private var dragActive = false
    private var liftedSource: ItemID?
    private var hitLatch = ItemDragHitLatch()
    private var projected: ItemDragLayout { ItemDragLayout(order: buttons.map(\.entry.id), preview: preview) }
    var extraPreviewSlots: Int { max(0, projected.slots.count - buttons.count) }
    var preferredContentWidth: CGFloat {
        guard preview == .none else { return CGFloat(projected.slots.count) * Layout.iconSlot }
        return buttons.reduce(0) { $0 + $1.preferredWidth }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(placeholder.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// rebuildAll = true：整体重建（展开动画完整重播）
    /// rebuildAll = false：按 identity 差分，统一处理新增、删除与保留项重排。
    @discardableResult
    func update(apps: [ItemEntry], rebuildAll: Bool) -> ItemListUpdate {
        if apps.map(\.id) != buttons.map(\.entry.id) { hitLatch.reset() }
        if rebuildAll {
            for button in buttons + Array(departingButtons.values) {
                button.removeFromSuperview()
            }
            departingButtons.removeAll()
            departureTokens.removeAll()
            buttons = apps.map { app in
                let button = makeButton(app)
                addSubview(button)
                return button
            }
            applyDragAppearance()
            needsLayout = true
            return .none
        }

        var oldFrames = Dictionary(uniqueKeysWithValues: buttons.map { ($0.entry.id, $0.frame) })
        var oldCenters = visualCenters()
        var kept = Dictionary(uniqueKeysWithValues: buttons.map { ($0.entry.id, $0) })
        var next: [ItemIconButton] = []
        var newcomers: [ItemIconButton] = []

        for app in apps {
            if let existing = kept.removeValue(forKey: app.id) {
                existing.update(entry: app)
                next.append(existing)
            } else if let returning = departingButtons.removeValue(forKey: app.id) {
                departureTokens[app.id, default: 0] += 1
                oldFrames[app.id] = returning.frame
                oldCenters[app.id] = returning.frame.midX
                restoreForReuse(returning)
                returning.update(entry: app)
                next.append(returning)
            } else {
                let button = makeButton(app)
                addSubview(button)
                next.append(button)
                newcomers.append(button)
            }
        }

        let removed = Array(kept.values)
        for button in removed {
            beginDeparture(button)
        }

        buttons = next
        applyDragAppearance()
        needsLayout = true
        layoutSubtreeIfNeeded()

        let newcomerIDs = Set(newcomers.map { $0.entry.id })
        for button in buttons where !newcomerIDs.contains(button.entry.id) {
            guard let oldFrame = oldFrames[button.entry.id], let layer = button.layer,
                  abs(oldFrame.midX - button.frame.midX) > 0.5 else { continue }
            let delta = (oldCenters[button.entry.id] ?? oldFrame.midX) - button.frame.midX
            if dragActive || preview != .none || Motion.shouldReduceMotion {
                ItemDragStyle.reposition(layer, offset: delta, lifted: button.isHidden)
            } else {
                Motion.spring(layer, keyPath: "transform.translation.x", from: delta, to: CGFloat(0),
                              stiffness: Motion.iconRepositionStiffness,
                              damping: Motion.iconRepositionDamping,
                              minDuration: Motion.iconRepositionDuration)
            }
        }
        for button in newcomers {
            rise(button, delay: Motion.iconInsertionDelay)
        }

        let removalDuration = removed.isEmpty
            ? 0
            : (Motion.shouldReduceMotion
               ? Motion.reducedMotionFadeDuration : Motion.dropDuration)
        return ItemListUpdate(hasInsertions: !newcomers.isEmpty,
                             hasRemovals: !removed.isEmpty,
                             removalDuration: removalDuration)
    }

    private func makeButton(_ app: ItemEntry) -> ItemIconButton {
        let button = ItemIconButton(entry: app)
        button.onBeginDrag = onBeginDrag
        button.onClick = { [weak self] entry in
            guard let self else { return }
            self.onUserLaunch?()
            if entry.kind == .widget {
                self.onSurge?(entry, button.frame)
            } else {
                self.onLaunch?(entry)
            }
        }
        button.onSetHidden = { [weak self] identity, hidden in self?.onSetHidden?(identity, hidden) }
        button.onTerminate = { [weak self] identity in self?.onTerminate?(identity) ?? false }
        button.onSetPinned = { [weak self] identity, pinned in self?.onSetPinned?(identity, pinned) }
        button.onSurge = { [weak self] entry, frame in self?.onSurge?(entry, frame) }
        button.onRemoveWidget = { [weak self] entry in self?.onRemoveWidget?(entry) }
        button.onMenuSessionChange = { [weak self] active in self?.onMenuSessionChange?(active) }
        return button
    }

    /// 悬停轮询：命中之外的按钮全部清悬停
    func setHover(hit: ItemIconButton?) {
        for button in buttons {
            button.setHovered(button === hit)
        }
    }

    func setKeyboardSelection(_ identity: ApplicationItemIdentity?) {
        for button in buttons {
            button.setKeyboardSelected(button.entry.id == identity.map(ItemID.application))
        }
    }

    func button(for identity: ApplicationItemIdentity) -> ItemIconButton? {
        buttons.first { $0.entry.id == .application(identity) }
    }

    func setDragContext(active: Bool, source: ItemID?) {
        guard dragActive != active || liftedSource != source else { return }
        dragActive = active
        liftedSource = source
        hitLatch.reset()
        applyDragAppearance()
    }

    func setDragPreview(_ newPreview: ItemDragPreview) {
        guard preview != newPreview else { return }
        let oldCenters = visualCenters()
        let oldExtra = extraPreviewSlots
        preview = newPreview
        if preview == .none { hitLatch.reset() }
        applyDragAppearance()
        needsLayout = true
        layoutSubtreeIfNeeded()
        for button in buttons {
            guard let old = oldCenters[button.entry.id], let layer = button.layer else { continue }
            ItemDragStyle.reposition(layer, offset: old - button.frame.midX, lifted: button.isHidden)
        }
        if oldExtra != extraPreviewSlots { onPreviewWidthChange?() }
        accommodateHitRegion()
    }

    private func visualCenters() -> [ItemID: CGFloat] {
        Dictionary(uniqueKeysWithValues: buttons.map {
            let translation = ($0.layer?.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat) ?? 0
            return ($0.entry.id, $0.frame.midX + translation)
        })
    }

    private func applyDragAppearance() {
        for button in buttons {
            let state: ItemDragIconState
            if button.entry.id == liftedSource { state = .lifted }
            else if case .receive(let id, let accepted) = preview, button.entry.id == id {
                state = accepted ? .receiving : .rejected
            } else { state = dragActive || preview != .none ? .tracking : .idle }
            button.setDragState(state)
        }
    }

    func dropLocation(at point: NSPoint) -> ItemDropLocation {
        let screenPoint = screenRect(NSRect(origin: point, size: .zero)).origin
        if let retained = hitLatch.retained(at: screenPoint) { return retained }
        let internalApplicationCanDeliver = liftedSource.flatMap { sourceID in
            buttons.first(where: { $0.entry.id == sourceID })?.entry.kind == .application
        } == true
        if case .receive(let targetID, _) = preview, internalApplicationCanDeliver {
            return ItemDropLocation(target: targetID, before: nil)
        }
        if preview == .none, !buttons.isEmpty {
            let candidates = buttons.sorted { $0.frame.minX < $1.frame.minX }
            if let target = candidates.first(where: { candidate in
                guard candidate.frame.contains(point) else { return false }
                return liftedSource == nil || (internalApplicationCanDeliver && candidate.entry.kind == .widget)
            }) {
                return ItemDropLocation(target: target.entry.id, before: nil)
            }
            let right = candidates.first { point.x < $0.frame.midX }
            return pinnedBoundaryClamp(ItemDropLocation(target: nil, before: right?.entry.id))
        }
        let layout = projected
        let origin = bounds.midX - CGFloat(layout.slots.count) * Layout.iconSlot / 2
        let overArtwork = abs(point.y - bounds.midY) <= Layout.iconSize / 2
        let hit = layout.hit(at: Double((point.x - origin) / Layout.iconSlot),
                             iconFraction: Double(Layout.iconSize / Layout.iconSlot),
                             allowsReceiving: liftedSource == nil && overArtwork)
        let lower = hit.lower.isFinite ? origin + CGFloat(hit.lower) * Layout.iconSlot : bounds.minX
        let upper = hit.upper.isFinite ? origin + CGFloat(hit.upper) * Layout.iconSlot : bounds.maxX
        let y = hit.location.target == nil ? bounds.minY : bounds.midY - Layout.iconSize / 2
        let height = hit.location.target == nil ? bounds.height : Layout.iconSize
        let location = pinnedBoundaryClamp(hit.location)
        hitLatch.capture(location, region: screenRect(NSRect(x: lower, y: y, width: max(0, upper - lower), height: height)))
        return location
    }

    /// 固定项的重排锚点不越过临时区：临时项恒居最右，
    /// 固定项落到临时区时收敛到临时区首项之前（固定项末位）。
    private func pinnedBoundaryClamp(_ location: ItemDropLocation) -> ItemDropLocation {
        guard location.target == nil,
              let sourceID = liftedSource,
              let source = buttons.first(where: { $0.entry.id == sourceID }),
              source.entry.isPinned else { return location }
        let tempIDs = buttons
            .filter { !$0.entry.isPinned }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.entry.id)
        return ItemDropLocation(target: nil,
                                before: ItemReorderBoundary.clampPinnedAnchor(location.before, temps: tempIDs))
    }

    private func screenRect(_ rect: NSRect) -> NSRect {
        let windowRect = convert(rect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    private func accommodateHitRegion() {
        switch preview {
        case .receive(let id, _):
            if let button = buttons.first(where: { $0.entry.id == id }) {
                hitLatch.accommodate(screenRect(NSRect(x: button.frame.midX - Layout.iconSize / 2,
                                                       y: bounds.midY - Layout.iconSize / 2,
                                                       width: Layout.iconSize, height: Layout.iconSize)))
            }
        case .reorder, .insert:
            hitLatch.accommodate(screenRect(placeholder.layer.frame))
        case .none: break
        }
    }

    func setActive(_ active: Bool) {
        for button in buttons { button.setActive(active) }
    }

    func refreshLayout() {
        for button in buttons + Array(departingButtons.values) {
            button.refreshLayout()
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func refreshAppearance() {
        for button in buttons + Array(departingButtons.values) {
            button.refreshAppearance()
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let layout = projected
        let dynamic = preview == .none
        let widths = dynamic ? buttons.map(\.preferredWidth) : Array(repeating: Layout.iconSlot, count: layout.slots.count)
        let total = widths.reduce(0, +)
        var cursor = (bounds.width - total) / 2
        let byID = Dictionary(uniqueKeysWithValues: buttons.map { ($0.entry.id, $0) })
        var placeholderFrame: NSRect?
        var count = 1
        for (index, slot) in layout.slots.enumerated() {
            let width = widths.indices.contains(index) ? widths[index] : Layout.iconSlot
            let frame = NSRect(x: cursor, y: 0, width: width, height: bounds.height)
            cursor += width
            switch slot {
            case .item(let id): byID[id]?.frame = frame
            case .placeholder(let amount, _):
                placeholderFrame = frame
                count = amount
                if case .reorder(let source, _) = preview { byID[source]?.frame = frame }
            }
        }
        placeholder.update(frame: placeholderFrame, count: count, appearance: effectiveAppearance,
                           scale: window?.backingScaleFactor ?? 2)
        accommodateHitRegion()
    }

    /// 涌潮波：自中心向两侧发散上涌，波窗封顶（Motion.waveStep）
    func waveIn() {
        alphaValue = 1
        let step = Motion.waveStep(count: buttons.count)
        let center = Double(buttons.count - 1) / 2
        for (index, button) in buttons.enumerated() {
            rise(button, delay: Motion.waveDelay + abs(Double(index) - center) * step)
        }
    }

    /// 退潮波：向中心汇聚下坠，外圈先离场（easeIn 加速离场）
    func waveOut() {
        let step = Motion.convergeStep(count: buttons.count)
        let center = Double(buttons.count - 1) / 2
        for (index, button) in buttons.enumerated() {
            let delay = abs(Double(index) - center) * step
            guard let layer = button.layer else { continue }
            if Motion.shouldReduceMotion {
                Motion.basic(layer, keyPath: "opacity", to: 0.0,
                             duration: Motion.reducedMotionFadeDuration, delay: delay)
            } else {
                Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                             duration: Motion.dropDuration, curve: .easeIn, delay: delay)
                Motion.basic(layer, keyPath: "opacity", to: 0.0,
                             duration: Motion.dropDuration, curve: .easeIn, delay: delay)
            }
        }
    }

    private func rise(_ button: ItemIconButton, delay: TimeInterval) {
        guard let layer = button.layer else { return }
        if Motion.shouldReduceMotion {
            Motion.basic(layer, keyPath: "opacity", from: Float(0), to: Float(1),
                         duration: Motion.reducedMotionFadeDuration, delay: delay)
            return
        }
        Motion.spring(layer, keyPath: "transform.translation.y", from: Motion.iconRiseOffset, to: CGFloat(0),
                      stiffness: Motion.iconRiseStiffness, damping: Motion.iconRiseDamping,
                      minDuration: Motion.iconRiseDuration, delay: delay)
        Motion.basic(layer, keyPath: "opacity", from: Float(0), to: Float(1),
                     duration: Motion.iconRiseDuration, delay: delay)
    }

    private func beginDeparture(_ button: ItemIconButton) {
        let identity = button.entry.id
        button.setHovered(false)
        departingButtons[identity] = button
        departureTokens[identity, default: 0] += 1
        let token = departureTokens[identity]
        let reduceMotion = Motion.shouldReduceMotion
        let duration = reduceMotion ? Motion.reducedMotionFadeDuration : Motion.dropDuration

        if let layer = button.layer {
            if !reduceMotion {
                Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                             duration: duration, curve: .easeIn)
                Motion.basic(layer, keyPath: "transform.scale", to: Motion.iconExitScale,
                             duration: duration, curve: .easeIn)
            }
            Motion.basic(layer, keyPath: "opacity", to: Float(0),
                         duration: duration, curve: .easeIn)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak button] in
            MainActor.assumeIsolated {
                guard let self, let button,
                      self.departureTokens[identity] == token,
                      self.departingButtons[identity] === button else { return }
                self.departingButtons.removeValue(forKey: identity)
                self.departureTokens.removeValue(forKey: identity)
                button.removeFromSuperview()
            }
        }
    }

    private func restoreForReuse(_ button: ItemIconButton) {
        guard let layer = button.layer else { return }
        layer.removeAnimation(forKey: "motion.transform.translation.x")
        layer.removeAnimation(forKey: "motion.transform.translation.y")
        layer.removeAnimation(forKey: "motion.transform.scale")
        layer.removeAnimation(forKey: "motion.opacity")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(CGFloat(0), forKeyPath: "transform.translation.x")
        layer.setValue(CGFloat(0), forKeyPath: "transform.translation.y")
        layer.setValue(CGFloat(1), forKeyPath: "transform.scale")
        layer.opacity = 1
        CATransaction.commit()
    }
}

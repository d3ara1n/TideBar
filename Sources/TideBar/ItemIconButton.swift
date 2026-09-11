import AppKit
import TideBarCore

/// 视觉子树不参与命中；事件始终由完整的 52pt 图标槽接收。
@MainActor
private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class IconArtworkView: NSView {
    var icon: NSImage {
        didSet {
            needsDisplay = true
            effect.update(icon: icon, state: dragState)
        }
    }
    private let effect = ItemDragIconEffect()
    private var dragState: ItemDragIconState = .idle

    init(icon: NSImage) {
        self.icon = icon
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(effect.layer)
    }

    func setDragState(_ state: ItemDragIconState) {
        dragState = state
        effect.update(icon: icon, state: state)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effect.layer.frame = NSRect(x: (bounds.width - Layout.iconSize) / 2,
                                   y: (bounds.height - Layout.iconSize) / 2,
                                   width: Layout.iconSize, height: Layout.iconSize)
        CATransaction.commit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let side = Layout.iconSize
        let rect = NSRect(x: (bounds.width - side) / 2,
                          y: (bounds.height - side) / 2,
                          width: side,
                          height: side)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

@MainActor
private final class HoverHaloView: PassthroughView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = AppearanceColors.cgColor(
            .labelColor, alpha: 0.12, for: effectiveAppearance
        )
        layer?.borderColor = AppearanceColors.cgColor(
            .labelColor, alpha: 0.52, for: effectiveAppearance
        )
    }
}

/// 图标右上角通知角标：数字胶囊 / 小圆点。出现与变化弹性轻弹，消失淡出。
/// 寄居 visualContainer，随悬停/按压的图标形变一起缩放（对齐 Dock 放大带角标的行为）。
@MainActor
private final class BadgeOverlayView: PassthroughView {
    private let capsule = CALayer()
    private let label = CATextLayer()
    private var value: BadgeValue?

    init(value: BadgeValue?) {
        self.value = value
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        capsule.backgroundColor = NSColor.systemRed.cgColor
        capsule.cornerCurve = .continuous
        capsule.opacity = value == nil ? 0 : 1
        label.alignmentMode = .center
        label.foregroundColor = NSColor.white.cgColor
        label.font = NSFont.systemFont(ofSize: Layout.badgeFontSize, weight: .semibold)
        label.fontSize = Layout.badgeFontSize
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        label.opacity = 0
        capsule.addSublayer(label)
        layer?.addSublayer(capsule)
        applyLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        applyLayout()
    }

    func update(_ newValue: BadgeValue?, animated: Bool) {
        guard newValue != value else { return }
        let removed = newValue == nil
        value = newValue
        applyLayout()
        guard animated else {
            setCapsuleOpacity(removed ? 0 : 1)
            return
        }
        if removed {
            Motion.basic(capsule, keyPath: "opacity", to: Float(0),
                         duration: Motion.badgeFadeDuration)
        } else {
            // 出现/变化弹性轻弹（与状态点数字同律）
            Motion.basic(capsule, keyPath: "opacity", from: Float(0), to: Float(1),
                         duration: Motion.badgePopDuration)
            Motion.spring(capsule, keyPath: "transform.scale", from: Motion.badgeAppearScale, to: CGFloat(1),
                          stiffness: Motion.badgeStiffness, damping: Motion.badgeDamping,
                          minDuration: Motion.badgePopDuration)
        }
    }

    /// 依当前值布置胶囊几何（数字宽度自适应；小圆点隐藏文字）
    private func applyLayout() {
        guard let value else { return }
        switch value {
        case .dot:
            let side = Layout.badgeDotSize
            label.opacity = 0
            capsule.frame = CGRect(x: bounds.width - side, y: bounds.height - side,
                                   width: side, height: side)
            capsule.cornerRadius = side / 2
        case .count(let count):
            let text = count > Layout.badgeCountCap ? "\(Layout.badgeCountCap)+" : "\(count)"
            label.string = text
            label.opacity = 1
            let width = max(Layout.badgeCapsuleMinWidth,
                            ceil(textWidth(for: text)) + Layout.badgeTextHInset * 2)
            capsule.frame = CGRect(x: bounds.width - width,
                                   y: bounds.height - Layout.badgeCapsuleHeight,
                                   width: width, height: Layout.badgeCapsuleHeight)
            capsule.cornerRadius = Layout.badgeCapsuleHeight / 2
            label.frame = capsule.bounds.insetBy(dx: 0, dy: 0.5)
        }
    }

    private func textWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: Layout.badgeFontSize, weight: .semibold)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return attributed.size().width
    }

    private func setCapsuleOpacity(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capsule.opacity = opacity
        CATransaction.commit()
    }
}

/// 条目图标：通用引用交互；窗口点、角标与潮涌只消费关联的应用状态。
@MainActor
final class ItemIconButton: NSView {
    private(set) var entry: ItemEntry
    var preferredWidth: CGFloat { customArtworkView?.preferredWidth ?? entry.preferredBarWidth ?? Layout.iconSlot }
    var onClick: ((ItemEntry) -> Void)?
    /// 调用方拥有拖拽 source；按钮只处理手势，不承载跨收起／重建的会话。
    var onBeginDrag: ((ItemIconButton, NSEvent) -> Bool)?
    var onSetHidden: ((AppIdentity, Bool) -> Void)?
    var onTerminate: ((AppIdentity) -> Void)?
    var onSetPinned: ((ItemID, Bool) -> Void)?
    /// 潮涌触发，携图标 frame（位于 ItemRowView 坐标系，即面板内容坐标）
    var onSurge: ((ItemEntry, NSRect) -> Void)?
    /// 小工具右键菜单的「移除小工具」；执行方负责确认弹窗
    var onRemoveWidget: ((ItemEntry) -> Void)?

    private enum VisualTransition {
        case enter
        case exit
        case press
    }

    /// 左下角 transform 原点放在图标底边中心；视觉内容相对它向左右各展开一半。
    private let motionPivot = PassthroughView(frame: .zero)
    private let visualContainer = PassthroughView(frame: .zero)
    private let haloView = HoverHaloView(frame: .zero)
    private let artworkView: IconArtworkView
    private let customArtworkView: AnyBarArtwork?
    private let statusIndicatorView: AppStatusIndicatorView
    private let badgeView: BadgeOverlayView
    private var dragState: ItemDragIconState = .idle
    /// 自定义 artwork 可关闭共享悬停特效（浮起/压下/光晕），完全自绘反馈
    private var usesSharedHoverEffects: Bool { customArtworkView?.usesSharedHoverEffects ?? true }
    private var hovering = false
    private var keyboardSelected = false
    private var pressed = false
    private var pressTimer: Timer?
    private var surged = false
    private var mouseDownScreenPoint: NSPoint?
    private var dragAttempted = false
    /// 菜单追踪期间的靶对象持有（NSMenuItem 不保留 target）
    private var menuActions: [MenuAction] = []

    init(entry: ItemEntry) {
        self.entry = entry
        self.artworkView = IconArtworkView(icon: entry.icon)
        self.customArtworkView = entry.kind == .widget
            ? ItemBehaviors.provider(for: entry)?.barArtwork(for: entry) : nil
        self.statusIndicatorView = AppStatusIndicatorView(entry: entry.application)
        self.badgeView = BadgeOverlayView(value: entry.badge)
        super.init(frame: NSRect(x: 0, y: 0, width: entry.preferredBarWidth ?? Layout.iconSlot, height: Layout.expandedHeight))
        wantsLayer = true   // 根层只承担整栏错峰升降，hover 使用独立视觉层避免 transform 争用
        motionPivot.wantsLayer = true
        motionPivot.layer?.masksToBounds = false
        visualContainer.wantsLayer = true
        artworkView.wantsLayer = true
        visualContainer.addSubview(haloView)
        visualContainer.addSubview(artworkView)
        if let customArtworkView { visualContainer.addSubview(customArtworkView) }
        visualContainer.addSubview(badgeView)
        artworkView.isHidden = customArtworkView != nil
        statusIndicatorView.isHidden = customArtworkView != nil
        badgeView.isHidden = customArtworkView != nil
        motionPivot.addSubview(visualContainer)
        addSubview(statusIndicatorView)
        addSubview(motionPivot)
        haloView.layer?.opacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 就地刷新条目（运行状态、图标、点点、角标变化），不动视图身份与交互状态
    func update(entry newEntry: ItemEntry) {
        guard newEntry.id == entry.id else { return }
        let iconChanged = !newEntry.icon.isEqual(entry.icon)
        let statusChanged = newEntry.application?.isRunning != entry.application?.isRunning
            || newEntry.application?.dotSignature != entry.application?.dotSignature
        let badgeChanged = newEntry.badge != entry.badge
        entry = newEntry
        if iconChanged { artworkView.icon = newEntry.icon }
        customArtworkView?.update(entry: newEntry)
        statusIndicatorView.update(entry: newEntry.application, animated: statusChanged)
        if badgeChanged { badgeView.update(newEntry.badge, animated: true) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 拖拽跟随图：自定义 artwork（widget 缩略网格等）截取当前展示，普通条目退回图标。
    func dragPreviewImage() -> NSImage {
        guard let customArtworkView else { return entry.icon }
        let side = Layout.iconSize
        let rect = NSRect(x: (customArtworkView.bounds.width - side) / 2,
                          y: (customArtworkView.bounds.height - side) / 2,
                          width: side, height: side)
        guard rect.intersects(customArtworkView.bounds),
              let rep = customArtworkView.bitmapImageRepForCachingDisplay(in: rect) else { return entry.icon }
        customArtworkView.cacheDisplay(in: rect, to: rep)
        guard let cgImage = rep.cgImage else { return entry.icon }
        return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
    }

    func setActive(_ active: Bool) {
        customArtworkView?.setActive(active)
    }

    func refreshLayout() {
        needsLayout = true
    }

    func refreshAppearance() {
        haloView.refreshAppearance()
    }

    override func layout() {
        super.layout()
        statusIndicatorView.frame = bounds
        let side = customArtworkView == nil ? Layout.iconVisualSide : max(bounds.height - 8, 1)
        let contentWidth = customArtworkView == nil ? side : min(bounds.width, preferredWidth)
        motionPivot.frame = NSRect(x: bounds.midX,
                                   y: (bounds.height - side) / 2,
                                   width: 1,
                                   height: 1)
        visualContainer.frame = NSRect(x: -contentWidth / 2,
                                       y: 0,
                                       width: contentWidth,
                                       height: side)
        haloView.frame = visualContainer.bounds
        artworkView.frame = visualContainer.bounds
        customArtworkView?.frame = visualContainer.bounds
        badgeView.frame = visualContainer.bounds
    }

    /// 悬停态由控制器鼠标采样轮询驱动：非激活悬浮窗上 tracking area 的
    /// entered/exited 合成不可靠（有状态机失步案例），改用确定性命中测试。
    func setDragState(_ state: ItemDragIconState) {
        guard dragState != state else { return }
        dragState = state
        isHidden = state == .lifted
        if state.suppressesHover {
            hovering = false
            pressed = false
        }
        artworkView.setDragState(state)
        animateVisualState(.exit)
    }

    func setHovered(_ on: Bool) {
        guard !dragState.suppressesHover, hovering != on else { return }
        hovering = on
        animateVisualState(on ? .enter : .exit)
    }

    func setKeyboardSelected(_ on: Bool) {
        guard keyboardSelected != on else { return }
        keyboardSelected = on
        customArtworkView?.setHighlightState(hovered: hovering, selected: keyboardSelected)
        guard usesSharedHoverEffects, !dragState.suppressesHover, let layer = haloView.layer else { return }
        let opacity: Float = on ? 0.72 : (hovering ? (pressed ? 0.82 : 1) : 0)
        Motion.basic(layer, keyPath: "opacity", to: opacity,
                     duration: Motion.shouldReduceMotion ? Motion.reducedMotionFadeDuration : Motion.hoverEnterDuration)
    }

    private func animateVisualState(_ transition: VisualTransition) {
        customArtworkView?.setHighlightState(hovered: hovering, selected: keyboardSelected)
        guard let visualLayer = motionPivot.layer, let haloLayer = haloView.layer else { return }
        if dragState.suppressesHover {
            ItemDragStyle.suppressHover(pivot: visualLayer, halo: haloLayer)
            return
        }
        let haloOpacity: Float = usesSharedHoverEffects
            ? (hovering ? (pressed ? 0.82 : 1) : (keyboardSelected ? 0.72 : 0)) : 0

        if Motion.shouldReduceMotion {
            visualLayer.removeAnimation(forKey: "motion.transform.translation.y")
            visualLayer.removeAnimation(forKey: "motion.transform.scale")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            visualLayer.setValue(0, forKeyPath: "transform.translation.y")
            visualLayer.setValue(1, forKeyPath: "transform.scale")
            CATransaction.commit()
            Motion.basic(visualLayer, keyPath: "opacity", to: pressed ? Float(0.82) : Float(1),
                         duration: Motion.pressDuration)
            Motion.basic(haloLayer, keyPath: "opacity", to: haloOpacity,
                         duration: Motion.hoverExitDuration)
            return
        }

        Motion.basic(visualLayer, keyPath: "opacity", to: Float(1),
                     duration: Motion.pressDuration)
        let offset: CGFloat
        let scale: CGFloat
        switch transition {
        case .enter:
            offset = usesSharedHoverEffects ? Motion.hoverLift : 0
            scale = usesSharedHoverEffects ? Motion.hoverScale : 1
            Motion.spring(visualLayer, keyPath: "transform.translation.y", to: offset,
                          stiffness: Motion.hoverStiffness, damping: Motion.hoverDamping,
                          minDuration: Motion.hoverEnterDuration)
            Motion.spring(visualLayer, keyPath: "transform.scale", to: scale,
                          stiffness: Motion.hoverStiffness, damping: Motion.hoverDamping,
                          minDuration: Motion.hoverEnterDuration)
            Motion.basic(haloLayer, keyPath: "opacity", to: haloOpacity,
                         duration: Motion.hoverEnterDuration)
        case .exit:
            offset = 0
            scale = 1
            Motion.basic(visualLayer, keyPath: "transform.translation.y", to: offset,
                         duration: Motion.hoverExitDuration, curve: .easeIn)
            Motion.basic(visualLayer, keyPath: "transform.scale", to: scale,
                         duration: Motion.hoverExitDuration, curve: .easeIn)
            Motion.basic(haloLayer, keyPath: "opacity", to: haloOpacity,
                         duration: Motion.hoverExitDuration, curve: .easeIn)
        case .press:
            offset = usesSharedHoverEffects ? Motion.pressOffset : 0
            scale = usesSharedHoverEffects ? Motion.pressScale : 1
            Motion.basic(visualLayer, keyPath: "transform.translation.y", to: offset,
                         duration: Motion.pressDuration)
            Motion.basic(visualLayer, keyPath: "transform.scale", to: scale,
                         duration: Motion.pressDuration)
            Motion.basic(haloLayer, keyPath: "opacity", to: haloOpacity,
                         duration: Motion.pressDuration)
        }
    }

    override func mouseDown(with event: NSEvent) {
        hovering = true
        pressed = true
        surged = false
        dragAttempted = false
        mouseDownScreenPoint = window?.convertPoint(toScreen: event.locationInWindow)
        animateVisualState(.press)
        // 无潮涌体的条目没有长按；拖拽仍使用同一阈值手势。
        guard entry.canSurge else { return }
        // 长按计时：期内松开视为点击，超时触发潮涌并吞掉本次点击
        pressTimer = Timer.scheduledTimer(withTimeInterval: Layout.surgePressDelay, repeats: false) { [weak self] _ in
            MainThreadBridge { [weak self] in
                guard let self else { return }
                self.pressTimer = nil
                self.surged = true
                self.pressed = false
                self.animateVisualState(.enter)
                self.onSurge?(self.entry, self.frame)
            }.call()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragAttempted else { return }
        if !surged, let origin = mouseDownScreenPoint,
           let point = window?.convertPoint(toScreen: event.locationInWindow),
           hypot(point.x - origin.x, point.y - origin.y) >= Layout.itemDragThreshold,
           let onBeginDrag {
            // 重排对所有条目一致；widget 的添加/移除仍归设置页。
            // 先撤销长按和点击，再进入可能嵌套事件追踪的 AppKit 拖拽调用。
            dragAttempted = true
            pressTimer?.invalidate()
            pressTimer = nil
            pressed = false
            hovering = false
            animateVisualState(.exit)
            _ = onBeginDrag(self, event)
            return
        }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if pressed != inside || hovering != inside {
            pressed = inside
            hovering = inside
            if !inside {
                pressTimer?.invalidate()
                pressTimer = nil
            }
            animateVisualState(inside ? .press : .exit)
        }
    }

    override func mouseUp(with event: NSEvent) {
        pressTimer?.invalidate()
        pressTimer = nil
        let wasPressed = pressed
        pressed = false
        hovering = bounds.contains(convert(event.locationInWindow, from: nil))
        animateVisualState(hovering ? .enter : .exit)
        mouseDownScreenPoint = nil
        guard wasPressed, hovering, !surged, !dragAttempted else { return }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option), entry.canSurge {
            onSurge?(entry, frame)
        } else {
            onClick?(entry)
        }
    }

    // MARK: 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        if entry.kind == .widget { return widgetMenu() }
        let menu = NSMenu()
        menuActions.removeAll()
        let identity = entry.id

        if entry.canPin {
            let pin = NSMenuItem(title: entry.isPinned
                                 ? L10nManager.shared.current.string("appMenu.unpin", table: .menus)
                                 : L10nManager.shared.current.string("appMenu.pin", table: .menus),
                                 action: #selector(MenuAction.run),
                                 keyEquivalent: "")
            let shouldPin = !entry.isPinned
            let setPinned = onSetPinned
            let pinAction = MenuAction(pin.title) { setPinned?(identity, shouldPin) }
            menuActions.append(pinAction)
            pin.target = pinAction
            menu.addItem(pin)
        }

        if entry.isAvailable, entry.capabilities.contains(.reveal) {
            let reveal = NSMenuItem(title: L10nManager.shared.current.string("appMenu.revealInFinder", table: .menus),
                                    action: #selector(MenuAction.run),
                                    keyEquivalent: "")
            let item = entry
            let action = MenuAction(reveal.title) { item.reveal() }
            menuActions.append(action)
            reveal.target = action
            menu.addItem(reveal)
        }
        menu.addItem(.separator())

        if let app = entry.application, app.isRunning {
            let shouldHide = !app.isHidden
            let visibility = NSMenuItem(title: shouldHide
                                        ? L10nManager.shared.current.string("appMenu.hide", table: .menus)
                                        : L10nManager.shared.current.string("appMenu.show", table: .menus),
                                        action: #selector(MenuAction.run),
                                        keyEquivalent: shouldHide ? "h" : "")
            if shouldHide { visibility.keyEquivalentModifierMask = .command }
            let setHidden = onSetHidden
            let action = MenuAction(visibility.title) { setHidden?(app.id, shouldHide) }
            menuActions.append(action)
            visibility.target = action
            menu.addItem(visibility)
        } else if entry.capabilities.contains(.open) {
            let open = NSMenuItem(title: L10nManager.shared.current.string("appMenu.open", table: .menus), action: #selector(MenuAction.run), keyEquivalent: "")
            let entry = entry
            let launch = onClick
            let action = MenuAction(open.title) { launch?(entry) }
            menuActions.append(action)
            open.target = action
            menu.addItem(open)
        }

        if let app = entry.application, app.canTerminate, app.isRunning {
            let quit = NSMenuItem(title: L10nManager.shared.current.string("appMenu.quit", table: .menus), action: #selector(MenuAction.run), keyEquivalent: "q")
            quit.keyEquivalentModifierMask = .command
            let terminate = onTerminate
            let action = MenuAction(quit.title) { terminate?(app.id) }
            menuActions.append(action)
            quit.target = action
            menu.addItem(quit)
        }
        return menu
    }

    /// 小工具菜单：类型自定义项在前，末位恒为「移除小工具」（移除执行方负责确认）。
    private func widgetMenu() -> NSMenu {
        let menu = NSMenu()
        menuActions.removeAll()
        if let provider = ItemBehaviors.provider(for: entry) {
            for action in provider.menuActions(for: entry) {
                let item = NSMenuItem(title: action.title,
                                      action: #selector(MenuAction.run), keyEquivalent: "")
                menuActions.append(action)
                item.target = action
                menu.addItem(item)
            }
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let entry = self.entry
        let removeHandler = onRemoveWidget
        let remove = MenuAction(L10nManager.shared.current.string("widgetMenu.remove", table: .menus)) {
            removeHandler?(entry)
        }
        let item = NSMenuItem(title: remove.title, action: #selector(MenuAction.run), keyEquivalent: "")
        menuActions.append(remove)
        item.target = remove
        menu.addItem(item)
        return menu
    }
}

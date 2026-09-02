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
        didSet { needsDisplay = true }
    }

    init(icon: NSImage) {
        self.icon = icon
        super.init(frame: .zero)
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

    private func updateAppearance() {
        let tone = NSColor.labelColor
        layer?.backgroundColor = tone.withAlphaComponent(0.12).cgColor
        layer?.borderColor = tone.withAlphaComponent(0.52).cgColor
    }
}

/// 展开态的单个 app 图标：悬停高亮 + 点点（窗口状态）+ 点击启动/切换/还原
@MainActor
final class AppIconButton: NSView {
    private(set) var entry: AppEntry
    var onClick: ((AppEntry) -> Void)?
    var onHide: ((AppIdentity) -> Void)?
    var onTerminate: ((AppIdentity) -> Void)?
    var onSetPinned: ((AppIdentity, Bool) -> Void)?
    /// 潮涌触发，携图标 frame（位于 IconRowView 坐标系，即面板内容坐标）
    var onSurge: ((AppEntry, NSRect) -> Void)?

    private enum VisualTransition {
        case enter
        case exit
        case press
    }

    private static let visualSide: CGFloat = 46
    /// 左下角 transform 原点放在图标底边中心；视觉内容相对它向左右各展开一半。
    private let motionPivot = PassthroughView(frame: .zero)
    private let visualContainer = PassthroughView(frame: .zero)
    private let haloView = HoverHaloView(frame: .zero)
    private let artworkView: IconArtworkView
    private var hovering = false
    private var pressed = false
    private var pressTimer: Timer?
    private var surged = false
    /// 菜单追踪期间的靶对象持有（NSMenuItem 不保留 target）
    private var menuActions: [MenuAction] = []

    init(entry: AppEntry) {
        self.entry = entry
        self.artworkView = IconArtworkView(icon: entry.icon)
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.iconSlot, height: Layout.expandedHeight))
        wantsLayer = true   // 根层只承担整栏错峰升降，hover 使用独立视觉层避免 transform 争用
        motionPivot.wantsLayer = true
        motionPivot.layer?.masksToBounds = false
        visualContainer.wantsLayer = true
        artworkView.wantsLayer = true
        visualContainer.addSubview(haloView)
        visualContainer.addSubview(artworkView)
        motionPivot.addSubview(visualContainer)
        addSubview(motionPivot)
        haloView.layer?.opacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 就地刷新条目（运行状态、图标、点点变化），不动视图身份与交互状态
    func update(entry newEntry: AppEntry) {
        guard newEntry.id == entry.id else { return }
        let iconChanged = !newEntry.icon.isEqual(entry.icon)
        let redraw = newEntry.isRunning != entry.isRunning
            || newEntry.dotSignature != entry.dotSignature
        entry = newEntry
        if iconChanged { artworkView.icon = newEntry.icon }
        if redraw { needsDisplay = true }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let side = Self.visualSide
        motionPivot.frame = NSRect(x: bounds.midX,
                                   y: (bounds.height - side) / 2,
                                   width: 1,
                                   height: 1)
        visualContainer.frame = NSRect(x: -side / 2,
                                       y: 0,
                                       width: side,
                                       height: side)
        haloView.frame = visualContainer.bounds
        artworkView.frame = visualContainer.bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        // 运行短线和窗口点不跟随 hover 缩放，保证状态信息稳定。
        drawWindowDots()
        drawRunningWithoutWindowsIndicator()
    }

    /// 点点：实心=活跃窗口、空心=最小化，>5 收敛为数字。
    private func drawWindowDots() {
        guard entry.isRunning, let windows = entry.windows, !windows.isEmpty else { return }
        let active = windows.filter { !$0.isMinimized }.count

        if windows.count > 5 {
            let text = "\(windows.count)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 2.5), withAttributes: attributes)
            return
        }

        let mini = windows.count - active
        let total = CGFloat(active + mini - 1) * Layout.dotPitch + Layout.dotSize
        var x = bounds.midX - total / 2
        for index in 0..<(active + mini) {
            let rect = NSRect(x: x, y: Layout.dotBaseline,
                              width: Layout.dotSize, height: Layout.dotSize)
            // 单一强调色：实心=活跃窗口，空心=最小化窗口；不叠加黑白轮廓，避免视觉刺眼。
            drawIndicator(in: rect, filled: index < active)
            x += Layout.dotPitch
        }
    }

    /// AX 未知与已知零窗口均没有可绘制窗口点，以短线明确表达进程仍在运行。
    private func drawRunningWithoutWindowsIndicator() {
        guard entry.isRunning else { return }
        if let windows = entry.windows, !windows.isEmpty { return }

        let rect = NSRect(x: bounds.midX - Layout.runningDashWidth / 2,
                          y: Layout.dotBaseline + (Layout.dotSize - Layout.runningDashHeight) / 2,
                          width: Layout.runningDashWidth,
                          height: Layout.runningDashHeight)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: Layout.runningDashHeight / 2,
                                yRadius: Layout.runningDashHeight / 2)
        NSColor.labelColor.withAlphaComponent(0.78).setFill()
        path.fill()
    }

    private func drawIndicator(in rect: NSRect, filled: Bool) {
        let tone = NSColor.labelColor
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 1.1
        if filled {
            tone.setFill()
            path.fill()
        }
        tone.setStroke()
        path.stroke()
    }

    /// 悬停态由控制器鼠标采样轮询驱动：非激活悬浮窗上 tracking area 的
    /// entered/exited 合成不可靠（有状态机失步案例），改用确定性命中测试。
    func setHovered(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        animateVisualState(on ? .enter : .exit)
    }

    private func animateVisualState(_ transition: VisualTransition) {
        guard let visualLayer = motionPivot.layer, let haloLayer = haloView.layer else { return }
        let haloOpacity: Float = hovering ? (pressed ? 0.82 : 1) : 0

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
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
            offset = Motion.hoverLift
            scale = Motion.hoverScale
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
            offset = Motion.pressOffset
            scale = Motion.pressScale
            Motion.basic(visualLayer, keyPath: "transform.translation.y", to: offset,
                         duration: Motion.pressDuration)
            Motion.basic(visualLayer, keyPath: "transform.scale", to: scale,
                         duration: Motion.pressDuration)
            Motion.basic(haloLayer, keyPath: "opacity", to: haloOpacity,
                         duration: Motion.pressDuration)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        hovering = true
        pressed = true
        surged = false
        animateVisualState(.press)
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
        guard wasPressed, hovering, !surged else { return }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) {
            onSurge?(entry, frame)
        } else {
            onClick?(entry)
        }
    }

    // MARK: 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menuActions.removeAll()

        if let windows = entry.windows, !windows.isEmpty {
            var addedWindow = false
            for (index, window) in windows.enumerated() {
                guard let app = entry.runningApp(for: window) else { continue }
                let item = NSMenuItem(title: window.title ?? "窗口 \(index + 1)",
                                      action: #selector(MenuAction.run),
                                      keyEquivalent: "")
                let action = MenuAction { AXReader.raise(window, app: app) }
                menuActions.append(action)
                item.target = action
                menu.addItem(item)
                addedWindow = true
            }
            if addedWindow { menu.addItem(.separator()) }
        }
        if entry.isRunning {
            let hide = NSMenuItem(title: "隐藏", action: #selector(MenuAction.run), keyEquivalent: "h")
            hide.keyEquivalentModifierMask = .command
            let identity = entry.identity
            let requestHide = onHide
            let action = MenuAction { requestHide?(identity) }
            menuActions.append(action)
            hide.target = action
            menu.addItem(hide)
        } else {
            let open = NSMenuItem(title: "打开", action: #selector(MenuAction.run), keyEquivalent: "")
            let entry = entry
            let launch = onClick
            let action = MenuAction { launch?(entry) }
            menuActions.append(action)
            open.target = action
            menu.addItem(open)
        }

        let pin = NSMenuItem(title: entry.isPinned ? "取消固定" : "固定到 TideBar",
                             action: #selector(MenuAction.run),
                             keyEquivalent: "")
        let identity = entry.identity
        let shouldPin = !entry.isPinned
        let setPinned = onSetPinned
        let pinAction = MenuAction { setPinned?(identity, shouldPin) }
        menuActions.append(pinAction)
        pin.target = pinAction
        menu.addItem(pin)

        if entry.canTerminate, entry.runningApp != nil {
            let quit = NSMenuItem(title: "退出", action: #selector(MenuAction.run), keyEquivalent: "q")
            quit.keyEquivalentModifierMask = .command
            let identity = entry.identity
            let terminate = onTerminate
            let action = MenuAction { terminate?(identity) }
            menuActions.append(action)
            quit.target = action
            menu.addItem(quit)
        }
        if let url = entry.applicationURL {
            let reveal = NSMenuItem(title: "在 Finder 中显示",
                                    action: #selector(MenuAction.run),
                                    keyEquivalent: "")
            let action = MenuAction { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            menuActions.append(action)
            reveal.target = action
            menu.addItem(reveal)
        }
        return menu
    }
}

/// 菜单项闭包靶：菜单追踪期间由按钮持有（NSMenuItem 不保留 target）
@MainActor
private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

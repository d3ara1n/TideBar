import AppKit

/// 展开态的单个 app 图标：悬停高亮 + 点点（窗口状态）+ 点击启动/切换/还原
@MainActor
final class AppIconButton: NSView {
    private(set) var entry: AppEntry
    var onClick: ((AppEntry) -> Void)?
    /// 潮涌触发，携图标 frame（位于 IconRowView 坐标系，即面板内容坐标）
    var onSurge: ((AppEntry, NSRect) -> Void)?

    private var hovering = false
    private var pressed = false
    private var pressTimer: Timer?
    private var surged = false
    /// 菜单追踪期间的靶对象持有（NSMenuItem 不保留 target）
    private var menuActions: [MenuAction] = []

    init(entry: AppEntry) {
        self.entry = entry
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.iconSlot, height: Layout.expandedHeight))
        wantsLayer = true   // 错峰升起动画走 layer transform/opacity
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 就地刷新条目（运行状态、图标、点点变化），不动视图身份与交互状态
    func update(entry newEntry: AppEntry) {
        guard newEntry.id == entry.id else { return }
        if newEntry.isRunning != entry.isRunning || newEntry.icon !== entry.icon
            || newEntry.dotSignature != entry.dotSignature {
            entry = newEntry
            needsDisplay = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let lift: CGFloat = pressed ? -1 : (hovering ? 2 : 0)
        // 图标纵向居中（Dock 同款），运行点在图标下方近底边
        let iconSide = Layout.iconSize
        let iconY = (bounds.height - iconSide) / 2 + lift
        if hovering {
            let circle = NSBezierPath(ovalIn: NSRect(x: (bounds.width - 46) / 2,
                                                     y: (bounds.height - 46) / 2,
                                                     width: 46, height: 46))
            // Clear 玻璃保持可读性，hover 回归系统语义黑白色。
            let tone = NSColor.labelColor
            tone.withAlphaComponent(0.12).setFill()
            circle.fill()
            tone.withAlphaComponent(0.52).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
        let iconRect = NSRect(x: (bounds.width - iconSide) / 2,
                              y: iconY,
                              width: iconSide,
                              height: iconSide)
        entry.icon.draw(in: iconRect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1)
        drawWindowDots()
    }

    /// 点点：实心=活跃窗口、空心=最小化，>5 收敛为数字；
    /// 无 AX 信息或零收录窗口不画（降级/零窗口与 Dock 语义一致：不误导）
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
    /// entered/exited 合成不可靠（有状态机失步案例），改用确定性命中测试
    func setHovered(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        surged = false
        needsDisplay = true
        // 长按计时：期内松开视为点击，超时触发潮涌并吞掉本次点击
        pressTimer = Timer.scheduledTimer(withTimeInterval: Layout.surgePressDelay, repeats: false) { [weak self] _ in
            MainThreadBridge { [weak self] in
                guard let self else { return }
                self.pressTimer = nil
                self.surged = true
                self.pressed = false
                self.needsDisplay = true
                self.onSurge?(self.entry, self.frame)
            }.call()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if pressed != inside {
            pressed = inside
            if !inside {
                pressTimer?.invalidate()
                pressTimer = nil
            }
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        pressTimer?.invalidate()
        pressTimer = nil
        let wasPressed = pressed
        pressed = false
        hovering = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
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

        if let windows = entry.windows, let app = entry.runningApp, !windows.isEmpty {
            for (index, window) in windows.enumerated() {
                let item = NSMenuItem(title: window.title ?? "窗口 \(index + 1)",
                                      action: #selector(MenuAction.run),
                                      keyEquivalent: "")
                let action = MenuAction { AXReader.raise(window, app: app) }
                menuActions.append(action)
                item.target = action
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        if let app = entry.runningApp {
            let quit = NSMenuItem(title: "退出", action: #selector(MenuAction.run), keyEquivalent: "q")
            quit.keyEquivalentModifierMask = .command
            let action = MenuAction { _ = app.terminate() }
            menuActions.append(action)
            quit.target = action
            menu.addItem(quit)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.id) {
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

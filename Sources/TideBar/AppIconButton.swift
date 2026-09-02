import AppKit

/// 展开态的单个 app 图标：悬停高亮 + 运行指示点 + 点击启动/激活
@MainActor
final class AppIconButton: NSView {
    private(set) var entry: AppEntry
    var onClick: ((AppEntry) -> Void)?

    private var hovering = false
    private var pressed = false

    init(entry: AppEntry) {
        self.entry = entry
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.iconSlot, height: Layout.expandedHeight))
        wantsLayer = true   // 错峰升起动画走 layer transform/opacity
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 就地刷新条目（运行状态翻转、图标更换），不动视图身份与交互状态
    func update(entry newEntry: AppEntry) {
        guard newEntry.id == entry.id else { return }
        if newEntry.isRunning != entry.isRunning || newEntry.icon !== entry.icon {
            entry = newEntry
            needsDisplay = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let onGlass = BarBackgroundFactory.usesGlass
        let lift: CGFloat = pressed ? -1 : (hovering ? 2 : 0)
        if hovering {
            let circle = NSBezierPath(ovalIn: NSRect(x: (bounds.width - 46) / 2, y: 13, width: 46, height: 46))
            if onGlass {
                // 玻璃底随亮暗自动翻转
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
                circle.fill()
            } else {
                NSColor.white.withAlphaComponent(0.14).setFill()
                circle.fill()
                NSColor.black.withAlphaComponent(0.18).setStroke()
                circle.lineWidth = 1
                circle.stroke()
            }
        }
        let iconSide = Layout.iconSize
        let iconRect = NSRect(x: (bounds.width - iconSide) / 2,
                              y: 17 + lift,
                              width: iconSide,
                              height: iconSide)
        entry.icon.draw(in: iconRect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1)
        if entry.isRunning {
            let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 2.25, y: 7, width: 4.5, height: 4.5))
            if onGlass {
                // 玻璃底：运行点随亮暗模式自动翻转（亮=深色点，暗=白点）
                NSColor.labelColor.setFill()
                dot.fill()
            } else {
                // 深色胶囊底：恒白 + 暗描边
                NSColor.white.withAlphaComponent(0.95).setFill()
                dot.fill()
                NSColor.black.withAlphaComponent(0.35).setStroke()
                dot.lineWidth = 1
                dot.stroke()
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways,
                                                 .inVisibleRect, .enabledDuringMouseDrag],
                                       owner: self,
                                       userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if pressed != inside {
            pressed = inside
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressed
        pressed = false
        hovering = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
        if wasPressed, hovering {
            onClick?(entry)
        }
    }
}

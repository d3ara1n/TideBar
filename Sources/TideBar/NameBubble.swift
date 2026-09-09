import AppKit

/// 名字气泡内容：玻璃底 + 名字文本；文本超宽时在泡内往返滚动。
/// 悬停名的唯一展示载体（所有条目通用），替代系统 tooltip。
@MainActor
final class NameBubbleView: NSView {
    private let glass: NSView?
    private let label: ItemNameLabelView

    static var preferredHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: Layout.nameBubbleFontSize)
        return ceil(font.ascender - font.descender) + Layout.nameBubblePaddingY * 2
    }

    static func preferredWidth(for name: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: Layout.nameBubbleFontSize)
        let textWidth = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        return min(textWidth + Layout.nameBubblePaddingX * 2, Layout.nameBubbleMaxWidth)
    }

    private static func labelFont() -> NSFont {
        NSFont.systemFont(ofSize: Layout.nameBubbleFontSize)
    }

    private static func labelColor() -> NSColor {
        BarBackgroundFactory.usesGlass ? .labelColor : NSColor.white.withAlphaComponent(0.92)
    }

    init(name: String) {
        glass = BarBackgroundFactory.makeGlassIfAvailable(cornerRadius: 10)
        label = ItemNameLabelView(name: name, font: Self.labelFont(), color: Self.labelColor())
        super.init(frame: .zero)
        wantsLayer = true
        if let glass { addSubview(glass) }
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        glass?.frame = bounds
        label.frame = bounds.insetBy(dx: Layout.nameBubblePaddingX, dy: Layout.nameBubblePaddingY)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 玻璃路径材质自绘背景；仅旧系统回退时手绘深色卡
        guard glass == nil else { return }
        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.55).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()
    }

    func update(name: String) {
        label.update(name: name)
    }

    /// 泡可见期间允许跑马灯；离场即停
    func setScrollingAllowed(_ allowed: Bool) {
        label.setScrollingAllowed(allowed)
    }
}

/// 名字气泡宿主：与潮涌同款窗口约束；纯展示，不接鼠标事件
/// （悬停判定由控制器的鼠标采样驱动，气泡自身不得截胡命中）。
@MainActor
final class NameBubblePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
}

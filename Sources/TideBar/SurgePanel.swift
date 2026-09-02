import AppKit
import ApplicationServices

// MARK: - 行

/// 潮涌列表项：窗口标题 + 文档图标（回退 app 图标）；最小化/他屏暗显。
/// 悬停态由控制器鼠标采样轮询驱动（tracking area 在非激活悬浮窗上不可靠）。
@MainActor
final class SurgeRowView: NSView {
    private let snapshot: WindowSnapshot
    private let icon: NSImage
    private let title: String
    private var hovering = false

    var onPick: ((WindowSnapshot) -> Void)?

    init(snapshot: WindowSnapshot, appIcon: NSImage, dimmed: Bool) {
        self.snapshot = snapshot
        self.title = snapshot.title ?? "窗口"
        self.icon = Self.icon(for: snapshot.document, appIcon: appIcon)
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.surgeWidth, height: Layout.surgeRowHeight))
        wantsLayer = true
        alphaValue = dimmed ? 0.45 : 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// kAXDocument → 文档图标；非文件路径/不存在则回退 app 图标
    private static func icon(for document: String?, appIcon: NSImage) -> NSImage {
        guard let document else { return appIcon }
        let path = document.hasPrefix("file://") ? URL(string: document)?.path : document
        guard let path, path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { return appIcon }
        return NSWorkspace.shared.icon(forFile: path)
    }

    func setHovered(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let onGlass = BarBackgroundFactory.usesGlass
        if hovering {
            let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 6, yRadius: 6)
            if onGlass {
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.14).setFill()
            }
            highlight.fill()
        }
        let side: CGFloat = 18
        let iconRect = NSRect(x: 14, y: (bounds.height - side) / 2, width: side, height: side)
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleColor: NSColor = onGlass ? .labelColor : NSColor.white.withAlphaComponent(0.92)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: titleColor,
            .paragraphStyle: paragraph,
        ]
        let titleRect = NSRect(x: iconRect.maxX + 10, y: (bounds.height - 17) / 2,
                               width: bounds.width - iconRect.maxX - 24, height: 17)
        (title as NSString).draw(in: titleRect, withAttributes: attributes)
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onPick?(snapshot)
        }
    }
}

// MARK: - 列表（decisions 命名 SurgeView）

/// 潮涌窗口列表：本屏正常 → 他屏暗显 → 最小化暗显；行自图标侧（下）错峰升起。
/// macOS 26 用液态玻璃底（与图标栏同材质），旧系统回退深色胶囊卡。
@MainActor
final class SurgeView: NSView {
    var onPick: ((WindowSnapshot) -> Void)?
    private let glass: NSView?

    init(windows: [WindowSnapshot], screen: NSScreen, appIcon: NSImage) {
        func onScreen(_ window: WindowSnapshot) -> Bool {
            guard let frame = window.frame else { return false }
            return screen.frame.intersects(frame)
        }
        let active = windows.filter { !$0.isMinimized }
        let rows: [(snapshot: WindowSnapshot, dimmed: Bool)] =
            active.filter(onScreen).map { ($0, false) }
            + active.filter { !onScreen($0) }.map { ($0, true) }
            + windows.filter(\.isMinimized).map { ($0, true) }

        let height = CGFloat(windows.count) * Layout.surgeRowHeight + Layout.surgeVPadding * 2
        glass = BarBackgroundFactory.makeGlassIfAvailable(cornerRadius: 12)
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.surgeWidth, height: height))
        wantsLayer = true
        if let glass {
            addSubview(glass)
        }

        let count = rows.count
        for (index, row) in rows.enumerated() {
            let view = SurgeRowView(snapshot: row.snapshot, appIcon: appIcon, dimmed: row.dimmed)
            view.frame = NSRect(x: 0,
                                y: Layout.surgeVPadding + CGFloat(count - 1 - index) * Layout.surgeRowHeight,
                                width: Layout.surgeWidth,
                                height: Layout.surgeRowHeight)
            view.onPick = { [weak self] snapshot in self?.onPick?(snapshot) }
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        glass?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        // 玻璃路径材质自绘背景；仅旧系统回退时手绘深色卡
        guard glass == nil else { return }
        let background = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.55).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()
    }

    /// 悬停轮询驱动（面板内容坐标）：命中行高亮，其余清悬停
    func setHover(at point: NSPoint) {
        let hit = hitTest(point) as? SurgeRowView
        for case let row as SurgeRowView in subviews {
            row.setHovered(row === hit)
        }
    }

    /// 错峰升起：靠近图标的行先动，逐行向上传递（与汐线展开共用语言）
    func riseRows() {
        let rowsBottomUp = subviews.compactMap { $0 as? SurgeRowView }.reversed()
        for (index, row) in rowsBottomUp.enumerated() {
            guard let layer = row.layer else { continue }
            let delay = Double(index) * Layout.surgeStaggerStep
            Motion.spring(layer, keyPath: "transform.translation.y", from: Motion.surgeRowRiseOffset, to: 0,
                          stiffness: Motion.iconRiseStiffness, damping: Motion.iconRiseDamping,
                          minDuration: Motion.iconRiseDuration, delay: delay)
            Motion.basic(layer, keyPath: "opacity", from: 0.0, to: 1.0,
                         duration: Motion.iconRiseDuration, delay: delay)
        }
    }

    /// 反向退落：顶部先坠、逐行向下传递（easeIn 加速离场，与收起语言一致）；返回总时长
    @discardableResult
    func dropRows() -> TimeInterval {
        let rowsTopDown = subviews.compactMap { $0 as? SurgeRowView }
        for (index, row) in rowsTopDown.enumerated() {
            guard let layer = row.layer else { continue }
            let delay = Double(index) * Layout.surgeStaggerStep
            Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                         duration: Motion.dropDuration, curve: .easeIn, delay: delay)
            Motion.basic(layer, keyPath: "opacity", to: 0.0,
                         duration: Motion.dropDuration, curve: .easeIn, delay: delay)
        }
        return Layout.surgeStaggerStep * Double(max(rowsTopDown.count - 1, 0)) + Motion.dropDuration
    }
}

// MARK: - 面板

/// 潮涌宿主窗口：非激活、悬浮于图标栏之上（TidePanel 同款约束 + 高一级）。
/// 可成为 key：玻璃背景采样需要（非 key 窗口采样层被 WindowServer 降级，见 M1 调查）。
@MainActor
final class SurgePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
}

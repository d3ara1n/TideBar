import AppKit
import TideBarCore

/// 小工具在图标栏中的自定义展示：表现形式与悬停特效都归 widget 自己决定。
/// - preferredWidth：条目占用宽度（普通应用条目为 Layout.iconSlot）
/// - usesSharedHoverEffects：false 时栏不再施加共享的浮起/压下/光晕，widget 自绘反馈
/// - setActive：栏展开/收起生命周期，动态 widget 在此启停刷新
/// - update：条目刷新（引用、名称变化），widget 按 entry 重建内容
@MainActor
protocol ItemBarArtwork: AnyObject {
    var preferredWidth: CGFloat { get }
    var usesSharedHoverEffects: Bool { get }
    func setActive(_ active: Bool)
    func update(entry: ItemEntry)
}

extension ItemBarArtwork {
    var usesSharedHoverEffects: Bool { true }
}

typealias AnyBarArtwork = NSView & ItemBarArtwork

/// 应用收藏夹的栏内图标：内容前 4 个应用的 2x2 缩略网格（单应用居中、空态用类型符号）。
/// 表现与应用条目同族，故沿用共享悬停特效。
@MainActor
final class ApplicationLauncherTileView: NSView, ItemBarArtwork {
    var preferredWidth: CGFloat { Layout.iconSlot }
    private var icons: [NSImage] = []

    init(entry: ItemEntry) {
        super.init(frame: .zero)
        wantsLayer = true
        reload(from: entry.reference)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func setActive(_ active: Bool) {
        // 静态内容；动态 widget 在此钩子启停刷新。
    }

    func update(entry: ItemEntry) {
        reload(from: entry.reference)
    }

    private func reload(from reference: ItemReference) {
        let references = WidgetReferences.applicationLauncherConfiguration(for: reference)?.applications ?? []
        icons = references.prefix(4).map { reference in
            if let url = ItemReferences.applicationURL(reference) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage()
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = Layout.iconSize
        let tile = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                          width: side, height: side)
        // 底板：与应用图标同族的圆角方块（低对比 label 色，随亮暗自适应）
        let plate = NSBezierPath(roundedRect: tile, xRadius: side * 0.225, yRadius: side * 0.225)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        plate.fill()
        NSColor.labelColor.withAlphaComponent(0.16).setStroke()
        plate.lineWidth = 1
        plate.stroke()

        if icons.isEmpty {
            let symbolSide = side * 0.44
            let symbol = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: symbolSide * 0.72, weight: .regular))
            if let symbol {
                let rect = NSRect(x: tile.midX - symbolSide / 2, y: tile.midY - symbolSide / 2,
                                  width: symbolSide, height: symbolSide)
                NSColor.labelColor.withAlphaComponent(0.45).set()
                symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return
        }

        if icons.count == 1 {
            let iconSide = side * 0.62
            icons[0].draw(in: NSRect(x: tile.midX - iconSide / 2, y: tile.midY - iconSide / 2,
                                     width: iconSide, height: iconSide),
                          from: .zero, operation: .sourceOver, fraction: 1)
            return
        }

        let inset = side * 0.2
        let gap = side * 0.08
        let mini = (side - inset * 2 - gap) / 2
        for (index, icon) in icons.enumerated() {
            let column = index % 2
            let row = index / 2
            let rect = NSRect(x: tile.minX + inset + CGFloat(column) * (mini + gap),
                              y: tile.maxY - inset - CGFloat(row + 1) * mini - CGFloat(row) * gap,
                              width: mini, height: mini)
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

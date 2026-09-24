import AppKit
import TideBarCore

/// 小工具在图标栏中的自定义展示：表现形式与悬停特效都归 widget 自己决定。
/// - preferredWidth：条目占用宽度（普通应用条目为 Layout.iconSlot）
/// - usesSharedHoverEffects：false 时栏不再施加共享的浮起/压下/光晕，widget 自绘反馈
/// - setHighlightState：悬停/键盘选中转发，自绘反馈的 artwork 据此点亮（如底板变亮）
/// - setActive：栏展开/收起生命周期，动态 widget 在此启停刷新
/// - update：条目刷新（引用、名称变化），widget 按 entry 重建内容
@MainActor
protocol ItemBarArtwork: AnyObject {
    var preferredWidth: CGFloat { get }
    /// 必须是 requirement：经 any 存在类型调用，重写者需动态派发生效
    var usesSharedHoverEffects: Bool { get }
    func setActive(_ active: Bool)
    func update(entry: ItemEntry)
    /// 必须是 requirement，同上；默认无操作。
    func setHighlightState(hovered: Bool, selected: Bool)
    /// 拖拽接收/拒绝反馈由 widget 自己决定，避免套用通用图标效果。
    func setDragFeedback(_ state: ItemDragIconState)
}

extension ItemBarArtwork {
    var usesSharedHoverEffects: Bool { true }
    func setHighlightState(hovered: Bool, selected: Bool) {}
    func setDragFeedback(_ state: ItemDragIconState) {}
}

typealias AnyBarArtwork = NSView & ItemBarArtwork

/// 应用收藏夹的栏内图标：内容前 4 个应用的 2x2 缩略网格（单应用居中、空态用类型符号）。
/// 悬停/选中为底板变亮，不上浮、不画圆环：点击是展开潮涌，不是启动应用。
@MainActor
final class ApplicationLauncherTileView: NSView, ItemBarArtwork {
    var preferredWidth: CGFloat { Layout.iconSlot }
    var usesSharedHoverEffects: Bool { false }
    private var icons: [NSImage] = []
    /// 失效条目（无 URL）用 template 符号回退，绘制前需显式设色随主题
    private var unavailableFlags: [Bool] = []
    private let highlightLayer = CALayer()
    private let dragFeedbackLayer = CALayer()
    private var artHovered = false
    private var artSelected = false
    private var dragFeedbackState: ItemDragIconState = .idle

    init(entry: ItemEntry) {
        super.init(frame: .zero)
        wantsLayer = true
        highlightLayer.cornerCurve = .continuous
        highlightLayer.opacity = 0
        layer?.addSublayer(highlightLayer)
        dragFeedbackLayer.cornerCurve = .continuous
        dragFeedbackLayer.opacity = 0
        layer?.addSublayer(dragFeedbackLayer)
        refreshHighlightColor()
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
        var nextIcons: [NSImage] = []
        var nextFlags: [Bool] = []
        for reference in references.prefix(4) {
            if let url = ItemReferences.applicationURL(reference) {
                nextIcons.append(NSWorkspace.shared.icon(forFile: url.path))
                nextFlags.append(false)
            } else {
                nextIcons.append(NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage())
                nextFlags.append(true)
            }
        }
        icons = nextIcons
        unavailableFlags = nextFlags
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshHighlightColor()
        needsDisplay = true
    }

    func setHighlightState(hovered: Bool, selected: Bool) {
        guard hovered != artHovered || selected != artSelected else { return }
        let wasLit = artHovered || artSelected
        artHovered = hovered
        artSelected = selected
        let lit = hovered || selected
        guard lit != wasLit else { return }
        Motion.basic(highlightLayer, keyPath: "opacity", to: lit ? Float(1) : Float(0),
                     duration: lit ? Motion.hoverEnterDuration : Motion.hoverExitDuration)
    }

    func setDragFeedback(_ state: ItemDragIconState) {
        guard state != dragFeedbackState else { return }
        let previous = dragFeedbackState
        dragFeedbackState = state

        let isReceiving = state == .receiving
        let isRejected = state == .rejected
        let opacity: Float = isReceiving ? 0.30 : (isRejected ? 0.38 : 0)
        dragFeedbackLayer.backgroundColor = (isRejected ? NSColor.black : NSColor.white).cgColor
        Motion.basic(dragFeedbackLayer, keyPath: "opacity", to: opacity,
                     duration: Motion.dragFeedbackDuration)

        guard let visualLayer = layer else { return }
        if isRejected, previous != .rejected, !Motion.shouldReduceMotion {
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, -3.5, 3.5, -2.2, 2.2, 0]
            animation.duration = 0.28
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            visualLayer.removeAnimation(forKey: "widget.drag.reject")
            visualLayer.add(animation, forKey: "widget.drag.reject")
        }

        let targetScale: CGFloat = isReceiving ? 1.06 : (isRejected ? 0.96 : 1)
        let targetOffset: CGFloat = isReceiving ? 1.5 : 0
        if Motion.shouldReduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            visualLayer.removeAnimation(forKey: "motion.transform.scale")
            visualLayer.removeAnimation(forKey: "motion.transform.translation.y")
            visualLayer.setValue(targetScale, forKeyPath: "transform.scale")
            visualLayer.setValue(targetOffset, forKeyPath: "transform.translation.y")
            CATransaction.commit()
        } else {
            Motion.spring(visualLayer, keyPath: "transform.scale", to: targetScale,
                          stiffness: 520, damping: 34, minDuration: Motion.dragFeedbackDuration)
            Motion.spring(visualLayer, keyPath: "transform.translation.y", to: targetOffset,
                          stiffness: 520, damping: 34, minDuration: Motion.dragFeedbackDuration)
        }
    }

    /// 高亮层目标透明度（模型值，动画即时设定）；供测试验证反馈链路
    var highlightOpacity: Float { highlightLayer.opacity }
    /// 拖拽反馈层目标透明度，供测试验证自绘反馈链路。
    var dragFeedbackOpacity: Float { dragFeedbackLayer.opacity }

    private func refreshHighlightColor() {
        highlightLayer.backgroundColor = AppearanceColors.cgColor(
            .labelColor, alpha: 0.12, for: effectiveAppearance)
    }

    override func layout() {
        super.layout()
        let side = Layout.iconSize
        highlightLayer.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
                                      width: side, height: side)
        dragFeedbackLayer.frame = highlightLayer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.cornerRadius = side * 0.225
        dragFeedbackLayer.cornerRadius = side * 0.225
        CATransaction.commit()
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
                tinted(symbol, color: NSColor.labelColor.withAlphaComponent(0.45))
                    .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return
        }

        if icons.count == 1 {
            // 单应用占满底板主体：小尺寸下仍可辨认是哪个应用，底板保留 widget 身份
            let iconSide = side * 0.8
            let icon = unavailableFlags[0] ? unavailableIcon(icons[0]) : icons[0]
            icon.draw(in: NSRect(x: tile.midX - iconSide / 2, y: tile.midY - iconSide / 2,
                                 width: iconSide, height: iconSide),
                      from: .zero, operation: .sourceOver, fraction: 1)
            return
        }

        let inset = side * 0.10
        let gap = side * 0.06
        let mini = (side - inset * 2 - gap) / 2
        for (index, icon) in icons.enumerated() {
            let column = index % 2
            let row = index / 2
            let rect = NSRect(x: tile.minX + inset + CGFloat(column) * (mini + gap),
                              y: tile.maxY - inset - CGFloat(row + 1) * mini - CGFloat(row) * gap,
                              width: mini, height: mini)
            let isUnavailable = unavailableFlags.indices.contains(index) && unavailableFlags[index]
            let image = isUnavailable ? unavailableIcon(icon) : icon
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    /// template 符号着色：NSImage.draw 不吃当前填充色，须 sourceIn 合成后随主题
    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceIn)
        result.unlockFocus()
        return result
    }

    private func unavailableIcon(_ fallback: NSImage) -> NSImage {
        tinted(fallback, color: NSColor.labelColor.withAlphaComponent(0.45))
    }
}

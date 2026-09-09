import AppKit

/// 拖拽视觉的唯一样式入口。只消费展示状态，不读取 pasteboard、文件或固定配置。
/// 更换占位形状、图标效果在本文件完成；时间与弹性统一由 Motion 提供。
@MainActor
enum ItemDragStyle {
    static let placeholderInset: CGFloat = 5
    static let placeholderCornerRatio: CGFloat = 0.23
    static let placeholderOpacity: CGFloat = 0.12
    static let receiverBrightness: Float = 0.30
    static let rejectionShade: Float = 0.38

    static func suppressHover(pivot: CALayer, halo: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (key, value) in [("transform.translation.y", CGFloat(0)), ("transform.scale", CGFloat(1)), ("opacity", CGFloat(1))] {
            pivot.removeAnimation(forKey: "motion.\(key)")
            pivot.setValue(value, forKeyPath: key)
        }
        halo.removeAnimation(forKey: "motion.opacity")
        halo.opacity = 0
    }

    static func reposition(_ layer: CALayer, offset: CGFloat, lifted: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if Motion.shouldReduceMotion || lifted || abs(offset) <= 0.5 {
            layer.removeAnimation(forKey: "motion.transform.translation.x")
            layer.setValue(CGFloat(0), forKeyPath: "transform.translation.x")
        } else {
            Motion.spring(layer, keyPath: "transform.translation.x", from: offset, to: CGFloat(0),
                          stiffness: Motion.dragRepositionStiffness, damping: Motion.dragRepositionDamping,
                          minDuration: Motion.dragRepositionDuration)
        }
    }
}

enum ItemDragIconState: Equatable {
    case idle, tracking, lifted, receiving, rejected
    var suppressesHover: Bool { self != .idle }
}

/// 独立图层只作用于 artwork 的不透明像素，不放大外圈、不改变 hit geometry。
@MainActor
final class ItemDragIconEffect {
    let layer = CALayer()
    private var state: ItemDragIconState = .idle
    private var icon: NSImage?

    init() { layer.opacity = 0 }

    func update(icon: NSImage, state: ItemDragIconState) {
        guard self.state != state || self.icon !== icon else { return }
        self.state = state
        self.icon = icon
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let tint: NSColor = state == .rejected ? .black : .white
        let image = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        // 立即生成遮罩内容，避免绘制闭包在后续刷新时读取可变状态。
        layer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let opacity: Float = switch state {
        case .receiving: ItemDragStyle.receiverBrightness
        case .rejected: ItemDragStyle.rejectionShade
        default: 0
        }
        Motion.basic(layer, keyPath: "opacity", to: opacity,
                     duration: Motion.shouldReduceMotion ? Motion.reducedMotionFadeDuration : Motion.dragFeedbackDuration)
    }
}

/// 成组占位也是一格，数量只表示输入引用数，不宣称去重后新增项数量。
@MainActor
final class ItemDragPlaceholder {
    let layer = CALayer()
    private let well = CALayer()
    private let stack = CALayer()
    private let countLabel = CATextLayer()

    init() {
        layer.opacity = 0
        for child in [stack, well, countLabel] { layer.addSublayer(child) }
        countLabel.alignmentMode = .center
        countLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        countLabel.fontSize = 12
        for child in [well, stack] { child.cornerCurve = .continuous }
    }

    func update(frame: CGRect?, count: Int = 1, appearance: NSAppearance, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let frame else {
            layer.opacity = 0
            return
        }
        layer.frame = frame
        let side = max(1, min(frame.width, Layout.iconSize) - ItemDragStyle.placeholderInset * 2)
        let rect = CGRect(x: (frame.width - side) / 2, y: (frame.height - side) / 2,
                          width: side, height: side)
        well.frame = rect
        well.cornerRadius = side * ItemDragStyle.placeholderCornerRatio
        well.backgroundColor = AppearanceColors.cgColor(.labelColor, alpha: ItemDragStyle.placeholderOpacity, for: appearance)
        stack.frame = rect.offsetBy(dx: 3, dy: 3)
        stack.cornerRadius = well.cornerRadius
        stack.backgroundColor = well.backgroundColor
        stack.isHidden = count <= 1
        countLabel.string = count > 1 ? (count > 99 ? "99+" : "\(count)") : nil
        countLabel.contentsScale = scale
        countLabel.foregroundColor = AppearanceColors.cgColor(.secondaryLabelColor, for: appearance)
        countLabel.frame = CGRect(x: rect.minX, y: rect.midY - 8, width: rect.width, height: 16)
        layer.opacity = 1
    }
}

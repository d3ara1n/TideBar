import AppKit
import QuartzCore

/// 名字文本引擎：居中静止 / 中截断「…」/ ping-pong 往返跑马灯三态。
/// 宿主（名字气泡）给定视口、字体与颜色；跑马灯只在宿主可见期间被允许。
@MainActor
final class ItemNameLabelView: NSView {
    private let textLayer = CATextLayer()
    private let font: NSFont
    private let color: NSColor
    private var name: String
    private var scrollingAllowed = false

    init(name: String, font: NSFont, color: NSColor) {
        self.name = name
        self.font = font
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        textLayer.alignmentMode = .center
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(textLayer)
        applyTextAttributes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 视觉子树不参与命中
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var isMarqueeRunning: Bool { textLayer.animation(forKey: Self.marqueeKey) != nil }

    func update(name newName: String) {
        guard newName != name else { return }
        name = newName
        relayout()
    }

    /// 宿主可见期才滚动；离场时停掉无限动画
    func setScrollingAllowed(_ allowed: Bool) {
        guard scrollingAllowed != allowed else { return }
        scrollingAllowed = allowed
        relayout()
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textLayer.foregroundColor = AppearanceColors.cgColor(color, for: effectiveAppearance)
    }

    // MARK: 形态

    private static let marqueeKey = "motion.name.marquee"

    private func applyTextAttributes() {
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = AppearanceColors.cgColor(color, for: effectiveAppearance)
    }

    private func relayout() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        applyTextAttributes()
        let textWidth = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        let lineHeight = ceil(font.ascender - font.descender)
        let centerY = (bounds.height - lineHeight) / 2
        func textFrame(_ width: CGFloat) -> CGRect {
            CGRect(x: 0, y: centerY, width: width, height: lineHeight)
        }
        let overflow = textWidth - bounds.width

        guard overflow > 0.5 else {
            // 写得下：居中静止
            layer?.mask = nil
            textLayer.removeAnimation(forKey: Self.marqueeKey)
            textLayer.truncationMode = .none
            textLayer.string = name
            textLayer.frame = textFrame(bounds.width)
            return
        }

        let scrolls = scrollingAllowed && !Motion.shouldReduceMotion && overflow > Layout.nameScrollMinOverflow
        guard scrolls else {
            // 写不下但不滚动：中截断
            layer?.mask = nil
            textLayer.removeAnimation(forKey: Self.marqueeKey)
            textLayer.truncationMode = .middle
            textLayer.string = name
            textLayer.frame = textFrame(bounds.width)
            return
        }

        // 写不下且允许动态：完整文本往返滚动，两端渐隐
        layer?.mask = fadeMask()
        textLayer.truncationMode = .none
        textLayer.string = name
        textLayer.frame = textFrame(textWidth)
        startMarquee(overflow: overflow)
    }

    /// ping-pong 往返：滚到尾端 → 停 → 滚回 → 停 → 循环。
    /// 匀速是可读性参数，不随动画速度系数缩放。
    private func startMarquee(overflow: CGFloat) {
        let travel = TimeInterval(overflow / Layout.nameScrollSpeed)
        let dwell = Layout.nameScrollDwell
        let total = travel * 2 + dwell * 2
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0.0, -overflow, -overflow, 0.0, 0.0]
        animation.keyTimes = [0,
                               travel / total,
                               (travel + dwell) / total,
                               (travel * 2 + dwell) / total,
                               1].map { NSNumber(value: $0) }
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut),
                                     CAMediaTimingFunction(name: .linear),
                                     CAMediaTimingFunction(name: .easeInEaseOut),
                                     CAMediaTimingFunction(name: .linear)]
        animation.duration = total
        animation.repeatCount = .infinity
        // 模型值归零再挂动画，换文案/重排时从头滚起
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.setValue(0, forKeyPath: "transform.translation.x")
        CATransaction.commit()
        textLayer.removeAnimation(forKey: Self.marqueeKey)
        textLayer.add(animation, forKey: Self.marqueeKey)
    }

    /// 滚动时两端渐隐遮罩；静止形态不用（渐隐只在有位移时才有意义）
    private func fadeMask() -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        let fade = min(Layout.nameFadeWidth / bounds.width, 0.45)
        mask.colors = [NSColor.clear.cgColor, NSColor.white.cgColor,
                       NSColor.white.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        return mask
    }
}

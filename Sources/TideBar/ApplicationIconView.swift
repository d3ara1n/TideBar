import AppKit

/// 应用图标的独立视觉层：启动缩放与残影不改变槽位、命中或整栏升降动画。
@MainActor
class ApplicationIconView: NSView {
    var icon: NSImage {
        didSet { updateContents() }
    }
    let imageLayer = CALayer()
    private let ghosts = [CALayer(), CALayer()]
    var iconSide: CGFloat
    private var launching = false
    private var active = true
    private var animating = false
    private var reduced = false

    init(icon: NSImage, side: CGFloat) {
        self.icon = icon
        self.iconSide = side
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for ghost in ghosts {
            ghost.opacity = 0
            ghost.contentsGravity = .resizeAspect
            layer?.addSublayer(ghost)
        }
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
        updateContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = NSRect(x: (bounds.width - iconSide) / 2, y: (bounds.height - iconSide) / 2,
                          width: iconSide, height: iconSide)
        for child in ghosts + [imageLayer] {
            child.frame = rect
            child.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.commit()
    }

    func setLaunching(_ launching: Bool) {
        self.launching = launching
        refreshAnimation()
    }

    func setActive(_ active: Bool) {
        self.active = active
        refreshAnimation()
    }

    private func updateContents() {
        let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for child in ghosts + [imageLayer] { child.contents = image }
        CATransaction.commit()
    }

    private func refreshAnimation() {
        let shouldAnimate = launching && active
        let reduce = Motion.shouldReduceMotion
        guard shouldAnimate != animating || reduced != reduce else { return }
        animating = shouldAnimate
        reduced = reduce
        let currentScale = imageLayer.presentation()?.value(forKeyPath: "transform.scale")
        imageLayer.removeAnimation(forKey: "launch.pulse")
        imageLayer.removeAnimation(forKey: "motion.transform.scale")
        for ghost in ghosts { ghost.removeAllAnimations() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 减少动态效果时以图标本体的静态淡化表示在途，不做循环缩放或发散。
        imageLayer.opacity = shouldAnimate && reduce ? 0.6 : 1
        CATransaction.commit()
        guard shouldAnimate, !reduce else {
            if !reduce, let currentScale {
                Motion.basic(imageLayer, keyPath: "transform.scale", from: currentScale, to: CGFloat(1),
                             duration: Motion.statusDuration)
            }
            return
        }

        let duration = Motion.launchPulseDuration
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, Motion.launchPulseScale, 1, 1]
        pulse.keyTimes = [0, 0.28, 0.72, 1]
        pulse.timingFunctions = [.init(name: .easeOut), .init(name: .easeInEaseOut), .init(name: .linear)]
        pulse.duration = duration
        pulse.repeatCount = .infinity
        imageLayer.add(pulse, forKey: "launch.pulse")

        for (index, ghost) in ghosts.enumerated() {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = Motion.launchGhostScale
            scale.duration = duration
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, Motion.launchGhostOpacity, 0]
            opacity.keyTimes = [0, 0.12, 1]
            opacity.duration = duration
            opacity.timingFunctions = [.init(name: .easeOut), .init(name: .easeIn)]
            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = duration
            group.beginTime = ghost.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * duration * 0.22
            group.repeatCount = .infinity
            ghost.add(group, forKey: "launch.ghost")
        }
    }
}

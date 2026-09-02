import AppKit
import QuartzCore

// MARK: - 玻璃背景（macOS 26+）

@available(macOS 26.0, *)
@MainActor
final class GlassBarBackgroundView: NSView {
    private let glass = NSGlassEffectView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glass.tintColor = .clear
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = bounds.height / 2
    }
}

@MainActor
enum BarBackgroundFactory {
    static var usesGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func makeGlassIfAvailable() -> NSView? {
        if #available(macOS 26.0, *) { return GlassBarBackgroundView(frame: .zero) }
        return nil
    }
}

// MARK: - 汐线胶囊

@MainActor
final class TidelineCapsuleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds,
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(0.92).setFill()
        pill.fill()
        layer?.shadowColor = NSColor.labelColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let layer else { return }
        layer.shadowColor = NSColor.labelColor.cgColor
        layer.shadowRadius = 5
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0.28
        // 呼吸只驱动 shadowOpacity，不与展开/收起的 transform/alpha 冲突
        let breath = CABasicAnimation(keyPath: "shadowOpacity")
        breath.fromValue = 0.1
        breath.toValue = 0.5
        breath.duration = 3.2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(breath, forKey: "breath")
    }

    /// 涌潮预告：底边为锚向上增厚、自中心加宽
    func swell() {
        guard let layer else { return }
        Motion.basic(layer, keyPath: "transform.scale.x", from: 1.0, to: 1.12,
                     duration: Motion.senseDuration)
        Motion.basic(layer, keyPath: "transform.scale.y", from: 1.0, to: 1.5,
                     duration: Motion.senseDuration)
    }

    /// 退潮归位：过冲轻弹（潮合上的一下）
    func pop() {
        guard let layer else { return }
        Motion.spring(layer, keyPath: "transform.scale", from: Motion.capsulePopScale, to: 1.0,
                      stiffness: Motion.capsulePopStiffness, damping: Motion.capsulePopDamping,
                      minDuration: Motion.capsulePopDuration)
    }
}

// MARK: - 图标横排

@MainActor
final class IconRowView: NSView {
    var onLaunch: ((AppEntry) -> Void)?
    private var buttons: [AppIconButton] = []

    /// rebuildAll = true：整体重建（展开动画完整重播）
    /// rebuildAll = false：按 id 差分，仅新项上涌、消失项淡出，其余原地保留
    func update(apps: [AppEntry], rebuildAll: Bool) {
        if rebuildAll {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = apps.map { app in
                let button = AppIconButton(entry: app)
                button.onClick = { [weak self] entry in
                    self?.onLaunch?(entry)
                }
                addSubview(button)
                return button
            }
            needsLayout = true
            return
        }

        var kept = Dictionary(uniqueKeysWithValues: buttons.map { ($0.entry.id, $0) })
        var next: [AppIconButton] = []
        var newcomers: [(button: AppIconButton, index: Int)] = []
        for (index, app) in apps.enumerated() {
            if let existing = kept.removeValue(forKey: app.id) {
                existing.update(entry: app)
                next.append(existing)
            } else {
                let button = AppIconButton(entry: app)
                button.onClick = { [weak self] entry in
                    self?.onLaunch?(entry)
                }
                addSubview(button)
                next.append(button)
                newcomers.append((button, index))
            }
        }
        for gone in kept.values {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                gone.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    gone.removeFromSuperview()
                }
            })
        }
        buttons = next
        needsLayout = true
        for (button, _) in newcomers {
            rise(button, delay: 0)
        }
    }

    override func layout() {
        super.layout()
        let total = CGFloat(buttons.count) * Layout.iconSlot
        let originX = (bounds.width - total) / 2
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: originX + CGFloat(index) * Layout.iconSlot,
                                  y: 0,
                                  width: Layout.iconSlot,
                                  height: bounds.height)
        }
    }

    /// 涌潮波：自中心向两侧发散上涌，波窗封顶（Motion.waveStep）
    func waveIn() {
        alphaValue = 1
        let step = Motion.waveStep(count: buttons.count)
        let center = Double(buttons.count - 1) / 2
        for (index, button) in buttons.enumerated() {
            rise(button, delay: Motion.waveDelay + abs(Double(index) - center) * step)
        }
    }

    /// 退潮波：向中心汇聚下坠，外圈先离场（easeIn 加速离场）
    func waveOut() {
        let step = Motion.convergeStep(count: buttons.count)
        let center = Double(buttons.count - 1) / 2
        for (index, button) in buttons.enumerated() {
            let delay = abs(Double(index) - center) * step
            guard let layer = button.layer else { continue }
            Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                         duration: Motion.dropDuration, curve: .easeIn, delay: delay)
            Motion.basic(layer, keyPath: "opacity", to: 0.0,
                         duration: Motion.dropDuration, curve: .easeIn, delay: delay)
        }
    }

    private func rise(_ button: AppIconButton, delay: TimeInterval) {
        guard let layer = button.layer else { return }
        Motion.spring(layer, keyPath: "transform.translation.y", from: Motion.iconRiseOffset, to: 0,
                      stiffness: Motion.iconRiseStiffness, damping: Motion.iconRiseDamping,
                      minDuration: Motion.iconRiseDuration, delay: delay)
        Motion.basic(layer, keyPath: "opacity", from: 0.0, to: 1.0,
                     duration: Motion.iconRiseDuration, delay: delay)
    }
}

// MARK: - 面板内容（编舞主体）
// 窗口恒为展开尺寸，所有形变发生在 layer 空间——与窗口 frame 解耦，
// 杜绝 frame 动画与内容动画两套时间轴失同步的「散架感」。
// 元素：剪影层（潮体，胶囊↔bar 弹性形变）、玻璃（26+ 稳态背景）、汐线、图标波。

@MainActor
final class TideBarView: NSView {
    private let glass: NSView?
    private let silhouette = CALayer()
    private let capsule = TidelineCapsuleView()
    private let iconRow = IconRowView()
    private(set) var isExpandedState = false

    override init(frame frameRect: NSRect) {
        glass = BarBackgroundFactory.makeGlassIfAvailable()
        super.init(frame: frameRect)
        wantsLayer = true
        // 层序自底向上：剪影（潮体）→ 玻璃 → 图标波 → 汐线
        silhouette.backgroundColor = NSColor.labelColor.withAlphaComponent(0.42).cgColor
        silhouette.borderWidth = 1
        silhouette.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        silhouette.opacity = 0
        layer?.addSublayer(silhouette)
        if let glass {
            glass.alphaValue = 0
            addSubview(glass)
        }
        addSubview(iconRow)
        capsule.wantsLayer = true
        addSubview(capsule)
        iconRow.onLaunch = { $0.activate() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private var capsuleShape: NSRect {
        NSRect(x: bounds.midX - Layout.capsuleWidth / 2,
               y: 2,
               width: Layout.capsuleWidth,
               height: Layout.capsuleHeight)
    }

    override func layout() {
        super.layout()
        glass?.frame = bounds
        iconRow.frame = bounds
        capsule.frame = capsuleShape
        // 剪影只在稳态跟随布局（避免打断形变动画）：
        // 展开稳态 = 全幅（26 下被玻璃盖住；旧系统即最终背景）；收起稳态 = 胶囊形状
        if isExpandedState {
            silhouette.frame = bounds
            silhouette.cornerRadius = bounds.height / 2
        } else if silhouette.opacity == 0 {
            silhouette.frame = capsuleShape
            silhouette.cornerRadius = capsuleShape.height / 2
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        silhouette.backgroundColor = NSColor.labelColor.withAlphaComponent(0.42).cgColor
        needsDisplay = true
    }

    // MARK: 状态切换

    func setExpanded(_ expanded: Bool, apps: [AppEntry] = [], immediate: Bool = false) {
        if expanded {
            guard !isExpandedState else { return }
            isExpandedState = true
            iconRow.update(apps: apps, rebuildAll: true)
            // 1) 汐线感应：增厚预告
            capsule.swell()
            fade(capsule, to: 0, delay: 0.08, duration: 0.12)
            // 2) 潮体显形并弹性胀开：胶囊 → bar
            Motion.basic(silhouette, keyPath: "opacity", from: 0.0, to: 1.0, duration: 0.08)
            Motion.spring(silhouette, keyPath: "bounds", to: NSValue(rect: bounds),
                          stiffness: Motion.swellStiffness, damping: Motion.swellDamping,
                          minDuration: Motion.swellDuration)
            Motion.spring(silhouette, keyPath: "position",
                          to: NSValue(point: CGPoint(x: bounds.midX, y: bounds.midY)),
                          stiffness: Motion.swellStiffness, damping: Motion.swellDamping,
                          minDuration: Motion.swellDuration)
            Motion.spring(silhouette, keyPath: "cornerRadius", to: bounds.height / 2,
                          stiffness: Motion.swellStiffness, damping: Motion.swellDamping,
                          minDuration: Motion.swellDuration)
            // 3) 玻璃显影接管，剪影功成身退（仅 26+；旧系统剪影即最终背景）
            if let glass {
                fade(glass, to: 1, delay: Motion.glassFadeDelay, duration: Motion.glassFadeDuration)
                let settle = Motion.glassFadeDelay + Motion.glassFadeDuration + 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
                    guard let self, self.isExpandedState else { return }
                    Motion.basic(self.silhouette, keyPath: "opacity", to: 0.0, duration: 0.15)
                }
            }
            // 4) 图标波自中心扫出
            iconRow.waveIn()
        } else {
            guard isExpandedState else { return }
            isExpandedState = false
            if immediate {
                hardReset()
                return
            }
            // 退潮：图标汇聚下坠、潮体加速缩回、汐线轻弹回归
            iconRow.waveOut()
            if let glass {
                fade(glass, to: 0, delay: 0, duration: Motion.glassFadeOut)
            }
            let retreatStart = max(0, Motion.collapseDuration - 0.12)
            Motion.basic(silhouette, keyPath: "bounds", to: NSValue(rect: capsuleShape),
                         duration: Motion.collapseDuration, curve: .easeIn)
            Motion.basic(silhouette, keyPath: "position",
                          to: NSValue(point: CGPoint(x: capsuleShape.midX, y: capsuleShape.midY)),
                         duration: Motion.collapseDuration, curve: .easeIn)
            Motion.basic(silhouette, keyPath: "cornerRadius", to: capsuleShape.height / 2,
                         duration: Motion.collapseDuration, curve: .easeIn)
            Motion.basic(silhouette, keyPath: "opacity", to: 0.0,
                         duration: 0.12, delay: retreatStart)
            fade(capsule, to: 1, delay: retreatStart, duration: 0.1)
            DispatchQueue.main.asyncAfter(deadline: .now() + retreatStart) { [weak self] in
                self?.capsule.pop()
            }
        }
    }

    /// 展开态下列表变更：差分刷新，不重播整体动画
    func refreshApps(_ apps: [AppEntry]) {
        iconRow.update(apps: apps, rebuildAll: false)
    }

    /// 立即回到收起终态（全屏抑制用）
    private func hardReset() {
        silhouette.removeAllAnimations()
        silhouette.opacity = 0
        silhouette.frame = capsuleShape
        silhouette.cornerRadius = capsuleShape.height / 2
        glass?.alphaValue = 0
        iconRow.alphaValue = 0
        capsule.alphaValue = 1
        capsule.layer?.removeAllAnimations()
        capsule.layer?.setAffineTransform(.identity)
    }

    private func fade(_ view: NSView, to: CGFloat, delay: TimeInterval, duration: TimeInterval) {
        let bridge = MainThreadBridge { [weak view] in
            guard let view else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = to
            }
        }
        let work = DispatchWorkItem { bridge() }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work.perform()
        }
    }
}

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
        glass.style = .regular
        let placeholder = NSView()
        placeholder.autoresizingMask = [.width, .height]
        glass.contentView = placeholder
        // regular 材质的背景采样层覆盖全窗口矩形且不受 cornerRadius 约束，
        // 必须用 layer 裁剪把它裁进胶囊形（alt-tab 同款）
        glass.wantsLayer = true
        glass.layer?.masksToBounds = true
        glass.layer?.cornerCurve = .continuous
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = bounds.height / 2
        glass.layer?.cornerRadius = bounds.height / 2
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
// 窗口恒为展开尺寸，所有形变发生在 layer 空间——与窗口 frame 解耦。
// 元素命名：潮体 silhouette（水体，展开/收起的形变主体）、玻璃 glass、
// 图标波 iconRow、汐线 tideline；均裸层自管锚点（钉中心，对称由构造保证）。
// 层序自底向上：潮体 → 玻璃 → 图标波 → 汐线。

@MainActor
final class TideBarView: NSView {
    private let glass: NSView?
    private let silhouette = CALayer()
    private let tideline = CALayer()
    private let iconRow = IconRowView()
    private(set) var isExpandedState = false
    /// 展开代数：状态切换即递增，使未决的延迟隐藏失效（防误杀下一次展开的潮体）
    private var expandGeneration = 0

    /// 水体基色（起潮深水，也是旧系统回退胶囊的背景色）
    private static let waterColor = NSColor.black.withAlphaComponent(0.45).cgColor
    /// 玻璃色调（凝成目标：亮色白、暗色深）
    private var glassToneColor: CGColor {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? NSColor.black.withAlphaComponent(0.55).cgColor
                    : NSColor.white.withAlphaComponent(0.92).cgColor
    }

    override init(frame frameRect: NSRect) {
        glass = BarBackgroundFactory.makeGlassIfAvailable()
        super.init(frame: frameRect)
        wantsLayer = true
        // 层序自底向上：潮体 → 玻璃 → 图标波 → 汐线（均为裸层，锚点自管、钉中心）
        silhouette.backgroundColor = Self.waterColor
        silhouette.borderWidth = 1
        silhouette.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        silhouette.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        silhouette.opacity = 0
        layer?.addSublayer(silhouette)
        if let glass {
            glass.alphaValue = 0
            addSubview(glass)
        }
        addSubview(iconRow)
        let line = NSColor.labelColor
        tideline.backgroundColor = line.withAlphaComponent(0.92).cgColor
        tideline.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        tideline.shadowColor = line.cgColor
        tideline.shadowRadius = 5
        tideline.shadowOffset = .zero
        tideline.shadowOpacity = 0.28
        layer?.addSublayer(tideline)
        // 呼吸只驱动 shadowOpacity，不与 transform/opacity 编舞冲突
        let breath = CABasicAnimation(keyPath: "shadowOpacity")
        breath.fromValue = 0.1
        breath.toValue = 0.5
        breath.duration = 3.2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        tideline.add(breath, forKey: "breath")
        iconRow.onLaunch = { $0.activate() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 潮体收起态缩放：全幅胶囊 → 汐线胶囊
    private var collapsedScale: CGPoint {
        CGPoint(x: Layout.capsuleWidth / max(bounds.width, 1),
                y: Layout.capsuleHeight / max(bounds.height, 1))
    }

    private var collapsedTransform: CATransform3D {
        CATransform3DMakeScale(collapsedScale.x, collapsedScale.y, 1)
    }

    override func layout() {
        super.layout()
        glass?.frame = bounds
        iconRow.frame = bounds
        // 汐线：胶囊贴底居中
        tideline.bounds = CGRect(origin: .zero, size: CGSize(width: Layout.capsuleWidth,
                                                              height: Layout.capsuleHeight))
        tideline.position = CGPoint(x: bounds.midX, y: 2 + Layout.capsuleHeight / 2)
        tideline.cornerRadius = Layout.capsuleHeight / 2
        // 潮体几何恒为全幅胶囊，形变只在 transform——几何设置不会打断动画
        silhouette.bounds = CGRect(origin: .zero, size: bounds.size)
        silhouette.position = CGPoint(x: bounds.midX, y: bounds.midY)
        silhouette.cornerRadius = bounds.height / 2
        if !isExpandedState, silhouette.opacity == 0 {
            silhouette.transform = collapsedTransform
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        let line = NSColor.labelColor
        tideline.backgroundColor = line.withAlphaComponent(0.92).cgColor
        tideline.shadowColor = line.cgColor
        needsDisplay = true
    }

    // MARK: 状态切换

    func setExpanded(_ expanded: Bool, apps: [AppEntry] = [], immediate: Bool = false) {
        expandGeneration += 1
        if expanded {
            guard !isExpandedState else { return }
            isExpandedState = true
            iconRow.update(apps: apps, rebuildAll: true)
            // 1) 汐线感应：增厚预告（裸层中心锚点，对称膨胀）
            Motion.basic(tideline, keyPath: "transform.scale.x", from: 1.0, to: 1.12,
                         duration: Motion.senseDuration)
            Motion.basic(tideline, keyPath: "transform.scale.y", from: 1.0, to: 1.5,
                         duration: Motion.senseDuration)
            Motion.basic(tideline, keyPath: "opacity", from: 1.0, to: 0.0,
                         duration: 0.12, delay: 0.08)
            // 2) 潮体显形并弹性胀开：胶囊 → bar（transform 缩放，中心对称）
            let peak: Float = glass != nil ? Motion.swellPeakOpacity : 1.0
            Motion.basic(silhouette, keyPath: "opacity", from: 0.0, to: peak, duration: 0.10)
            let scale = collapsedScale
            Motion.spring(silhouette, keyPath: "transform.scale.x", from: scale.x, to: 1.0,
                          stiffness: Motion.swellStiffness, damping: Motion.swellDamping,
                          minDuration: Motion.swellDuration)
            Motion.spring(silhouette, keyPath: "transform.scale.y", from: scale.y, to: 1.0,
                          stiffness: Motion.swellStiffness, damping: Motion.swellDamping,
                          minDuration: Motion.swellDuration)
            // 3) 玻璃与水体交叉淡化，且水体同步调成玻璃色调——
            //    淡出时已是玻璃的颜色，「黑矩形消失」隐形（仅玻璃路径；无玻璃回退时潮体即背景）
            if let glass {
                fade(glass, to: 1, delay: Motion.glassFadeDelay, duration: Motion.glassFadeDuration)
                Motion.basic(silhouette, keyPath: "backgroundColor", to: glassToneColor,
                             duration: Motion.waterTintDuration, delay: Motion.waterTintDelay)
                Motion.basic(silhouette, keyPath: "opacity", from: peak, to: 0.0,
                             duration: 0.30, delay: Motion.glassFadeDelay)
                // 编舞落幕后彻底隐藏潮体：任何残留（色调/边界/动画尾巴）都不可能渲染
                let generation = expandGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.glassFadeDelay + 0.35) { [weak self] in
                    guard let self, self.isExpandedState, generation == self.expandGeneration else { return }
                    self.silhouette.isHidden = true
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
            // 退潮：玻璃退场、水体颜色沉回深色调并归来接管收缩
            iconRow.waveOut()
            silhouette.isHidden = false
            let retreatOpacity: Float = glass != nil ? Motion.retreatOpacity : 1.0
            if let glass {
                fade(glass, to: 0, delay: 0, duration: Motion.glassFadeOut)
                Motion.basic(silhouette, keyPath: "backgroundColor", to: Self.waterColor,
                             duration: Motion.glassFadeOut)
                Motion.basic(silhouette, keyPath: "opacity", from: 0.0,
                             to: Motion.retreatOpacity, duration: Motion.glassFadeOut)
            }
            let scale = collapsedScale
            Motion.basic(silhouette, keyPath: "transform.scale.x", to: scale.x,
                         duration: Motion.collapseDuration, curve: .easeIn)
            Motion.basic(silhouette, keyPath: "transform.scale.y", to: scale.y,
                         duration: Motion.collapseDuration, curve: .easeIn)
            let tail = max(0, Motion.collapseDuration - 0.12)
            Motion.basic(silhouette, keyPath: "opacity", from: retreatOpacity, to: 0.0,
                         duration: 0.15, delay: tail)
            // 汐线回归 + 轻弹（潮合上的一下）
            Motion.basic(tideline, keyPath: "opacity", from: 0.0, to: 1.0,
                         duration: 0.1, delay: tail)
            Motion.spring(tideline, keyPath: "transform.scale", from: Motion.capsulePopScale, to: 1.0,
                          stiffness: Motion.capsulePopStiffness, damping: Motion.capsulePopDamping,
                          minDuration: Motion.capsulePopDuration, delay: tail)
        }
    }

    /// 展开态下列表变更：差分刷新，不重播整体动画
    func refreshApps(_ apps: [AppEntry]) {
        iconRow.update(apps: apps, rebuildAll: false)
    }

    /// 立即回到收起终态（全屏抑制用）
    private func hardReset() {
        silhouette.removeAllAnimations()
        silhouette.isHidden = false
        silhouette.transform = collapsedTransform
        silhouette.opacity = 0
        glass?.alphaValue = 0
        iconRow.alphaValue = 0
        tideline.removeAllAnimations()
        tideline.opacity = 1
        tideline.transform = CATransform3DIdentity
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

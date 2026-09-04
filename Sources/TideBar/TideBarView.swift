import AppKit
import QuartzCore
import TideBarCore

// MARK: - 稳定磨砂背景

@MainActor
final class StableBlurBackgroundView: NSView {
    private let effect = NSVisualEffectView(frame: .zero)
    /// nil = 胶囊（height/2）；数值 = 定圆角（潮涌圈角卡片）
    private let fixedCornerRadius: CGFloat?

    init(cornerRadius: CGFloat? = nil) {
        self.fixedCornerRadius = cornerRadius
        super.init(frame: .zero)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        // NSGlassEffectView 会随宿主窗口 key 状态切换外观；固定 active 避免失焦变色。
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        effect.layer?.cornerCurve = .continuous
        addSubview(effect)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        effect.frame = bounds
        let radius = fixedCornerRadius ?? bounds.height / 2
        effect.layer?.cornerRadius = radius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        effect.appearance = dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
    }
}

@MainActor
enum BarBackgroundFactory {
    static var usesGlass: Bool { true }

    static func makeGlassIfAvailable(cornerRadius: CGFloat? = nil) -> NSView? {
        StableBlurBackgroundView(cornerRadius: cornerRadius)
    }
}

// MARK: - 图标横排

struct AppListUpdate {
    let hasInsertions: Bool
    let hasRemovals: Bool
    let removalDuration: TimeInterval

    static let none = AppListUpdate(hasInsertions: false, hasRemovals: false, removalDuration: 0)
}

@MainActor
final class IconRowView: NSView {
    var onLaunch: ((AppEntry) -> Void)?
    var onSetHidden: ((AppIdentity, Bool) -> Void)?
    var onTerminate: ((AppIdentity) -> Void)?
    var onSetPinned: ((AppIdentity, Bool) -> Void)?
    var onSurge: ((AppEntry, NSRect) -> Void)?
    private var buttons: [AppIconButton] = []
    /// 离场项保留到动画结束，避免列表真值先删除导致视图瞬间消失。
    private var departingButtons: [AppIdentity: AppIconButton] = [:]
    private var departureTokens: [AppIdentity: Int] = [:]

    /// rebuildAll = true：整体重建（展开动画完整重播）
    /// rebuildAll = false：按 identity 差分，统一处理新增、删除与保留项重排。
    @discardableResult
    func update(apps: [AppEntry], rebuildAll: Bool) -> AppListUpdate {
        if rebuildAll {
            for button in buttons + Array(departingButtons.values) {
                button.removeFromSuperview()
            }
            departingButtons.removeAll()
            departureTokens.removeAll()
            buttons = apps.map { app in
                let button = makeButton(app)
                addSubview(button)
                return button
            }
            needsLayout = true
            return .none
        }

        var oldFrames = Dictionary(uniqueKeysWithValues: buttons.map { ($0.entry.id, $0.frame) })
        var kept = Dictionary(uniqueKeysWithValues: buttons.map { ($0.entry.id, $0) })
        var next: [AppIconButton] = []
        var newcomers: [AppIconButton] = []

        for app in apps {
            if let existing = kept.removeValue(forKey: app.id) {
                existing.update(entry: app)
                next.append(existing)
            } else if let returning = departingButtons.removeValue(forKey: app.id) {
                departureTokens[app.id, default: 0] += 1
                oldFrames[app.id] = returning.frame
                restoreForReuse(returning)
                returning.update(entry: app)
                next.append(returning)
            } else {
                let button = makeButton(app)
                addSubview(button)
                next.append(button)
                newcomers.append(button)
            }
        }

        let removed = Array(kept.values)
        for button in removed {
            beginDeparture(button)
        }

        buttons = next
        needsLayout = true
        layoutSubtreeIfNeeded()

        let newcomerIDs = Set(newcomers.map { $0.entry.id })
        if !Motion.shouldReduceMotion {
            for button in buttons where !newcomerIDs.contains(button.entry.id) {
                guard let oldFrame = oldFrames[button.entry.id], let layer = button.layer else { continue }
                let delta = oldFrame.midX - button.frame.midX
                guard abs(delta) > 0.5 else { continue }
                Motion.spring(layer, keyPath: "transform.translation.x", from: delta, to: CGFloat(0),
                              stiffness: Motion.iconRepositionStiffness,
                              damping: Motion.iconRepositionDamping,
                              minDuration: Motion.iconRepositionDuration)
            }
        }
        for button in newcomers {
            rise(button, delay: Motion.iconInsertionDelay)
        }

        let removalDuration = removed.isEmpty
            ? 0
            : (Motion.shouldReduceMotion
               ? Motion.reducedMotionFadeDuration : Motion.dropDuration)
        return AppListUpdate(hasInsertions: !newcomers.isEmpty,
                             hasRemovals: !removed.isEmpty,
                             removalDuration: removalDuration)
    }

    private func makeButton(_ app: AppEntry) -> AppIconButton {
        let button = AppIconButton(entry: app)
        button.onClick = { [weak self] entry in self?.onLaunch?(entry) }
        button.onSetHidden = { [weak self] identity, hidden in self?.onSetHidden?(identity, hidden) }
        button.onTerminate = { [weak self] identity in self?.onTerminate?(identity) }
        button.onSetPinned = { [weak self] identity, pinned in self?.onSetPinned?(identity, pinned) }
        button.onSurge = { [weak self] entry, frame in self?.onSurge?(entry, frame) }
        return button
    }

    /// 悬停轮询：命中之外的按钮全部清悬停
    func setHover(hit: AppIconButton?) {
        for button in buttons {
            button.setHovered(button === hit)
        }
    }

    func refreshLayout() {
        for button in buttons + Array(departingButtons.values) {
            button.refreshLayout()
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func refreshAppearance() {
        for button in buttons + Array(departingButtons.values) {
            button.refreshAppearance()
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
            if Motion.shouldReduceMotion {
                Motion.basic(layer, keyPath: "opacity", to: 0.0,
                             duration: Motion.reducedMotionFadeDuration, delay: delay)
            } else {
                Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                             duration: Motion.dropDuration, curve: .easeIn, delay: delay)
                Motion.basic(layer, keyPath: "opacity", to: 0.0,
                             duration: Motion.dropDuration, curve: .easeIn, delay: delay)
            }
        }
    }

    private func rise(_ button: AppIconButton, delay: TimeInterval) {
        guard let layer = button.layer else { return }
        if Motion.shouldReduceMotion {
            Motion.basic(layer, keyPath: "opacity", from: Float(0), to: Float(1),
                         duration: Motion.reducedMotionFadeDuration, delay: delay)
            return
        }
        Motion.spring(layer, keyPath: "transform.translation.y", from: Motion.iconRiseOffset, to: CGFloat(0),
                      stiffness: Motion.iconRiseStiffness, damping: Motion.iconRiseDamping,
                      minDuration: Motion.iconRiseDuration, delay: delay)
        Motion.basic(layer, keyPath: "opacity", from: Float(0), to: Float(1),
                     duration: Motion.iconRiseDuration, delay: delay)
    }

    private func beginDeparture(_ button: AppIconButton) {
        let identity = button.entry.id
        button.setHovered(false)
        departingButtons[identity] = button
        departureTokens[identity, default: 0] += 1
        let token = departureTokens[identity]
        let reduceMotion = Motion.shouldReduceMotion
        let duration = reduceMotion ? Motion.reducedMotionFadeDuration : Motion.dropDuration

        if let layer = button.layer {
            if !reduceMotion {
                Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                             duration: duration, curve: .easeIn)
                Motion.basic(layer, keyPath: "transform.scale", to: Motion.iconExitScale,
                             duration: duration, curve: .easeIn)
            }
            Motion.basic(layer, keyPath: "opacity", to: Float(0),
                         duration: duration, curve: .easeIn)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak button] in
            MainActor.assumeIsolated {
                guard let self, let button,
                      self.departureTokens[identity] == token,
                      self.departingButtons[identity] === button else { return }
                self.departingButtons.removeValue(forKey: identity)
                self.departureTokens.removeValue(forKey: identity)
                button.removeFromSuperview()
            }
        }
    }

    private func restoreForReuse(_ button: AppIconButton) {
        guard let layer = button.layer else { return }
        layer.removeAnimation(forKey: "motion.transform.translation.x")
        layer.removeAnimation(forKey: "motion.transform.translation.y")
        layer.removeAnimation(forKey: "motion.transform.scale")
        layer.removeAnimation(forKey: "motion.opacity")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(CGFloat(0), forKeyPath: "transform.translation.x")
        layer.setValue(CGFloat(0), forKeyPath: "transform.translation.y")
        layer.setValue(CGFloat(1), forKeyPath: "transform.scale")
        layer.opacity = 1
        CATransaction.commit()
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
    var onSetHidden: ((AppIdentity, Bool) -> Void)?
    var onTerminate: ((AppIdentity) -> Void)?
    var onSetPinned: ((AppIdentity, Bool) -> Void)?
    /// 潮涌触发透传（携图标 frame，面板内容坐标）
    var onSurge: ((AppEntry, NSRect) -> Void)?

    /// 悬停轮询驱动（屏幕坐标 → 命中图标高亮）
    func updateHover(atScreen point: NSPoint) {
        guard let window else { return }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        iconRow.setHover(hit: iconRow.hitTest(local) as? AppIconButton)
    }
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
        // 锚点钉在底边中心（汐线处）：潮体从汐线涌起、退回落回汐线，不从几何中心胀开
        silhouette.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        silhouette.opacity = 0
        layer?.addSublayer(silhouette)
        if let glass {
            glass.alphaValue = 0
            addSubview(glass)
        }
        addSubview(iconRow)
        updateAppearance()
        tideline.anchorPoint = CGPoint(x: 0.5, y: 0.5)
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
        iconRow.onLaunch = { $0.primaryClick() }
        iconRow.onSetHidden = { [weak self] identity, hidden in self?.onSetHidden?(identity, hidden) }
        iconRow.onTerminate = { [weak self] identity in self?.onTerminate?(identity) }
        iconRow.onSetPinned = { [weak self] identity, pinned in self?.onSetPinned?(identity, pinned) }
        iconRow.onSurge = { [weak self] entry, frame in self?.onSurge?(entry, frame) }
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
        // 潮体几何恒为全幅胶囊，形变只在 transform——几何设置不会打断动画；
        // 锚点在底边中心（汐线上沿），收起态缩放后正落在汐线位置
        silhouette.bounds = CGRect(origin: .zero, size: bounds.size)
        silhouette.position = CGPoint(x: bounds.midX, y: 2)
        silhouette.cornerRadius = bounds.height / 2
        if !isExpandedState, silhouette.opacity == 0 {
            silhouette.transform = collapsedTransform
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let opacity = AppConfiguration.shared.tidelineBrightness.opacity(isDark: dark)
        tideline.backgroundColor = AppearanceColors.cgColor(
            .labelColor, alpha: CGFloat(opacity), for: effectiveAppearance
        )
        tideline.shadowColor = AppearanceColors.cgColor(.labelColor, for: effectiveAppearance)
    }

    // MARK: 状态切换

    func setExpanded(_ expanded: Bool, apps: [AppEntry] = [], immediate: Bool = false) {
        expandGeneration += 1
        if expanded {
            guard !isExpandedState else { return }
            isExpandedState = true
            iconRow.update(apps: apps, rebuildAll: true)
            if Motion.shouldReduceMotion {
                silhouette.removeAllAnimations()
                silhouette.isHidden = glass != nil
                silhouette.transform = CATransform3DIdentity
                silhouette.opacity = glass == nil ? 1 : 0
                glass?.alphaValue = 1
                tideline.removeAllAnimations()
                tideline.opacity = 0
                iconRow.waveIn()
                return
            }
            // 1) 汐线感应：增厚预告（裸层中心锚点，对称膨胀）
            Motion.basic(tideline, keyPath: "transform.scale.x", from: 1.0, to: 1.12,
                         duration: Motion.senseDuration)
            Motion.basic(tideline, keyPath: "transform.scale.y", from: 1.0, to: 1.5,
                         duration: Motion.senseDuration)
            Motion.basic(tideline, keyPath: "opacity", from: 1.0, to: 0.0,
                         duration: Motion.tidelineFadeDuration, delay: Motion.glassFadeDelay)
            // 2) 潮体显形并弹性胀开：胶囊 → bar（transform 缩放，中心对称）
            let peak: Float = glass != nil ? Motion.swellPeakOpacity : 1.0
            Motion.basic(silhouette, keyPath: "opacity", from: 0.0, to: peak,
                         duration: Motion.silhouetteRevealDuration)
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
                             duration: Motion.silhouetteFadeDuration, delay: Motion.glassFadeDelay)
                // 编舞落幕后彻底隐藏潮体：任何残留（色调/边界/动画尾巴）都不可能渲染
                let generation = expandGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.glassFadeDelay
                                               + Motion.silhouetteFadeDuration + 0.05) { [weak self] in
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
            if Motion.shouldReduceMotion {
                iconRow.waveOut()
                silhouette.removeAllAnimations()
                silhouette.isHidden = false
                silhouette.transform = collapsedTransform
                silhouette.opacity = 0
                glass?.alphaValue = 0
                tideline.removeAllAnimations()
                tideline.opacity = 1
                tideline.transform = CATransform3DIdentity
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
            let tail = max(0, Motion.collapseDuration - Motion.collapseTail)
            Motion.basic(silhouette, keyPath: "opacity", from: retreatOpacity, to: 0.0,
                         duration: Motion.retreatFadeDuration, delay: tail)
            // 汐线回归 + 轻弹（潮合上的一下）
            Motion.basic(tideline, keyPath: "opacity", from: 0.0, to: 1.0,
                         duration: Motion.tidelineReturnDuration, delay: tail)
            Motion.spring(tideline, keyPath: "transform.scale", from: Motion.capsulePopScale, to: 1.0,
                          stiffness: Motion.capsulePopStiffness, damping: Motion.capsulePopDamping,
                          minDuration: Motion.capsulePopDuration, delay: tail)
        }
    }

    /// 展开态下列表变更：差分刷新，不重播整体动画。
    @discardableResult
    func refreshApps(_ apps: [AppEntry]) -> AppListUpdate {
        iconRow.update(apps: apps, rebuildAll: false)
    }

    func refreshLayout() {
        iconRow.refreshLayout()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func refreshAppearance() {
        updateAppearance()
        iconRow.refreshAppearance()
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

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
        // 效果视图默认随宿主窗口 key 状态切换外观；固定 active 避免失焦变色。
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        // 胶囊（nil）必须用 circular 曲线：满半径下 continuous 是超椭圆端部，
        // 与潮体/汐线的半圆胶囊不一致，交叉淡化时可见形状跳变；定圆角卡片保持 continuous
        effect.layer?.cornerCurve = fixedCornerRadius == nil ? .circular : .continuous
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
    private let iconRow = ItemRowView()
    private(set) var isExpandedState = false
    weak var dragCoordinator: ItemDragCoordinator? {
        didSet {
            if let dragCoordinator {
                registerForDraggedTypes([ItemDragCoordinator.pasteboardType, .fileURL])
                iconRow.onBeginDrag = { [weak dragCoordinator] button, event in
                    dragCoordinator?.begin(from: button, event: event) ?? false
                }
            } else {
                unregisterDraggedTypes()
                iconRow.onBeginDrag = nil
            }
            syncDragContext()
        }
    }
    private var destinationTracking = false
    var onPreviewWidthChange: (() -> Void)?
    var extraPreviewSlots: Int { isExpandedState ? iconRow.extraPreviewSlots : 0 }

    func syncDragContext() {
        iconRow.setDragContext(active: destinationTracking || dragCoordinator?.isDragging == true,
                               source: dragCoordinator?.liftedItemID)
    }
    var onUserLaunch: (() -> Void)?
    var onSetHidden: ((AppIdentity, Bool) -> Void)?
    var onTerminate: ((AppIdentity) -> Void)?
    var onSetPinned: ((ItemID, Bool) -> Void)?
    /// 潮涌触发透传（携图标 frame，面板内容坐标）
    var onSurge: ((ItemEntry, NSRect) -> Void)?
    /// 悬停目标变化（携图标 frame，本视图坐标系）；nil 表示离开图标区
    var onHoverItem: ((ItemEntry, NSRect) -> Void)?
    var onHoverClear: (() -> Void)?

    /// 悬停轮询驱动（屏幕坐标 → 命中图标高亮）；目标变化时上报，驱动名字气泡
    func updateHover(atScreen point: NSPoint) {
        guard let window else { return }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        syncDragContext()
        let hit = iconRow.hitTest(local) as? ItemIconButton
        iconRow.setHover(hit: hit)
        let hitID = hit?.entry.id
        guard hitID != hoveredItemID else { return }
        hoveredItemID = hitID
        if let hit {
            onHoverItem?(hit.entry, hit.frame)
        } else {
            onHoverClear?()
        }
    }
    /// 展开代数：状态切换即递增，使未决的延迟隐藏失效（防误杀下一次展开的潮体）
    private var expandGeneration = 0
    /// 未确认通知的持久波纹环（细线涟漪发散，展开即止）
    private var rippleRings: [CALayer] = []
    private var applicationIntakeWork: DispatchWorkItem?
    private var applicationIntakeUntil: CFTimeInterval = 0
    private var notificationPulseUntil: CFTimeInterval = 0
    /// 当前悬停目标（去重上报用）
    private var hoveredItemID: ItemID?

    /// 收纳只形变汐线，不改窗口或图层几何；同一动作期间的新启动合并消化。
    func intakeApplications() {
        let now = CACurrentMediaTime()
        guard !isExpandedState, window?.isVisible == true, !Motion.shouldReduceMotion,
              now >= notificationPulseUntil, now >= applicationIntakeUntil else { return }

        // 收起的回归轻弹尚未结束时，等它落定；展开或隐藏会撤销这次请求。
        let remaining = ["transform.scale.x", "transform.scale.y", "opacity"].compactMap {
            tideline.animation(forKey: "motion.\($0)")
        }.map { max(0, $0.beginTime + $0.duration - now) }.max() ?? 0
        applicationIntakeUntil = now + remaining + Motion.intakeDuration
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applicationIntakeWork = nil
                guard !self.isExpandedState, self.window?.isVisible == true,
                      !Motion.shouldReduceMotion,
                      CACurrentMediaTime() >= self.notificationPulseUntil else {
                    self.applicationIntakeUntil = 0
                    return
                }
                self.applicationIntakeUntil = CACurrentMediaTime() + Motion.intakeDuration
                Motion.keyframePulse(self.tideline, keyPath: "transform.scale.x",
                                     peak: Motion.intakeScaleX, rest: CGFloat(1),
                                     duration: Motion.intakeDuration,
                                     growFraction: Motion.intakeGatherFraction)
                Motion.keyframePulse(self.tideline, keyPath: "transform.scale.y",
                                     peak: Motion.intakeScaleY, rest: CGFloat(1),
                                     duration: Motion.intakeDuration,
                                     growFraction: Motion.intakeGatherFraction)
            }
        }
        applicationIntakeWork = work
        if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
        } else {
            work.perform()
        }
    }

    private func clearApplicationIntakeRequest() {
        applicationIntakeWork?.cancel()
        applicationIntakeWork = nil
        applicationIntakeUntil = 0
    }

    /// 隐藏时撤销待播及正在播放的收纳，不影响独立的通知涟漪。
    func cancelApplicationIntake() {
        let wasActive = applicationIntakeWork == nil && CACurrentMediaTime() < applicationIntakeUntil
        clearApplicationIntakeRequest()
        guard wasActive else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for axis in ["x", "y"] {
            let keyPath = "transform.scale.\(axis)"
            tideline.removeAnimation(forKey: "motion.\(keyPath)")
            tideline.setValue(CGFloat(1), forKeyPath: keyPath)
        }
        CATransaction.commit()
    }

    /// 汐线脉冲：新角标出现时细线一次轻涌（仅收起态；进行中重触发从当前
    /// presentation 重新起跳，天然合并为一次）。展开态不脉冲——角标本身即反馈。
    func pulseTideline() {
        guard !isExpandedState else { return }
        // 通知优先：接续收纳当前形态，撤销尚未播放的收纳。
        clearApplicationIntakeRequest()
        notificationPulseUntil = CACurrentMediaTime()
            + (Motion.shouldReduceMotion ? Motion.pulseReduceDuration : Motion.pulseDuration)
        if Motion.shouldReduceMotion {
            Motion.keyframePulse(tideline, keyPath: "opacity",
                                 peak: Motion.pulseReducePeak, rest: Float(1),
                                 duration: Motion.pulseReduceDuration, growFraction: 0.5)
            return
        }
        Motion.keyframePulse(tideline, keyPath: "transform.scale.y",
                             peak: Motion.pulseScalePeakY, rest: CGFloat(1),
                             duration: Motion.pulseDuration, growFraction: Motion.pulseGrowFraction)
        Motion.keyframePulse(tideline, keyPath: "transform.scale.x",
                             peak: Motion.pulseScalePeakX, rest: CGFloat(1),
                             duration: Motion.pulseDuration, growFraction: Motion.pulseGrowFraction)
    }

    /// 汐线波纹：未被展开确认的新角标期间，细线持续涟漪发散。
    /// 展开即用户已知（setExpanded 里停），全部角标消失也停（控制器清）。
    /// 减少动态效果时不做常驻循环（一次性脉冲已足够，且循环动画正是该人群忌讳）。
    func startTidelineRipple() {
        guard !isExpandedState, rippleRings.isEmpty, !Motion.shouldReduceMotion else { return }
        let stagger = Motion.tidelineRippleDuration / Double(Motion.tidelineRippleRingCount)
        for index in 0..<Motion.tidelineRippleRingCount {
            let ring = CALayer()
            ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ring.bounds = CGRect(origin: .zero,
                                 size: CGSize(width: Layout.capsuleWidth, height: Layout.capsuleHeight))
            ring.position = tideline.position
            ring.cornerRadius = Layout.capsuleHeight / 2
            ring.borderWidth = Motion.tidelineRippleBorderWidth
            ring.borderColor = rippleColor
            ring.opacity = 0
            layer?.addSublayer(ring)
            attachRippleAnimation(to: ring, delay: Double(index) * stagger)
            rippleRings.append(ring)
        }
    }

    func stopTidelineRipple() {
        for ring in rippleRings {
            ring.removeAllAnimations()
            ring.removeFromSuperlayer()
        }
        rippleRings.removeAll()
    }

    private var rippleColor: CGColor {
        AppearanceColors.cgColor(.labelColor, alpha: 0.5, for: effectiveAppearance)
    }

    /// 单环循环：自线宽扩散（横向 2.3 倍、纵向到终态波高），淡入快淡出慢
    private func attachRippleAnimation(to ring: CALayer, delay: TimeInterval) {
        let duration = Motion.tidelineRippleDuration
        let begin = CACurrentMediaTime() + delay

        let scaleX = CABasicAnimation(keyPath: "transform.scale.x")
        scaleX.fromValue = 1
        scaleX.toValue = Motion.tidelineRippleScaleX
        scaleX.duration = duration
        scaleX.beginTime = begin
        scaleX.repeatCount = .infinity
        ring.add(scaleX, forKey: "ripple.scale.x")

        let scaleY = CABasicAnimation(keyPath: "transform.scale.y")
        scaleY.fromValue = 1
        scaleY.toValue = Motion.tidelineRippleEndHeight / Layout.capsuleHeight
        scaleY.duration = duration
        scaleY.beginTime = begin
        scaleY.repeatCount = .infinity
        ring.add(scaleY, forKey: "ripple.scale.y")

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [Float(0), Motion.tidelineRipplePeakOpacity, Float(0)]
        opacity.keyTimes = [0, 0.3, 1]
        opacity.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                   CAMediaTimingFunction(name: .easeIn)]
        opacity.duration = duration
        opacity.beginTime = begin
        opacity.repeatCount = .infinity
        ring.add(opacity, forKey: "ripple.opacity")
    }

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
        iconRow.onPreviewWidthChange = { [weak self] in self?.onPreviewWidthChange?() }
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
        iconRow.onUserLaunch = { [weak self] in self?.onUserLaunch?() }
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
        // 裸图层的几何立即跟随窗口；动效只由显式编舞驱动。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        super.layout()
        glass?.frame = bounds
        iconRow.frame = bounds
        // 汐线：胶囊贴底居中
        tideline.bounds = CGRect(origin: .zero, size: CGSize(width: Layout.capsuleWidth,
                                                              height: Layout.capsuleHeight))
        tideline.position = CGPoint(x: bounds.midX, y: 2 + Layout.capsuleHeight / 2)
        tideline.cornerRadius = Layout.capsuleHeight / 2
        for ring in rippleRings {
            ring.position = tideline.position
        }
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
        let ripple = rippleColor
        for ring in rippleRings {
            ring.borderColor = ripple
        }
    }

    // MARK: 拖拽目标

    // 注册在稳定的内容视图上；图标行在再次展开时可以全部重建。
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isExpandedState else { return [] }
        destinationTracking = true
        syncDragContext()
        return dragCoordinator?.update(sender, in: self) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isExpandedState else { return [] }
        destinationTracking = true
        syncDragContext()
        return dragCoordinator?.update(sender, in: self) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dragCoordinator?.exit(self)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isExpandedState && dragCoordinator?.canPerform(sender, in: self) == true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isExpandedState else { return false }
        return dragCoordinator?.perform(sender, in: self) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dragCoordinator?.ended(sender, in: self)
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    func dropLocation(for sender: any NSDraggingInfo) -> ItemDropLocation {
        let point = iconRow.convert(sender.draggingLocation, from: nil)
        return iconRow.dropLocation(at: point)
    }

    func setDropFeedback(_ intent: ItemDropIntent?, accepted: Bool = true) {
        destinationTracking = intent != nil && isExpandedState
        syncDragContext()
        iconRow.setDragPreview(ItemDragPreview(intent: isExpandedState ? intent : nil, accepted: accepted))
    }

    // MARK: 状态切换

    func setExpanded(_ expanded: Bool, apps: [ItemEntry] = [], immediate: Bool = false) {
        if !expanded { setDropFeedback(nil) }
        clearApplicationIntakeRequest()
        notificationPulseUntil = 0
        if expanded {
            // 展开即确认：未读提醒的波纹停住（角标本身接管展示）
            stopTidelineRipple()
            guard !isExpandedState else { return }
            // 代数只在真实状态切换时递增：无操作重入不得否决已排定的淡入淡出
            expandGeneration += 1
            isExpandedState = true
            hoveredItemID = nil
            syncDragContext()
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
            Motion.basic(tideline, keyPath: "transform.scale.x", to: 1.12,
                         duration: Motion.senseDuration)
            Motion.basic(tideline, keyPath: "transform.scale.y", to: 1.5,
                         duration: Motion.senseDuration)
            Motion.basic(tideline, keyPath: "opacity", to: 0.0,
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
            expandGeneration += 1
            isExpandedState = false
            hoveredItemID = nil
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
            // 与感应、通知、收纳共用轴向动画键，后来的动作可从当前形态接管。
            for axis in ["x", "y"] {
                Motion.spring(tideline, keyPath: "transform.scale.\(axis)",
                              from: Motion.capsulePopScale, to: 1.0,
                              stiffness: Motion.capsulePopStiffness, damping: Motion.capsulePopDamping,
                              minDuration: Motion.capsulePopDuration, delay: tail)
            }
        }
    }

    /// 展开态下列表变更：差分刷新，不重播整体动画。
    @discardableResult
    func refreshApps(_ apps: [ItemEntry]) -> ItemListUpdate {
        let result = iconRow.update(apps: apps, rebuildAll: false)
        return result
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

    func setKeyboardSelection(_ identity: AppIdentity?) {
        iconRow.setKeyboardSelection(identity)
    }

    func iconFrame(for identity: AppIdentity) -> NSRect? {
        iconRow.button(for: identity)?.frame
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
        let generation = expandGeneration
        let bridge = MainThreadBridge { [weak self, weak view] in
            guard let self, let view, self.expandGeneration == generation else { return }
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

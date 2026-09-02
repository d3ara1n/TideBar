import AppKit
import QuartzCore

/// 汐线：胶囊随亮暗模式自适应（labelColor 自动解析），辉光呼吸
@MainActor
final class TidelineCapsuleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor.labelColor.withAlphaComponent(0.92)
        let pill = NSBezierPath(roundedRect: bounds,
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        color.setFill()
        pill.fill()
        // 辉光颜色随外观同步，呼吸动画只驱动 shadowOpacity，互不干扰
        layer?.shadowColor = NSColor.labelColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, layer != nil else { return }
        layer?.shadowColor = NSColor.white.cgColor
        layer?.shadowRadius = 5
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 0.28
        // 呼吸只动 shadowOpacity，不动 opacity——避免与展开/收起的视图淡入淡出互相覆盖
        let breath = CABasicAnimation(keyPath: "shadowOpacity")
        breath.fromValue = 0.1
        breath.toValue = 0.5
        breath.duration = 3.2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(breath, forKey: "breath")
    }
}

/// 展开态背景：macOS 26+ 液态玻璃（NSGlassEffectView）
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

/// 展开态背景：旧系统回退自绘深色胶囊
@MainActor
final class PillBarBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        NSColor.black.withAlphaComponent(0.42).setFill()
        pill.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        pill.lineWidth = 1
        pill.stroke()
    }
}

@MainActor
enum BarBackgroundFactory {
    static var usesGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func make() -> NSView {
        if #available(macOS 26.0, *) {
            return GlassBarBackgroundView(frame: .zero)
        }
        return PillBarBackgroundView(frame: .zero)
    }
}

/// 图标横排：布局按钮 + 展开时的「错峰升降」上涌动画；
/// 列表变更走差分（新项错峰上涌、旧项淡出），只有展开动画才全量重播
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
        // 消失项：淡出后移除（completionHandler 在主线程回调）
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
        staggerIn(newcomers)
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

    /// 展开全量上涌：图标自窗口底边下涌出（decisions「错峰升降」）；
    /// beginTime + fillMode(.backwards) 实现逐项延迟，不改 frame、不与布局打架
    func appearStaggered() {
        alphaValue = 1
        staggerIn(buttons.enumerated().map { ($0.element, $0.offset) })
    }

    private func staggerIn(_ items: [(button: AppIconButton, index: Int)]) {
        alphaValue = 1
        let now = CACurrentMediaTime()
        for (button, index) in items {
            guard let layer = button.layer else { continue }
            let delay = CFTimeInterval(index) * Layout.staggerStep
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = -14
            rise.toValue = 0
            rise.duration = Layout.staggerDuration
            rise.beginTime = now + delay
            rise.fillMode = .backwards
            rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(rise, forKey: "rise")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Layout.staggerDuration
            fade.beginTime = now + delay
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "fade")
        }
    }
}

/// 面板内容：收起态汐线胶囊 ↔ 展开态图标栏（含过渡动画）
@MainActor
final class TideBarView: NSView {
    private let capsule = TidelineCapsuleView()
    private let barBackground = BarBackgroundFactory.make()
    private let iconRow = IconRowView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        iconRow.onLaunch = { entry in entry.activate() }
        addSubview(barBackground)
        addSubview(iconRow)
        addSubview(capsule)
        barBackground.alphaValue = 0
        iconRow.alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        barBackground.frame = bounds
        iconRow.frame = bounds
        capsule.frame = NSRect(x: bounds.midX - Layout.capsuleWidth / 2,
                               y: 2,
                               width: Layout.capsuleWidth,
                               height: Layout.capsuleHeight)
    }

    /// 切换展开/收起；展开时用给定 app 列表重建图标并错峰上涌
    func setExpanded(_ expanded: Bool, apps: [AppEntry]) {
        if expanded {
            iconRow.update(apps: apps, rebuildAll: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                barBackground.animator().alphaValue = 1
                capsule.animator().alphaValue = 0
            }
            iconRow.appearStaggered()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                barBackground.animator().alphaValue = 0
                iconRow.animator().alphaValue = 0
                capsule.animator().alphaValue = 1
            }
        }
    }

    /// 展开态下列表变更：差分刷新，不重播整体动画
    func refreshApps(_ apps: [AppEntry]) {
        iconRow.update(apps: apps, rebuildAll: false)
    }
}

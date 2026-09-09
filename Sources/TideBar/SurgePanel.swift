import AppKit
import ApplicationServices

// MARK: - 潮涌体协议

/// 潮涌体：条目类型提供的长按面板内容。容器（SurgePanel 与控制器）负责窗口、
/// 玻璃材质、锚定定位、Esc 与离场防抖；体自绘内容与自身状态（列表／空／错误／截断）。
/// 悬停由控制器转发采样点驱动（非激活悬浮窗上 NSTrackingArea 不可靠）。
/// 键盘会话（⌥Tab）只覆盖应用窗口导航，相关钩子由应用体实现。
@MainActor
protocol SurgeBody: AnyObject {
    /// 期望的面板内容尺寸；面板窗口与玻璃按此包裹
    var bodySize: NSSize { get }
    /// 悬停采样（体坐标系）：体自行命中处理
    func setHover(at point: NSPoint)
    /// 错峰升起（进入动画，与汐线展开共用语言）
    func rise()
    /// 反向退落；返回总时长
    @discardableResult
    func drop() -> TimeInterval
    /// 语言切换时重绘动态文案
    func refreshLocalizedText()
    /// 键盘会话选择（应用窗口体）
    func setKeyboardSelection(_ identifier: Int?)
    /// 键盘会话导航标识（应用窗口体）
    func rowIdentifiers() -> [Int]
}

extension SurgeBody {
    func setHover(at point: NSPoint) {}
    func rise() {}
    @discardableResult
    func drop() -> TimeInterval { 0 }
    func refreshLocalizedText() {}
    func setKeyboardSelection(_ identifier: Int?) {}
    func rowIdentifiers() -> [Int] { [] }
}

/// 体存在类型：既是视图，又实现潮涌体协议
typealias AnySurgeBody = NSView & SurgeBody

// MARK: - 行

/// 行尾标签语义：draw 时按语言解析词条，语言切换即时生效
enum SurgeRowBadge {
    case none
    case minimized
    case offscreen
}

/// 潮涌通用行：图标 + 标题 + 行尾标签；拾取回调由体注入。
@MainActor
final class SurgeRowView: NSView {
    struct Model {
        let identifier: Int
        let title: String
        let icon: NSImage
        let badge: SurgeRowBadge
        /// 暗显（最小化／他屏等降级呈现）
        let isDimmed: Bool
    }

    private let model: Model
    private var hovering = false
    private var keyboardSelected = false

    var onPick: ((Int) -> Void)?

    init(model: Model) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.surgeWidth, height: Layout.surgeRowHeight))
        wantsLayer = true
        alphaValue = model.isDimmed ? 0.45 : 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    var rowIdentifier: Int { model.identifier }

    func setHovered(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        needsDisplay = true
    }

    func setKeyboardSelected(_ on: Bool) {
        guard keyboardSelected != on else { return }
        keyboardSelected = on
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let onGlass = BarBackgroundFactory.usesGlass
        if hovering || keyboardSelected {
            let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 2), xRadius: 6, yRadius: 6)
            if onGlass {
                NSColor.labelColor.withAlphaComponent(keyboardSelected && !hovering ? 0.18 : 0.12).setFill()
            } else {
                NSColor.white.withAlphaComponent(keyboardSelected && !hovering ? 0.2 : 0.14).setFill()
            }
            highlight.fill()
        }
        let side: CGFloat = 18
        let iconRect = NSRect(x: 14, y: (bounds.height - side) / 2, width: side, height: side)
        model.icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleColor: NSColor = onGlass ? .labelColor : NSColor.white.withAlphaComponent(0.92)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: titleColor,
            .paragraphStyle: paragraph,
        ]
        // 状态标签：最小化优先，其次他屏；宽度按文字实测，仅占用行尾空间
        let badgeText: String?
        switch model.badge {
        case .none: badgeText = nil
        case .minimized: badgeText = L10nManager.shared.current.string("window.minimizedBadge", table: .runtime)
        case .offscreen: badgeText = L10nManager.shared.current.string("window.offscreenBadge", table: .runtime)
        }
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Layout.surgeMinimizedBadgeFontSize, weight: .medium),
            .foregroundColor: titleColor,
        ]
        var badgeWidth: CGFloat = 0
        var textSize = NSSize.zero
        if let badgeText {
            textSize = (badgeText as NSString).size(withAttributes: badgeAttributes)
            badgeWidth = textSize.width + Layout.surgeMinimizedBadgePaddingX * 2
        }
        let badgeReserve = badgeText == nil ? 0 : badgeWidth + Layout.surgeMinimizedBadgeGap
        let titleRect = NSRect(x: iconRect.maxX + 10, y: (bounds.height - 17) / 2,
                               width: bounds.width - iconRect.maxX - 24 - badgeReserve, height: 17)
        (model.title as NSString).draw(in: titleRect, withAttributes: attributes)

        if let badgeText {
            let badgeRect = NSRect(x: bounds.width - Layout.surgeMinimizedBadgeTrailing - badgeWidth,
                                   y: (bounds.height - Layout.surgeMinimizedBadgeHeight) / 2,
                                   width: badgeWidth, height: Layout.surgeMinimizedBadgeHeight)
            let background = NSBezierPath(roundedRect: badgeRect,
                                            xRadius: Layout.surgeMinimizedBadgeCornerRadius,
                                            yRadius: Layout.surgeMinimizedBadgeCornerRadius)
            let fill: NSColor
            if onGlass {
                fill = NSColor(cgColor: AppearanceColors.cgColor(.labelColor, alpha: 0.14,
                                                                 for: effectiveAppearance)) ?? .labelColor
            } else {
                fill = NSColor.white.withAlphaComponent(0.18)
            }
            fill.setFill()
            background.fill()
            // draw(in:) 水平自然对齐且贴顶，用恰好包裹文字的 rect 以标签中心手动居中
            let textRect = NSRect(x: badgeRect.midX - textSize.width / 2,
                                  y: badgeRect.midY - textSize.height / 2,
                                  width: textSize.width, height: textSize.height)
            (badgeText as NSString).draw(in: textRect, withAttributes: badgeAttributes)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onPick?(model.identifier)
        }
    }
}

// MARK: - 错峰升降

/// 行级错峰动画：靠近图标的行先动；应用窗口行与目录最近文件行共用同一语言。
@MainActor
enum SurgeMotion {
    /// 升起：自图标侧（下）逐行向上传递
    static func rise(_ rows: [NSView]) {
        for (index, row) in rows.reversed().enumerated() {
            guard let layer = row.layer else { continue }
            let delay = Double(index) * Layout.surgeStaggerStep
            if Motion.shouldReduceMotion {
                Motion.basic(layer, keyPath: "opacity", from: 0.0, to: 1.0,
                             duration: Motion.reducedMotionFadeDuration, delay: delay)
            } else {
                Motion.spring(layer, keyPath: "transform.translation.y", from: Motion.surgeRowRiseOffset, to: 0,
                              stiffness: Motion.iconRiseStiffness, damping: Motion.iconRiseDamping,
                              minDuration: Motion.iconRiseDuration, delay: delay)
                Motion.basic(layer, keyPath: "opacity", from: 0.0, to: 1.0,
                             duration: Motion.iconRiseDuration, delay: delay)
            }
        }
    }

    /// 退落：顶部先坠、逐行向下传递（easeIn 加速离场，与收起语言一致）；返回总时长
    @discardableResult
    static func drop(_ rows: [NSView]) -> TimeInterval {
        for (index, row) in rows.enumerated() {
            guard let layer = row.layer else { continue }
            let delay = Double(index) * Layout.surgeStaggerStep
            if !Motion.shouldReduceMotion {
                Motion.basic(layer, keyPath: "transform.translation.y", to: Motion.iconDropOffset,
                             duration: Motion.dropDuration, curve: .easeIn, delay: delay)
            }
            Motion.basic(layer, keyPath: "opacity", to: 0.0,
                         duration: Motion.shouldReduceMotion ? Motion.reducedMotionFadeDuration : Motion.dropDuration,
                         curve: .easeIn, delay: delay)
        }
        return Layout.surgeStaggerStep * Double(max(rows.count - 1, 0))
            + (Motion.shouldReduceMotion ? Motion.reducedMotionFadeDuration : Motion.dropDuration)
    }
}

// MARK: - 应用体

/// 应用潮涌体：窗口行列表。本屏正常 → 他屏暗显 → 最小化暗显＋「已最小化」标签。
/// 潮涌：图标下方点点语义的对偶，点击行 = 还原/聚焦对应窗口。
@MainActor
final class AppSurgeView: NSView, SurgeBody {
    var onPick: ((WindowSnapshot) -> Void)?

    private var rows: [SurgeRowView] = []
    private var snapshots: [Int: WindowSnapshot] = [:]
    var bodySize: NSSize {
        NSSize(width: Layout.surgeWidth,
               height: CGFloat(rows.count) * Layout.surgeRowHeight + Layout.surgeVPadding * 2)
    }

    /// kAXDocument → 文档图标；非文件路径/不存在则回退 app 图标
    private static func icon(for document: String?, appIcon: NSImage) -> NSImage {
        guard let document else { return appIcon }
        let path = document.hasPrefix("file://") ? URL(string: document)?.path : document
        guard let path, path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { return appIcon }
        return NSWorkspace.shared.icon(forFile: path)
    }

    init(windows: [WindowSnapshot], screen: NSScreen, appIcon: NSImage) {
        let viewDisplayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        func onScreen(_ window: WindowSnapshot) -> Bool {
            guard let viewDisplayID, let screenID = window.screenID else { return false }
            return screenID == viewDisplayID
        }
        let active = windows.filter { !$0.isMinimized }
        let ordered: [(snapshot: WindowSnapshot, isOffscreen: Bool)] =
            active.filter(onScreen).map { ($0, false) }
            + active.filter { !onScreen($0) }.map { ($0, true) }
            + windows.filter(\.isMinimized).map { ($0, !onScreen($0)) }
        let fallbackTitle = L10nManager.shared.current.string("window.fallbackTitle", table: .runtime)
        super.init(frame: .zero)
        wantsLayer = true

        let count = ordered.count
        for (index, entry) in ordered.enumerated() {
            let model = SurgeRowView.Model(identifier: entry.snapshot.elementIdentifier,
                                           title: entry.snapshot.title ?? fallbackTitle,
                                           icon: Self.icon(for: entry.snapshot.document, appIcon: appIcon),
                                           badge: entry.snapshot.isMinimized ? .minimized
                                               : (entry.isOffscreen ? .offscreen : .none),
                                           isDimmed: entry.snapshot.isMinimized || entry.isOffscreen)
            let row = SurgeRowView(model: model)
            row.onPick = { [weak self] identifier in self?.pick(identifier) }
            row.frame = NSRect(x: 0,
                               y: Layout.surgeVPadding + CGFloat(count - 1 - index) * Layout.surgeRowHeight,
                               width: Layout.surgeWidth,
                               height: Layout.surgeRowHeight)
            snapshots[model.identifier] = entry.snapshot
            rows.append(row)
            addSubview(row)
        }
        frame = NSRect(origin: .zero, size: bodySize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 行点击：按行标识取回窗口快照交给拾取回调
    private func pick(_ identifier: Int) {
        if let snapshot = snapshots[identifier] {
            onPick?(snapshot)
        }
    }

    /// 悬停轮询驱动（面板内容坐标）：命中行高亮，其余清悬停
    func setHover(at point: NSPoint) {
        let hit = hitTest(point) as? SurgeRowView
        for row in rows {
            row.setHovered(row === hit)
        }
    }

    func setKeyboardSelection(_ identifier: Int?) {
        for row in rows {
            row.setKeyboardSelected(identifier == row.rowIdentifier)
        }
    }

    func refreshLocalizedText() {
        for row in rows {
            row.needsDisplay = true
        }
    }

    func rowIdentifiers() -> [Int] {
        rows.map(\.rowIdentifier)
    }

    func rise() {
        SurgeMotion.rise(rows)
    }

    @discardableResult
    func drop() -> TimeInterval {
        SurgeMotion.drop(rows)
    }
}

// MARK: - 面板

/// 潮涌宿主窗口：非激活、悬浮于图标栏之上（TidePanel 同款约束 + 高一级）。
/// 无需成为 key：方向键由 app 级 local monitor 拦截，不依赖潮涌面板的 key 状态。
@MainActor
final class SurgePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
}

/// 潮涌容器视图：玻璃底（或回退深色卡）+ 体内容；材质归容器，体只画内容。
@MainActor
final class SurgeContainerView: NSView {
    let body: AnySurgeBody
    private let glass: NSView?

    init(body: AnySurgeBody) {
        self.body = body
        glass = BarBackgroundFactory.makeGlassIfAvailable(cornerRadius: 12)
        super.init(frame: NSRect(origin: .zero, size: body.bodySize))
        wantsLayer = true
        if let glass {
            addSubview(glass)
        }
        body.frame = bounds
        addSubview(body)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        glass?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        // 玻璃路径材质自绘背景；仅旧系统回退时手绘深色卡
        guard glass == nil else { return }
        let background = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.55).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()
    }
}

import AppKit
import Combine
import TideBarCore

/// 稳定托盘符号 + 未结束数量 + 完成个数进度。收起只停止显示动画，不停止工作。
@MainActor
final class TaskTrayTileView: NSView, ItemBarArtwork {
    var preferredWidth: CGFloat { Layout.iconSlot }
    var usesSharedHoverEffects: Bool { false }
    private var session: TaskTraySession?
    private var subscription: AnyCancellable?
    private let symbol = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private var active = false
    private var highlighted = false
    private var feedback: ItemDragIconState = .idle

    init(entry: ItemEntry) {
        super.init(frame: .zero)
        wantsLayer = true
        symbol.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)
        symbol.imageScaling = .scaleProportionallyDown
        addSubview(symbol)
        badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        badge.alignment = .center
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.masksToBounds = true
        badge.setAccessibilityElement(false)
        addSubview(badge)
        progress.style = .bar
        progress.controlSize = .mini
        progress.minValue = 0
        progress.maxValue = 1
        progress.isDisplayedWhenStopped = false
        addSubview(progress)
        update(entry: entry)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func update(entry: ItemEntry) {
        guard let id = WidgetReferences.payload(for: entry.reference)?.instanceID else { return }
        let next = TaskTrayStore.shared.session(for: id)
        if session !== next {
            session = next
            subscription = next.changes.sink { [weak self] in self?.refresh() }
        }
        toolTip = TaskTrayWidgetBehavior.hoverName(for: entry)
        setAccessibilityLabel(toolTip)
        refresh()
    }

    func setActive(_ active: Bool) {
        self.active = active
        refresh()
    }

    func setHighlightState(hovered: Bool, selected: Bool) {
        highlighted = hovered || selected
        needsDisplay = true
    }

    func setDragFeedback(_ state: ItemDragIconState) {
        feedback = state
        symbol.alphaValue = state == .rejected ? 0.35 : 1
        needsDisplay = true
    }

    private func refresh() {
        guard let session else { return }
        badge.stringValue = session.badgeCount > 99 ? "99+" : "\(session.badgeCount)"
        badge.isHidden = session.badgeCount == 0
        badge.layer?.backgroundColor = AppearanceColors.cgColor(.systemBlue, for: effectiveAppearance)
        symbol.contentTintColor = .labelColor
        progress.stopAnimation(nil)
        progress.isHidden = session.unfinishedCount == 0
        if let fraction = session.countProgress {
            progress.isIndeterminate = false
            progress.doubleValue = fraction
            progress.toolTip = TaskTrayText.string("tray.countProgress", session.waveFinished, session.waveTotal)
        } else {
            progress.isIndeterminate = true
            progress.toolTip = TaskTrayText.string("tray.running")
            if active && session.unfinishedCount > 0 && !Motion.shouldReduceMotion {
                progress.startAnimation(nil)
            }
        }
        setAccessibilityValue(TaskTrayText.string("tray.pendingCount", session.badgeCount))
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func layout() {
        super.layout()
        let side = Layout.iconSize
        let tile = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        symbol.frame = tile.insetBy(dx: side * 0.23, dy: side * 0.23).offsetBy(dx: 0, dy: 2)
        let badgeWidth: CGFloat = session?.badgeCount ?? 0 > 99 ? 27 : 21
        badge.frame = NSRect(x: tile.maxX - badgeWidth + 3, y: tile.maxY - 15, width: badgeWidth, height: 16)
        progress.frame = NSRect(x: tile.minX + 7, y: tile.minY + 5, width: side - 14, height: 5)
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = Layout.iconSize
        let rect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let path = NSBezierPath(roundedRect: rect, xRadius: side * 0.225, yRadius: side * 0.225)
        let color: NSColor = feedback == .receiving ? .controlAccentColor : .labelColor
        color.withAlphaComponent(highlighted || feedback == .receiving ? 0.20 : 0.10).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
        if Motion.shouldReduceMotion, session?.unfinishedCount ?? 0 > 0, session?.countProgress == nil {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 7, y: rect.minY + 5, width: side - 14, height: 3),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

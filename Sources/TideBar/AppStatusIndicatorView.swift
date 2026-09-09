import AppKit
import QuartzCore

/// 应用运行与窗口状态标记：灰色短线、窗口圆点和数量之间连续过渡。
/// 圆点四态：亮/灰 = 点击后本屏有/无变化（窗口在本屏/别屏），
/// 实/空 = 活跃/最小化；颜色通道即点击后果预期，与形态通道正交。
@MainActor
final class AppStatusIndicatorView: NSView {
    /// isDimmed = 窗口归属不在本屏（归属未知时按本屏处理，不淡化）
    private struct WindowDot: Equatable {
        let isMinimized: Bool
        let isDimmed: Bool

        var order: Int { (isMinimized ? 2 : 0) + (isDimmed ? 1 : 0) }
    }

    private enum State: Equatable {
        case none
        case running
        case windows([WindowDot])
        case count(Int)
    }

    private let markers: [CALayer] = (0..<5).map { _ in CALayer() }
    private let countLayer = CATextLayer()
    private var state: State = .none

    init(entry: AppEntry) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for marker in markers {
            marker.opacity = 0
            layer?.addSublayer(marker)
        }
        countLayer.alignmentMode = .center
        countLayer.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        countLayer.fontSize = 9.5
        countLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        countLayer.opacity = 0
        layer?.addSublayer(countLayer)
        update(entry: entry, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        countLayer.frame = NSRect(x: 0, y: 1.5, width: bounds.width, height: 12)
        apply(state, animated: false, previous: state)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(state, animated: false, previous: state)
    }

    func update(entry: AppEntry, animated: Bool) {
        let next = Self.makeState(entry, viewDisplayID: viewDisplayID)
        guard next != state else {
            apply(next, animated: false, previous: state)
            return
        }
        let previous = state
        state = next
        apply(next, animated: animated, previous: previous)
    }

    /// 所在面板的显示器；未挂载时返回 nil，点色按本屏处理
    private var viewDisplayID: CGDirectDisplayID? {
        (window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func makeState(_ entry: AppEntry, viewDisplayID: CGDirectDisplayID?) -> State {
        guard entry.isRunning else { return .none }
        guard let windows = entry.windows, !windows.isEmpty else { return .running }
        if windows.count > markersLimit { return .count(windows.count) }
        let dots = windows.map { window in
            WindowDot(isMinimized: window.isMinimized,
                      isDimmed: {
                          guard let viewDisplayID, let screenID = window.screenID else { return false }
                          return screenID != viewDisplayID
                      }())
        }.sorted { $0.order < $1.order }
        return .windows(dots)
    }

    private static let markersLimit = 5

    private func apply(_ next: State, animated: Bool, previous: State) {
        let reduceMotion = Motion.shouldReduceMotion
        let shouldAnimate = animated && !reduceMotion
        let tone = AppearanceColors.cgColor(.labelColor, for: effectiveAppearance)
        let quietTone = AppearanceColors.cgColor(.secondaryLabelColor, for: effectiveAppearance)

        switch next {
        case .none:
            for (index, marker) in markers.enumerated() {
                set(marker, keyPath: "opacity", to: Float(0), animated: shouldAnimate,
                    delay: Double(markers.count - index - 1) * Motion.statusStagger)
            }
            set(countLayer, keyPath: "opacity", to: Float(0), animated: shouldAnimate)

        case .running:
            configure(marker: markers[0], index: 0, count: 1, filled: true,
                      dash: true, color: quietTone, animated: shouldAnimate)
            for (index, marker) in markers.dropFirst().enumerated() {
                set(marker, keyPath: "opacity", to: Float(0), animated: shouldAnimate,
                    delay: Double(markers.count - index - 2) * Motion.statusStagger)
            }
            set(countLayer, keyPath: "opacity", to: Float(0), animated: shouldAnimate)

        case .windows(let dots):
            for (index, marker) in markers.enumerated() {
                guard index < dots.count else {
                    set(marker, keyPath: "opacity", to: Float(0), animated: shouldAnimate)
                    continue
                }
                let dot = dots[index]
                configure(marker: marker, index: index, count: dots.count,
                          filled: !dot.isMinimized, dash: false,
                          color: dot.isDimmed ? quietTone : tone,
                          animated: shouldAnimate)
            }
            set(countLayer, keyPath: "opacity", to: Float(0), animated: shouldAnimate)

        case .count(let count):
            countLayer.string = "\(count)"
            countLayer.foregroundColor = tone
            for (index, marker) in markers.enumerated() {
                set(marker, keyPath: "opacity", to: Float(0), animated: shouldAnimate,
                    delay: Double(markers.count - index - 1) * Motion.statusStagger)
            }
            let changedCount: Bool
            if case .count(let oldCount) = previous {
                changedCount = oldCount != count
            } else {
                changedCount = true
            }
            if shouldAnimate && changedCount {
                Motion.basic(countLayer, keyPath: "opacity", from: Float(0), to: Float(1),
                             duration: Motion.statusDuration)
                Motion.spring(countLayer, keyPath: "transform.scale", from: CGFloat(0.8), to: CGFloat(1),
                              stiffness: Motion.statusStiffness, damping: Motion.statusDamping,
                              minDuration: Motion.statusDuration)
            } else {
                set(countLayer, keyPath: "opacity", to: Float(1), animated: false)
                set(countLayer, keyPath: "transform.scale", to: CGFloat(1), animated: false)
            }
        }

        if animated && reduceMotion, let root = layer {
            Motion.basic(root, keyPath: "opacity", from: Float(0.55), to: Float(1),
                         duration: Motion.reducedMotionFadeDuration)
        }
    }

    private func configure(marker: CALayer, index: Int, count: Int, filled: Bool,
                           dash: Bool, color: CGColor, animated: Bool) {
        let size = dash
            ? CGSize(width: Layout.runningDashWidth, height: Layout.runningDashHeight)
            : CGSize(width: Layout.dotSize, height: Layout.dotSize)
        let totalWidth = dash
            ? Layout.runningDashWidth
            : CGFloat(count - 1) * Layout.dotPitch + Layout.dotSize
        let x = bounds.midX - totalWidth / 2 + size.width / 2
            + (dash ? 0 : CGFloat(index) * Layout.dotPitch)
        let position = CGPoint(x: x, y: Layout.dotBaseline + Layout.dotSize / 2)
        let background = filled ? color : NSColor.clear.cgColor
        let borderWidth: CGFloat = dash ? 0 : 1.1
        let delay = dash ? 0 : Double(index) * Motion.statusStagger

        set(marker, keyPath: "bounds", to: CGRect(origin: .zero, size: size),
            animated: animated, delay: delay)
        set(marker, keyPath: "position", to: position, animated: animated, delay: delay)
        set(marker, keyPath: "cornerRadius", to: min(size.width, size.height) / 2,
            animated: animated, delay: delay)
        set(marker, keyPath: "backgroundColor", to: background, animated: animated, delay: delay)
        set(marker, keyPath: "borderColor", to: color, animated: animated, delay: delay)
        set(marker, keyPath: "borderWidth", to: borderWidth, animated: animated, delay: delay)
        set(marker, keyPath: "opacity", to: Float(1), animated: animated, delay: delay)
    }

    private func set(_ target: CALayer, keyPath: String, to value: Any,
                     animated: Bool, delay: TimeInterval = 0) {
        if animated {
            Motion.basic(target, keyPath: keyPath, to: value,
                         duration: Motion.statusDuration, delay: delay)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            target.setValue(value, forKeyPath: keyPath)
            CATransaction.commit()
        }
    }
}

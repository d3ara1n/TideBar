import AppKit

/// 全屏收起态的紧凑点击入口。窗口边界就是命中边界，区域外点击由 WindowServer 正常分发。
@MainActor
final class TidelineClickPanel: NSPanel {
    private let clickView = TidelineClickView(frame: .zero)

    var onClick: (() -> Void)? {
        get { clickView.onClick }
        set { clickView.onClick = newValue }
    }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        contentView = clickView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setEnabled(_ enabled: Bool, above panel: TidePanel) {
        if enabled {
            guard !isVisible else { return }
            order(.above, relativeTo: panel.windowNumber)
        } else {
            clickView.cancelClick()
            if isVisible { orderOut(nil) }
        }
    }
}

@MainActor
private final class TidelineClickView: NSView {
    var onClick: (() -> Void)?
    private var pressed = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let shouldOpen = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if shouldOpen { onClick?() }
    }

    func cancelClick() {
        pressed = false
    }
}

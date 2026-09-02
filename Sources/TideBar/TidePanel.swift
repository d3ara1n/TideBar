import AppKit

/// 悬浮于所有 Space 的非激活面板（decisions.md「交互与技术约定」）
@MainActor
final class TidePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 先尝试系统状态栏层级，使展开栏覆盖最大化窗口；若实测干扰系统面板再回退为 .floating。
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true   // 汐线常态点击穿透；展开态由 controller 关闭
    }

    override var canBecomeKey: Bool { true }
}

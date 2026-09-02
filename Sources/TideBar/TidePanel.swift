import AppKit

/// 悬浮于所有 Space 的非激活面板
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
        // 状态栏层级：展开栏覆盖最大化窗口；潮涌面板在此基础上再加一级
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true   // 汐线常态点击穿透；展开态由 controller 关闭
    }

    override var canBecomeKey: Bool { true }
}

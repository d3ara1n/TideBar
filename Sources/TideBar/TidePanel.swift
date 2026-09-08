import AppKit
import QuartzCore

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

    /// 窗口原点与内容中心在同一次事务中更新，绘制前完成布局。
    /// 显式窗口动画仍驱动 frame；每次几何更新都同步内容，避免汐线追赶窗口中心。
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        super.setFrame(frameRect, display: false)
        contentView?.layoutSubtreeIfNeeded()
        if flag { displayIfNeeded() }
    }

    override var canBecomeKey: Bool { true }
}

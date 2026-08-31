import AppKit

// TideBar · 汐 — 屏幕底部的潮汐 Dock
// 阶段 0 骨架：常驻一条白色细线，验证「底边悬浮 + 全 Space 常驻 + hover 感知」基础链路

/// 悬浮于所有 Space 底部的非激活面板
final class TidePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}

/// 底部细线视图：白色圆角胶囊，hover 感知
final class TidelineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: NSRect(x: bounds.midX - 80, y: 4, width: 160, height: 5),
                                xRadius: 2.5, yRadius: 2.5)
        NSColor.white.withAlphaComponent(0.9).setFill()
        pill.fill()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        NSLog("tide rising 🌊")
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("tide ebbing 🌙")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标、不进 Cmd-Tab

guard let screen = NSScreen.main else { fatalError("no screen") }
let size = NSSize(width: 240, height: 28)
let panel = TidePanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2,
                                          y: screen.frame.minY + 4,
                                          width: size.width,
                                          height: size.height))
panel.contentView = TidelineView(frame: NSRect(origin: .zero, size: size))
panel.orderFrontRegardless()

app.run()

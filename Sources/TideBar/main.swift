import AppKit

// TideBar · 汐 — 屏幕底部的潮汐 Dock
// 汐线 ↔ 图标栏潮汐交互（M1）+ AX 窗口管理：点点/潮涌/还原（M2）

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标、不进 Cmd-Tab

let controller = TideBarController()
controller.start()

app.run()

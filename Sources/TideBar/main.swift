import AppKit

// TideBar · 汐 — 屏幕底部的潮汐 Dock
// M1：汐线 ↔ 图标栏 的潮汐交互验证（plans/todo-2026-09-core-interaction.md）

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标、不进 Cmd-Tab

let controller = TideBarController()
controller.start()

app.run()

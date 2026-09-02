import AppKit

// TideBar · 汐 — 屏幕底部的潮汐 Dock
// 汐线 ↔ 图标栏潮汐交互；点点/潮涌直达任意窗口（含最小化）

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 无 Dock 图标、不进 Cmd-Tab
let delegate = AppDelegate()
app.delegate = delegate
app.run()

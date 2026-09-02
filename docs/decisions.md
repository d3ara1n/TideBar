# 已定决策

只增不改的决策真值。推翻决策时新增条目并注明取代关系，不删旧条。每条决策就地附调研来源。

## 架构：藏 UI、留进程

系统 Dock 进程保留运行，仅配置级隐藏；TideBar 作为悬浮面板盖在底部。所有商业 Dock 替代品（uBar/ActiveDock）均此路线。

```bash
# 隐藏系统 Dock（uBar 官方方案：自动隐藏延迟 1000 秒 = 实际不可唤出）
defaults write com.apple.dock autohide-delay -float 1000 && killall Dock
# 恢复
defaults delete com.apple.dock autohide-delay && killall Dock
```

这是对用户系统的修改，将来由 App 内首次启动向导引导用户执行，不静默改。

来源：uBar 官方文档 https://ubarapp.com/documentation/

## 为什么不能真禁用 Dock 进程

`launchctl bootout gui/$(id -u)/com.apple.dock` 技术上可持久禁用，但 Dock 进程还托管：

| 托管功能 | 禁用后果 |
|---|---|
| Cmd-Tab 应用切换器 | 失效 |
| Mission Control / App Exposé | 失效（由 Dock 进程渲染） |
| 窗口最小化 | 应用请求最小化时挂起（genie 动画由 Dock 渲染） |
| Launchpad | 失效（macOS 26 已移除 Launchpad，此项自然消失） |

来源：
- https://512pixels.net/2022/04/fix-mission-control-and-app-switcher-crashes-in-macos-monterey/
- https://stackoverflow.com/questions/9778688/

## 功能可行性边界

立案时查此表定成本预期：⭐ 常规，⭐⭐⭐ 以上是需要专项调研的硬骨头。

| 功能 | 方案 | 难度 |
|---|---|---|
| 启动/固定图标/拖拽管理 | NSWorkspace + NSDraggingDestination | ⭐ |
| 运行中应用 + 指示点 | `NSWorkspace.runningApplications` + 通知 | ⭐ |
| 右键菜单（退出/Finder 显示） | NSMenu + `NSRunningApplication.terminate()` | ⭐ |
| 废纸篓监控/移入/清空 | FSEvents 监控 `~/.Trash` + `NSWorkspace.recycleURLs` | ⭐⭐ |
| 废纸篓「放回原处」 | 无公开 API，需解析 `.DS_Store` 私有 `ptbN`/`ptbL` 记录 | ⭐⭐⭐ 可砍 |
| 悬停窗口实时预览 | ScreenCaptureKit（公开 API，12.3+） | ⭐⭐⭐ |
| 最小化窗口枚举/还原 | 无公开 API：AX（`kAXMinimized` 设 false 还原）或私有 SkyLight；AltTab 2026 已全量转 SkyLight | ⭐⭐⭐⭐ 最难 |
| 图标角标 | 无公开 API（NSDockTile 仅自用） | ⭐⭐⭐ 可砍 |
| 放大效果/启动弹跳 | 自绘动画 | ⭐ |
| 最小化动画本身 | 不可接管（Dock+WindowServer 私有管线）；藏 Dock 架构下系统动画照常，观感 = 窗口缩向底边，可接受 | — |
| Mission Control 按钮 | `open -a "Mission Control"`（已验证 macOS 26 存在该 App） | ⭐ |

来源：
- ScreenCaptureKit（WWDC22）：https://developer.apple.com/videos/play/wwdc2022/10156/
- AltTab SkyLight 重构：https://github.com/lwouis/alt-tab-macos/commit/163cf315aab3360d5544d97b20e2cf54047b9c25
- Put Back 的 .DS_Store 私有格式：https://stackoverflow.com/questions/18707618/
- DockDoor（AX + ScreenCaptureKit 参考实现）：https://github.com/ejbills/DockDoor

## 权限策略

- 当前零权限：hover 检测用不可见热区窗口 + NSTrackingArea，鼠标事件不需授权（键盘全局监听才要辅助功能）
- 后期加窗口预览 → 屏幕录制权限；最小化窗口管理 → 辅助功能权限。均告别 App Store，走 Developer ID + 公证直发（$99/年，开发期不需要）

## 交互与技术约定

- **窗口层组合**：borderless + nonactivating + canJoinAllSpaces + fullScreenAuxiliary，`level = .floating`
- **全屏 Space**：默认只留细线不展开（盖住视频/游戏体验差；uBar 的做法是完全隐藏）
- **hover 收起防抖**：mouse exited 后 ~300ms 延迟收起，期间 re-enter 取消，防边缘抖动闪烁
- **多显示器**：每屏一个 panel，监听 `NSScreen.didChangeScreenParametersNotification`

## 2026-09 调研修订

来源：[research-dock-alternatives.md](research-dock-alternatives.md) §六，逐条注明取代关系。

1. **使命收窄（取代「核心差异化 = 零存在感 + 完整 Dock 功能」）**：不做 dock 杂务——废纸篓、角标、拖拽管理不做，窗口预览延后。被隐藏 Dock 带走的能力用自有方案还原：窗口瓦片一体收录全部窗口（含最小化），不区分是否最小化，点击即开。
2. **分期推进**：M1 潮汐交互验证（细线 + 展开 + 固定/运行图标，零权限，手感不成立则项目复盘）→ M2 窗口瓦片（AX 窗口枚举/聚焦/还原，需辅助功能权限）→ M3 系统接管向导（App 内开关执行隐藏，快照/恢复/自愈）。
3. **接近检测改道（取代「权限策略」的 NSTrackingArea 热区方案）**：全局 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`。鼠标类事件零权限（仅键盘类需辅助功能）；汐线窗口保持点击穿透，无需热区吃事件。兜底：local monitor + 低频轮询 `NSEvent.mouseLocation`。NSTrackingArea 降级为展开面板内部 hover 方案。
4. **隐藏参数补全（细化「架构」节命令集）**：M3 完整参数 = autohide + autohide-delay 1000 + autohide-time-modifier 0 + no-bouncing + tilesize 16 + magnification false + largesize 16 + mineffect scale。tilesize 组针对 Mission Control/Exposé 无视 autohide 强显；mineffect 针对 genie 动画指向隐藏 Dock 穿帮。向导标配快照/恢复/自愈（隐藏指纹检测 + atexit/signal 兜底）。
5. **废纸篓不做（取代可行性表 FSEvents 行的方案预期）**：将来若重启，已验证路线是 kqueue（`DispatchSourceFileSystemObject` + `O_EVTONLY`），无项目用 FSEvents。
6. **可行性表勘误**：窗口预览的现实 = 枚举用 ScreenCaptureKit、逐窗抓图仍以私有 `CGSHWCaptureWindowList` 为主流（能截最小化窗口；纯 SCK 在 14/15 有崩溃/bug，AltTab 至 macOS 26 才全量 SCK），「AltTab 2026 已全量转 SkyLight」表述过时。录屏授权须重启 app 后生效，向导流程需按此设计。

# TideBar · 汐 — 开发交接文档

> macOS Dock 替代品：平时缩成屏幕底部一条细线，鼠标靠近时如潮汐般展开。核心差异化 = 零存在感 + 完整 Dock 功能。
>
> 本文档承接 2026-08-31 的可行性调研与阶段 0 开发，新会话读此文档即可继续，无需重新调研。

## 1. 产品定位

- **形态**：替代系统 Dock 的自绘底部栏（AppKit / Swift）
- **灵魂交互**：空闲时缩成 2~3pt 细线（白色胶囊，即"汐线"）贴屏幕底边；鼠标进入热区展开为图标栏，离开后收起
- **原则**：系统级功能不自绘（见架构决策），精力全部花在差异化交互与窗口体验上
- **命名**：TideBar（目录/bundle 用 ASCII），中文显示名「汐」。同名 iOS 潮汐监测 App（2024，海洋气象类）无实质冲突；**上架前需复审产品名**
- **对标**：uBar、ActiveDock；参考开源 DockDoor。无现成产品做过"细线收起态"交互，差异化成立

## 2. 关键调研结论（已验证，勿重复调研）

### 2.1 架构决策：藏 UI、留进程 ✅ 已定

系统 Dock 进程**保留运行**，仅配置级隐藏；TideBar 作为悬浮面板盖在底部。所有商业 Dock 替代品（uBar/ActiveDock）均此路线。

```bash
# 隐藏系统 Dock（uBar 官方方案：自动隐藏延迟 1000 秒 = 实际不可唤出）
defaults write com.apple.dock autohide-delay -float 1000 && killall Dock
# 恢复
defaults delete com.apple.dock autohide-delay && killall Dock
```

注意：这是对用户系统的修改，将来应由 App 内首次启动向导引导用户执行，不要静默改。

### 2.2 为什么不能真禁用 Dock 进程（结论：不可行）

`launchctl bootout gui/$(id -u)/com.apple.dock` 技术上可持久禁用，但 Dock 进程还托管：

| 托管功能 | 禁用后果 |
|---|---|
| Cmd-Tab 应用切换器 | 失效 |
| Mission Control / App Exposé | 失效（由 Dock 进程渲染） |
| 窗口最小化 | 应用请求最小化时**挂起**（genie 动画由 Dock 渲染） |
| Launchpad | 失效（macOS 26 已移除 Launchpad，此项自然消失） |

### 2.3 功能可行性速查表

| 功能 | 方案 | 难度 |
|---|---|---|
| 启动/固定图标/拖拽管理 | NSWorkspace + NSDraggingDestination | ⭐ |
| 运行中应用 + 指示点 | `NSWorkspace.runningApplications` + 通知 | ⭐ |
| 右键菜单（退出/Finder 显示） | NSMenu + `NSRunningApplication.terminate()` | ⭐ |
| 废纸篓监控/移入/清空 | FSEvents 监控 `~/.Trash` + `NSWorkspace.recycleURLs` | ⭐⭐ |
| 废纸篓「放回原处」 | 无公开 API，需解析 `.DS_Store` 私有 `ptbN`/`ptbL` 记录 | ⭐⭐⭐ 可砍 |
| 悬停窗口实时预览 | ScreenCaptureKit（公开 API，12.3+） | ⭐⭐⭐ |
| 最小化窗口枚举/还原 | 无公开 API：AX（`kAXMinimized` 设 false 还原，附赠系统 genie-back 动画）或私有 SkyLight；AltTab 2026 已全量转私有 SkyLight 事件 | ⭐⭐⭐⭐ 最难 |
| 图标角标 | 无公开 API（NSDockTile 仅自用） | ⭐⭐⭐ 可砍 |
| 放大效果/启动弹跳 | 自绘动画 | ⭐ |
| 最小化动画本身 | **不可接管**（Dock+WindowServer 私有管线）；藏 Dock 架构下系统动画照常，观感=窗口缩向底边，可接受 | — |
| Mission Control 按钮 | `open -a "Mission Control"`（已验证 macOS 26 存在该 App） | ⭐ |

### 2.4 权限策略

- **MVP 零权限**：hover 检测用不可见热区窗口 + NSTrackingArea，鼠标事件不需任何授权（键盘全局监听才要辅助功能）
- 后期加窗口预览 → 屏幕录制权限；最小化窗口管理 → 辅助功能权限。均会告别 App Store，走 Developer ID + 公证直发（$99/年，开发期不需要）

## 3. 已知坑（后续开发必读）

1. **全屏应用**是独立 Space：面板已设 `.fullScreenAuxiliary` 可悬浮其上，但盖住视频/游戏体验差 → 决策：全屏 Space 时默认只留细线不展开（uBar 的做法是完全隐藏）
2. **Tahoe 特有**：窗口所在 Space 非活跃时 ScreenCaptureKit 可能返回空白帧（阶段 3 前需验证）
3. 与 BetterTouchTool/Rectangle 类窗口管理工具有 AX 互踩案例（uBar 也有幽灵窗口 bug）
4. 多显示器：每屏一个 panel；监听 `NSScreen.didChangeScreenParametersNotification`
5. hover 防抖：收起需延迟（~300ms）+ 重新进入则取消，否则边缘抖动会闪

## 4. 环境与工程约定

- 开发机：macOS 26.6.2（25G83，Tahoe），Apple Silicon，Retina 主屏；Xcode 26 + CLT 26.6 + Swift 6.3.3 已装齐
- 工具链：SPM（`Package.swift`，swift-tools 6.0，最低 macOS 14），**零第三方依赖**，不用 Xcode 工程
- 常用命令：`swift build` / `swift run`（run 会占终端，Ctrl-C 退出；bash 里冒烟测试必须「启动→验证→kill」一条命令内完成）
- bundle id 占位 `dev.tidebar.TideBar`，发布前换用户自己的
- 协作规范见全局 `~/.agents/AGENTS.md`（先提案后行动、未经同意不 commit 等），此处不重复

## 5. 当前进度

**阶段 0（骨架）✅ 已完成**：仓库 `~/Projects/TideBar`，git 已 init **未提交**（等用户确认）。

- `Package.swift`：单 executable target
- `Sources/TideBar/main.swift`：
  - `.accessory` 激活策略（无 Dock 图标、不进 Cmd-Tab）
  - `TidePanel`（NSPanel）：borderless + nonactivating + canJoinAllSpaces + fullScreenAuxiliary，`level = .floating`，底边居中
  - `TidelineView`：透明热区（240×28pt）中画 160×5pt 白色胶囊；NSTrackingArea hover 感知（enter→`tide rising` / exit→`tide ebbing` 日志）
- 编译 + 冒烟（启动 3s 后 kill）均通过

## 6. 路线图

### 阶段 1 — 核心交互（下一步，当前阶段）
- [ ] 展开态视图：~64pt 高图标栏（占位灰块即可），圆角背景
- [ ] 细线 ↔ 图标栏过渡动画（NSAnimationContext / layer 动画），panel frame 随高度调整
- [ ] 收起防抖：mouse exited 后 300ms 延迟收起，期间 re-enter 取消
- [ ] 全屏 Space 检测：全屏时保持细线态
- [ ] 多屏支持：每屏一个 panel + 屏幕参数变更通知

### 阶段 2 — MVP 功能对标 Dock
- [ ] NSWorkspace 运行应用列表 + 运行指示点（+ 启动/退出通知刷新）
- [ ] 固定应用：拖入/拖出/排序，点击启动或激活（`activate(options: [.activateIgnoringOtherApps])`）
- [ ] 右键菜单：退出、在 Finder 中显示、(在阶段 3 加窗口列表)
- [ ] 废纸篓：图标 + FSEvents 计数 + 右键清空 + 拖入移入回收
- [ ] 拖文件到应用图标 → 用该应用打开（LaunchServices）
- [ ] 首次启动向导：执行系统 Dock 隐藏命令 + 可一键还原
- [ ] 打包 `.app`（SPM build 产物 + Info.plist + ad-hoc 签名脚本）

### 阶段 3 — 硬骨头（决定产品上限）
- [ ] AX 枚举各应用窗口（含最小化）+ 点击还原（`kAXMinimized=false`）
- [ ] ScreenCaptureKit 悬停实时预览（先验证 Tahoe 空白帧问题）
- [ ] 角标方案评估（可砍）

## 7. 待决事项

- 首次 git commit 未执行（等用户确认）
- 产品名上架前复审（App Store 有同名 iOS 潮汐工具）
- 阶段 3 的私有 API 路线（AX vs SkyLight）在进入阶段 3 时再定，倾向先 AX（公开 API，App Store 外无所谓但维护成本低）

## 8. 调研来源（备查）

- uBar 官方文档（Dock 隐藏命令/权限说明）：https://ubarapp.com/documentation/
- Dock 进程托管 Mission Control/Cmd-Tab：https://512pixels.net/2022/04/fix-mission-control-and-app-switcher-crashes-in-macos-monterey/
- 禁 Dock 后最小化挂起：https://stackoverflow.com/questions/9778688/
- AltTab 转私有 SkyLight 事件重构：https://github.com/lwouis/alt-tab-macos/commit/163cf315aab3360d5544d97b20e2cf54047b9c25
- DockDoor（AX + ScreenCaptureKit 参考实现）：https://github.com/ejbills/DockDoor
- ScreenCaptureKit 公开 API（WWDC22）：https://developer.apple.com/videos/play/wwdc2022/10156/
- Tahoe 非活跃 Space 空白帧：https://stackoverflow.com/questions/79949880/
- Put Back 的 .DS_Store 私有格式：https://stackoverflow.com/questions/18707618/

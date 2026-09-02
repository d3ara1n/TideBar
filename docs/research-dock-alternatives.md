# 调研：开源 macOS Dock 替代品

调研时间 2026-09。方法：逐仓库克隆读源码（DockDoor master、alt-tab-macos v11.5.0、SketchyBar 2.24.0、Ice v0.11.12、Docky、Focus Dock、Pier、Plank、Latte Dock），其余项目查证 README/issues/发布说明；API 行为经 Apple 官方文档与多来源交叉验证。查证不到的标「未确认」。

本文是调研档案（事实与方案）。据此产生的决策修订见 [decisions.md](decisions.md)；文中与 decisions.md 现有条目的冲突在 §六 单独列出。

## 一、项目全景

真正做「dock 本体」的开源项目很少，且多为 2026 年新建。按成熟度排序：

| 项目 | 活跃度 | 技术栈 | 成熟度 | 系统 Dock 处理 |
|---|---|---|---|---|
| [Docky](https://github.com/josejuanqm/docky) ⭐1253 | 2026-09 仍推送 | Swift + Xcode 工程，GPLv3，macOS 14+ | **最完整能用**：图标/文件夹/Widget/Launchpad/窗口切换器/自定义图标，notarized 分发 | 开关式隐藏 + 看门狗自愈 |
| [Focus Dock](https://github.com/The-Portland-Company/focus-dock-for-macos) ⭐0 | 2026-05→06 | SwiftUI + AppKit（NSPanel + NSHostingController），XcodeGen | **半成品但架构最完整**：iOS 式文件夹、放大、角标、**唯一完整实现最小化窗口** | 最细致的隐藏实现 |
| [AeroBar](https://github.com/adityaonx/AeroBar) ⭐28 | 2026-06→08 alpha | Swift/AppKit + SwiftUI | 半成品：Win11 玻璃任务栏 + 开始菜单 + 窗口标签 | 改设置 + 看门狗保护 |
| [OpenBoringBar](https://github.com/nagisa77/OpenBoringBar) ⭐22 | 2026-04 | Swift | 早期；闭源 [boringBar](https://boringbar.com)（$40，Show HN 520 分）的开源克隆 | 克隆版无隐藏代码，共存 |
| [Pier](https://github.com/openwarehq/pier) ⭐0 | 2026-08 新建 | Swift + SPM（无 Xcode 工程），零权限零网络 | 半成品；与 TideBar 技术路线最像 | **共存派**，只读系统 Dock 镜像 |
| meDock、mikerosoft、TaskLane、deskbar、MultiDock、Tungsten Edge | — | — | 玩具/半成品 | 全部共存 |

第三梯队（玩具/存疑，仅备查）：RetroDock（gist 单文件）、BoxedDock（已停更 2023，实为快捷键切换器）、InfyniDock（内容未深验）、DockMaster Pro（**疑为 AI 生成**：仓库只是静态 HTML 文档站，声称的源码仓库 404）。

增强类（不替代 Dock，但技术高度相关）：

- **[DockDoor](https://github.com/ejbills/DockDoor)** ⭐5977：悬停预览/Alt-Tab 增强；商业版 DockDoor Pro 才真替换 Dock 本体
- **[alt-tab-macos](https://github.com/lwouis/alt-tab-macos)** ⭐16231：Cmd-Tab 增强
- **[DockAway](https://github.com/akhairaddin/DockAway)**：用合成 ⌘⌥D 键（CGEvent）切系统 Dock autohide，读实时配置自校验、退出还原——「只切换不重绘」路线范例

商业对标补充：uBar 官方现行方案即 autohide-delay 1000（见 §二）；boringBar FAQ 承认「隐藏后 Dock 在 Mission Control 里仍可见」（见 §三坑 2）。

**关键发现：没有任何项目做过「细线收起态」**——TideBar 的潮汐交互差异化成立，同时意味着边缘接近检测在 dock 类项目中无先例，需从菜单栏类项目（Ice）借鉴。

## 二、系统 Dock 入口替代方案

### 行业标准：配置级隐藏 + 快照/恢复/自愈

uBar → Docky → Focus Dock → AeroBar 全线一致：

```bash
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000     # 杜绝边缘热区抢先弹出
defaults write com.apple.dock autohide-time-modifier -float 0
defaults write com.apple.dock no-bouncing -bool true
killall Dock
```

- **没有项目静默自动执行**，全是 App 内开关由用户开启
- **没有项目用 launchctl 禁 Dock 进程**（禁用后果见 decisions.md「为什么不能真禁用 Dock 进程」）
- 成熟实现的标配三件套：
  - **快照原始值 → 覆盖 → 恢复**（8 个键左右；对原本不存在的键用 `CFPreferencesSetAppValue(key, nil, …)` 删除回默认）
  - **崩溃自愈**：Docky 用 LoginItems 看门狗 app（DockyDockWatchdog）+ 状态 plist（记录 ownerPID）；Focus Dock 用 atexit/signal handler（QuitBackstop.swift）+「隐藏指纹」检测（autohide=true && delay≥900 && timeModifier=0）防止把自家写入值误存回原始值
  - 恢复时机：关开关、退出、看门狗发现进程异常消失

### 两个进阶参数（Focus Dock 源码注释明言理由）

| 参数 | 理由 |
|---|---|
| `tilesize=16`（最小值）+ `magnification=false` + `largesize=16` | **Mission Control / Exposé 无视 autohide 强显系统 Dock**；缩到 16px 后强显只是「一条细缝」，不抢视觉 |
| `mineffect=scale` | genie 最小化动画指向（已隐藏的）系统 Dock 图标位置，穿帮；scale 原地缩小无指向性 |

另验证：`tilesize` 可写 1（UI 滑块只到 16，defaults 无下限），配合 `pinning=start` 可挪到角落（Ask Different 长答案，未在项目中见到实际使用）。

### 实验路线：让系统 Dock 当「空间保留者」

Docky 的 `Docky/Private/SkyLightSpaceReservationProbe.swift`（实验性，未接入运行时）：用私有 CGS 把系统 Dock 窗口 alpha 设 0——**保留它的屏幕空间预留、只擦像素**，Dock 进程继续占位但不可见。与 TideBar「藏 UI、留进程」架构完全同向，可解决窗口避让问题（§三坑 4），但无人做成，风险高，且依赖私有 API。

### 共存派

Pier、OpenBoringBar、meDock、MultiDock 等完全不动系统 Dock，隐藏留给用户。Pier README 明说「alongside the real Dock or replace it」；代价见 §三坑 4。MultiDock 明确自认「不是替代品」。

## 三、坑清单

1. **Mission Control / Exposé 强显系统 Dock**（无视 autohide）→ `tilesize=16` 对策。双重来源：Focus Dock 源码注释 + boringBar FAQ。
2. **genie 最小化动画指向隐藏 Dock 位置** → `mineffect=scale`。
3. **最小化窗口无落点（最难）**：Cmd+M 后窗口进不可见的 Dock，Cmd+Tab 不还原最小化窗口（须按住 Option）。**调研中只有 Focus Dock 完整解决**（`MinimizedMonitor.swift` + `MinimizeAnimator.swift`）：
   - AX 每 1.5s 轮询各 app `kAXWindows`/`kAXMinimized`，列出最小化窗口作 tile；私有 `_AXUIElementGetWindow` 拿 CGWindowID + 私有 `CGWindowListCreateImage` 缓存「最小化前最后一帧」当缩略图
   - 点击还原 = `AXUIElementSetAttributeValue(kAXMinimized, false)` + `kAXRaiseAction` + `activate(.activateAllWindows)`
   - 拦截动画：AXObserver 监听 `kAXWindowMiniaturizedNotification`，私有 `CGSSetWindowAlpha` 把真实窗口 alpha 归零（系统动画在隐形目标上播放），再自绘「图标飞向 tile」覆盖动画
   - 全程需辅助功能权限；Docky 的窗口切换器也能还原 minimized 窗口但没做动画拦截；其余项目一律不碰
4. **窗口不绕开自绘 dock**：macOS 只为自家 Dock 保留 `visibleFrame`。对策三派：uBar/AeroBar 用 AX 主动重排窗口（Java/Carbon 应用失效、与窗口管理器冲突，uBar 有官方冲突名单）；Rectangle Pro 用户以 `screenEdgeGapBottom` 手动垫边；Pier 承认不做。**展开态会被 maximize 窗口压住，汐线收起态被盖概率低。**
5. **窗口层级 vs IME**：Ghostty PR #5361——窗口 level 提到系统 Dock 之上会破坏日文输入。印证 TideBar `.floating`（低于 Dock）+ 隐藏系统 Dock 的组合。
6. **通知角标拿不到**：macOS 不向第三方发布 dock 角标计数。Pier 直接不做；Focus Dock 用 AX 轮询系统 Dock 树（`com.apple.dock` 的 `AXStatusLabel`）读角标，需辅助功能权限。
7. **`~/.Trash` 可读性不一致**：Pier/Docky 能直接 `contentsOfDirectory` 读，Focus Dock 却遇 EPERM(TCC)（ad-hoc 签名下 AppleScript 也被拒），兜底 = 轮询 shell 调 `/usr/bin/osascript "tell application Finder to count items of trash"`（Apple 签名二进制有独立 AppleEvents 授权）。**macOS 26 上需实测 TideBar 场景哪种可行。**

## 四、横向技术方案

### 运行 app 枚举

- `NSWorkspace.shared.runningApplications` + **KVO `observe(\.runningApplications)`**（AltTab `src/events/RunningApplicationsEvents.swift` 注释：launch 通知只对 GUI app 触发，KVO 全覆盖）+ 250ms 去抖
- 过滤：`activationPolicy == .regular`；`.prohibited` 不建 AXUIElement；AltTab 额外用 XPC 判定（`GetProcessForPID`+`GetProcessInformation`，`processType == "XPC!"` 排除）+ zombie 判定 + 黑名单（`ApplicationDiscriminator.swift`）

### 图标获取

- 主路径 **`NSRunningApplication.icon`**；per-bundle 缓存只取一次，off-main 取图主线程赋值（AltTab `Application.swift:128`）
- 兜底链：`urlForApplication(withBundleIdentifier:)` → `icon(forFile:)` → `icon(forFileType: "app")` generic（AltTab 只在设置页用这个链，主路径 icon nil 直接画空）
- 坑：**Big Sur 起系统图标自带内边距需按版本裁剪**（AltTab 实测 Big Sur+ 24pt、macOS 26 84pt——该值需自行复验）；无 bundle 结构进程 `bundleURL` 为 nil；`activationPolicy == .prohibited` 不该有图标

### 鼠标接近边缘检测（汐线命根子）

| 维度 | NSTrackingArea | `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` | CGEventTap |
|---|---|---|---|
| 权限 | 零 | **鼠标类零权限**（官方文档：仅 key 类事件需辅助功能；多来源实测 mouseMoved 无权限可用） | Input Monitoring 或辅助功能，`CGPreflightListenEventAccess` 预检 |
| 覆盖 | 仅自己窗口矩形 | 全系统（收「派发给其他 app」的事件，自家激活时收不到，需 local monitor 兜底） | 全系统 |
| 关键局限 | tracking 依赖鼠标事件流 → 热区窗口必须吃鼠标事件 = 隐形点击拦截层，与穿透矛盾 | 高频回调需节流 | 键盘事件在 Secure Input（密码框）时被 mask；鼠标不受影响 |
| 适用 | **展开后面板内部 hover**（DockDoor 的退出检测即此） | **接近检测主路线**（Ice 菜单栏 hover 即此） | 纯鼠标检测属杀鸡用牛刀 |

推荐组合（IslandOverlay 写法）：全局 mouseMoved monitor + `addLocalMonitorForEvents` + 低频 Timer 轮询 `NSEvent.mouseLocation` 三重兜底；回调里只做距离阈值判断，不做动画。

### NSPanel 配置套路

四项目横向一致的基底：

```swift
styleMask = [.borderless, .nonactivatingPanel]   // nonactivatingPanel 必须在 styleMask 里，isFloatingPanel 替代不了
level = .floating                                 // 梯队：.floating < .statusBar < .mainMenu+1 < .popUpMenu（AltTab：能盖右键菜单；.screenSaver 最高但拖拽放不上去）
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
isOpaque = false; backgroundColor = .clear; hasShadow = false
isFloatingPanel = true; animationBehavior = .none
hidesOnDeactivate = false                         // 必须，否则切 app 就消失
orderFrontRegardless()                            // 不抢焦点置前
```

- 可交互子 view 覆写 `acceptsFirstMouse = true`（Ice）；面板要收键盘时覆写 `canBecomeKey = true` + `becomesKeyOnlyIfNeeded = true`
- **`ignoresMouseEvents` 动态开关 = 「零存在感 + 可交互」标准组合拳**（Ice overlay 平时 true 点穿透，进入目标区域翻 false）
- 两派 Space 策略：DockDoor/AltTab 用 `canJoinAllSpaces` 常驻；**Ice 刻意不用**——切 Space 后旧面板残留，改用 `[.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]` + 监听 `activeSpaceDidChangeNotification` 主动管理。TideBar 全屏 Space「只留细线」可参考后者
- DockDoor 多屏：不按屏建窗口（预览跟随系统 Dock），按鼠标所在屏定位（`NSScreen.screenFromQuartzPoint`）+ `didChangeScreenParametersNotification`；SketchyBar 则每屏一个 bar 窗口 + `CGDisplayRegisterReconfigurationCallback` 热插拔

### 窗口预览/截图现状

- `CGWindowListCreateImage` 已废弃（macOS 14 起）→ **现实 = 窗口枚举已迁 ScreenCaptureKit（`SCShareableContent`），逐窗抓图仍是私有 `CGSHWCaptureWindowList` 主流**：私有 API 能截最小化窗口且单次调用返回数组。AltTab 直到 macOS 26 才全 SCK（14 崩溃 `-SCStreamManager serverDidDisconnect`、15 有 #5190 bug）；DockDoor 枚举用 SCK、抓图用 CGS
- SCK 抓帧：14+ `SCScreenshotManager.captureImage`；26+ `captureScreenshot`/`captureSampleBuffer`（避免反复开 stream）
- **录屏授权后必须重启 app 才生效**（TCC 决定在进程启动时绑定）——直接决定授权向导流程设计
- 缓存标配：按 pid/Space 缓存 + TTL + 并发限 4（DockDoor `SpaceWindowCacheManager`）

### 事件监听补充

- AltTab 全局热键：CGEventTap（listenOnly, flagsChanged）+ **Carbon `RegisterEventHotKey`（刻意用它免辅助功能权限）**，权限判定 `AXIsProcessTrustedWithOptions`
- SketchyBar（纯 C、零 AppKit 参考）：鼠标交互走 Carbon Event Manager + 私有 `SLSAddTrackingRect`（WindowServer 层 tracking），**无需任何权限**；事件驱动架构统一分发 28 种事件（WindowServer 通知、NSWorkspace、FSEvents 热加载、CVDisplayLink 动画）。其私有 CGS 建窗路线（`SLSNewWindowWithOpaqueShapeAndContext`）与 TideBar「系统能力优先」相悖，不采纳
- Ice 真隐藏菜单栏图标的手段是模拟鼠标拖拽（`CGWarpMouseCursorPosition` + 构造 CGEvent + 两个 EventTap 转发绕过伪造事件过滤）——复杂度高，TideBar 用不上，仅备查

### 废纸篓

| 项目 | 状态检测 | 移入 |
|---|---|---|
| Docky | **kqueue**（`DispatchSourceFileSystemObject` + `O_EVTONLY` 打开 `~/.Trash`，监听 write/rename/delete）事件驱动 + `contentsOfDirectory` 判空满 | `FileManager.trashItem` |
| Pier | `contentsOfDirectory(.trashDirectory)` 定时轮询（注释自认「便宜轮询」） | `NSWorkspace.recycle` |
| Focus Dock | EPERM → 轮询 shell osascript「count items of trash」 | — |

**没有项目用 FSEvents 监控 `~/.Trash`**；kqueue 是已验证的更轻事件驱动路线。

## 五、对 TideBar 的启示

1. **入口替代抄行业方案**：autohide-delay 1000 基础上补 `tilesize=16` + `mineffect=scale` + `no-bouncing`，配快照/恢复/自愈三件套；用户向导内开关
2. **接近检测走全局 mouseMoved monitor**（零权限、不拦点击），NSTrackingArea 留给展开后的面板内部 hover
3. **NSPanel 组合照抄已验证配置**（§四），汐线态用 `ignoresMouseEvents=true` 穿透
4. **枚举/图标用标准链**：KVO runningApplications + NSRunningApplication.icon + 兜底链 + per-bundle 缓存
5. **窗口预览延后立项**：零权限阶段先做「图标 + 标题」悬停卡片；缩略图二期接受录屏权限 + 重启约束
6. **两个新决策点需拍板**：① 最小化窗口还原（做完整 Dock 绕不开，参考 Focus Dock）；② 展开态被 maximize 窗口压住是否接受/是否 AX 重排
7. **差异化确认**：无人做过细线收起态；「SkyLight alpha=0 空间保留者」是潜在差异化路径（高风险，观察 Docky 实验）

## 六、与 decisions.md 现有条目的冲突（待修订）

> decisions.md 只增不改，以下修订需新增条目注明取代关系。

1. **接近检测路线**：decisions.md 权限策略写「hover 检测用不可见热区窗口 + NSTrackingArea」——调研结论 NSTrackingArea 热区会拦截点击、与汐线穿透矛盾，应改为全局 mouseMoved monitor（§四）。NSTrackingArea 降级为展开态面板内部 hover 方案。
2. **隐藏参数集**：decisions.md 架构条目只有 autohide-delay 1000，缺 Mission Control 强显（tilesize=16）与 genie 指向（mineffect=scale）两项对策（§二）。
3. **废纸篓方案**：可行性表写 FSEvents——调研未见任何项目用 FSEvents，kqueue 是已验证更轻路线（§四）。
4. **悬停预览难度评估**：可行性表写「ScreenCaptureKit ⭐⭐⭐」——现实是逐窗抓图仍以私有 CGS API 为主流（能截最小化窗口），纯 SCK 方案在 14/15 有已知崩溃/bug（§四）。
5. **最小化窗口条目**：「AltTab 2026 已全量转 SkyLight」表述过时——AltTab 现为 macOS 26 用 SCK、旧系统私有 CGS（§四）。

## 七、待核实清单

- AltTab 的 macOS 26 图标内边距 84pt：源码实测值，TideBar 需自行复验
- 鼠标类全局 monitor / NSTrackingArea 在 System Settings 等特定场景是否失效：未找到权威来源（有据可查的只有键盘事件受 Secure Input 屏蔽）
- `~/.Trash` 在 macOS 26 的 TCC 可读性：三种实现（直接读 / kqueue / osascript）需实测
- 私有 SkyLight API（CGSHWCaptureWindowList、CGSSetWindowAlpha）走 Developer ID 公证的审核风险：未确认
- boringBar（闭源）隐藏系统 Dock 的具体机制：未确认（从「Mission Control 仍可见」推断为普通 autohide）
- 多显示器系统 Dock 不跟随外接屏的 Tahoe/Sequoia bug：有复现报告与 Feedback ID，影响面待验证

## 来源

仓库（均为克隆读源码）：[ejbills/DockDoor](https://github.com/ejbills/DockDoor) · [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos) · [FelixKratz/SketchyBar](https://github.com/FelixKratz/SketchyBar) · [jordanbaird/Ice](https://github.com/jordanbaird/Ice) · [josejuanqm/docky](https://github.com/josejuanqm/docky) · [The-Portland-Company/focus-dock-for-macos](https://github.com/The-Portland-Company/focus-dock-for-macos) · [adityaonx/AeroBar](https://github.com/adityaonx/AeroBar) · [openwarehq/pier](https://github.com/openwarehq/pier) · [ricotz/plank](https://github.com/ricotz/plank) · [psifidotos/Latte-Dock](https://github.com/psifidotos/Latte-Dock)

关键文档/讨论：
- uBar 系统隐藏方案：https://ubarapp.com/documentation/
- Apple 事件监控文档（key 需辅助功能、mouse 不需）：developer.apple.com/documentation/appkit/nsevent
- ScreenCaptureKit（WWDC22）：https://developer.apple.com/videos/play/wwdc2022/10156/
- Ghostty PR #5361（窗口 level 与 IME）：https://github.com/ghostty-org/ghostty/pull/5361
- Secure Event Input：https://developer.apple.com/library/archive/technotes/tn2150/

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
- 后期加窗口预览 → 屏幕录制权限；最小化窗口管理 → 辅助功能权限。项目走开源、非 App Store 分发路线，不以商店审核为技术约束

## 交互与技术约定

- **窗口层组合**：borderless + nonactivating + canJoinAllSpaces + fullScreenAuxiliary，`level = .floating`
- **全屏 Space**：默认只留细线不展开（盖住视频/游戏体验差；uBar 的做法是完全隐藏）
- **hover 收起防抖**：mouse exited 后 ~300ms 延迟收起，期间 re-enter 取消，防边缘抖动闪烁
- **多显示器**：每屏一个 panel，监听 `NSScreen.didChangeScreenParametersNotification`

## 2026-09 M2 实现约定

1. **鼠标态统一采样器驱动（取代 tracking area 事件）**：非激活悬浮窗上 NSTrackingArea 的 entered/exited 合成不可靠（实测有稳定复现的状态机失步：悬停无反应/有反应交替）。图标悬停、潮涌行悬停、潮涌离场判定全部由接近检测采样器（mouseMoved 事件 + 40ms 节流 + 0.25s 兜底轮询）做命中测试驱动；点击/长按仍走 mouseDown/Up 事件流（该路径可靠）。
2. **玻璃采样需要 key**：NSGlassEffectView 在非 key 窗口被 WindowServer 降级采样（发黑）。汐线展开时与潮涌显示时均 `makeKey()`，潮涌收起时 key 还给原屏汐线面板。
3. **AX 窗口收录规则**：`subrole == AXStandardWindow` 或 `minimized == true`。最小化窗口的 subrole 不可靠（实测：访达最小化丢 std 标记、Zen 最小化报 AXDialog），必须 min 兜底；对话框/访达桌面元素两者皆不满足，天然排除，无需特例。依据见 plans/archived/todo-2026-09-window-surge.md 探针结论。

## 2026-09 调研修订

来源：[research-dock-alternatives.md](research-dock-alternatives.md) §六，逐条注明取代关系。

1. **使命收窄（取代「核心差异化 = 零存在感 + 完整 Dock 功能」）**：不做 dock 杂务——废纸篓、角标、拖拽管理不做，窗口预览延后。被隐藏 Dock 带走的能力用自有方案还原：窗口瓦片一体收录全部窗口（含最小化），不区分是否最小化，点击即开。
2. **分期推进**：M1 潮汐交互验证（细线 + 展开 + 固定/运行图标，零权限，手感不成立则项目复盘）→ M2 窗口瓦片（AX 窗口枚举/聚焦/还原，需辅助功能权限）→ M3 系统接管向导（App 内开关执行隐藏，快照/恢复/自愈）。
3. **接近检测改道（取代「权限策略」的 NSTrackingArea 热区方案）**：全局 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`。鼠标类事件零权限（仅键盘类需辅助功能）；汐线窗口保持点击穿透，无需热区吃事件。兜底：local monitor + 低频轮询 `NSEvent.mouseLocation`。NSTrackingArea 降级为展开面板内部 hover 方案。
4. **隐藏参数补全（细化「架构」节命令集）**：M3 完整参数 = autohide + autohide-delay 1000 + autohide-time-modifier 0 + no-bouncing + tilesize 16 + magnification false + largesize 16 + mineffect scale。tilesize 组针对 Mission Control/Exposé 无视 autohide 强显；mineffect 针对 genie 动画指向隐藏 Dock 穿帮。向导标配快照/恢复；配置漂移仅在设置页打开或用户主动检查时发现，不做常驻自愈。
5. **废纸篓不做（取代可行性表 FSEvents 行的方案预期）**：将来若重启，已验证路线是 kqueue（`DispatchSourceFileSystemObject` + `O_EVTONLY`），无项目用 FSEvents。
6. **可行性表勘误**：窗口预览的现实 = 枚举用 ScreenCaptureKit、逐窗抓图仍以私有 `CGSHWCaptureWindowList` 为主流（能截最小化窗口；纯 SCK 在 14/15 有崩溃/bug，AltTab 至 macOS 26 才全量 SCK），「AltTab 2026 已全量转 SkyLight」表述过时。录屏授权须重启 app 后生效，向导流程需按此设计。

## 2026-09 M3 接管层级决策

1. **优先高层级顶置，失败则接受展开态遮盖**：TideBar 面板优先使用 `NSWindow.Level.statusBar`，潮涌面板高一级，用于验证展开态覆盖最大化窗口的体验；不使用 `.screenSaver`，避免压住系统级安全界面。若状态栏层级干扰菜单、弹窗或全屏 Space，则回退为普通悬浮层，暂不做 AX 窗口避让。
2. **接管态与测试态分离**：测试态继续使用悬浮高度（默认 140pt）；接管态由配置模式驱动，贴底运行（offsetY = 0）。
3. **不采用私有 CoreDock API 的理由**：即使项目走开源、非 App Store 分发，也不把私有 API 作为长期基础设施；唯一原因是系统版本兼容性、行为稳定性和后续维护成本不可控。短期实验可以单独验证，但不能成为 M3 的默认实现。

## 2026-09 M3 状态检查决策

1. **不做常驻自动自愈**：不运行 Dock 配置轮询计时器，不引入后台 helper 或 LaunchAgent。只在 TideBar 启动、接管/恢复操作后、设置界面打开或用户主动点击检查时读取 Dock 配置。
2. **漂移只告警，修复需显式操作**：发现 Dock 配置与接管指纹不一致时，设置界面显示警告信息条；用户点击“立即检查并修复”后才重新应用接管参数。

## 潮涌：窗口交互模型（2026-09 定稿）

取代「2026-09 调研修订」条目 1 中「窗口瓦片一体收录全部窗口」的形态设想；能力路线（AX 枚举/还原）不变，粒度与交互重设计。AX 能力依据见 [research-dock-alternatives.md](research-dock-alternatives.md) §三坑 3（Focus Dock 源码验证）。

1. **app 为中心，二级展开**：展开态以 app 图标为粒度（不平铺窗口）；图标下方点点 = 窗口状态（实心=活跃数、空心=最小化数，>5 收敛为数字；读不到窗口信息不画）。
2. **三条到达路径**：点击 = 切换最近非最小化窗口（仅剩最小化则还原最近一个；AX 不可用时退化为 activate）；长按或 ⌥+点击 = 「潮涌」展开该 app 的窗口列表；右键菜单同样列出窗口（原生 Dock 惯例，可发现性保底）。
3. **潮涌内容**：窗口标题（`kAXTitle`）为主 + 文档图标（`kAXDocument` → `NSWorkspace.icon(forFile:)`，失败退回 app 图标）；最小化窗口暗显。实时缩略图继续延后（可行性表照旧）。
4. **还原/聚焦**：`kAXMinimized` 置 false + `kAXRaiseAction` + `activateIgnoringOtherApps`；AX 读不到窗口的 app 降级为纯图标 + activate（即 M1 行为）。
5. **命名**：二级展开名「潮涌」，代码标识 Surge（SurgePanel/SurgeView）；与「汐线」成对——汐为收敛态，涌为突发态。
6. **动画语言「错峰升降」**：列表项从图标栏背后逐项错峰升起（每项延迟 20~30ms，弹簧曲线），收起反向退落；汐线展开共用此语言。
7. **M2 前置探针**：开工前半日实测 `kAXWindows` / `kAXMinimized` / `kAXTitle` / `kAXDocument` 在真实 app 集的覆盖表，覆盖不可接受则复盘。

## 2026-09 应用身份与 Finder 行为决策

取代 `plans/archived/todo-2026-09-window-surge.md` 中「访达因永在运行而常驻图标」的实现结论；窗口收录规则与普通应用的 AX 降级行为不变。

1. **身份统一**：bundle identifier 以 ASCII 不区分大小写的规范身份参与比较、去重、UI identity 和行为索引；启动、窗口操作与文件定位仍使用采集阶段解析出的 URL、PID 和运行实例，不用规范字符串反查系统对象。
2. **应用聚合、窗口归属到进程**：同一身份的多个运行实例在图标栏只生成一个条目；窗口知识按 PID 观测并聚合，每个窗口保留 owner PID，窗口动作始终发送给所属实例。任一实例无法完整确认窗口集合或最小化态时，聚合结果为未知，不报告不完整点数。
3. **Finder 仅代表通用规则收录窗口**：Finder 只有在窗口知识已知且至少有一个收录窗口时显示；标准窗口或最小化窗口均计入，桌面 AX 元素由通用规则自然排除，不增加 Finder 窗口类型特判。已知零窗口、AX 未授权、尚未完成枚举或读取降级时均隐藏；固定配置只决定其出现时的位置，不能使其常驻。
4. **动作能力由模型约束**：菜单只展示模型允许的动作，受保护的终止动作统一通过执行入口再次读取当前模型并校验规范身份对应的行为。Finder 不具备终止能力，不提供“退出”，也不尝试在终止 Finder 后恢复桌面。
5. **identity 与内容修订分离**：identity 只负责复用视图；进程、能力或可观测窗口模型变化必须替换最新模型。被跟踪条目消失、窗口知识降级或可观测窗口模型变化时，已展开潮涌立即失效并关闭。

## 2026-09 应用右键菜单范围

1. **只承诺通用菜单**：窗口直达、打开/激活、隐藏、固定切换、退出和在 Finder 中显示由 TideBar 自行构建；不承诺复刻系统 Dock 的完整菜单。
2. **不继承其他应用的自定义 Dock 菜单**：`applicationDockMenu(_:)` 只允许应用向系统 Dock 提供自己的菜单，没有供第三方进程读取任意应用菜单的公开 API。TideBar 不把 Dock 私有 API 或瞬态 AX 菜单抓取作为基础设施。
3. **增强能力重新立项**：最近项目及其文档图标、针对特定应用的专属动作均为未来可选能力，不纳入通用菜单实现；若立项，需重新评估数据来源、权限与系统版本稳定性。

来源：
- Apple `NSApplicationDelegate.applicationDockMenu(_:)`：https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:)
- Apple `NSDockTilePlugIn`：https://developer.apple.com/documentation/appkit/nsdocktileplugin

## 2026-09 应用状态与列表动画

1. **动画跟随模型真值**：窗口点变化、应用新增与应用删除均由 Registry/AX 已确认的数据变化触发，不在点击、启动请求或退出请求发生时提前假设结果。
2. **状态标记连续过渡**：运行但无可显示窗口使用次要标签灰色短线；首个窗口出现时短线收缩为圆点，最后窗口关闭时反向变化。状态标记使用独立图层，不再依赖 `draw(_:)` 瞬时重绘。
3. **列表按 identity 差分编舞**：新增项从汐线下方上涌，删除项向汐线沉落，保留项用 transform 完成位置过渡。离场结束前不得缩小面板边界，避免动画被窗口裁剪。
4. **只呈现可见变化**：展开态实时播放模型变化；收起期间不积压逐项动画，下次展开统一使用整栏涌潮动画。减少动态效果开启时退化为短促淡化。

## 2026-09 应用管理右键菜单

取代「潮涌：窗口交互模型」条目 2 中的右键窗口直达约定，并细化「应用右键菜单范围」条目 1。

1. **导航与管理分离**：窗口导航只由长按或 `⌥`+点击打开的潮涌承担；右键菜单不列窗口，只提供应用级管理动作。
2. **稳定顺序**：菜单依次为固定状态、在 Finder 中显示、分隔线、打开或显示/隐藏、退出。固定文案使用对称的“固定到 TideBar”与“取消在 TideBar 中固定”。
3. **可见性跟随系统真值**：未运行应用显示“打开”；运行应用全部实例均隐藏时显示“显示”，否则显示“隐藏”。隐藏状态进入内容修订，并由工作区隐藏/取消隐藏通知刷新。
4. **动作统一校验**：显示、隐藏和退出执行前均刷新模型并校验运行实例身份；显示会解除隐藏并激活首选实例。Finder 等受保护应用仍不提供退出。

## 2026-09 Finder 桌面与资源管理器角色分离

取代「应用身份与 Finder 行为决策」条目 3 中“固定配置不能使 Finder 常驻”的约定。

1. **桌面角色完全忽略**：Finder 常驻进程承载系统桌面，但进程存在本身不代表 TideBar 中的 Finder 正在运行，不贡献图标、运行短线或窗口点。
2. **资源管理器以收录窗口判定运行**：Finder 只有存在至少一个按通用规则收录的窗口时才处于逻辑运行状态；窗口全部关闭后即转为逻辑未运行。
3. **固定与运行状态解耦**：固定 Finder 即使没有收录窗口也保留图标；未固定 Finder 则仅在逻辑运行时显示。默认固定列表不包含 Finder，用户可通过 UI 手动固定或取消固定。
4. **系统进程引用继续保留**：Finder 的 `NSRunningApplication` 仍用于激活、reopen、隐藏和显示等系统动作，但不能直接决定 `AppEntry.isRunning`。固定且无窗口时点击现有 Finder 进程并发送 reopen，以打开资源管理器窗口。
5. **终止保护不变**：Finder 不提供退出动作，也不尝试终止 Finder 后恢复桌面。

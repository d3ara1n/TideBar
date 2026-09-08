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

## 2026-09-08 潮涌最小化窗口标记

补充「潮涌：窗口交互模型」条目 3：暗显同时承担「他屏」与「最小化」两义，无法区分（图标栏圆点的实心/空心能区分，形成体验缺口）。

1. **双维度正交**：亮度 = 是否本屏可见（本屏正常，他屏与最小化暗显），行尾标记 = 是否最小化；他屏窗口仅暗显，最小化窗口暗显 + 标记。
2. **标记 = SF Symbol `minus`（12pt，行尾右缘，随标题色）**：与红绿灯最小化按钮同语言、纯状态符号（行点击始终是还原，无动作误导）。排除菱形（系统 Window 菜单惯例，但被读作「注意/消息」类特殊标记）、`minus.rectangle` 与 `dock.arrow.down.rectangle`（小尺寸暗显下笔画多、细节易糊）。

## 2026-09-08 潮涌最小化标记修订：minus 符号 → 文字胶囊标签

取代本日「潮涌最小化窗口标记」条目 2 的符号选型；双维度正交（条目 1）不变。

1. **标记 = 行尾圆角矩形文字标签**（`window.minimizedBadge`：「已最小化」/ Minimized，10.5pt medium，quiet 填充，随标题色，圆角 5pt 非胶囊）：minus 在列表行语境被读作删除/移除动作，胶囊 + minus 更是「移除 chip」的经典控件形态；状态分词文字无动作歧义，标签形态天然读作状态描述。
2. **动态让位布局**：标签仅在最小化行出现，宽度按文字实测；出现时标题截断点左移（标签宽 + 8pt 间隙 + 12pt 右缘留白），无标签的行标题占满行尾——不为偶发元素常驻留白。

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
5. **动作文案指明对象**：显示/隐藏菜单项的 zh-Hans 文案为「显示窗口／隐藏窗口」，消除被误读为图标显隐的歧义；英文沿用系统 Dock 惯用语 "Show／Hide"。引导页右键能力概要同步为「固定、窗口显隐与退出」。

## 2026-09 Finder 桌面与资源管理器角色分离

取代「应用身份与 Finder 行为决策」条目 3 中“固定配置不能使 Finder 常驻”的约定。

1. **桌面角色完全忽略**：Finder 常驻进程承载系统桌面，但进程存在本身不代表 TideBar 中的 Finder 正在运行，不贡献图标、运行短线或窗口点。
2. **资源管理器以收录窗口判定运行**：Finder 只有存在至少一个按通用规则收录的窗口时才处于逻辑运行状态；窗口全部关闭后即转为逻辑未运行。
3. **固定与运行状态解耦**：固定 Finder 即使没有收录窗口也保留图标；未固定 Finder 则仅在逻辑运行时显示。默认固定列表不包含 Finder，用户可通过 UI 手动固定或取消固定。
4. **系统进程引用继续保留**：Finder 的 `NSRunningApplication` 仍用于激活、reopen、隐藏和显示等系统动作，但不能直接决定 `AppEntry.isRunning`。固定且无窗口时点击现有 Finder 进程并发送 reopen，以打开资源管理器窗口。
5. **终止保护不变**：Finder 不提供退出动作，也不尝试终止 Finder 后恢复桌面。

## 2026-09 快捷键与开发启动边界

1. **全局热键不引入新的 TCC 权限**：使用 Carbon `RegisterEventHotKey` 接收有限的快捷键事件，不使用全局键盘监控；快捷键本身不新增辅助功能或屏幕录制授权要求。窗口级导航仍受现有辅助功能授权约束，未授权时退化为应用激活。
2. **快捷键与鼠标状态机分层**：热键注册、键盘导航状态和 TideBar 鼠标接近/展开状态分别维护；热键注册失败或注销时，鼠标交互必须保持完整。
3. **开发与发布启动路径分离**：`swift run` 继续作为开发期主路径，保留已授权 Terminal 的调试体验；正式 `TideBar.app` 只承担发布和登录项启动，不作为快捷键或核心功能的开发前置条件。
4. **正式 Bundle 使用稳定签名**：Bundle 从 Finder、登录项或 `open` 启动时作为独立 TCC 主体处理，需要单独授予辅助功能权限。开发 Bundle 不采用每次重建都会变化的 ad-hoc 身份作为长期授权方案，改用稳定的自签名或 Apple Development 签名。
5. **首版 `⌥Tab` 采用临时切换会话**：第一次触发优先定位当前前台应用，后续按键循环切换；空闲延迟可在设置页配置（默认约 0.9 秒），超时后自动提交当前选择并收起。`Return` 立即提交，`Esc` 取消。`⌥Space` 独立作为持久 toggle，不受超时影响。该条取代上一条“Return/Esc 唯二出口”的试运行约定。
6. **快捷键配置统一由运行时重载**：设置页保存快捷键后，使用 KeyboardShortcuts 的内置存储与 Carbon 注册机制立即生效；快捷键录入至少包含一个修饰键和一个普通键，注册成功不等于系统层面无冲突。`⌥Space` 与 `⌥Tab` 的初始选择共用当前前台应用优先、首个条目回退的规则。
7. **快捷键录入采用 KeyboardShortcuts**：不再维护自制 Recorder 和第二套 Carbon 注册；使用 KeyboardShortcuts 3.0.1 的 SwiftUI Recorder，利用其录制期间暂停热键、失焦结束录制、Esc 取消和 Delete 清除等机制。该依赖是快捷键功能的专项例外，不引入 SwiftUIX 等通用 UI 大依赖。

## 2026-09 通知角标路线实测

1. **AX 读 Dock 角标在接管态成立**：本机（macOS 26，autohide-delay 1000 + tilesize 16 接管态）实测 `com.apple.dock` 进程 AX 树可枚举全部 `AXDockItem`，`AXStatusLabel` 实时携带角标字符串（QQ 1→2→3 轮询期间实时递增，Canary Mail '16'、微信 '7'），系统 Dock 完全隐藏不影响读取与更新。可行性表「图标角标 ⭐⭐⭐ 可砍」的成本预期据此下调为 ⭐⭐（辅助功能权限已有，1Hz 全树轮询开销可忽略）；是否捡回属产品决策，以立案为准。
2. **路线约束**：无变更推送，只能轮询；读到字符串，可解析为数字则显示数字，否则退化为小圆点或不显示；覆盖面 = Dock 角标镜像，与系统设置中各 app 的角标开关天然一致。
3. **来源**：uBar 在同款接管参数下即以 `AXStatusLabel` 显示角标；SketchyBar、simple-bar、BadgeBar、Focus Dock 同路线。本机一次性探针验证（探针已删，结论留档）。

## 2026-09 统一轮询与角标落地

1. **统一轮询调度器（PollScheduler）为常驻轮询唯一入口**：单一基频 Timer（= 需求最小间隔）承载全部需求；按名注册/注销，相位错开分片，容差 1/5 基频允许系统合并唤醒；主线程 tick 只做触发，重活（AX 读取）由需求自调度后台队列回桥。接近检测兑底、Dock 角标、设置页权限轮询全部迁入；设置页改为开窗注册、关窗注销。
2. **角标落地（取代可行性表「⭐⭐⭐ 可砍」的优先级结论；成本判定见上一节实测）**：BadgeStore 后台读 Dock AX 树，展开 1s/收起 4s 自适应、展开瞬间立即全量读、接管关闭时不轮询（系统 Dock 可见时镜像无意义）；badge 进 AppEntry 模型真值，不触发潮涌失效；Dock 标题与应用显示名小写规范化对位，匹配不到静默忽略。
3. **汐线通知语言：轻涌 + 持久涟漪，展开即确认**：新角标一次轻涌，未确认期间双环错相涟漪循环（线源扁椭圆形态，横向 1.3 倍线宽、终态波高 14pt）；停止条件 = 任意一次展开（用户已知）或全部角标消失（从横幅读完）；减少动态效果时脉冲退化为短淡化、不做常驻循环。设计动机：一次性提醒与系统横幅注意力重复，持久动效表达「未被知晓」状态而非「事件发生」瞬间。
4. **解析与展示约定**：AXStatusLabel 正整数→计数角标（99+ 封顶）、非空非数字→小圆点、空/零→不显示；连续读取失败 3 轮才清值，Dock 重启期间保留旧值防闪烁。

## 2026-09 裸进程身份（扩展「应用身份与 Finder 行为决策」条目 1）

1. **无 bundle 的 regular GUI 进程照收，身份由可执行路径派生**（`AppIdentity(路径)`，沿用 ASCII 小写规范化）：.NET/Avalonia 调试目标、直跑 jar 等裸 exe 在系统 Dock 有落点，TideBar 对齐；此前的 bundleIdentifier 硬过滤是漏洞。路径身份与 bundle 身份天然不碰撞（bundle identifier 不含路径分隔符）。
2. **路径经 `proc_pidpath` 解析**（公升 libproc API），保留真实大小写供文件操作；规范化身份仅作聚合键。
3. **裸进程不支持固定**：固定配置按 bundle identifier 存储，裸进程右键菜单不提供固定项；将来需要可扩展按路径固定。
4. **身份对账双通道**：动作校验（AppActionDispatcher）与窗口观测（WindowStore）对 bundle 进程按 bundle identifier 比对，对裸进程按可执行路径比对，均归于条目的规范化身份。

## 2026-09 本地化与应用内语言切换

1. **资源格式用经典 .strings（SE-0278），不用 String Catalogs**：xcstrings 的编译与符号生成绑定 Xcode/xcodebuild 链路，`swift build` 不原生支持；本项目无 Xcode 工作流，其自动提取/审校优势为零。词条按功能域分 table（Onboarding/Settings/Menus/Runtime/Labels），en + zh-Hans 双语人工维护，key 点分层命名。
2. **应用内切换 = 自定义 lproj bundle 查找**：`L10nManager` 按用户偏好从 Bundle.module 加载对应 lproj 子 bundle，全部文案查找显式指定该 bundle，不依赖系统 preferred localization；「跟随系统」按系统语言 zh 前缀归 zh-Hans，其余归 en。SwiftUI 根视图持 observable 对象整树刷新，AppKit 处（状态栏菜单、设置窗标题）订阅语言通知重建；系统错误描述（`error.localizedDescription`）保持系统本地化直通，不经词条。
3. **SPM 把 lproj 目录名规范化为小写（zh-Hans.lproj → zh-hans.lproj），而 `path(forResource:)` 按精确名匹配**——自定义加载必须精确名查不到时按小写回查，否则非英文 bundle 加载失败静默回退、界面恒为英文（首次实现即踩此坑，GUI 验收暴露）。
4. **UI 标签不进 TideBarCore**：偏好枚举的界面标签位于 TideBar 层 extension 查词条，调用点用同名 API 无感；`DockError` 的用户可见描述走词条，NSLog 描述保持英文可 grep。

## 2026-09 本地化依赖与展示状态

细化并取代「本地化与应用内语言切换」条目 2 的 SwiftUI 刷新约定与条目 4 的标签查找约定；资源格式、语言解析规则和 Core/UI 分层保持不变。

1. **语言以不可变快照接入依赖图**：`@Observable L10nManager` 原子替换包含偏好、实际语言和 bundle 的 `Localization`。每个 hosting root 通过 `LocalizedContent` 注入快照和 locale，消费视图声明 `@Environment(\.l10n)`；根视图观察不等于子树全部重算。不用语言作为 `.id`，语言变化不能重置 UI 状态。
2. **枚举标签持 key，不隐式查全局语言**：UI 层 extension 提供 `titleKey`，`ForEach` 内由独立读取环境的 `LocalizedText` 解析。两个语言选择器共用组件与状态写入路径；“跟随系统”与显式选择即使解析到同一语言，也必须更新选中项。
3. **状态保存语义，展示时翻译**：自有 Dock 错误以 `DockFailure` 保留错误类型与参数；向导和设置页展示时解析词条，只有外部系统错误才保存系统描述。AppKit 监听状态提交后的语言通知，刷新菜单、窗口标题与已展开潮涌的回退文案。
4. **验收必须覆盖原生控件与独立子视图**：资源和状态单测不能替代 GUI 验收。权限轮询仅在权限值变化时发布，语言刷新不能依赖不相关的轮询或用户操作。

来源：
- Apple，SwiftUI 依赖图与视图值比较：https://developer.apple.com/videos/play/wwdc2021/10022/
- Apple，Environment 消费者更新：https://developer.apple.com/documentation/swiftui/environment
- Apple，Observation 与模型读取：https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
- Apple，`id(_:)` 的状态重置语义：https://developer.apple.com/documentation/swiftui/view/id(_:)

## 2026-09 汐线应用收纳反馈

细化「应用状态与列表动画」的收起态反馈约定；收起期间仍不积压逐项图标动画。

1. **逻辑运行状态驱动**：Registry 确认应用从未运行进入运行态后发送一次合并事件，覆盖已固定应用；固定操作、普通窗口内容刷新、初始快照不触发。窗口驱动的应用首次获得窗口知识只建立基线，读取降级保留上次已知运行状态，避免把 AX 就绪或恢复当作启动。
2. **中心固定、向内收纳**：可见折叠汐线一次轻微收窄、增厚后恢复，默认约 360ms，只改变显式 transform，不改变窗口或图层几何。Registry 去抖合并同轮启动，待播或动作进行中的后续启动合并消化。
3. **衔接与优先级**：收起回归动作结束后再收纳；中途展开取消待播并从当前形态接续；全屏隐藏撤销待播与正在播放的收纳。通知脉冲优先接管，脉冲期间不追加收纳，独立的持久涟漪照常运行。
4. **反馈不积压**：展开态、隐藏态、减少动态效果开启时不播放收纳，也不补播到下次折叠或显示。

## 2026-09 展开态永不避让

1. **遮盖是产品特色**：TideBar 的核心交换是「收起态零占用 + 展开态按需盖在内容之上」，屏幕空间寸土不让；展开态覆盖最大化窗口底边是预期行为，不是缺陷。
2. **窗口避让明确不做（取代「2026-09 M3 接管层级决策」条 1 中「暂不做 AX 窗口避让」的措辞）**：AX 窗口重排（uBar 路线）、SkyLight 空间预留等一切避让路线不立项；一旦避让，产品退化为「另一条常驻任务栏」，差异化不成立。
3. **全屏观感由设置解决**：FullscreenBehavior 三档（lineOnly 细线保留 / normal 正常展开 / hidden 完全隐藏）覆盖全屏 Space 的取舍，不引入新的避让机制。

## 2026-09 窗口实时预览不做

1. **不做悬停窗口实时预览（取代 product.md「窗口预览延后」的立项预期）**：ScreenCaptureKit 逐窗抓图的成本高于收益；可行性表「悬停窗口实时预览」行仅作技术路线留档，不代表可立项。
2. **隐私话术反而受益**：不显示缩略图坐实「不读屏幕内容、永远不请求屏幕录制权限」的对外承诺；copy.md 权限话术与 FAQ 已与此一致。

## 全屏检测与权限降级

细化「展开态永不避让」条目 3 的三档全屏行为及辅助功能权限的使用范围。

1. **全屏真值来自辅助功能**：读取窗口 `AXFullScreen`，不以窗口覆盖整屏的尺寸条件判断。`CGWindowListCopyWindowInfo` 只提供当前 Space 的可见窗口，按 PID 与窗口坐标匹配 AX 元素，按显示器交集面积确定屏幕归属。刘海安全区和 Split View 的半屏尺寸不影响全屏属性；无需屏幕录制权限或私有窗口 ID API。
2. **无法匹配即未知**：同进程不同 Space 的同坐标窗口若报告不同全屏状态，不猜测可见者；权限缺失、属性不支持和超时同样保留未知。同一 Space 内短暂失败最多保留最近 2 秒内的确认值；切换 Space 或显示器布局时立即清空旧确认值。持续不可读时恢复普通交互，检测状态仍为未知。撤销权限立即丢弃确认值，授权恢复后自动重试。
3. **后台采集、统一调度**：全屏采集复用控制器已有的轮询入口，每 0.5 秒至多发起一轮后台串行读取，设置、Space、应用激活和显示器变化触发刷新。在途结果受代次校验约束；CG 可见窗口在采集期间变化时，按屏幕丢弃不一致结果，避免他屏窗口移动影响当前屏。
4. **所有展开入口共享限制**：鼠标、持久快捷键、应用切换快捷键和潮涌入口均消费同一全屏状态；已确认全屏时，lineOnly 不展开，hidden 隐藏面板并停止命中，normal 正常交互。全屏限制生效时结束该屏键盘会话。

依据：本机显示器 CG bounds 为 1710×1112pt、safeAreaInsets.top 为 38pt；Apple [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) 描述原生全屏内容位于安全区域内；[Logoer PR #31](https://github.com/lihaoyun6/Logoer/pull/31) 记录 macOS 26 上最大化与全屏窗口尺寸不可区分的实测。

## 全屏默认点击展开

取代「交互与技术约定」中的全屏默认行为、「展开态永不避让」条目 3 的 lineOnly 档定义，以及「全屏检测与权限降级」条目 4 对 lineOnly 的展开限制；AX 检测与未知降级策略不变。

1. **默认档为点击展开（Click to Expand）**：全屏时保留汐线，收起状态只有直接点击汐线附近的小区域才展开，鼠标靠近和快捷键均不绕过该门槛。normal 正常显示和 hidden 完全隐藏维持其定义；没有有效保存值时使用新默认。
2. **紧凑容错区域**：视觉汐线为 160×3pt，点击入口为贴底的 184×16pt 矩形，左右各加 12pt。该尺寸是实现层手感参数，不沿用普通模式的大接近热区；区域外的游戏操作直接交给系统原本的目标窗口。
3. **独立非激活点击窗口**：主汐线面板维持展开尺寸及收起穿透；另用同屏紧凑 NSPanel 接收点击，窗口边界即命中边界，不做全局点击监听、事件拦截或转发。左键在区域内按下并松开才展开，点击入口不成为 key / main 窗口。
4. **只改变收起态的展开条件**：点击后沿用图标、潮涌、键盘导航和离场收起；下一次收起再要求点击。进入点击模式时收起已有栏，后续全屏轮询不重复收起；展开、完全隐藏、退出全屏、停用和重建时撤销点击入口。

## 2026-09-08 基线回退与画面路线

1. **部署基线回 macOS 14**：全代码无 26 特有 API（v14 全量编译零可用性报错），swift-tools 维持 6.2。2026-09-05 的 26 基线（8f93d94）系随开发机与依赖政策对齐，无 API 必要性。
2. **ScreenCaptureKit 永不引入（延伸「窗口实时预览不做」）**：任何窗口画面能力不走 SCK，权限面永久收敛到辅助功能一项，与对外权限话术一致；调研文档中的 SCK 路线描述仅作同类应用现状留档。缩略图类能力若立项，走私有 CGS（SkyLight）抓图（不触发 TCC、可截最小化窗口）。

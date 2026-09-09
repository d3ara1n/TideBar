# 已定决策

决策真值，描述最终状态。演进过程看 git log 与 `plans/archived/`；推翻决策时改写对应条目并同步受影响文档。每条决策就地附调研来源与实测依据。

## 架构：藏 UI、留进程

系统 Dock 进程保留运行，仅配置级隐藏；TideBar 作为悬浮面板盖在底部。所有商业 Dock 替代品（uBar/ActiveDock）均此路线。接管参数集（uBar 方案为基底，Focus Dock 补全两项对策）：

```bash
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000        # 延迟 1000 秒 = 实际不可唤出
defaults write com.apple.dock autohide-time-modifier -float 0
defaults write com.apple.dock no-bouncing -bool true
defaults write com.apple.dock tilesize -int 16                  # Mission Control/Exposé 无视 autohide 强显，缩到 16px 只剩细缝
defaults write com.apple.dock magnification -bool false
defaults write com.apple.dock largesize -int 16
defaults write com.apple.dock mineffect -string scale           # genie 动画指向已隐藏的 Dock 位置，穿帮；scale 原地缩小
killall Dock
```

标配快照/恢复：接管前快照原始值，恢复时对原本不存在的键用 `CFPreferencesSetAppValue(key, nil, …)` 删回默认。配置漂移只在启动、接管/恢复操作、设置页打开或用户主动检查时发现，不做常驻自愈。

这是对用户系统的修改，由 App 内首次启动向导引导用户执行，不静默改。

来源：
- uBar 官方文档 https://ubarapp.com/documentation/
- Focus Dock 源码注释（tilesize/mineffect 理由）：https://github.com/The-Portland-Company/focus-dock-for-macos
- 同类实现横评见 [research-dock-alternatives.md](research-dock-alternatives.md) §二

## 为什么不能真禁用 Dock 进程

`launchctl bootout gui/$(id -u)/com.apple.dock` 技术上可持久禁用，但 Dock 进程还托管：

| 托管功能 | 禁用后果 |
|---|---|
| Cmd-Tab 应用切换器 | 失效 |
| Mission Control / App Exposé | 失效（由 Dock 进程渲染） |
| 窗口最小化 | 应用请求最小化时挂起（genie 动画由 Dock 渲染） |
| Launchpad | 失效 |

来源：
- https://512pixels.net/2022/04/fix-mission-control-and-app-switcher-crashes-in-macos-monterey/
- https://stackoverflow.com/questions/9778688/

## 功能可行性边界

立案时查此表定成本预期：⭐ 常规，⭐⭐⭐ 以上是需要专项调研的硬骨头。已落地的行注明现状。

| 功能 | 方案 | 难度 |
|---|---|---|
| 启动/固定图标管理 | NSWorkspace + NSDraggingDestination | ⭐ |
| 运行中应用 | `NSWorkspace.runningApplications` + 通知 | ⭐ |
| 右键菜单（退出/Finder 显示） | NSMenu + `NSRunningApplication.terminate()` | ⭐ |
| 最小化窗口枚举/还原 | 无公开 API；AX 路线（`kAXMinimized` 置 false + `kAXRaiseAction`）已由潮涌落地 | ⭐⭐ |
| 图标角标 | Dock AX 镜像（`com.apple.dock` 的 `AXStatusLabel`）已落地，见「通知角标」 | ⭐⭐ |
| 放大效果/启动弹跳 | 自绘动画 | ⭐ |
| 最小化动画本身 | 不可接管（Dock+WindowServer 私有管线）；藏 Dock 架构下系统动画照常，观感 = 窗口缩向底边，可接受 | — |
| Mission Control 按钮 | `open -a "Mission Control"` | ⭐ |

**已明确不做**（产品边界见 [product.md](product.md)，此处留可行性依据）：

- 废纸篓：不做。若将来重启，kqueue（`DispatchSourceFileSystemObject` + `O_EVTONLY`）是同类项目验证过的更轻事件驱动路线，无项目用 FSEvents；「放回原处」无公开 API，需解析 `.DS_Store` 私有 `ptbN`/`ptbL` 记录。
- 窗口实时预览：不做，见「窗口画面与 ScreenCaptureKit」。

来源：
- DockDoor（AX + 抓图参考实现）：https://github.com/ejbills/DockDoor
- Put Back 的 .DS_Store 私有格式：https://stackoverflow.com/questions/18707618/
- 调研横评见 [research-dock-alternatives.md](research-dock-alternatives.md) §四

## 权限策略

- 唯一权限面 = 辅助功能：窗口枚举/聚焦/还原、全屏检测。鼠标类事件（全局 mouseMoved）与 Carbon `RegisterEventHotKey` 快捷键零权限，不新增 TCC 授权。
- 屏幕录制权限永不引入，见「窗口画面与 ScreenCaptureKit」。
- 项目走开源、非 App Store 分发路线，不以商店审核为技术约束。

## 窗口层级与避让

1. **优先高层级顶置，接受展开态遮盖**：汐线面板与全屏点击入口用 `NSWindow.Level.statusBar`，潮涌面板高一级，展开态覆盖最大化窗口是预期体验；不使用 `.screenSaver`，避免压住系统级安全界面。若后续发现 statusBar 层级干扰菜单、弹窗或全屏 Space，回退普通悬浮层（仍不做窗口避让）。
2. **遮盖是产品特色，一切避让路线不立项**：核心交换是「收起态零占用 + 展开态按需盖在内容之上」；AX 窗口重排（uBar 路线）、SkyLight 空间预留等一旦立项，产品退化为「另一条常驻任务栏」。窗口 level 压过系统 Dock 有 IME 风险（Ghostty PR #5361），statusBar 层级 + 隐藏系统 Dock 的组合无此问题。
3. **全屏观感由设置解决**：FullscreenBehavior 三档（clickToExpand 点击展开 / normal 正常展开 / hidden 完全隐藏），不引入避让机制。
4. **不采用私有 CoreDock API**：不把私有 API 作为长期基础设施（系统版本兼容性与维护成本不可控）；短期实验可单独验证。
5. **接管态与测试态分离**：接管态由配置模式驱动，贴底运行（offsetY = 0）；测试态使用悬浮高度（默认 140pt）。
6. **不做常驻自动自愈**：不运行 Dock 配置轮询计时器，不引入后台 helper 或 LaunchAgent；漂移只告警，设置界面显示警告信息条，用户点击「立即检查并修复」后才重新应用接管参数。

来源：
- Ghostty PR #5361（窗口 level 与 IME）：https://github.com/ghostty-org/ghostty/pull/5361

## 交互与鼠标态约定

- **窗口层组合**：borderless + nonactivating + canJoinAllSpaces + fullScreenAuxiliary；level 见「窗口层级与避让」。收起态靠 `ignoresMouseEvents` 点击穿透，进入交互翻回 false。
- **鼠标态统一采样器驱动（非激活悬浮窗上 NSTrackingArea 不可靠）**：实测 entered/exited 合成有稳定复现的状态机失步。图标悬停、潮涌行悬停、离场判定全部由接近检测采样器（mouseMoved 事件 + 40ms 节流 + 0.25s 兜底轮询）做命中测试驱动；点击/长按仍走 mouseDown/Up 事件流（该路径可靠）。离场收起防抖 300ms，期间 re-enter 取消。
- **接近检测主路线**：全局 `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`（鼠标类零权限）+ local monitor 兜底自家激活态 + 低频轮询 `NSEvent.mouseLocation` 兜底。NSTrackingArea 仅用于展开面板内部 hover。
- **key 只服务键盘会话**：材质质量与窗口 key 状态无关（NSVisualEffectView 以 `.state = .active` 固定渲染）；`makeKey()` 仅在键盘会话开始时调用（local monitor 只能看到投递给本 app 的键盘事件，潮涌面板自身无需 key），鼠标展开不改变 frontmost。
- **多显示器**：每屏一个 panel，监听 `NSScreen.didChangeScreenParametersNotification`。

## 条目类型与固定生命周期

1. **类型与保留策略正交**：`item` 是展示与交互单位；类型决定行为，固定关系决定持久保留。固定应用和临时应用不是两种行为类型，不复制应用状态与动作实现。
2. **固定项 + 临时项组合**：固定项按用户顺序展示；临时项由运行应用产生。应用按既有 AppIdentity 合并，已固定且运行的应用只有一个 item，窗口点、潮涌、角标、激活与退出行为不受固定状态影响。普通应用退出后临时项消失，固定项保留；Finder 沿用「Finder 角色」的逻辑运行规则。
3. **应用能力不泛化为所有条目的必填字段**：文件、目录通过 NSWorkspace 打开，拥有自身菜单，不提供应用退出、运行短线或潮涌；打开文件不把它合并进默认打开应用。小组件等未来类型可接入自身行为，不要求具备 URL、bundle identifier 或进程。
4. **身份、定位与展示分离**：通用 item 身份不能复用 AppIdentity 的字符串规范化规则，文件路径须保留真实大小写。固定记录有稳定身份、类型与类型专属持久化内容；文件资源优先以 bookmark 定位，解析失败保留失效项。名称与图标不是身份，资源去重与应用运行身份匹配由各类型负责。
5. **集中解析与动作分发**：拖入资源识别、固定记录存取与列表组合、类型行为各自收敛到 module；栏、设置页、菜单使用同一套结果与操作入口。应用类型复用现有窗口与进程 module，不建设通用插件框架或提前实现小组件。

## 拖拽会话与展开状态

1. **系统拖拽会话承载事务**：采用 AppKit dragging source/destination；内部移动携带条目身份，外部资源按系统类型识别（应用包优先于普通目录）。排序预览不落库，成功松手才提交，Esc 或系统取消恢复原状态。
2. **拖出不是删除资源**：仅在内部固定项确认于栏外松手时取消固定；越界、收起、无效 drop 与取消不能混为同一结果。运行中的应用取消固定后仍以临时项存在；未固定临时项拖出不退出应用。
3. **会话存活不等于保持展开**：不默认引入覆盖整个拖拽过程的展开 hold。正常模式下沿用热区展开与离场收起；源条目身份、拖拽对象及事务由会话保留，不依赖图标视图是否仍显示。回到热区展开后重算落点，不丢失拖拽上下文。
4. **采样与窗口约束必须验证**：不能假设普通 mouseMoved 在系统拖拽期间持续送达；复用统一采样器与位置轮询，并验收收起穿透、展开后接收 drop、离开再进入和跨屏路径。若现有机制不足，先定位事件或窗口约束，不以永久展开、额外拦截窗口或全局事件转发绕过。
5. **既有交互规则继续生效**：拖动超过阈值取消长按潮涌，已开始拖拽不再触发点击；全屏 clickToExpand / hidden 不因拖拽绕过展开门槛。需要改变门槛或增加可见性 hold 时，必须先确认具体场景与行为。

## UI 技术栈分工

1. **窗口层恒为 AppKit**：borderless/nonactivating、level、collectionBehavior、makeKey 语义只有 NSPanel/NSWindow 能表达；SwiftUI Window scene 服务常规应用模型，不适用于零存在感悬浮窗（DockDoor 等同类同样只在 NSPanel 内宿主 SwiftUI）。
2. **画布层（汐线/图标栏/潮涌）用 NSView + CALayer**：编舞需要 keyPath 级控制（anchorPoint 钉底边、同层正交动画、精确 from-value、spring 参数与错峰 delay）；窗口几何由控制器命令式计算；常驻窗口空闲零开销（合成器线程重复动画，无 SwiftUI 宿主 runtime），图标行按 identity 差分复用。
3. **SwiftUI 用于窗口界面**：设置页、引导页、KeyboardShortcuts 录制器等数据驱动表单，经 `NSHostingController` + `LocalizedContent` 注入语言快照。
4. **材质直控 NSVisualEffectView**：material/blendingMode/state/appearance 全部可显式钉死（`.active` 固定 + 深浅色覆盖），不套 SwiftUI Material 密封抽象。

## 潮涌：窗口交互模型

应用条目以 app 图标为粒度（不平铺窗口）。AX 能力依据见 [research-dock-alternatives.md](research-dock-alternatives.md) §三坑 3（Focus Dock 源码验证）。

1. **点点语义**：图标下方点点 = 窗口状态（实心=活跃数、空心=最小化数，>5 收敛为数字；读不到窗口信息不画）。
2. **三条到达路径**：点击 = 切换最近非最小化窗口（仅剩最小化则还原最近一个；AX 不可用时退化为 activate）；长按或 ⌥+点击 = 「潮涌」展开该 app 的窗口列表；右键 = 应用管理菜单（见「应用右键菜单」，不列窗口）。
3. **潮涌内容**：窗口标题（`kAXTitle`）为主 + 文档图标（`kAXDocument` → `NSWorkspace.icon(forFile:)`，失败退回 app 图标）。
4. **最小化标记双维度正交**：亮度 = 是否本屏可见（他屏与最小化暗显），行尾文字胶囊标签 = 是否最小化（`window.minimizedBadge`：「已最小化」/ Minimized，10.5pt medium，quiet 填充，圆角 5pt 非胶囊；随标题色）。标签仅最小化行出现，宽度按文字实测，出现时标题截断点左移（标签宽 + 8pt 间隙 + 12pt 右缘留白），不为偶发元素常驻留白。符号类标记（minus/菱形/`minus.rectangle`）均被否决：minus 在行语境读作删除动作，菱形读作「注意」标记。
5. **还原/聚焦**：`kAXMinimized` 置 false + `kAXRaiseAction` + `activateIgnoringOtherApps`；AX 读不到窗口的 app 降级为纯图标 + activate。
6. **AX 窗口收录规则**：`subrole == AXStandardWindow` 或 `minimized == true`。最小化窗口的 subrole 不可靠（实测：访达最小化丢 std 标记、Zen 最小化报 AXDialog），必须 min 兜底；对话框/访达桌面元素两者皆不满足，天然排除。依据见 `plans/archived/todo-2026-09-window-surge.md` 探针结论。
7. **命名**：二级展开名「潮涌」，代码标识 Surge（SurgePanel/SurgeView）；与「汐线」成对——汐为收敛态，涌为突发态。
8. **动画语言「错峰升降」**：列表项从图标栏背后逐项错峰升起（每项延迟 20~30ms，弹簧曲线），收起反向退落；汐线展开共用此语言。

## 应用身份与进程模型

1. **身份统一**：bundle identifier 以 ASCII 不区分大小写的规范身份参与比较、去重、UI identity 和行为索引；启动、窗口操作与文件定位仍使用采集阶段解析出的 URL、PID 和运行实例，不用规范字符串反查系统对象。
2. **应用聚合、窗口归属到进程**：同一身份的多个运行实例在图标栏只生成一个条目；窗口知识按 PID 观测并聚合，每个窗口保留 owner PID，窗口动作始终发送给所属实例。任一实例无法完整确认窗口集合或最小化态时，聚合结果为未知，不报告不完整点数。
3. **裸进程照收**：无 bundle 的 regular GUI 进程（.NET/Avalonia 调试目标、直跑 jar 等）身份由可执行路径派生（`AppIdentity(路径)`，`proc_pidpath` 解析，公升 libproc API），与 bundle 身份天然不碰撞（bundle identifier 不含路径分隔符）。裸进程没有可靠的应用启动定位，不支持固定，右键菜单不提供固定项；将可执行文件作为文件资源固定不等于承诺重建其原启动参数与环境。
4. **身份对账双通道**：动作校验（AppActionDispatcher）与窗口观测（WindowStore）对 bundle 进程按 bundle identifier 比对，对裸进程按可执行路径比对，均归于条目的规范化身份。
5. **identity 与内容修订分离**：identity 只负责复用视图；进程、能力或可观测窗口模型变化必须替换最新模型。被跟踪条目消失、窗口知识降级或可观测窗口模型变化时，已展开潮涌立即失效并关闭。

## Finder 角色

1. **桌面角色完全忽略**：Finder 常驻进程承载系统桌面，进程存在本身不代表「正在运行」，不贡献图标、运行短线或窗口点。
2. **资源管理器以收录窗口判定运行**：存在至少一个按通用规则收录的窗口（标准或最小化）即逻辑运行；全部关闭即逻辑未运行。桌面 AX 元素由通用规则自然排除，无 Finder 特判。
3. **固定与运行状态解耦**：固定 Finder 无收录窗口也保留图标；未固定 Finder 仅逻辑运行时显示。默认固定列表不含 Finder。
4. **系统进程引用用于动作**：Finder 的 `NSRunningApplication` 仍用于激活、reopen、隐藏/显示；固定且无窗口时点击现有进程并发送 reopen 打开资源管理器窗口，但不直接决定 `AppEntry.isRunning`。
5. **无退出动作**：Finder 不提供终止，也不尝试终止后恢复桌面。

## 应用右键菜单

1. **导航与管理分离**：窗口导航只由长按或 ⌥+点击的潮涌承担；右键菜单只提供应用级管理动作，依次为固定状态、在 Finder 中显示、分隔线、打开或显示/隐藏、退出。固定文案对称：「固定到 TideBar」/「取消在 TideBar 中固定」。
2. **可见性跟随系统真值**：未运行应用显示「打开」；运行应用全部实例均隐藏时显示「隐藏窗口」的反义项，否则显示「隐藏窗口」。隐藏状态进入内容修订，由工作区隐藏/取消隐藏通知刷新。zh-Hans 文案「显示窗口／隐藏窗口」消除误读，英文沿用系统 Dock 惯用语 "Show／Hide"。
3. **动作统一校验**：显示、隐藏和退出执行前均刷新模型并校验运行实例身份；显示会解除隐藏并激活首选实例。受保护应用（Finder）不提供退出。
4. **只承诺通用菜单，不继承应用自定义 Dock 菜单**：`applicationDockMenu(_:)` 只允许应用向系统 Dock 提供自己的菜单，无公开 API 供第三方读取；不把 Dock 私有 API 或瞬态 AX 菜单抓取作为基础设施。最近项目、特定应用专属动作属未来可选能力，若立项需重新评估数据来源、权限与稳定性。

来源：
- Apple `NSApplicationDelegate.applicationDockMenu(_:)`：https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:)
- Apple `NSDockTilePlugIn`：https://developer.apple.com/documentation/appkit/nsdocktileplugin

## 应用状态与列表动画

1. **动画跟随模型真值**：窗口点变化、应用新增与应用删除均由 Registry/AX 已确认的数据变化触发，不在点击、启动请求或退出请求发生时提前假设结果。
2. **状态标记连续过渡**：运行但无可显示窗口使用次要标签灰色短线；首个窗口出现时短线收缩为圆点，最后窗口关闭时反向变化。状态标记使用独立图层，不依赖 `draw(_:)` 瞬时重绘。
3. **列表按 identity 差分编舞**：新增项从汐线下方上涌，删除项向汐线沉落，保留项用 transform 完成位置过渡。离场结束前不得缩小面板边界，避免动画被窗口裁剪。
4. **只呈现可见变化**：展开态实时播放模型变化；收起期间不积压逐项动画，下次展开统一使用整栏涌潮动画。减少动态效果开启时退化为短促淡化。

## 汐线应用收纳反馈

1. **逻辑运行状态驱动**：Registry 确认应用从未运行进入运行态后发送一次合并事件，覆盖已固定应用；固定操作、普通窗口内容刷新、初始快照不触发。窗口驱动的应用首次获得窗口知识只建立基线，读取降级保留上次已知运行状态，避免把 AX 就绪或恢复当作启动。
2. **中心固定、向内收纳**：可见折叠汐线一次轻微收窄、增厚后恢复，默认约 360ms，只改变显式 transform，不改变窗口或图层几何。Registry 去抖合并同轮启动，待播或动作进行中的后续启动合并消化。
3. **衔接与优先级**：收起回归动作结束后再收纳；中途展开取消待播并从当前形态接续；全屏隐藏撤销待播与正在播放的收纳。通知脉冲优先接管，脉冲期间不追加收纳，独立的持久涟漪照常运行。
4. **反馈不积压**：展开态、隐藏态、减少动态效果开启时不播放收纳，也不补播到下次折叠或显示。

## 统一轮询与通知角标

1. **PollScheduler 是常驻轮询唯一入口**：单一基频 Timer（= 需求最小间隔）承载全部需求；按名注册/注销，相位错开分片，容差 1/5 基频允许系统合并唤醒；主线程 tick 只做触发，重活（AX 读取）由需求自调度后台队列回桥。接近检测兜底、Dock 角标、设置页权限轮询全部迁入；设置页开窗注册、关窗注销。
2. **角标路线（本机实测成立）**：接管态（autohide-delay 1000 + tilesize 16）下 `com.apple.dock` 进程 AX 树可枚举全部 `AXDockItem`，`AXStatusLabel` 实时携带角标字符串；无变更推送，只能轮询。覆盖面 = Dock 角标镜像，与系统设置中各 app 的角标开关天然一致。uBar、SketchyBar、simple-bar、BadgeBar、Focus Dock 同路线。
3. **BadgeStore 落地**：后台读 Dock AX 树，展开 1s/收起 4s 自适应、展开瞬间立即全量读、接管关闭时不轮询（系统 Dock 可见时镜像无意义）；badge 进 AppEntry 模型真值，不触发潮涌失效；Dock 标题与应用显示名小写规范化对位，匹配不到静默忽略。
4. **汐线通知语言：轻涌 + 持久涟漪，展开即确认**：新角标一次轻涌，未确认期间双环错相涟漪循环（线源扁椭圆形态，横向 1.3 倍线宽、终态波高 14pt）；停止条件 = 任意一次展开（用户已知）或全部角标消失（从横幅读完）；减少动态效果时脉冲退化为短淡化、不做常驻循环。动机：一次性提醒与系统横幅注意力重复，持久动效表达「未被知晓」状态而非「事件发生」瞬间。
5. **解析与展示约定**：AXStatusLabel 正整数→计数角标（99+ 封顶）、非空非数字→小圆点、空/零→不显示；连续读取失败 3 轮才清值，Dock 重启期间保留旧值防闪烁。

## 快捷键与开发启动边界

1. **全局热键不引入新的 TCC 权限**：使用 Carbon `RegisterEventHotKey` 接收有限的快捷键事件，不使用全局键盘监控。窗口级导航仍受辅助功能授权约束，未授权时退化为应用激活。
2. **快捷键与鼠标状态机分层**：热键注册、键盘导航状态和鼠标接近/展开状态分别维护；热键注册失败或注销时，鼠标交互必须保持完整。
3. **开发与发布启动路径分离**：`swift run` 是开发期主路径（保留已授权 Terminal 的调试体验）；正式 `TideBar.app` 只承担发布和登录项启动。两条路径共存，Bundle 的构建/签名/授权问题不得阻塞功能开发。
4. **正式 Bundle 使用稳定签名**：Bundle 从 Finder、登录项或 `open` 启动时作为独立 TCC 主体，需单独授予辅助功能权限；开发 Bundle 不用每次重建都变化的 ad-hoc 身份，改用稳定的自签名或 Apple Development 签名。
5. **首版 `⌥Tab` 采用临时切换会话**：第一次触发优先定位当前前台应用，后续按键循环切换；空闲超时自动提交当前选择并收起（设置页可配，默认约 0.9 秒）。`Return` 立即提交，`Esc` 取消。`⌥Space` 独立作为持久 toggle，不受超时影响。两个快捷键的初始选择共用当前前台应用优先、首个条目回退的规则。
6. **快捷键录入采用 KeyboardShortcuts**：不维护自制 Recorder 和第二套 Carbon 注册；使用 KeyboardShortcuts 3.0.1 的 SwiftUI Recorder（录制期间暂停热键、失焦结束录制、Esc 取消、Delete 清除）。设置页保存后经其内置存储与 Carbon 注册立即生效；录入至少一个修饰键加一个普通键，注册成功不等于系统层面无冲突。该依赖是快捷键功能的专项例外，不引入 SwiftUIX 等通用 UI 大依赖。

## 本地化与应用内语言切换

1. **资源格式用经典 .strings（SE-0278），不用 String Catalogs**：xcstrings 的编译与符号生成绑定 Xcode/xcodebuild 链路，`swift build` 不原生支持。词条按功能域分 table（Onboarding/Settings/Menus/Runtime/Labels），en + zh-Hans 双语人工维护，key 点分层命名。
2. **应用内切换 = 自定义 lproj bundle 查找**：`L10nManager` 按用户偏好从 Bundle.module 加载对应 lproj 子 bundle，全部文案查找显式指定该 bundle，不依赖系统 preferred localization；「跟随系统」按系统语言 zh 前缀归 zh-Hans，其余归 en。
3. **SPM 把 lproj 目录名规范化为小写（zh-Hans.lproj → zh-hans.lproj），而 `path(forResource:)` 按精确名匹配**——自定义加载必须精确名查不到时按小写回查，否则非英文 bundle 加载失败静默回退、界面恒为英文（首次实现即踩此坑，GUI 验收暴露）。
4. **语言以不可变快照接入依赖图**：`@Observable L10nManager` 原子替换包含偏好、实际语言和 bundle 的 `Localization`。每个 hosting root 通过 `LocalizedContent` 注入快照和 locale，消费视图声明 `@Environment(\.l10n)`；不用语言作为 `.id`（会重置 UI 状态）。枚举标签持 key（UI 层 extension 提供 `titleKey`），由独立读取环境的 `LocalizedText` 解析；两个语言选择器共用组件与状态写入路径。
5. **状态保存语义，展示时翻译**：自有 Dock 错误以 `DockFailure` 保留错误类型与参数，向导和设置页展示时解析词条；只有外部系统错误才保存系统描述（`error.localizedDescription` 保持系统本地化直通）。AppKit 处（状态栏菜单、设置窗标题、已展开潮涌回退文案）监听语言通知重建。NSLog 运行时日志保持英文可 grep。
6. **验收必须覆盖原生控件与独立子视图**：资源和状态单测不能替代 GUI 验收；权限轮询仅在权限值变化时发布，语言刷新不能依赖不相关的轮询或用户操作。

来源：
- Apple，SwiftUI 依赖图与视图值比较：https://developer.apple.com/videos/play/wwdc2021/10022/
- Apple，`id(_:)` 的状态重置语义：https://developer.apple.com/documentation/swiftui/view/id(_:)

## 全屏检测与点击展开

1. **全屏真值来自辅助功能**：读取窗口 `AXFullScreen`，不以覆盖整屏的尺寸条件判断。`CGWindowListCopyWindowInfo` 只提供当前 Space 的可见窗口，按 PID 与窗口坐标匹配 AX 元素，按显示器交集面积确定屏幕归属。刘海安全区和 Split View 半屏不影响全屏属性；无需屏幕录制权限或私有窗口 ID API。
2. **无法匹配即未知**：同进程不同 Space 的同坐标窗口若报告不同全屏状态，不猜测可见者；权限缺失、属性不支持和超时同样保留未知。同一 Space 内短暂失败最多保留最近 2 秒内的确认值；切换 Space 或显示器布局时立即清空。持续不可读时恢复普通交互；撤销权限立即丢弃确认值，授权恢复后自动重试。
3. **后台采集、统一调度**：复用 PollScheduler 轮询入口，每 0.5 秒至多一轮后台串行读取，设置、Space、应用激活和显示器变化触发刷新。在途结果受代次校验约束；CG 可见窗口在采集期间变化时，按屏幕丢弃不一致结果。
4. **默认档为点击展开（Click to Expand）**：全屏时保留汐线，收起状态只有直接点击汐线附近的紧凑区域才展开，鼠标靠近和快捷键均不绕过。视觉汐线 160×3pt，点击入口为贴底 184×16pt 矩形、左右各加 12pt（实现层手感参数，区域外操作直接交给系统目标窗口）。
5. **独立非激活点击窗口**：主汐线面板维持展开尺寸及收起穿透；另用同屏紧凑 NSPanel（TidelineClickPanel）接收点击，窗口边界即命中边界，不做全局点击监听、事件拦截或转发。左键在区域内按下并松开才展开；点击入口不成为 key / main 窗口。
6. **所有展开入口共享全屏状态**：鼠标、持久快捷键、应用切换快捷键和潮涌入口消费同一全屏状态；点击档要求点击，normal 正常交互，hidden 隐藏面板并停止命中。全屏限制生效时结束该屏键盘会话。只改变收起态的展开条件：点击后沿用图标、潮涌、键盘导航和离场收起，下一次收起再要求点击；进入点击模式时收起已有栏，后续全屏轮询不重复收起；展开、完全隐藏、退出全屏、停用和重建时撤销点击入口。

依据：本机显示器 CG bounds 为 1710×1112pt、safeAreaInsets.top 为 38pt；Apple [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) 描述原生全屏内容位于安全区域内；[Logoer PR #31](https://github.com/lihaoyun6/Logoer/pull/31) 记录 macOS 26 上最大化与全屏窗口尺寸不可区分的实测。

## 窗口画面与 ScreenCaptureKit

1. **不做悬停窗口实时预览**：ScreenCaptureKit 逐窗抓图的成本高于收益；可行性表相关行仅作技术路线留档。
2. **ScreenCaptureKit 永不引入**：任何窗口画面能力不走 SCK，权限面永久收敛到辅助功能一项；对外话术源 [copy.md](copy.md) §五 现为占位稿，定稿时须与本决策一致。缩略图类能力若立项，走私有 CGS（SkyLight）抓图——不触发 TCC、可截最小化窗口；调研文档 §四留有同类应用现状（纯 SCK 在 macOS 14/15 有崩溃/bug，AltTab 至 macOS 26 才全量 SCK；逐窗抓图主流是私有 `CGSHWCaptureWindowList`）。
3. **隐私话术受益**：不显示缩略图坐实「不读屏幕内容、永远不请求屏幕录制权限」的对外承诺。

## 部署基线

**macOS 14**：全代码无 macOS 26 特有 API，swift-tools 维持 6.2。开发机与依赖政策对齐不构成抬高基线的理由，无 API 必要性不动基线。

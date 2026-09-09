# 潮涌体：类型自定义的长按面板

> 状态：已实现，`swift build`、测试（97 项）通过；待用户 GUI 验收。决策已同步改写 `docs/decisions.md`「潮涌：类型化长按面板」。文件条目伪预览体另案。

## 已确认契约

- 潮涌 = 通用长按面板，不再是窗口列表的别名。容器（NSPanel、层级、玻璃材质、图标锚定定位、Esc、离场防抖、keep-region）归控制器；内容由条目类型提供（潮涌体）。app 的窗口行与目录的文件行只是恰好形似，可共享视觉组件，但不构成契约——widget 的潮涌体可以是任意自绘视图。
- 每个类型有自己的潮涌体与状态呈现：正常内容、空态、不可读/错误态、截断态都由体自己表达，这是潮涌的自定义能力所在，容器不做统一空态。
- `ItemCapabilities` 增加 surge 内容能力；`ItemBehaviorProviding` 增加潮涌体构造；`ItemIconButton` 长按与 ⌥+点击的触发门槛从 `application != nil` 改为查能力。
- 目录潮涌 = 最近文件列表：「最近」= 修改时间排序，显示前若干行（实现层定，约 8）；隐藏文件跳过；子目录参与排序（实现层可调）；行点击打开目标。
- 数据源：无「按属性取 top-N」的文件系统 API（目录迭代序非 mtime 序；Spotlight/NSMetadataQuery 依赖索引，不适合瞬时面板）。采用 `contentsOfDirectory` + prefetch `[.contentModificationDateKey, .isDirectoryKey]` 单次批量取值；病态大目录后台计算 + 软预算封顶，超限以截断态呈现。
- 失效模型按类型分：应用沿用窗口 revision 失效；目录体在打开时按需计算，天然新鲜。不引入 FSEvents、常驻轮询，零空闲成本。
- 键盘会话（⌥Tab/⌥Space）维持应用窗口导航语义，本期不覆盖目录与文件。
- 悬停判定继续由统一采样器驱动，控制器把采样点转发给潮涌体协议钩子，体内部自行处理命中；不回归 NSTrackingArea。

## 实现地图

| 路径 | 职责 |
|---|---|
| `Sources/TideBar/SurgePanel.swift` | 潮涌体协议（SurgeBody）、通用行与错峰动画（SurgeRowView / SurgeMotion）、应用窗口体（AppSurgeView）、容器视图（SurgeContainerView，玻璃归容器）与宿主面板 |
| `Sources/TideBar/DirectorySurgeView.swift` | 目录潮涌体与最近文件数据源（DirectoryRecentFiles：批量 mtime、预算封顶、状态行） |
| `Sources/TideBar/ItemBehavior.swift` | `surgeBody` 能力与体构造入口；应用体、目录体各自实现 |
| `Sources/TideBar/ItemIconButton.swift`、`ItemRowView.swift`、`TideBarView.swift` | 长按与 ⌥+点击门槛改查 capability，透传 ItemEntry |
| `Sources/TideBar/TideBarController.swift` | 请求代数化异步体构造、容器呈现、按类型失效、采样点转发与键盘会话钩子 |

## 已实现

- [x] `ItemCapabilities` / `ItemBehaviorProviding` 增加 surge 体能力与构造入口
- [x] `ItemIconButton` 触发门槛改 capability（长按 + ⌥+点击）
- [x] `TideBarController`：`surgeIdentity` 泛化为 `ItemID`；失效按类型；面板尺寸由潮涌体给出；异步体构造带请求代数防过期
- [x] 目录最近文件潮涌体（列表 + 空态 + 不可读/错误态 + 截断态）
- [x] 最近文件数据源（批量 mtime + 后台计算 + 封顶），测试覆盖排序、上限、预算、空、失败与隐藏文件
- [x] 改写 `docs/decisions.md`「潮涌」为通用长按面板模型（窗口列表降为应用体条目）
- [x] 离场防抖改为「进入过才算离场」：触发点在图标上，未进入不排防抖，潮涌随栏滞留区存活；按住左键期间不排防抖；潮涌在场时名字气泡让位（同层级不叠盖）；present 时以注册表当前真值对账窗口修订
- [x] 收场语义再泛化（用户拍板）：潮涌打开即驻留，不因鼠标离开收场，离场防抖机制移除；收场 = 他处完成点击（按下与松开均在面板外，长按松手豁免，拖入丢弃不收场）、右/中键面板外按下、Esc、行拾取、失效、会话结束、模式变化；栏收起不再连带收走潮涌（全屏隐藏/点击档进入时显式收场）
- [x] 修复收场判定从未生效：monitor 事件被局部变量遮蔽，改经 `NSEventBox` 过主线程桥；拖动开始不收场（起点非目标动作，键盘会话照常结束），拖拽结束的松手豁免且豁免不跨下一次按下存活；潮涌面板不是拖出移除的有效落点；拖拽期间悬停不点亮行

## 下一阶段（另案）

- 文件条目潮涌体：仅文件图标 + 文件名的伪预览，不预览内容，只是避免 noop 的交互降级。

## 不做

- 不建通用插件框架、不提前实现小组件；widget 立案时只增加内容形态，不动容器。
- 不引入新权限、FSEvents、常驻轮询；文件访问服从系统控制，失败以体的错误态呈现。
- 不做目录内容的实时刷新与监视。

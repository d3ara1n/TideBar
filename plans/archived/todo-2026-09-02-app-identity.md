# 应用统一身份与行为能力重构

> 立案 2026-09-02，完成 2026-09-02（用户 GUI 验收通过）。稳定结论见 `docs/decisions.md`。

## 背景

应用固定项、运行实例、窗口观测和 UI 差分当前分别使用未经规范化的 bundle identifier 字符串。系统 Finder 的运行标识为 `com.apple.finder`，默认固定项使用 `com.apple.Finder`，导致同一应用被拆成两个条目；窗口状态只归到运行条目。右键菜单又以 `runningApp != nil` 作为唯一退出条件，可直接终止同时托管桌面的 Finder 进程。

本任务不以修正某个字符串或在菜单中增加 Finder 条件分支收口，而是建立统一身份、窗口知识、行为能力和受保护动作入口。

## 产品决策

1. 应用身份比较不区分 bundle identifier 的 ASCII 大小写；系统操作使用采集阶段解析出的 URL、PID 和运行实例，不反查规范化字符串。
2. 每个应用身份在图标栏最多生成一个条目；同一身份的多个运行实例在应用粒度聚合，窗口仍保留所属 PID。
3. Finder 仅在窗口状态已知且至少存在一个通用规则收录窗口时显示；AX 未授权、尚未完成枚举或读取降级时隐藏。标准窗口或最小化窗口均计入，桌面元素自然排除，不增加 Finder 窗口类型特判。
4. Finder 不具备终止能力，任何 UI 和动作入口都不得终止其进程；不尝试在终止 Finder 后补救桌面。
5. 固定配置不能覆盖系统级行为约束。固定列表中的重复项和大小写变体按规范化身份去重，保留第一次出现的位置。
6. Finder 桌面 AX 元素继续由既有窗口收录规则排除，不增加 Finder 窗口类型特判。

## 架构不变量

- `AppIdentity` 是应用比较、Hash、UI identity、策略索引和潮涌跟踪的唯一键。
- `WindowStore` 以 PID 保存观测真值，不按 bundle identifier 任取一个运行实例。
- 窗口知识显式区分未知与已知空集合；未知不等同于零窗口。
- 列表组合由纯数据输入完成，输出中 `AppIdentity` 唯一。
- 行为能力由模型层解析；视图只渲染能力，实际动作入口再次校验能力。
- 窗口动作使用窗口所属 PID 对应的运行实例。
- UI 条目身份稳定，但相同身份的新模型必须替换旧模型，避免持有过期进程或 AX 元素。

## 阶段一：统一身份与纯列表组合器

- [x] 新增小型 `AppIdentity` 值类型，以 ASCII 小写作为规范键。
- [x] 新增轻量运行实例/固定项描述和纯 `AppListComposer`。
- [x] 固定配置在读取边界规范化、去重并保留首次顺序。
- [x] 运行实例按身份聚合，组合器保证每个身份最多一个输出。
- [x] `AppRegistry` 改为采集系统对象并交由组合器决定身份、顺序和基础可见性。
- [x] 增加测试 target，覆盖大小写身份、重复固定项、同身份多 PID 和普通固定/运行项。
- [x] 本阶段不改变 Finder 的窗口可见性和退出行为，避免身份迁移与产品行为同时发生。

### 阶段一验收

- `com.apple.Finder` 固定项与 `com.apple.finder` 运行实例只产生一个应用身份。
- 同一 bundle identifier 的多个运行实例不会产生重复 UI id。
- 普通固定未运行应用仍可显示，运行应用排序与固定顺序保持现状。
- 组合器测试和 `swift build` 通过。

## 阶段二：窗口知识与行为策略

- [x] `WindowStore` 暴露按 PID 查询的 `WindowKnowledge`。
- [x] 窗口快照携带 owner PID；组合器按身份聚合多个实例的窗口知识。
- [x] 任一实例窗口知识未知时，应用整体窗口知识保持未知，不报告不完整点数。
- [x] 引入最小 `AppBehavior`：可见性与终止能力，不建设通用策略框架。
- [x] Finder 行为声明为 `whenHasKnownWindows` 与 `terminationForbidden`。
- [x] 固定配置不能强制显示 Finder；未知或已知零窗口均隐藏。
- [x] 点击窗口时使用 owner PID 对应的运行实例。

### 阶段二验收

- Finder 已知零窗口时隐藏；已知非空时唯一显示且点数正确。
- Finder 窗口状态未知时隐藏。
- 多 PID 同身份窗口正确聚合，窗口动作指向所有者实例。
- 普通应用的 AX 降级行为保持纯图标与激活。
- 测试和 `swift build` 通过。

## 阶段三：动作保护与 UI 生命周期

- [x] `AppEntry` 携带模型层解析的动作能力和完整内容修订信息。
- [x] 退出动作移出 `AppIconButton` 的直接系统调用，统一走受保护入口并二次校验。
- [x] Finder 菜单不显示“退出”，动作入口也拒绝终止 Finder。
- [x] 相同 identity 的按钮始终接收最新 entry；重绘优化与模型替换分离。
- [x] 被跟踪条目消失、窗口知识未知或窗口内容变化时关闭过期潮涌。
- [x] 配置变化先刷新 Registry，再刷新或重建面板。
- [x] 在 `docs/decisions.md` 新增取代 Finder 常驻结论的决策，不修改归档计划。
- [x] 完成全量回归测试和 `swift build`。

### 阶段三验收

- Finder 在所有菜单和动作入口都不可终止。
- 关闭 Finder 最后一个收录窗口后，图标与已展开潮涌正确消失。
- 进程替换、可观测窗口标题变化或能力变化不会留下旧运行实例和旧 AX 元素。
- 普通应用仍可退出；固定、启动、激活、窗口直达行为无回归。

## 测试矩阵

- 固定项大小写与运行实例不同：唯一身份、正确运行态。
- 固定列表含重复及大小写变体：保留第一次出现的位置。
- 同身份多 PID：唯一条目，无 UI identity 冲突。
- Finder `.known([])`：隐藏。
- Finder `.known(nonEmpty)`：唯一显示、点数正确、无终止能力。
- Finder `.unknown`：隐藏。
- 固定列表包含 Finder：仍遵守窗口可见性规则。
- 普通固定未运行应用：显示并可启动。
- 普通运行应用窗口未知：显示、无点、可激活。
- 条目消失：潮涌关闭。
- 同身份进程替换、可观测窗口标题或能力变化：UI 获得最新模型。

## 影响范围

- `Package.swift`
- `Sources/TideBar/AppRegistry.swift`
- `Sources/TideBar/WindowStore.swift`
- `Sources/TideBar/AppIconButton.swift`
- `Sources/TideBar/TideBarView.swift`
- `Sources/TideBar/TideBarController.swift`
- 新增身份、组合器与测试文件
- `docs/decisions.md`

## 非目标

- 不引入第三方依赖。
- 不改变 AX 窗口收录规则。
- 不实现 Finder 自定义“退出”或桌面重启机制。
- 不建设可配置的通用规则引擎。
- 不改写或迁移 UserDefaults 中的原始固定项；只在读取边界规范化。

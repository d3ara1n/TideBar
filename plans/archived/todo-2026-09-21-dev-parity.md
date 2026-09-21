# 开发运行与正式行为对齐（todo-2026-09-21）

## 背景

原设计把 `swift run` 定位成「UI 造型预览台」：居中悬浮、常驻展开，并闸掉了角标镜像（BadgeStore 的 `isProduction && isTakeoverEnabled`）、全屏策略（强制 `.normal`）、快捷键注册（AppDelegate 的 `isProduction` 包裹）与设置页快捷键段。后果：通知语言（角标/轻涌/涟漪）、全屏避让、快捷键设置等正式功能无法在开发循环里迭代调试，与「开发路径是主路径」的定位矛盾。

裁决：开发运行的隔离目标只有系统副作用，不是功能。对齐原则 = 行为与正式一致，仅保留三类隔离：不写系统 Dock（无接管/还原）、配置不落盘（内存覆盖层读正式域）、bundle 依赖能力不启用（登录项、Sparkle）。

## 改动

1. **TideBarController**：删除开发态常驻展开逻辑（随正式一样收起起步）；全屏行为不再强制 `.normal`。开发栏保持悬浮屏幕中央（热区随行），与系统 Dock 并存互不干扰。
2. **BadgeStore**：轮询闸改为 `isDevelopment || isTakeoverEnabled`——开发运行镜像角标，生产未接管（本栏不存在）仍不轮询。
3. **AppDelegate**：快捷键接线与注册去掉生产闸；KeyboardShortcuts 录制落在进程名域，与正式 `dev.dearain.TideBar` 域隔离。
4. **SettingsWindowController**：快捷键页对开发运行可见；注释同步。
5. **docs/decisions.md**：#70 改写为「开发与正式行为对齐，仅隔离系统副作用」；#170 轮询条件、#186 启动路径分离条目同步。

保留不动：DockController 全部系统写入闸、LoginItem、UpdateCoordinator、设置页登录项/更新区块、内存配置覆盖层、设置窗标题「— 开发」后缀、`configurationDidChange` 的开发早退（开发面板生命周期不随 takeover 开关驱动）。

## 验收

- `swift build --build-system native` 通过。
- `swift run`：悬浮屏中央的细线起步、接近展开、可收起；QQ 来消息可见角标 + 轻涌 + 涟漪（顺带验收 todo-2026-09-21-ripple-follows-source）；⌥Space/⌥Tab 生效且可在设置页改键；退出后系统 Dock 无任何变更、正式配置无写入。

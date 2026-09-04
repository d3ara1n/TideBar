# 应用管理右键菜单

> 实现、测试、构建验证与用户 GUI 验收完成。

## 背景

窗口导航已经由长按和 `⌥`+点击打开的潮涌承担。右键菜单继续列出窗口会混合导航与应用管理职责，并随窗口数量改变长度。

## 产品方案

右键菜单只保留应用级动作，顺序固定为：

1. `固定到 TideBar` / `取消在 TideBar 中固定`
2. `在 Finder 中显示`
3. 分隔线
4. 未运行时显示 `打开`；运行时按真实状态显示 `显示` / `隐藏`
5. 允许退出时显示 `退出`

固定与取消固定的文案都明确出现 TideBar，保持语义对称。窗口列表不再出现在右键菜单中。

## 实现约束

- 监听应用隐藏与取消隐藏通知，使菜单状态跟随系统真值。
- 同一应用身份有多个运行实例时，全部实例均隐藏才视为隐藏。
- 隐藏、显示和退出均通过统一动作入口，在执行前刷新模型并校验运行实例身份。
- `显示`解除隐藏后激活首选运行实例；固定未运行应用继续通过现有启动路径打开。
- Finder 等受保护应用继续不提供退出。

## 验收

- 右键菜单不再包含窗口列表。
- 固定文案为 `固定到 TideBar` / `取消在 TideBar 中固定`。
- 未运行应用显示“打开”，不显示“退出”。
- 可见的运行应用显示“隐藏”；隐藏后再次打开菜单显示“显示”。
- “显示”可解除隐藏并激活应用。
- Finder 不显示“退出”。
- `swift build` 通过；GUI 行为由用户运行验收。

## 影响范围

- `Sources/TideBar/AppRegistry.swift`
- `Sources/TideBar/AppActionDispatcher.swift`
- `Sources/TideBar/AppIconButton.swift`
- `Sources/TideBar/TideBarView.swift`
- `Sources/TideBar/TideBarController.swift`
- `Sources/TideBarCore/AppContentRevision.swift`
- `Tests/TideBarCoreTests/AppContentRevisionTests.swift`
- `docs/product.md`
- `docs/decisions.md`

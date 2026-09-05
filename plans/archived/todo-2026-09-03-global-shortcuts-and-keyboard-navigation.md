# 全局快捷键与键盘导航

> 状态：快捷键设置、delay 配置与统一会话状态机已实现，构建与测试通过，待用户 GUI 验收。

## 背景

汐目前以鼠标接近、点击、长按和 ⌥+点击为主要入口。窗口管理的核心价值是快速抵达窗口，因此需要提供键盘可达路径，同时不破坏现有鼠标交互。

## 产品方案

### 全局快捷键

首版提供以下默认快捷键，并预留后续配置能力：

- `⌥Space`：切换当前鼠标所在屏幕的 TideBar 展开/收起状态。
- `⌥Tab`：进入临时应用切换模式；第一次优先定位当前前台应用，后续每次按键切换到下一个应用；空闲超时自动激活当前选择并收起。`Return` 立即激活，`Esc` 取消。
- `Esc`：退出快捷键模式、关闭潮涌或取消当前选择。

快捷键冲突、不可注册或用户关闭时，鼠标路径必须完整可用。

### 键盘导航

- 展开栏中使用左右方向键选择应用。
- 进入某个应用的潮涌后，使用上下方向键选择窗口。
- `Return` 激活选中窗口；最小化窗口沿用现有 AX 还原流程。
- `Esc` 按层级退出：先关闭潮涌，再收起快捷键展开态。
- 选中项必须有清晰但克制的高亮，不依赖鼠标位置。

## 实现约束

- 先设计独立的 `ShortcutManager` / `BarSessionState`，不要把 Carbon 或事件处理直接塞入 `TideBarController` 的鼠标状态机。
- 全局快捷键使用系统 API（如 Carbon `RegisterEventHotKey`），不引入第三方依赖；注册失败只记录状态，不影响鼠标路径。
- 快捷键回调统一桥接到主线程；退出、重载和配置变更时注销或更新注册。
- `BarSessionState` 统一维护持久会话（`⌥Space`）与临时切换会话（`⌥Tab`）的模式、焦点屏幕、展开所有权、应用/窗口选择和超时截止时间。
- 键盘状态只保存屏幕标识、应用 identity 和窗口稳定标识，不持有过期的 `AXUIElement`；真正激活前从最新 `AppEntry` 重新查找窗口。
- 键盘模式必须有明确的焦点屏幕和选中项；多屏时以鼠标所在屏幕为默认目标，找不到时回退主屏。
- `⌥Space` 只负责唤起或收起目标屏幕的 TideBar；唤起前优先选中当前前台应用，无法匹配时回退第一个可见应用。
- `⌥Tab` 进入临时切换模式：第一次优先定位当前前台应用，后续每次按键切换应用；约 0.9 秒无新输入后自动提交当前选择并收起面板。
- 面板成为 key window 后，通过本地键盘事件处理左右/上下方向键、`Return` 和 `Esc`；处理不了的事件继续交给系统。
- 潮涌窗口模型失效、应用消失或窗口被关闭时，选中状态应安全清除，不激活过期的 `AXUIElement`；窗口列表更新时按稳定标识重新定位或取消选择。
- 辅助功能未授权时仍允许展开应用栏和浏览可见应用；窗口级导航不可用时退化为应用激活。
- 不新增屏幕录制权限，也不依赖窗口内容预览。

## 待实现前确认

- 设置页提供两个快捷键的录入、恢复默认和临时切换 delay 配置；录入限制为“至少一个修饰键 + 一个普通键”。系统级冲突无法由 Carbon 注册结果完全判断，界面不虚报无冲突。

## 验收

- 默认快捷键可以在其他应用前台时唤起 TideBar。
- 快捷键不会阻塞现有鼠标接近展开和点击路径。
- 左右键可以选择应用，上下键可以选择窗口，Return 可以激活窗口，Esc 可以逐层退出。
- 多屏场景下快捷键目标屏幕稳定。
- AX 未授权、窗口列表降级和模型更新期间无崩溃或误激活。
- `swift build` 通过；GUI 行为由用户运行验收。

## 建议实施顺序

1. 新增 `ShortcutManager`，注册 `⌥Space` 与 `⌥Tab`，并在应用退出时注销；先验证快捷键不会改变现有 `swift run` 和 Terminal 授权路径。
2. 新增 `BarSessionState`，统一表达持久会话（`⌥Space`）与临时切换会话（`⌥Tab`）的屏幕归属、展开所有权、应用/窗口选择和超时截止时间。
3. 在 `TideBarController` 增加会话投递与副作用：`⌥Space` 持久 toggle；`⌥Tab` 按键循环并在空闲超时后提交；鼠标采样器只在无会话屏幕上驱动自动收起。
4. 在 `TideBarView`、`IconRowView`、`AppIconButton`、`SurgeView` 和 `SurgeRowView` 增加键盘选中高亮，并与鼠标悬停高亮解耦。
5. 在模型更新、屏幕变化、全屏隐藏、潮涌关闭和窗口修订变化时统一清理或修正选择状态。
6. 增加状态转换测试，完成 `swift build` 与 `swift test` 后再由用户运行 `swift run` 验收全局快捷键和多屏行为。

## 影响范围

- 新增 `Sources/TideBar/ShortcutManager.swift`（基于 KeyboardShortcuts 3.0.1）
- 新增 `Sources/TideBar/KeyboardNavigationState.swift`（或等价实现）
- `Sources/TideBar/AppDelegate.swift`
- `Sources/TideBar/TideBarController.swift`
- `Sources/TideBar/TideBarView.swift`
- `Sources/TideBar/AppIconButton.swift`
- `Sources/TideBar/SurgePanel.swift`
- `Sources/TideBar/AppConfiguration.swift`
- `Package.swift` 与 `Package.resolved`（新增 KeyboardShortcuts 专项依赖）
- `Sources/TideBar/SettingsWindowController.swift`

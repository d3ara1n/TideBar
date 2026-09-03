# 全局快捷键与键盘导航

> 状态：已立项，待实现。

## 背景

汐目前以鼠标接近、点击、长按和 ⌥+点击为主要入口。窗口管理的核心价值是快速抵达窗口，因此需要提供键盘可达路径，同时不破坏现有鼠标交互。

## 产品方案

### 全局快捷键

首版提供以下默认快捷键，并预留后续配置能力：

- `⌥Space`：切换当前鼠标所在屏幕的 TideBar 展开/收起状态。
- `⌥Tab`：进入窗口切换模式，按住或连续触发可在最近使用的应用/窗口间移动。
- `Esc`：退出快捷键模式、关闭潮涌或取消当前选择。

快捷键冲突、不可注册或用户关闭时，鼠标路径必须完整可用。

### 键盘导航

- 展开栏中使用左右方向键选择应用。
- 进入某个应用的潮涌后，使用上下方向键选择窗口。
- `Return` 激活选中窗口；最小化窗口沿用现有 AX 还原流程。
- `Esc` 按层级退出：先关闭潮涌，再收起快捷键展开态。
- 选中项必须有清晰但克制的高亮，不依赖鼠标位置。

## 实现约束

- 先设计独立的 `ShortcutManager` / `KeyboardNavigationState`，不要把 Carbon 或事件处理直接塞入 `TideBarController` 的鼠标状态机。
- 全局快捷键使用系统 API（如 Carbon `RegisterEventHotKey`），不引入第三方依赖。
- 快捷键回调统一桥接到主线程；退出、重载和配置变更时注销或更新注册。
- 键盘模式必须有明确的焦点屏幕和选中项；多屏时以鼠标所在屏幕为默认目标。
- 潮涌窗口模型失效、应用消失或窗口被关闭时，选中状态应安全清除，不激活过期的 `AXUIElement`。
- 辅助功能未授权时仍允许展开应用栏和浏览可见应用；窗口级导航不可用时退化为应用激活。
- 不新增屏幕录制权限，也不依赖窗口内容预览。

## 待实现前确认

- `⌥Tab` 是“按住循环、松开激活”还是“每次按键切换并保持面板”，需要在实现前以可操作原型确认。
- 快捷键是否开放设置页自定义，以及冲突提示的最低范围。

## 验收

- 默认快捷键可以在其他应用前台时唤起 TideBar。
- 快捷键不会阻塞现有鼠标接近展开和点击路径。
- 左右键可以选择应用，上下键可以选择窗口，Return 可以激活窗口，Esc 可以逐层退出。
- 多屏场景下快捷键目标屏幕稳定。
- AX 未授权、窗口列表降级和模型更新期间无崩溃或误激活。
- `swift build` 通过；GUI 行为由用户运行验收。

## 影响范围

- 新增 `Sources/TideBar/ShortcutManager.swift`
- 新增 `Sources/TideBar/KeyboardNavigationState.swift`（或等价实现）
- `Sources/TideBar/AppDelegate.swift`
- `Sources/TideBar/TideBarController.swift`
- `Sources/TideBar/TideBarView.swift`
- `Sources/TideBar/SurgePanel.swift`
- `Sources/TideBar/AppConfiguration.swift`
- `Sources/TideBar/SettingsWindowController.swift`

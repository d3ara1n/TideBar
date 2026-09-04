# 外观与全屏行为设置

> 状态：已完成。代码与构建验证通过，GUI 行为待用户运行验收。

## 背景

设置中心的“外观与交互”页面统一管理主题、图标栏、汐线、动画和全屏行为。配置通过持久化枚举与通知机制驱动运行中的面板即时刷新，布局和动画参数保持单一真值。

## 产品方案

设置项按“外观”和“行为”分组：

### 外观

1. **主题**
   - 提供跟随系统、亮色、暗色三档，默认跟随系统。
   - 统一作用于设置窗口、汐线、图标栏、潮涌和应用菜单，切换后立即生效。

2. **应用图标大小**
   - 提供紧凑、标准、宽松三档。
   - 同步调整图标绘制尺寸与图标栏槽位，避免图标互相遮挡。
   - 潮涌窗口列表不随该设置改变行高。

3. **汐线亮度**
   - 提供自动、低、标准、高四档。
   - 自动跟随当前主题对应的外观；手动档只调整汐线视觉层，不改变命中热区。

4. **展开动画**
   - 提供标准、柔和、快速三档。
   - 统一影响汐线展开、图标波、潮涌升降和面板尺寸过渡；不允许各组件各自解释速度。

5. **减少动态效果**
   - 提供跟随系统、始终关闭、始终开启三档。
   - 开启后退化为短促淡化，不使用弹簧过冲与大位移。

### 全屏应用中的显示行为

提供三档：

1. **仅显示汐线**（默认）：全屏 Space 中保留底部细线，但不因鼠标靠近展开。
2. **正常显示**：全屏 Space 中仍可展开完整图标栏和潮涌。
3. **完全隐藏**：全屏 Space 中隐藏面板与汐线，不响应接近检测。

切换设置后应立即作用于当前屏幕；从全屏状态离开后恢复正常状态，不需要重启。

## 实现约束

- 配置集中放入 `AppConfiguration`，使用明确的 Codable/RawRepresentable 枚举或等价类型，不在视图中散落 UserDefaults key。
- `Layout` 与 `Motion` 不再把所有用户可调参数固定为静态常量；保留派生几何和动画计算的单一真值。
- 配置变更通过现有通知机制传播，`TideBarController` 负责重排面板和刷新全屏行为。
- 写入 `CALayer` 的 AppKit 语义色统一按视图 `effectiveAppearance` 解析，禁止直接将动态 `NSColor` 固化为 `CGColor`。
- 图标尺寸变化时需要处理当前展开态的面板宽度、图标布局和动画状态，不能只修改绘制 rect。
- 全屏模式为“完全隐藏”时，不能遗留不可见面板继续截留鼠标或保持 key。
- 所有设置都必须有默认值；读取非法或旧值时回退默认值。

## 验收

- 主题设置提供跟随系统、亮色、暗色三档，切换立即作用于整个 TideBar，重启后保持。
- 汐线、应用悬浮指示器和窗口状态标记随主题同步更新颜色。
- 设置页不再显示相关 `ComingSoon` 占位行。
- 修改图标大小后，当前展开栏即时更新，图标与槽位保持对齐。
- 修改汐线亮度后，收起态视觉即时更新，热区范围不变。
- 修改动画档位后，下一次展开/收起使用新参数。
- 减少动态效果设置能覆盖系统设置，并在界面上明确当前来源。
- 三种全屏行为在普通全屏应用和多屏场景下均符合定义。
- 配置重启后仍然保留。
- `swift build` 通过；GUI 行为由用户运行验收。

## 影响范围

- `Sources/TideBar/AppearanceColors.swift`
- `Sources/TideBar/AppConfiguration.swift`
- `Sources/TideBar/AppDelegate.swift`
- `Sources/TideBar/Layout.swift`
- `Sources/TideBar/Motion.swift`
- `Sources/TideBar/TideBarController.swift`
- `Sources/TideBar/TideBarView.swift`
- `Sources/TideBar/AppIconButton.swift`
- `Sources/TideBar/SurgePanel.swift`
- `Sources/TideBar/SettingsWindowController.swift`
- 必要时补充 `TideBarCore` 配置纯值测试

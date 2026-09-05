# 固定项目页交互重构

> 状态：已完成并验收。

## 背景

设置中心的固定项目页目前是「编辑模式开关 + 上下箭头按钮 + 移除按钮」的旧范式，与 macOS 惯例（直接拖拽、右键操作、悬浮操作）脱节。经调研（2026-09），原生 SwiftUI 已覆盖所需能力，无需第三方库。

## 方案

- **排序**：`List` + `ForEach.onMove`。macOS 的 List 没有编辑模式概念，挂上 `.onMove` 后行即可全天候直接拖拽重排，删除 `isEditing` 状态与 chevron 按钮。
- **移除**：行右键 `.contextMenu`（主路径）+ hover 悬浮移除按钮（`onHover`，Dock 同款交互）。不使用 `.swipeActions`（`.sidebar` 样式与 `NavigationSplitView` 内不可靠）。
- **添加**：搜索式应用选择器（`NSWorkspace` 扫描 /Applications + `.searchable` 过滤，系统设置「登录项」同款体验）替代 `NSOpenPanel`。

## 决策记录

- 不引入第三方重排包（twostraws/reorderable、Dragula、globulus/swiftui-reorderable-foreach 等）：均为 iOS 优先、DragGesture 自绘路线，macOS 支持与维护性存疑，且对列表场景不如原生 `onMove`。
- 原生 `.reorderable()` / `.reorderContainer()` 属 macOS 27 / Xcode 27（本机 macOS 26.5 SDK 实测不存在），本方案不依赖；网格/图标式编辑 UI 的演进见 `todo-2026-09-05-macos27-native-reorderable.md`。

## 验收

- 固定项目可直接拖拽排序，无编辑模式开关。
- 右键与悬浮均可移除单项；「恢复默认」保留确认。
- 添加应用走搜索选择器，可见已安装应用并按名称过滤。
- 未安装应用仍以警示态展示。
- `swift build` 通过；GUI 行为由用户运行验收。

## 影响范围

- `Sources/TideBar/SettingsWindowController.swift`（`PinnedPage`、`SettingsModel` 相关方法）

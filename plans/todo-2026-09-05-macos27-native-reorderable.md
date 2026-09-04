# 升级 Xcode 27 后采用原生 reorderable API

> 状态：延后立案，待 Xcode 27 正式版。

## 背景

WWDC26 发布了 SwiftUI 原生任意容器拖拽重排 API（`DynamicViewContent.reorderable()`、`View.reorderContainer(for:in:isEnabled:move:)` 等，覆盖 list/stack/grid/custom layout，拖拽时有系统占位与落点反馈）。本机 macOS 26.5 SDK 实测无此 API，属 Xcode 27 / macOS 27 工具链。

## 行动

- Xcode 27 正式版可用后，将固定项目页（及届时任何需要拖拽重排的容器）迁移到原生 API。
- 迁移前若需要网格/图标式的拖拽编辑 UI，用 `LazyVGrid` + `onDrag`/`DropDelegate` 手写，接受其在 Xcode 27 后被替换——不为等待 API 而冻结 UI 演进。

## 触发条件

- Xcode 27（macOS 27 SDK）正式发布且项目开发环境升级完成。

## 参考

- Apple 文档：Reordering items in lists, stacks, grids, and custom layouts
- WWDC26 Session 271: Build powerful drag and drop in SwiftUI

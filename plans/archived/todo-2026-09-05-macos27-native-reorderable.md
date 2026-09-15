# 升级 Xcode 27 后采用原生 reorderable API

> 状态：已结案，无 SwiftUI 拖拽排序消费点。固定项目页未立项，设置页为增删改查不排序；AppKit 图标栏拖拽归 `todo-2026-09-09-items-and-drag.md` 管辖。将来若出现 SwiftUI 容器排序需求，重新立案。

## 背景

WWDC26 发布了 SwiftUI 原生任意容器拖拽重排 API（`DynamicViewContent.reorderable()`、`View.reorderContainer(for:in:isEnabled:move:)` 等，覆盖 list/stack/grid/custom layout，拖拽时有系统占位与落点反馈）。本机 macOS 26.5 SDK 实测无此 API，属 Xcode 27 / macOS 27 工具链。

## 行动

- Xcode 27 正式版可用且部署基线允许后，评估固定项目页等 SwiftUI 容器迁移到原生 API；升级工具链本身不等于提高最低系统版本。
- 迁移前若设置页需要网格/图标式的拖拽编辑 UI，用 `LazyVGrid` + `onDrag`/`DropDelegate` 手写——不为等待 API 而冻结 UI 演进。
- AppKit 图标栏的内部拖拽与外部资源固定使用系统 dragging source/destination，不属于本计划的 SwiftUI 容器迁移范围；实施见 `todo-2026-09-09-items-and-drag.md`。

## 触发条件

- Xcode 27（macOS 27 SDK）正式发布且项目开发环境升级完成。

## 参考

- Apple 文档：Reordering items in lists, stacks, grids, and custom layouts
- WWDC26 Session 271: Build powerful drag and drop in SwiftUI

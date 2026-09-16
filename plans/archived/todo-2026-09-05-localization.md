# 本地化（国际化）

**状态**：已完成。App UI 与应用显示名均已本地化，随 app-bundle 打包交付，验证通过。本地化是对外发布的**前置项**，英文为主、中文（zh-Hans）为自带第二语言。

## 背景

确定开源发布，GitHub 与官网受众以英文为主；README、官网与 App UI 均需双语，本地化在转 public 前完成。

## 范围

### 1. 物料层（已完成）

- [docs/glossary.md](../docs/glossary.md) 记录产品词汇的中英文名称与含义。
- README 双文件：`README.md`（EN 主文档）+ `README.zh-CN.md`，顶部互链。
- 官网按 EN 主 + zh 切换设计（随 branding 立案产出）。

### 2. App UI 层（已完成）

- 实现与回归检查参考见 [软件本地化与应用内语言切换](archived/todo-2026-09-06-localization.md)。
- UI 文案覆盖设置中心、onboarding、菜单栏菜单、图标右键菜单、工具提示、确认弹窗、状态文案。
- 经典 `.strings` 配合显式语言快照与 SwiftUI 环境依赖；开发语言 en，第二语言 zh-Hans。
- NSLog 运行时日志保持英文，不进字符串表。
- App 显示名本地化（`CFBundleDisplayName`：en "TideBar" / zh-Hans "汐"）已随 app-bundle 打包交付。

### 3. 验证

- 双语言下过一遍设置中心与 onboarding（含权限引导流程），确认无截断、无漏翻。

## 排序

应用显示名与资源包已由 app-bundle 计划交付，验证通过，归档本计划。

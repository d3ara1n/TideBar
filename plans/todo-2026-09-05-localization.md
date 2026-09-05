# 本地化（国际化）

**状态**：已激活（2026-09-06 拍板）——对外发布的**前置项**；英文为主、中文（zh-Hans）为自带第二语言。

## 背景

确定开源发布，GitHub 与官网受众以英文为主；README 与官网均需双语。对外物料层已双语化（见 docs/copy.md），App UI 层的 i18n 是转 public 前必须补齐的最后一块。

## 范围

### 1. 物料层（已完成）

- [docs/copy.md](../docs/copy.md) 改为双语话术源头：EN 主、zh 并排定稿。
- README 双文件：`README.md`（EN 主文档）+ `README.zh-CN.md`，顶部互链。
- 官网按 EN 主 + zh 切换设计（随 branding 立案产出）。

### 2. App UI 层（未开工，转 public 前必须完成）

- UI 文案全面 i18n：设置中心、onboarding、菜单栏菜单、图标右键菜单、工具提示、确认弹窗、通知类状态文案。
- 基建选型开工时定（倾向 String Catalog）；开发语言 en，第二语言 zh-Hans。
- 硬编码文案分布（立案快照）：`SettingsWindowController.swift`（大头）、`OnboardingView.swift`、`AppConfiguration.swift`、`SurgePanel.swift` 等。
- NSLog 运行时日志保持英文，不进字符串表。
- App 显示名本地化（`CFBundleDisplayName`：en "TideBar" / zh-Hans "汐 TideBar"）随 app-bundle 打包一并处理。

### 3. 验证

- 双语言下过一遍设置中心与 onboarding（含权限引导流程），确认无截断、无漏翻。

## 排序

建议窗口：品牌资产交付后、app-bundle 打包开工前——文案从此冻结在字符串表里，打包与官网直接受益。

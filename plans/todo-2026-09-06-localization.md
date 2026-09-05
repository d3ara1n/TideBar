# 软件本地化与应用内语言切换

> 状态：已实现，待 GUI 验收（`swift build` 与 36 项测试已过；`swift run` 后验证语言切换、词条完整性与界面刷新）。

## 背景

- UI 文案现状为硬编码中文（onboarding、设置中心、右键菜单等），与「英文第一语言、中文第二语言」的品牌语言规范不符。
- 语言切换必须内置于 onboarding 向导：非中文用户首次启动时就要能切换，不能要求先懂中文才能改设置。
- `docs/copy.md` 定位澄清：面向开发者的话术参考，非派生源头；本地化资源独立人工维护，与它无派生关系。

## 方案决策

**资源格式用经典 `.strings`（SE-0278），不用 String Catalogs（`.xcstrings`）。**

xcstrings 的核心优势（编译器自动提取、可视化审校、符号生成）全部绑定 Xcode/xcodebuild 构建链，`swift build` 不原生支持，需自维护 build plugin 调 `xcstringstool` 补齐，且有已知边角问题；本项目无 Xcode 工作流，其优势为零、成本为实。`.strings` 是纯文本，`swift build` 原生支持，零新依赖。

**应用内切换用自定义 lproj bundle 查找实现。**

`.strings` 默认按系统 preferred localization 自动命中，应用内切换需绕开该机制：按用户偏好从 `Bundle.module` 手动加载对应 `.lproj` 子 bundle，所有文案查找显式指定该 bundle。

## 技术方案

1. **资源骨架**：`Package.swift` 包级 `defaultLocalization: "en"`，TideBar target 增 `resources: [.process("Resources")]`；新增：
   - `Sources/TideBar/Resources/en.lproj/Localizable.strings`
   - `Sources/TideBar/Resources/zh-Hans.lproj/Localizable.strings`
2. **L10n 基础设施**（TideBar 内新文件）：
   - 语言偏好枚举（跟随系统 / English / 简体中文），持久化 UserDefaults；
   - 解析实际 locale：「跟随系统」按系统语言判 zh 前缀归 zh-Hans，其余归 en；
   - 按解析结果加载对应 lproj 子 bundle，暴露文案查找 API（key 点分层命名，如 `onboarding.intro.title`）；
   - 语言变更经现有主线程桥广播，各 UI 订阅刷新。
3. **SwiftUI 部分**（onboarding）：语言状态入 model，切换即视图刷新。
4. **AppKit 部分**（设置窗口、状态项、右键菜单、汐线/潮涌面板）：切换时重建/刷新文案。
5. **存量文案 key 化**：全局排查硬编码的用户可见字符串（`OnboardingView`、`SettingsWindowController`、菜单与面板），替换为 key + 双语词条。

## 产品方案

- onboarding 首步内置语言切换：三选「跟随系统 / English / 简体中文」，默认跟随系统。
- 设置中心提供同样的语言选项，与 onboarding 共享同一偏好。
- 默认值「跟随系统」；用户显式选择后以显式选择为准。

## 实现约束

- 复数场景暂不引入 `.stringsdict`，出现真实需求再评估。
- 概念词双语对照（汐线 Tide Line · 点点 Dots · 潮涌 Surge · 涟漪 Ripple）在两种语言词条中保持一致，以 `docs/copy.md` 概念词一节为参考。
- 词条 key 与所在功能域对应，避免跨域复用。
- 零新依赖。

## 附带文档修正（copy.md 定位）

- `AGENTS.md` 语言规范：删「话术源头是 `docs/copy.md`（双语并排），各载体从它派生」，改为「`docs/copy.md` 是开发者了解项目话术的参考（定位、命名、概念词对照），非派生源头」；文档地图行同步。
- `docs/copy.md` 头部「唯一源头／各载体从此档派生／禁止另起炉灶」声明同步软化为参考定位。

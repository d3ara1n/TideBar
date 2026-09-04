# 本地化（国际化）

**状态**：延后，未开工。

## 背景

UI 文案硬编码中文，无任何本地化基建（无 String Catalog / `.strings` / `.lproj`）。

硬编码文案分布（立案时快照）：

- `SettingsWindowController.swift`：设置窗口标题、接管流程状态文案（大头）
- `AppConfiguration.swift`：外观选项名（跟随系统/亮色/暗色）
- `SurgePanel.swift`：无标题窗口兜底文案（"窗口"）

## 目标

至少 zh-Hans / en 双语言；基建造型（String Catalog vs 传统 `.strings`）开工时定。

## 延后原因

文案随功能迭代频繁变动，过早抽字符串表会持续付维护成本、收益为零。

## 开工条件

- 设置界面文案趋于稳定，或
- 出现非中文用户需求。

# M1：潮汐交互验证（细线 ↔ 图标栏）

> 立案 2026-09-02。全项目最大的、唯一无法纸面验证的风险的验证尖刀：若「汐线 + 热区展开」的手感在日常使用中不成立，项目到此复盘。前置调研见 [research-dock-alternatives.md](../docs/research-dock-alternatives.md)。

## 目标

汐线在鼠标靠近时展开为图标栏，离开后收起——立住「零存在感」的核心体验，并以数天真实使用验证手感。

## 范围

- [x] 汐线渲染：2~3pt 白色胶囊贴底边（panel 配置见 decisions.md「交互与技术约定」；接近检测按「2026-09 调研修订」条目 3：全局 mouseMoved monitor + local monitor + 低频轮询兜底，汐线保持点击穿透）
- [x] 展开态：~64pt 高图标栏，圆角背景
- [x] 图标：固定 + 运行 app（`NSRunningApplication.icon` 兜底链 + NSWorkspace 启停通知 250ms 去抖）与运行指示点
- [x] 点击启动/激活/重开：NSWorkspace + reopen Apple event（Dock 同款；若被 TCC 拦则静默降级为仅激活）
- [x] 细线 ↔ 图标栏过渡动画（NSAnimationContext / layer 动画），panel frame 随高度调整
- [x] 收起防抖：mouse exited 后 300ms 延迟收起，期间 re-enter 取消
- [x] 全屏 Space 检测：全屏时保持细线态（零权限启发式：普通层窗口铺满整屏）
- [x] 多屏支持：每屏一个 panel + 屏幕参数变更通知

## 权限

零权限，全程不触发辅助功能/录屏授权。

## 验证前提

测试期不隐藏系统 Dock：TideBar 悬浮于屏幕底边上方 `offsetY`（UserDefaults 键 `tidebar.offsetY`，缺省 140pt）避开重叠；固定项可用 `tidebar.pinned`（bundle id 数组）覆盖。手感验证通过后，手动执行 Dock 隐藏命令（见 decisions.md「架构」；向导属 M3）做贴底复验。

## 验收

编译通过后由用户 `swift run` 日常使用数天：

- 误触发率可接受，打字/触控板操作无干扰
- 防抖不闪烁；全屏 Space 只留细线；多屏不串扰
- 点击启动/激活符合直觉
- 手感不成立 → 停止，记录结论并复盘

## 后续阶段（本档不展开）

- M2 潮涌（窗口列表与最小化还原）：[todo-2026-09-window-surge.md](todo-2026-09-window-surge.md)
- M3 系统接管向导：App 内开关 + 快照/恢复/自愈

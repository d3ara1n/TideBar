# M2：潮涌——窗口列表与最小化还原

> 立案 2026-09-02，完成 2026-09-02（用户实测通过；互踩与避让观察项留 known-issues）。交互模型见 [decisions.md](../docs/decisions.md)「潮涌」节。

## 目标

展开态从「app 图标 + activate」升级为完整窗口管理：点点反映窗口状态，潮涌列出窗口，点击直达任意窗口（含最小化还原）。

## 前置探针（已完成，2026-09-02）

- [x] AX 探针工具（`Sources/AXProbe`）：对真实运行 app 集逐项打印 `kAXWindows` / `kAXMinimized` / `kAXTitle` / `kAXDocument` / `kAXPosition` / subrole / id 实测值
- [x] 覆盖表已产出，判定 **GO**（见下）

### 覆盖表（三轮实测，15 个 app）

- axfail 0；真实窗口上 `kAXTitle` / `kAXMinimized` / `kAXPosition` / `AXFullScreen` 全覆盖（含最小化样本：访达、Zen）
- `kAXDocument` 4/9 稀疏，属预期（锦上添花，回退 app 图标）
- 样本：SwiftUI/AppKit 原生（Zed/Ghostty/QQ/钉钉/Canary/CotEditor/系统设置/活动监视器）、JVM（Rider）、Avalonia（Fork）、Gecko（Zen）
- 未验证：微信开窗态、Electron 类（日常无样本）→ known-issues 跟踪，降级路径兑底

### 实测 quirk → 数据层规则

1. **窗口收录 = `subrole == AXStandardWindow` 或 `minimized == true`**：最小化窗口 subrole 不可靠（实测：访达最小化丢 std 标记、Zen 最小化报 `AXDialog`），必须用 min 兑底；对话框永远最小化不了，零误伤
2. **访达桌面元素无需特例**：无标题 + subrole 缺失 + 非最小化，天然不满足收录条件
3. **零收录窗口的 app**（微信关窗、仅桌面的访达等）：不画点点，点击 = activate（M1 行为）；访达因永在运行而常驻图标，与系统 Dock 一致

## 范围

- [x] 窗口数据层：按 app 惰性枚举 `kAXWindows`，AXObserver 订阅窗口创建/销毁/最小化/还原/标题变更；收录规则见前置探针结论（std 或 minimized）
- [x] 点点：实心=活跃窗口数、空心=最小化数、>5 收敛为数字；读不到窗口信息或零收录窗口不画
- [x] 点击升级：raise 最近非最小化窗口（activate 隐含，与 Dock 语义一致）；仅剩最小化则还原最近一个
- [x] 潮涌（SurgePanel）：长按（~0.4s，期间松开视为点击）或 ⌥+点击触发，从图标上方错峰升起，收起反向退落
- [x] 列表项：窗口标题为主 + 文档图标（`kAXDocument` → `NSWorkspace.icon(forFile:)`，失败退回 app 图标），最小化窗口暗显
- [x] 屏幕归属：潮涌列表本屏窗口在前正常显示，他屏窗口靠后暗显（与最小化暗显同语言）；点点保持全局窗口计数（含他屏）
- [x] 右键菜单：窗口列表直达 + 常规项（退出 / 在 Finder 显示）
- [x] 还原/聚焦：`kAXMinimized=false` + `kAXRaiseAction` + `activateIgnoringOtherApps`
- [x] 降级：AX 读不到窗口的 app 保持 M1 行为（纯图标 + activate，不画点点）；未授权时 WindowStore 整体休眠

## 权限

辅助功能（AX）。授权引导用 `AXIsProcessTrustedWithOptions` 系统弹窗，完整向导属 M3。

## 验收

编译通过后用户日常使用验证：

- 点点与实际窗口数一致；潮涌手感（长按阈值、错峰动画）成立
- 最小化窗口点击即还原；探针覆盖表中的降级 app 表现符合预期
- 与 Rectangle / BetterTouchTool 类工具无互踩（known-issues 对应条目观察）

## 后续阶段（本档不展开）

- M3 系统接管向导
- 潮涌缩略图（实时窗口预览）：独立立项，录屏权限 + Tahoe SCK 空白帧验证前置

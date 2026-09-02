# M2：潮涌——窗口列表与最小化还原

> 立案 2026-09-02。交互模型见 [decisions.md](../docs/decisions.md)「潮涌」节；M1 验收通过后启动，前置探针先行。

## 目标

展开态从「app 图标 + activate」升级为完整窗口管理：点点反映窗口状态，潮涌列出窗口，点击直达任意窗口（含最小化还原）。

## 前置探针（半日，先于一切开发）

- [ ] AX 探针工具：对真实 app 集（Finder / Safari / Chrome / Electron 类 / Java 类 / Terminal / 微信等）逐项打印 `kAXWindows` / `kAXMinimized` / `kAXTitle` / `kAXDocument` / `kAXPosition`（屏幕归属）实测值
- [ ] 产出覆盖表；读不到窗口的 app 占比或名单不可接受 → 本档复盘，降级方案再议

## 范围

- [ ] 窗口数据层：按 app 惰性枚举 `kAXWindows`，AXObserver 订阅窗口创建/销毁/最小化/还原/标题变更
- [ ] 点点：实心=活跃窗口数、空心=最小化数、>5 收敛为数字；读不到窗口信息不画；「运行中但零窗口」的表示实现时定
- [ ] 点击升级：raise 最近非最小化窗口；仅剩最小化窗口则还原最近一个
- [ ] 潮涌（SurgePanel）：长按（~0.4s，期间松开视为点击）或 ⌥+点击触发，从图标上方错峰升起，收起反向退落
- [ ] 列表项：窗口标题为主 + 文档图标（`kAXDocument` → `NSWorkspace.icon(forFile:)`，失败退回 app 图标），最小化窗口暗显
- [ ] 屏幕归属：潮涌列表本屏窗口在前正常显示，他屏窗口靠后暗显（与最小化暗显同语言）；点点保持全局窗口计数（含他屏）
- [ ] 右键菜单：窗口列表直达 + 常规项（退出 / 在 Finder 显示）
- [ ] 还原/聚焦：`kAXMinimized=false` + `kAXRaiseAction` + `activateIgnoringOtherApps`
- [ ] 降级：AX 读不到窗口的 app 保持 M1 行为（纯图标 + activate，不画点点）

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

# 已知问题

会随时间消灭的问题：验证完成或修复后删除条目。持久性约定在 [decisions.md](decisions.md)。

## Tahoe：非活跃 Space 的 ScreenCaptureKit 可能返回空白帧

进入悬停窗口预览（ScreenCaptureKit）前需先验证此行为。

来源：https://stackoverflow.com/questions/79949880/

## 与窗口管理工具的 AX 互踩风险

BetterTouchTool/Rectangle 类工具存在 AX 互踩案例（uBar 也有幽灵窗口 bug）。做 AX 枚举窗口（最小化还原）时留意。

## 展开态被最大化窗口压住（窗口避让）

macOS 只为系统 Dock 保留 visibleFrame，自绘任务栏没有空间预留。汐线收起态不受影响；展开态在最大化窗口下会被压住。当前测试期 offsetY=140 悬浮未暴露；M3 隐藏系统 Dock（offsetY 归零）前拍板：接受瞬态 overlay，或做 AX 窗口重排（uBar 路线，有兼容性代价）。背景见 [research-dock-alternatives.md](research-dock-alternatives.md) §三坑 4。

## 微信开窗态与 Electron 类 app 的 AX 表现未实测

探针三轮未捕获样本（微信始终零窗口；日常无 Electron app）。M2 实装后日常使用验证；读不到则按降级路径处理（纯图标 + activate）。

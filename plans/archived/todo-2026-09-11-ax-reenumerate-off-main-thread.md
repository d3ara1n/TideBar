# 窗口 AX 重枚举移出主线程

> 状态：已完成，用户验收通过（高负载场景交互不再冻结，无 data race 告警）。
> 实现：三段拆分——主线程调度（Watch.generation + 纯值请求）→ `dev.dearain.TideBar.ax`
> 串行队列采集（全部 AX IPC，含 observer 创建与通知注册）→ 主线程应用（代数/pid
> 校验丢弃过期结果，degraded/重试梯语义不变，主线程仅挂摘 runloop source）。
> 踩坑记录：DispatchWorkItem 闭包继承上下文 MainActor 隔离，后台执行触发
> Swift 6 运行时隔离检查刷屏；显式 @Sendable 剥离继承后修复。

## 问题

`WindowStore.reenumerate(pid:)` 在主线程同步执行 AX IPC：kAXWindows 列表 + 每窗口 subrole / 最小化 / 位置 / 尺寸 / 标题 / 文档逐属性读取，元素级 0.5s 超时。编译、游戏等场景下目标 app 无暇响应，每次读取烧满超时；全部观测对象串行累计可达数秒，期间主线程冻结，表现为：

- 展开后悬停高亮、名字气泡迟滞（采样器跑在主线程）；
- 离场收起防抖、切换器提交超时等主队列计时整体顺延；
- 潮涌面板呈现（长按 → presentSurge）同样排队。

触发面：展开时的 `refreshAll()` 全量重枚举（deadline = now）、app 启停/AX 通知去抖后的重枚举（0.15s）、重试梯（0.25s…4s）。

## 交付范围

- `reenumerate` 的属性采集段移到后台队列；快照结果与 `Watch` 状态更新回主线程。
- 采集内容、收录规则、degraded 判定、去抖与重试语义保持等价；过期结果丢弃（代数或 pid 存活校验）。
- AXObserver 生命周期相应迁移或在主线程保持（通知安装与 runloop source 挂载线程需一致）。
- BadgeStore 已在后台队列，不动。

## 关键取舍

- AXUIElement API 线程安全；Swift 6 下非 Sendable 类型跨线程需明确隔离边界（如专用 serial queue 采集 + MainActor 回传）。
- 先串行队列（逐 app 一轮），避免并发 AX 风暴进一步压垮忙碌的目标 app；并发化等有实测再议。
- 只改执行线程，不改行为语义——对账以现有测试与 WindowStore 日志为准。

## 验收重点

- 高负载（编译/游戏）下展开后悬停高亮即时、收起防抖不再整体顺延。
- 窗口点、潮涌列表、最小化标签等窗口知识与现状一致（无丢通知、无幽灵窗口、无降级误报）。
- app 启动/退出风暴、AX 授权中途授予、observer 重建等边界不回归。

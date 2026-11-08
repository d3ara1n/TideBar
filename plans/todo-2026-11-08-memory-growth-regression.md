# 常驻内存增长：生命周期修复与验收

## 范围与状态

以当前工作区代码为修复基线，目标是让对象数量和图像资源由当前条目集合、显示尺寸与正在进行的操作决定，不随展开次数或运行时长持续累积。不采用自动重启、定时清缓存或强制内存回收。

实现与回归检查已完成，应用及测试目标编译通过；测试执行、GUI 与长期驻留验收未完成，验收前保持立案。

## 现场证据（2026-11-08）

只读检查用户已运行的程序，未启动、关闭或重启 GUI，未修改系统设置或申请权限。

- PID 807，启动时间 2026-11-02 20:23:39 +0800；采样时约运行 5 天 21 小时。
- 系统：macOS 27.2 (26B123)，Apple Silicon。
- `footprint -p 807`：物理足迹约 2354 MB，峰值约 2553 MB；Malloc Small 约 1144 MB、CG Image 约 1000 MB、Malloc Large 约 122 MB、CoreAnimation 约 63 MB。
- `vmmap -summary 807`：CG Image 13,706 个区域，约 995 MB 已换出。RSS 与物理足迹口径不同，不能以较低 RSS 否定活动监视器的约 2.4 GB。
- `heap -s --noContent 807`：`ItemIconButton`、`IconArtworkView`、`BadgeOverlayView`、`HoverHaloView`、`AppStatusIndicatorView`、`ItemDragIconEffect` 各 22,270 个；`NSImage` 31,009 个、`CGImage` 31,341 个、`CALayer` 164,655 个；`ItemRowView` 只有 1 个。
- 原始 heap、footprint、vmmap-summary 文本在本机 `/tmp/tidebar-memory-2026-11-08/`，不纳入 git；临时目录不保证长期留存。footprint/vmmap 文件为随后复采，与上述首次采样允许小幅差异。

现场已确认展示对象异常累积，未获取完整引用图或分配调用栈，不能把全部 2354 MB 精确归于某一个持有边。

## 生命周期约束与实现

- [x] 按 `ItemID` 对账与复用按钮；展开只重置交互与动画，不创建整批替代视图。当前成员之外只保留尚未完成离场动画的按钮。
- [x] 点击回调显式传 sender，读取其最新 entry/frame，不捕获拥有回调的按钮。菜单选择沿用同一发送入口。
- [x] 离场标记使用 UUID，返回时删除标记；旧完成回调不能误删归来或再次离场的条目，不为已返回条目保留历史 token。
- [x] 收起／离场撤销长按与循环反馈；最终移除撤销观察者、菜单靶对象、widget 展示订阅与按钮回调。任务执行与展示解绑，撤销订阅不取消任务。
- [x] 菜单靶对象跨过当前关闭／动作同步派发后释放，不在 `didCloseMenu` 中提前销毁所选 action target，也不异步清空新一轮菜单的共享数组。
- [x] 图标按显示尺寸与 backing scale 生成受限位图，本体与残影共享；layout 不重复生成，图标、尺寸、外观或 scale 变化才替换。
- [x] 接受／拒绝态才生成显示尺寸的拖拽遮罩；透明态不生成，淡出后释放；代数保护重入效果不被旧清理误清空。不对最终会被纯色填充覆盖的图像做额外 Core Image 去饱和。
- [x] `WindowStore` 工作区通知在外层弱捕获 owner；销毁卸载全部 AX runloop source、撤销通知并取消尚未执行的工作。
- [x] AX refcon 指向由 watch 与在途请求持有、只弱引用 store 的上下文；后台 observer 仅在主线程校验通过后才挂载。结果应用同时校验上下文身份与调度代数，避免移除再添加相同 PID 时接纳旧结果。
- [x] `AppRegistry`／`ItemRegistry` 启动幂等、销毁撤销通知；角标轮询按实例注册和注销，单轮后台 AX 读取有 autoreleasepool。
- [x] 展示缓存按当前完整固定记录修剪，不保留已删除、已更名或配置变化的历史键。
- [x] 最终生命周期约束写入 `docs/decisions.md`。

## 回归检查

`Tests/TideBarTests/ItemLifetimeTests.swift` 覆盖：200 次展开后按钮身份与子视图数量稳定、复用后使用最新模型和 frame、条目／容器移除后弱引用归零、离场归来与过期回调、最终退休撤销回调、菜单关闭后仍能派发动作且随后释放靶对象、WindowStore 启动后可释放、位图像素预算与共享、透明拖拽态零遮罩与淡出释放、淡出重入保护。

WindowStore 启动检查仅使用既有授权，不申请授权；无授权的测试环境不能覆盖真实 AX observer 安装与在途回调。

- [x] `swift build --build-system native` 通过。
- [x] `swift build --build-system native --build-tests` 通过（只编译，不执行测试或启动 GUI）。
- [x] `git diff --check` 通过。
- [ ] CI 执行完整测试通过。
- [ ] 用户运行 `swift run --build-system native`，验收展开／收起、普通点击、小工具点击／长按、右键选择、拖拽收起后再展开、离场归来、跨显示器及亮暗外观。注意图标清晰度、残影和拖拽明暗效果。
- [ ] 用户反复展开／收起、启停应用后，对同一进程复采 heap/footprint；等待短期动画结束后按钮数量应围绕当前条目规模稳定，不按展开次数递增。
- [ ] 用户持续运行至接近原复现时长，按相同物理足迹口径观察曲线；若按钮稳定但其他类别仍持续增长，按新增类型与持有链继续定位，不宣称一次修复已消除所有可能的泄漏。
- [ ] 用户验收通过后归档本计划。

## CI 与测试有效性审查

- 当前合并暂停，长期内存观察由用户安排在下个版本；本次不以版本观察代替自动化测试的实际结果。
- 原 CI 仅执行 `swift build` 与 `swift test`。Sparkle 二进制获取是干净构建的依赖准备，不是下载功能测试；三次 HTTP 504 均发生在构建前置阶段，测试被跳过，应记录为基础设施阻塞，不能报告为代码测试失败或通过。
- 不增加下载验证流程或专用缓存预热脚本，不更改代理。恢复测试执行与合并前，先确认实际测试断言能发现代码回归，而非测量网络、已安装应用或本机授权情况。
- 已扫描 Tests/：未发现 HTTP 请求、下载 API 或外部命令调用。`windowStoreDoesNotKeepItselfAliveAfterStarting` 依赖真实 AX 授权，无授权时 start 提前返回，不能覆盖观察者自持有；`WidgetOrderingTests` 启动真实 Registry、混入本机运行应用与 AX 观测，排序断言有意义但测试隔离不足。这两项需要在测试有效性审查中处理，不能把无授权环境下的通过视为完整覆盖。

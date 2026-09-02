# TideBar 项目规范

macOS Dock 替代品：平时缩成屏幕底部一条细线，鼠标靠近时如潮汐般展开。完整定位见 `docs/product.md`。

## 心智模型

- **产品灵魂 = 零存在感 + 完整 Dock 功能**：空闲时细线若隐若现，展开后功能对标系统 Dock。一切实现取舍服务于此。
- **系统级功能不自绘**：启动、运行列表、右键菜单、废纸篓等用系统能力（NSWorkspace / NSMenu / FSEvents / AX / ScreenCaptureKit），精力只花在差异化交互与窗口体验上。
- **窗口层与事件模型是根基**：NSPanel 的 styleMask / level / collectionBehavior 组合决定一切行为；动交互之前先确认窗口层约束允许（各约束的依据见 `docs/decisions.md`）。

## 环境

- 开发机：macOS 26（Tahoe）、Apple Silicon；Xcode 26 + Swift 6.3.3
- 技术栈：Swift 6 + SPM（swift-tools 6.0，最低 macOS 14），**零第三方依赖**，不用 Xcode 工程
- bundle id 占位 `dev.tidebar.TideBar`，发布前更换

## 构建与验证

- `swift build` 编译；`swift run` 运行（占终端，Ctrl-C 退出）。
- **agent 的验证职责止于 `swift build`**：GUI 的运行验证由用户执行 `swift run` 并操作 UI 确认；不做「启动→等几秒→杀掉」式的自动冒烟。
- 系统级命令（如隐藏系统 Dock 的 defaults 写入）只输出给用户执行，或经确认后执行，不静默改。

## 文档地图

| 文档 | 内容 | 生命周期 |
|---|---|---|
| `docs/product.md` | 产品定位、灵魂交互、命名、对标 | 极稳定 |
| `docs/decisions.md` | 已定架构决策、可行性边界、权限策略 | 只增不改 |
| `docs/known-issues.md` | 会随时间消灭的问题 | 条目解决即删 |
| `plans/` | 立案任务（当前要做什么的唯一真值） | 见下 |

## plans 纪律

- `todo-<日期>-<主题>.md`：立案任务。完成即移入 `plans/archived/`；有留存价值的结论转 docs/。
- `plans/archived/`：已结束的计划，只进不出。
- **延后即立案**：不做的事必须落到 plans/ 或 known-issues.md；聊天即焚，未入档的决策视为未发生。
- 文件名即性质，从名字直接读出生命周期；新类型前缀按需增设（常驻手册用全大写），但必须能一句话说清其生命周期。

## 决策边界

- **agent 自主**：内部类拆分、动画实现方式、命名、代码组织、实现层参数。
- **必须拍板**：交互范式变更、系统级修改、涉及用户授权的能力（屏幕录制/辅助功能）、引入第三方依赖（项目原则是零依赖）。

## 约定

- 文档、注释、提交信息用中文；运行时日志（NSLog）用正式英文，保证可 grep。
- 提交信息用 Conventional Commits 格式（type 英文小写：feat/fix/docs/chore/refactor…，主题中文）。
- AI 辅助的提交加 `Co-Authored-By: <模型名> <邮箱>` trailer；模型身份查 `PI_*` 环境变量，无对应邮箱用 `noreply@pi.dev`，不得伪造 provider 域名。
- 代码与文档不留「原来是 A 改成 B」的历史痕迹，追溯看 git log。

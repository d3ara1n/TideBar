# README 重写（发布前置）

> 状态：已完成并归档（2026-09-16）。README 中英双语与 banner 已提交（0e8bd2c）；仓库转 public 时复核 Releases/官网链接与社交预览可达。

## 背景

现有 README 在功能演进过程中增量修补，与当前交互（通用条目与拖拽、潮涌体、全屏点击展开、窗口循环等）存在口径落差；且未接入任何真实演示素材。用户拍板：发布前重写。

## 结构（已与用户确认）

1. **Hero 首屏**：banner 占满顶部、不设 H1（banner 自带字标，即标题载体）；下接徽章（Release / macOS 14+ / MIT）、快速链接、双语互链。应用截图与演示 GIF 均不使用
2. **Why TideBar**：系统 Dock 三痛点对照（占空间 / 最小化难还原 / 无窗口状态）+ 差异化定位（零存在感 + 窗口管理）
3. **Features**：按旅程分四组——汐线与展开 / 窗口管理 / 条目与固定 / 通知感知
4. **Install**：系统要求、下载解压、未公证 Open Anyway、首次引导
5. **Dock Takeover & Recovery**：独立成节——接管改动、恢复路径；崩溃/强杀后需手动重启 TideBar 并在设置页关闭接管，此步骤显式分步教给用户
6. **Usage**：鼠标操作表、键盘操作表、全屏行为、设置入口速览
7. **Permissions & Privacy**：辅助功能逐条用途与未授权降级；无账号无遥测，唯一联网是 Sparkle 更新检查
8. **Known Limitations**：独立成节——无缩略图、无废纸篓、无应用专属 Dock 菜单、部分应用无窗口信息、展开覆盖不挤占窗口
9. **Build from Source**：工具链、build/run、开发注意事项
10. **Feedback & Contributing**
11. **License**

不设 Acknowledgements：依赖仅 KeyboardShortcuts 与 Sparkle，第三方许可声明由应用包内承接，README 不单列。

## 范围

- `README.md`（EN 为主）与 `README.zh-CN.md` 同步重写，顶部互链保持。
- 内容对齐当前实现：功能清单、安装与权限引导、鼠标／键盘操作表、Dock 接管与恢复、权限与限制、源码构建、反馈与许可。
- Banner 定稿：GPT 生成位图，通用图形条目（无第三方应用图标、无截图、无演示 GIF、无深色版）；压缩后存 `assets/banner.png`——仓库展示资产，不进 `brand/`（产品资产）。
- 词汇与 `docs/glossary.md` 一致；行为与 `docs/decisions.md` 一致（如拖出语义、临时项生命周期）。
- 结构按使用者旅程组织：第一屏讲清产品是什么 + 演示，其次安装，再操作细节。

## 验收

- 中英文表达相同的功能与限制，无一方多出未实现的能力。
- 素材与当前应用行为一致，页面不展示占位。
- 全部链接（Releases / Issues / 官网 / 许可证）在仓库 public 后可用。

完成后归档本计划；branding 计划中 README 相关待完成项由本计划承接。

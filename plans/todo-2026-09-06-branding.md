# 品牌与文档

> 状态：话术源、README、LICENSE 已完成；官网方案已定未开工；剩余品牌资产、演示素材、关于页、命名统一。

## 背景

发布渠道已定（2026-09-06）：开源 GitHub、下载走 GitHub Releases，另建介绍性官网落地页。官网方案已定（同日拍板）：GitHub Pages，站点放仓库 `website/` 目录经 Actions 发布，域名 `tidebar.dearain.dev`（DNS 侧加 CNAME → `d3ara1n.github.io`）；不用 Vercel。发布产物（`.app` 打包）在品牌素材与 README 占位就绪后再开工。

品牌信息目前零散且占位：README 只是开发者骨架（构建命令 + 文档链接）；设置「关于」页仅有版本号与一句话定位；应用图标、菜单栏图标、关于页形象全部使用 SF Symbol `water.waves` 占位；「汐」「TideBar」「汐 TideBar」三种叫法在 UI 与文档中并存，未统一。

对外话术源头已产出：[docs/copy.md](../docs/copy.md)（slogan、pitch、功能四条、权限话术、FAQ、对比表、载体派生规则）。本立项的 README、关于页工作以它为输入。

## 范围

### 0. 对外话术源（已完成）

- [docs/copy.md](../docs/copy.md)：对外文案唯一源头，后续 README、关于页、Releases 说明、官网均从它派生；文案变更先改该档再同步载体。

### 1. 品牌资产

- App 图标（macOS 26 风格，圆角矩形 + 汐主题意象），供 `.app` 与 Dock 接管提示使用。
- 菜单栏图标：替换 `water.waves` 占位，可考虑模板图（template image）适配菜单栏。
- 关于页与 README 共用的品牌形象（图标 + 名称 + 一句话定位）。

### 2. README 重写（已完成）

- 面向使用者的完整介绍：slogan、pitch、核心功能四条、权限与隐私、安装、文档、许可证，全部从 docs/copy.md 派生。
- 演示素材位已留占位（`docs/images/demo.gif`），素材产出后替换（复用 onboarding 演示动画产出，与向导演示同源）。

### 3. 设置「关于」页完善

- 品牌形象（图标）+ 名称 + 定位语。
- 版本与构建号（已有）保留；补充版权信息、反馈渠道（发布渠道定了再填）。

### 4. 命名统一

- 确定对外唯一主名称（建议「汐 TideBar」首次出现，行文用「汐」），梳理 UI 文案、README、docs 中的现有叫法并统一。

### 5. LICENSE（已完成）

- MIT 已拍板（2026-09-06），`LICENSE` 已入库；README 已链接。

## 边界

- 品牌资产（图标等）在本立项产出；打包进 `.app` 的接线由 todo-2026-09-03-app-bundle-and-login-item.md 承接，其开工在本立项素材就绪之后（2026-09-06 拍板）。
- 演示动画的产出依赖 onboarding 已归档立案中的演示位实现（汐线→应用栏→潮涌、接管前后对比）；若 README 先行，先用截图。
- 官网落地页发布前完成，随本立项产出：静态单页放 `website/`，零构建手写 HTML/CSS，经 `.github/workflows/` 的 Pages 工作流发布（Pages 的分支部署模式只认根目录或 `docs/`，子目录必须走 Actions）；仓库侧加 `CNAME` 指向 `tidebar.dearain.dev`。下载与发布动作走 GitHub Releases。

## 开工条件

- 出现对外展示需求（发布、开源、给他人演示），或
- app-bundle 立项开工前（图标资产是其前置之一）。

# 品牌与文档

> 状态：话术源（双语）、README（双语）、LICENSE、命名统一、关于页已完成；本地化升格为发布前置（App UI 层由 todo-2026-09-05-localization.md 承接）；实心品牌标记已定稿，单色／彩色与菜单栏素材已导出、待接入；Dock 图标由用户通过 Icon Composer 制作；演示素材待录屏。

## 背景

发布渠道已定（2026-09-06）：开源 GitHub、下载走 GitHub Releases，另建介绍性官网落地页。仓库已建：github.com/d3ara1n/TideBar（**private**，待品牌资产与演示素材就绪后再转 public）。**本地化为 branding 前置（同日拍板）：对外物料英文为主、中文为第二语言**——话术源已双语化，README 拆为 README.md（EN 主）+ README.zh-CN.md；App UI 的 en/zh-Hans 本地化由 todo-2026-09-05-localization.md 承接，转 public 前完成。官网方案已定（同日拍板）：GitHub Pages，站点放仓库 `website/` 目录经 Actions 发布，域名 `tidebar.dearain.dev`（DNS 侧加 CNAME → `d3ara1n.github.io`），双语 EN 主 + zh 切换；不用 Vercel。发布产物（`.app` 打包）在品牌素材与 README 占位就绪后再开工。

品牌信息目前零散且占位：README 只是开发者骨架（构建命令 + 文档链接）；设置「关于」页仅有版本号与一句话定位；应用图标、菜单栏图标、关于页形象全部使用 SF Symbol `water.waves` 占位；「汐」「TideBar」「汐 TideBar」三种叫法在 UI 与文档中并存，未统一。

对外话术源头已产出：[docs/copy.md](../docs/copy.md)（slogan、pitch、功能四条、权限话术、FAQ、对比表、载体派生规则）。本立项的 README、关于页工作以它为输入。

## 范围

### 0. 对外话术源（已完成）

- [docs/copy.md](../docs/copy.md)：对外文案唯一源头，后续 README、关于页、Releases 说明、官网均从它派生；文案变更先改该档再同步载体。

### 1. 品牌资产（素材已导出，接入待执行）

- 构图：三条独立绘制的波浪配日月圆盘；圆盘位于波浪上方，呈升起意象，外围透明留白截断第一条波浪，下两条波浪完整。实心版为主标记，空心版为正式备选，两版及单色预览均保留。
- 正式素材与使用说明：`brand/ASSETS.md`。唯一设计源为 `brand/sources/` 的实心／空心／菜单栏三份 SVG 与 `palettes.json`。`mono/` 提供单色 SVG / PNG / PDF；`color/` 提供配色表驱动的 Light／Dark 实心版，均为透明纯色，不含光影或背景。
- `menubar/` 提供光学校正后的 18pt 模板 PDF、18/36px PNG 与 SVG；接入时显式设置 `isTemplate = true`，由系统适配颜色。
- `composer/light/`、`composer/dark/` 提供对齐的波浪／圆盘两层 SVG 与透明 PNG；完整 Dock 图标由用户通过 Icon Composer 制作，打包由 app-bundle 任务承接。
- `node tools/export-brand.mjs` 一键生成全部成品及两张预览 SVG／PNG；使用系统 XML 变换与 librsvg，不在脚本中维护图形坐标。`previews/` 保留实心／空心对照布局，并提供彩色与菜单栏对照。
- 验证：一键命令检查 12 份素材 PNG、7 份 PDF、2 张 PNG 预览的尺寸、透明背景、模板纯黑、主题几何及 Composer 分层合成；回归测试覆盖重复导出、配色／几何替换、错误输入保护和旧产物清理。实际菜单栏显示与 Icon Composer 导入待用户确认。
- 待接入：菜单栏（AppDelegate `configureStatusItem`）、关于页与引导页的 `water.waves` 占位，以及 README／网站标记。本轮不改应用代码。

### 2. README 重写（已完成）

- 面向使用者的完整介绍：slogan、pitch、核心功能四条、权限与隐私、安装、文档、许可证，全部从 docs/copy.md 派生。
- 演示素材位已留占位（`docs/images/demo.gif`），素材产出后替换（复用 onboarding 演示动画产出，与向导演示同源）。

### 3. 设置「关于」页（已完成，图标待品牌资产替换）

- slogan（PageHeader 描述）、产品定位副标、版权（© 2026 Chien Zhang）、反馈渠道（GitHub Issues 链接）已补齐。
- 版本与构建号（已有）保留；图标仍为 `water.waves` 占位，品牌资产交付后替换。

### 4. 命名统一（已完成）

- 标准：首次出现「汐 TideBar」，行文「汐」。
- UI 文案已全部梳理（onboarding、设置中心、菜单栏菜单、右键菜单、工具提示）；NSLog 运行时日志按约定保持英文不动。

### 5. LICENSE（已完成）

- MIT 已拍板（2026-09-06），`LICENSE` 已入库；README 已链接。

## 边界

- 品牌资产（图标等）在本立项产出；打包进 `.app` 的接线由 todo-2026-09-03-app-bundle-and-login-item.md 承接，其开工在本立项素材就绪之后（2026-09-06 拍板）。
- 演示动画的产出依赖 onboarding 已归档立案中的演示位实现（汐线→应用栏→潮涌、接管前后对比）；若 README 先行，先用截图。
- 官网落地页发布前完成，随本立项产出：静态单页放 `website/`，零构建手写 HTML/CSS，经 `.github/workflows/` 的 Pages 工作流发布（Pages 的分支部署模式只认根目录或 `docs/`，子目录必须走 Actions）；仓库侧加 `CNAME` 指向 `tidebar.dearain.dev`。下载与发布动作走 GitHub Releases。

## 开工条件

- 出现对外展示需求（发布、开源、给他人演示），或
- app-bundle 立项开工前（图标资产是其前置之一）。

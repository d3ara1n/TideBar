# 品牌与文档

> 状态：双语 README、官网文案、产品词汇表、LICENSE 与应用「关于」页已完成。品牌素材已导出，应用内 PDF 与网站标记已接入，正式 `.app` 图标由打包流程接入。真实演示素材与品牌素材的人工验收待完成。

## 发布载体

- 源码与反馈：GitHub 仓库 `d3ara1n/TideBar`；下载与版本说明：GitHub Releases。
- 官网：`website/` 中的 Astro 静态站点，经 `.github/workflows/website.yml` 发布到 GitHub Pages，域名 `tidebar.dearain.dev`。
- README、官网与软件 UI：英文为主，中文为第二语言，各自按读者需要编写。
- [产品词汇表](../docs/glossary.md) 只记录名称、英文对应词与含义；实现与权限边界以 [decisions.md](../docs/decisions.md) 为准。

## 已完成

### 使用说明

- `README.md` 与 `README.zh-CN.md` 互链，说明功能、安装、Dock 接管与恢复、鼠标和键盘操作、权限与限制、源码构建、反馈与许可证。
- README 面向使用者；产品定位、架构决策和词汇表由开发文档入口维护。
- 官网介绍实际功能，提供下载、使用说明和反馈入口。
- 应用「关于」页包含功能简介、版本、版权信息与反馈入口。

### 品牌资产

- 素材与使用说明见 `brand/ASSETS.md`。设计源为 `brand/sources/` 的实心、空心、菜单栏 SVG 与 `palettes.json`。
- `mono/` 提供单色 SVG / PNG / PDF；`color/` 提供 Light / Dark 实心版。
- `menubar/` 提供光学校正后的 18 pt 模板 PDF、18/36 px PNG 与 SVG；应用使用模板图像，由系统适配颜色。
- `composer/` 提供 Icon Composer 源与应用图标，打包流程见 [应用打包与发布](archived/todo-2026-09-10-app-bundle-release.md)。
- `node tools/export-brand.mjs` 生成素材与预览；回归检查覆盖尺寸、透明背景、模板色、主题几何、分层合成和重复导出。
- 应用菜单栏、关于页与引导页接入资源 bundle 内的 PDF；网站使用浅色与深色标记。
- MIT 许可证已写入 `LICENSE`。

## 待完成

- [ ] 人工确认菜单栏图标的显示效果与 Icon Composer 素材导入。
- [x] 录制真实操作并接入应用与官网：onboarding 第 1 步循环演示视频、网站汐线导航「演示」窗口（随显隐暂停，reduced-motion 不自动播放）。
- [ ] README 重写与演示素材接入：由 `todo-2026-09-16-readme-rewrite.md` 承接（发布前置）。
- [ ] 仓库公开时检查下载、官网与 GitHub 社交预览是否可访问；官网目前使用 GitHub 仓库预览图，可按需要上传专用分享图。

## 验收

- 中英文表达相同的功能与限制，产品词汇含义一致。
- 真实演示与当前应用行为一致。
- 下载、源码、反馈与语言切换链接可用；桌面、窄屏和无 JavaScript 页面可阅读。

完成后归档本计划；素材说明保留在 `brand/ASSETS.md`，产品词汇保留在 `docs/glossary.md`。

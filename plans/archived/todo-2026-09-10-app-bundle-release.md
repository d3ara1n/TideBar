# App Bundle 打包与分发

## 目标

- [x] `swift build` 产出可分发的 `TideBar.app`：bundle id `dev.dearain.TideBar`、版本号、应用图标、en/zh-Hans 显示名
- [x] 构建产物用本地自签证书签名
- [x] Release 产物发布到 GitHub Releases：workflow 与 secrets（`MAC_SIGNING_P12` / `MAC_SIGNING_P12_PASSWORD` / `SPARKLE_EDDSA_KEY`）全部就绪；启用时 `workflow_dispatch` 首跑验证（首版 0.1.0，真发布），之后交周一 cron

## 已定方案

### 打包（`scripts/build-app.sh`）

- `swift build -c release` → 脚本组装 bundle：`MacOS/TideBar` + `Resources/TideBar_TideBar.bundle`（SwiftPM 资源，`Bundle.module` 经 `Bundle.main.resourceURL` 命中）+ `AppIcon.icns` + 双语 `InfoPlist.strings`（en=TideBar，zh-Hans=汐）
- `Info.plist` 脚本生成：`LSUIElement=true`（Dock 替代品自身不进 Dock）、`LSMinimumSystemVersion=14.0`、版本号由参数注入
- 签名身份固定 `TideBar Signing`（自签证书，10 年至 2036，codeSigning EKU；备份与 CI 素材在 `~/.signing/tidebar/`）
- 产物：`dist/TideBar.app` + `ditto --keepParent` 的 `dist/TideBar-<ver>.zip`（保签名）

### 图标（`scripts/make-icon.sh`）

- 源文件 `brand/composer/app.icon`（Icon Composer 格式）；ictool 导出各尺寸 PNG → `iconutil` 转 icns
- `AppIcon.icns` 预生成提交仓库；CI 只消费成品，不依赖 ictool（构建可复现）
- Liquid Glass（Assets.car）不在初版范围，icns 覆盖 macOS 14~26

### 发布流（`.github/workflows/release.yml`）

- 每周一 cron（UTC 02:00）+ `workflow_dispatch` 手动通道；PR 合并与 push 不触发发布
- 单 workflow 全链路（GITHUB_TOKEN 推的 tag 不触发其他 workflow，tag 仅作历史标记）：`compute-version.sh` 相对上个 `v*` tag 按 conventional commits 算版本（breaking→major / feat→minor / fix·perf·refactor→patch，无变更跳过）→ 构建签名 → 官方 --generate-notes 按 PR 生成 release note（.github/release.yml 分组，PR 打 label 进组） → `gh release create --target` 原子建 tag 与 release，zip + appcast.xml 同挂 asset
- 首个版本自 0.0.0 基线起步（首个 feat 即 0.1.0）
- PR 开发流：`.github/workflows/ci.yml` 跑 `swift build` + `swift test`；squash merge 保留 conventional 中文主题，PR label 进 release note 分组
- Release workflow 由用户在 Actions 页面控制禁用/启用；schedule 型 60 天无 push 会被 GitHub 自动禁用，属预期

## 边界

- 不公证，不上架 App Store；用户首开右键→打开，README 说明。
- 打包脚本只产出构建产物，不注册任何系统状态。
- 登录项为应用内功能，由 [todo-2026-09-10-app-side-update-login.md](todo-2026-09-10-app-side-update-login.md) 落地。
- Sparkle 管道与应用侧均已落地，决策真值见 [decisions.md](../../docs/decisions.md)「自更新与发布管道」「开机启动」。

# 应用侧接入：检查更新与开机启动

## 目标

- [x] Sparkle 应用侧落地：SPM 依赖、framework 随包分发、AboutPage 检查更新入口与自动检查开关
- [x] 开机启动管理：SMAppService 注册/注销，OverviewPage 开关，requiresApproval 引导；向导完成页同步提供 opt-out 默认勾选（跳过与完成同效，按终值对称设置），LoginItem 统一入口
- [x] build-app.sh 支持 framework 嵌套签名与自动检查默认键
- [x] swift build + 本地打包验证（含 appcast 对新 zip 的解析）

## 待验收

- [ ] 用户 GUI 验收：open dist/TideBar.app → 关于页「检查更新」（应拉到 feed 并提示已是最新/无可更新）、概览页登录开关注册/注销、系统设置登录项列表同步

## 方案

- **UpdateCoordinator 单例**（照 DockController 模式）包装 SPUStandardUpdaterController；`isAvailable = Bundle.main.bundleURL.pathExtension == "app"`，开发路径（swift run 裸可执行）不启动 updater，UI 禁用并提示开发构建——沿用「开发与发布启动路径分离」。
- **登录项走 SMAppService.mainApp**（macOS 13+ API，基线 14）：register/unregister 直接调用，状态开窗与操作后刷新（无通知渠道，不轮询）；SettingsModel 直连，不建薄 manager。
- **UI 落点**：检查更新 + 自动开关进 AboutPage（版本区语义）；登录启动 toggle 进 OverviewPage 新「通用」区。
- **打包**：Sparkle.framework → `Contents/Frameworks/`，先 framework 后 app 嵌套签名；可执行文件 rpath 处理 `@executable_path/../Frameworks`；Info.plist 增 `SUEnableAutomaticChecks=true`、`SUScheduledCheckInterval=86400`。

## 边界

- 不做更新进度 UI、不自动安装（Sparkle 默认确认弹窗即可）。
- 登录项不含任何后台 helper（app 本体注册，SMAppService 标准路径）。

## 词条（Settings table）

- `about.updateSection` / `about.checkForUpdates` / `about.automaticChecks` / `about.updatesDevHint`
- `general.section` / `general.loginItem` / `general.loginItemFooter` / `general.loginItemRequiresApproval` / `general.loginItemDevHint`

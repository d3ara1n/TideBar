# 应用侧接入：检查更新与开机启动

## 目标

- [x] Sparkle 应用侧落地：SPM 依赖、framework 随包分发、AboutPage 检查更新入口与自动检查开关
- [x] 开机启动管理：SMAppService 注册/注销，OverviewPage 开关，requiresApproval 引导；向导完成页同步提供 opt-out 默认勾选（跳过与完成同效，按终值对称设置），`LoginItem` 统一入口
- [x] build-app.sh 支持 framework 嵌套签名与自动检查默认键
- [x] swift build + 本地打包验证（含 appcast 对新 zip 的解析）
- [x] GUI 验收：检查更新入口、登录开关与向导勾选；开发路径（swift run）下登录自启与检查更新以提示文案替代控件

## 方案

- **UpdateCoordinator 单例**（照 DockController 模式）包装 SPUStandardUpdaterController；`isAvailable = Bundle.main.bundleURL.pathExtension == "app"`，开发路径（swift run 裸可执行）不启动 updater，UI 显示开发构建提示——沿用「开发与发布启动路径分离」。
- **登录项走 SMAppService.mainApp**（macOS 13+ API，基线 14）：`LoginItem.set` 统一 register/unregister；状态开窗与操作后刷新（无通知渠道，不轮询）；`requiresApproval` 提供系统设置引导。
- **UI 落点**：检查更新 + 自动开关进 AboutPage（版本区语义）；登录启动 toggle 进 OverviewPage「通用」区；向导完成页 opt-out 勾选。
- **打包**：Sparkle.framework → `Contents/Frameworks/`（保留官方 Developer ID 签名，外层签名封印嵌套完整性），可执行文件补 rpath `@loader_path/../Frameworks`；Info.plist 增 `SUEnableAutomaticChecks=true`、`SUScheduledCheckInterval=86400`。

## 边界

- 不做更新进度 UI、不自动安装（Sparkle 默认确认弹窗即可）。
- 登录项不含任何后台 helper（app 本体注册，SMAppService 标准路径）。

决策真值见 [decisions.md](../../docs/decisions.md)「自更新与发布管道（Sparkle）」「开机启动」。

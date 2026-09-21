# 计划：swiftbuild 后端 sdk 标记问题观察

立案日期：2026-09-18　状态：观察中（已有规避措施，无需日常动作）

## 事实

- 系统按可执行文件 `LC_BUILD_VERSION.sdk` 做新外观（Liquid Glass）的 linked-on-or-after 判定；sdk < 26 的产物被按旧样式渲染（含标题栏度量错乱）。
- Xcode 27（27A266a）的 SwiftPM 默认构建后端 swiftbuild 会把该字段写成部署目标（14.0）而非真实 SDK 版本；native 后端写入正确值（实测 sdk 27.0，CI Xcode 26 旧后端产物 sdk 26.5）。
- 官方文档无「27 SDK 需 opt-in 新外观」的规则，方向相反（27 SDK 下兼容 key 被忽略）；未检索到官方承认此后端标记 bug。

## 当前规避（全部已落地）

- 日常本地构建、运行与 CI 使用 `--build-system native`，保留正确的 SDK 标记。
- `build-app.sh` 发布打包使用 swiftbuild，并显式传递 `-platform_version macos 14.0 <当前 SDK>`：既采用其适配标准 `.app/Contents/Resources` 的资源 accessor，又覆盖错误的 SDK 标记。
- 发布脚本自动嵌入所有 SwiftPM 资源 bundle 与顶层 framework，并校验 accessor、动态依赖、严格签名以及最终 `minos 14.0 / sdk <当前 SDK>`。
- native 后端已被标记 deprecated，日常构建时有无害警告。

## 重新评估的触发条件

任一满足即重新立案处理：

1. SwiftPM 移除 native 后端（deprecation 落地），影响日常构建、运行与 CI。
2. SwiftPM 修复 swiftbuild 的 sdk 标记；升级工具链后以无链接覆盖的 release 构建配合 `vtool -show-build` 验证。
3. swiftbuild 资源 accessor 不再优先查找 `Bundle.main.resourceURL`，或任一发布门禁报警。

## 届时动作

- SDK 标记修复后：发布脚本保留 swiftbuild 与全部完整性门禁，仅移除链接器 `platform_version` 覆盖。
- native 被移除而 SDK bug 未修：日常构建与 CI 切换 swiftbuild；需要运行 GUI 的开发产物沿用发布脚本已经验证的链接覆盖参数，或在工具链提供等价正式入口后改用正式入口。
- 资源 accessor 行为变化：以标准签名布局 `Contents/Resources` 为约束调整打包方案，不把资源放到 `.app` 根目录，也不放宽 `codesign --deep --strict`。

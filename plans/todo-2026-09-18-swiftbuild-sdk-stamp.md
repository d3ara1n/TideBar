# 计划：swiftbuild 后端 sdk 标记问题观察

立案日期：2026-09-18　状态：观察中（已有规避措施，无需日常动作）

## 事实

- 系统按可执行文件 `LC_BUILD_VERSION.sdk` 做新外观（Liquid Glass）的 linked-on-or-after 判定；sdk < 26 的产物被按旧样式渲染（含标题栏度量错乱）。
- Xcode 27（27A266a）的 SwiftPM 默认构建后端 swiftbuild 会把该字段写成部署目标（14.0）而非真实 SDK 版本；native 后端写入正确值（实测 sdk 27.0，CI Xcode 26 旧后端产物 sdk 26.5）。
- 官方文档无「27 SDK 需 opt-in 新外观」的规则，方向相反（27 SDK 下兼容 key 被忽略）；未检索到官方承认此后端标记 bug。

## 当前规避（全部已落地）

- 本地与 CI 一律 `--build-system native`（AGENTS.md 构建命令、ci.yml、build-app.sh）。
- `build-app.sh` 发布门禁：`vtool` 校验产物 `sdk ≥ 26`，不满足即失败。
- native 后端已被标记 deprecated，构建时有无害警告。

## 重新评估的触发条件

任一满足即重新立案处理：

1. SwiftPM 移除 native 后端（deprecation 落地）。
2. SwiftPM 修复 swiftbuild 的 sdk 标记（升级工具链后验证：`swift build -c release` 默认后端 + `vtool -show-build` 看 sdk 是否为真实 SDK 版本）。
3. 发布门禁报警（sdk < 26 导致 release 失败）。

## 届时动作

- 工具链修复后：移除所有 `--build-system native` 与 AGENTS.md 相应说明；门禁保留（防回归）。
- native 被移除而 bug 未修：切到「swiftbuild + 链接器显式覆盖」，**已验证可行**（2026-09-18，Xcode 27A266a）：
  ```bash
  swift build -c release --build-system swiftbuild \
    -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$(xcrun --show-sdk-version)"
  ```
  产物 minos 14.0 / sdk 27.0；注意 swiftbuild 产物路径变为 `.build/out/Products/<Config>/`，build-app.sh 的拷贝路径需同步。日常 `swift run` 不建议带这串参数（长且易错），仅作为发布/脚本路径的替代。

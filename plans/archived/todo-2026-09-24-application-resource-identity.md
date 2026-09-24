# 应用资源身份重构

> 立案 2026-09-24，完成 2026-09-24。将 bundle-only 应用身份拆分为运行策略身份与栏内资源身份。

## 目标

- 同 bundle identifier 的不同 `.app` 路径在 TideBar 主栏中作为不同 item。
- 同一 `.app` 路径的多个 PID 聚合为一个 item。
- 固定、打开、隐藏、退出、窗口潮涌、键盘选择和内部拖拽都保留实际资源位置。
- 旧 bundle-only 固定记录继续可读，能解析 bookmark 时迁移为路径身份。
- 应用收藏夹按 `.app` 位置去重，不同路径允许并存。

## 完成项

- [x] 新增 `ApplicationItemIdentity`，与 `AppIdentity`（运行策略身份）分离。
- [x] AppListComposer 按应用路径组合运行实例，保留 bundle ID 运行策略。
- [x] AppRegistry、ItemRegistry、拖拽、隐藏状态和键盘导航改用资源身份定位 item。
- [x] 固定记录生成路径身份，旧 bookmark 记录启动时迁移并保留原数据语义。
- [x] 应用收藏夹接收与去重按实际应用位置处理。
- [x] 增加同 bundle 多路径、拖拽接收和路径去重测试。
- [x] `swift build --build-system native` 与 `swift test --build-system native` 通过。

## 稳定结论

- `NSWorkspace.urlForApplication(withBundleIdentifier:)` 只适合作为 bundle-only 旧数据的降级查找，不足以表达用户选择的具体应用副本。
- 运行行为按 `AppIdentity` 校验，资源定位和主栏选择按 `ApplicationItemIdentity` 校验。

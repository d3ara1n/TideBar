# macOS 27 上回归测试 NSGlassEffectView，达标则接入玻璃背景

> 状态：立案待执行。本机已 macOS 27.0 + Xcode 26.6；NSGlassEffectView 属 macOS 26 SDK，即刻可测，无需等 Xcode 27。

## 背景

- M2 期间潮线/潮涌曾用 NSGlassEffectView：材质与窗口 key 状态耦合（非 key 降级采样、发黑），且它没有 `state` 属性无法钉死。潮涌面板点击窗口激活其他 app 即失 key，背景随之变化——对 Dock 替代品不可接受。动画语言定稿时改用 NSVisualEffectView（`.hudWindow` / `.behindWindow` / `.state = .active` 固定 + 深浅色钉死），key 耦合由此消解，即现行 `StableBlurBackgroundView`。
- 材质渲染属系统（WindowServer）管线，与 SDK 版本无关；macOS 27 重做渲染管线（扩散、暗边、高光，新增系统透明度滑块），但无迹象表明 key 耦合被解绑，不预期随系统升级修复。发黑只是当年失 key 退化的极端表现，本质是 key 耦合。
- 第三方在 27 上存在 tint 实色、灰块等回归报告（Pearcleaner #577、cmux #6334）；27 SDK 给 NSGlassEffectView 新增 `effectIsInteractive`，待 Xcode 27 正式版另行评估，不在本计划。

## 行动

- **通过标准（一票否决）**：渲染全程与 key 状态无关。潮涌面板内点击窗口激活其他 app、失 key、回 key，背景不得变化（颜色、采样质量、透明度）；这正是本产品的日常路径，无法绕开。
- 通过后再验观感：胶囊与定圆角卡片两种形态；展开/收起透明度编舞；深浅色外观；系统透明度滑块各档位；常驻窗口空闲时的合成器开销。
- 与现行 `StableBlurBackgroundView` 对照定夺：
  - 达标 → 以 `if #available(macOS 26.0, *)` 门控接入 `BarBackgroundFactory`，NSVisualEffectView 留作 macOS 14–25 fallback（部署基线 14 不变），并修订 decisions「UI 技术栈分工」的材质条目；
  - 不达标 → 结案留档，维持现状。

## 验收

- agent 止于 `swift build`；渲染质量、观感与性能由用户 `swift run` 操作 UI 确认。

## 参考

- key 耦合历史结论：git 4d0e29c「玻璃采样需要 key」（后被 c58a06f 重写为「key 只服务键盘会话」）
- macOS 27 Liquid Glass 变更：MacRumors「All the Liquid Glass Changes in macOS Golden Gate」

# 品牌素材使用说明

TideBar 主标记为实心日月圆盘与三条波浪。圆盘外围的透明留白截断第一条波浪，下两条波浪完整，呈日月升出水面的意象。空心圆盘是正式备选，默认品牌展示使用实心版。

所有标记本体均为纯色、透明背景，无渐变、高光、阴影或圆角底板。预览背景不属于素材。

## 文件选择

| 目录 | 内容 | 用途 |
|---|---|---|
| `mono/` | `solid`、`outline`，各含黑色与 `-white` 白色版本，SVG / PNG / PDF | 原始单色标记；README 与单色应用内展示 |
| `color/` | `light`、`dark`，SVG / PNG / PDF | 彩色主标记；网站、应用内、完整前景图层 |
| `menubar/` | `TideBarTemplate.pdf`、`.svg`、`.png`、`TideBarTemplate@2x.png` | 菜单栏专用纯黑透明模板 |
| `composer/light/`、`composer/dark/` | `waves` 与 `orb`，SVG / PNG | Icon Composer 分层前景 |
| `previews/mono.svg`、`mono.png` | 实心／空心两版、深浅背景及小尺寸对照 | 保留的单色选稿预览，不作应用资源 |
| `previews/color.svg`、`color.png` | 彩色主题及菜单栏光学校正版对照 | 配色与小尺寸参考，不作应用资源 |

### 尺寸与色彩

- 标准 SVG 与 PNG：1024 × 1024，SVG 内部几何坐标为 256 × 256；四周透明留白属于构图，勿逐层自动裁切。
- 标准 PDF：256 × 256pt，保留矢量路径与裁剪，无栅格图片。
- PNG：带透明通道的 sRGB。
- 菜单栏 PDF：18 × 18pt；PNG：18 × 18px（1×）、36 × 36px（2×）。
- 菜单栏使用独立光学校正：紧凑取景、加粗波浪、略增圆盘，保留原构图；并非标准标记直接缩小。

| 主题 | 波浪 | 圆盘 |
|---|---|---|
| Light | 深青蓝 `#167D9A` | 琥珀金 `#F2AE49` |
| Dark | 浅青蓝 `#65CADD` | 柔月金 `#F5D69A` |

Light / Dark 指标记所在界面的背景主题。素材本身不包含背景，也不自行切换主题，由使用方选择相应文件。

## 各载体用法

### macOS 菜单栏

优先加载 `menubar/TideBarTemplate.pdf` 为 `NSImage`，设置 18 × 18pt 显示尺寸，并显式设置 `isTemplate = true`，交由系统控制颜色。PDF 不是模板图的强制格式，黑色透明 PNG 同样可用；选择 PNG 时将 1×／2× 作为同一图片的不同表示或通过资产目录管理，不把 36px 当成 36pt 图标。

### 应用内

SPM 直接打包 PDF 资源，经 `NSImage` / SwiftUI 展示，无需 SVG 解析依赖。SVG 可经 Xcode asset catalog 编译使用，但不能假定将裸 SVG 复制到 bundle 后，普通 `Image` / `NSImage` 加载接口就会解析它。本次未接入应用代码。

### 网站与 README

- 网站：按背景选择 `color/light.svg` 或 `color/dark.svg`，阴影交给页面样式。
- README：使用 `<picture>` 的 `prefers-color-scheme` 为深浅背景选不同文件。
- 黑色 mono SVG 使用 `currentColor`，内联时可继承文字颜色；通过 `<img>` 引用时不会继承宿主页面颜色。
- `-white.svg` 使用显式白色，适合深色背景的外部图片引用。
- 每份 SVG 的裁剪 ID 唯一；同一 SVG 多次内联时，调用方仍需为各实例添加唯一 ID 前缀。通过 `<img>` 引用不需要。

### Icon Composer

同一主题下的 `waves.svg` 与 `orb.svg` 都是 1024 × 1024 透明画布，直接作为对齐图层导入，便于分别设置材质。不要逐层裁切或分别缩放。也可直接导入 `color/light.svg` / `dark.svg` 作为单一前景。

SVG 优先；如果导入环境对波浪裁剪支持不完整，同目录提供几何一致的透明 PNG。背景、材质、高光、阴影及最终 `.icon` 项目由用户在 Icon Composer 制作；本目录不包含成品 Dock 图标。

## 导出与验证

在项目根目录执行，使用系统 Swift、CoreGraphics、Image I/O 和 Node，无第三方依赖：

```sh
mkdir -p .build/brand-module-cache
swift -module-cache-path .build/brand-module-cache tools/export-brand.swift
swift -module-cache-path .build/brand-module-cache tools/verify-brand.swift
node tools/build-brand-preview.mjs
qlmanage -t -s 1200 -o brand/previews brand/previews/color.svg
mv brand/previews/color.svg.png brand/previews/color.png
```

`tools/export-brand.swift` 是标准版、彩色版、分层版及菜单栏版的统一几何源。`previews/mono.*` 是保留的选稿展示，不随导出覆盖，其小尺寸样本为标准版直接缩放；最终菜单栏校正版见 `previews/color.*`。

自动验证覆盖：12 份 PNG、7 份 PDF 的尺寸，PNG 背景与断口透明度、模板纯黑、主题几何一致性，以及 Composer 两层逐像素重建完整图标。已检查 SVG 与 PDF 的静态渲染；实际菜单栏显示与 Icon Composer 导入仍由用户操作确认。预览中的 2× 样本按 18pt 展示，PNG 预览在 1× 屏幕上不能替代真实 Retina 检查。

## 格式依据

- [Apple：NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate)
- [Apple：Icon Composer 导入与分层](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Apple：Xcode 12 SVG 资产支持](https://developer.apple.com/documentation/xcode-release-notes/xcode-12-release-notes)

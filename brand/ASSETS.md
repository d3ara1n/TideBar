# 品牌素材使用说明

TideBar 主标记为实心日月圆盘与三条波浪。圆盘外围的透明留白截断第一条波浪，下两条波浪完整，呈日月升出水面的意象。空心圆盘是正式备选，默认品牌展示使用实心版。

所有标记本体均为纯色、透明背景，无渐变、高光、阴影或圆角底板。预览背景不属于素材。

## 文件选择

| 目录 | 内容 | 用途 |
|---|---|---|
| `sources/` | `solid.svg`、`outline.svg`、`menubar.svg`、`palettes.json` | 唯一设计源，日常只编辑这里 |
| `mono/` | `solid`、`outline`，各含黑色与 `-white` 白色版本，SVG / PNG / PDF | 原始单色标记；README 与单色应用内展示 |
| `color/` | `light`、`dark`，SVG / PNG / PDF | 彩色主标记；网站、应用内、完整前景图层 |
| `menubar/` | `TideBarTemplate.pdf`、`.svg`、`.png`、`TideBarTemplate@2x.png` | 菜单栏专用纯黑透明模板 |
| `composer/light/`、`composer/dark/` | `waves` 与 `orb`，SVG / PNG | Icon Composer 分层前景 |
| `previews/mono.svg`、`mono.png` | 实心／空心两版、深浅背景及小尺寸对照 | 自动生成的单色对照，不作应用资源 |
| `previews/color.svg`、`color.png` | 彩色主题及菜单栏光学校正版对照 | 配色与小尺寸参考，不作应用资源 |

### 尺寸与色彩

- 标准 SVG 与 PNG：1024 × 1024；SVG 沿用母版的 `viewBox` 与宽高比规则。四周透明留白属于构图，勿逐层自动裁切。
- 标准 PDF：256 × 256pt，保留矢量路径与裁剪，无栅格图片。
- PNG：带透明通道的 sRGB。
- 菜单栏 PDF：18 × 18pt；PNG：18 × 18px（1×）、36 × 36px（2×）。
- 菜单栏使用独立光学校正：紧凑取景、加粗波浪、略增圆盘，保留原构图；并非标准标记直接缩小。

配色唯一真值为 `sources/palettes.json`：`mono` 管理单色主色／反色，`themes.light` 和 `themes.dark` 分别管理 `waves` 与 `orb`。预览中的色号标签也从配置生成，不另外维护。

Light / Dark 指标记所在界面的背景主题。素材本身不包含背景，也不自行切换主题，由使用方选择相应文件。菜单栏纯黑是系统模板约束，不参与品牌配色。

## 各载体用法

### macOS 菜单栏

优先加载 `menubar/TideBarTemplate.pdf` 为 `NSImage`，设置 18 × 18pt 显示尺寸，并显式设置 `isTemplate = true`，交由系统控制颜色。PDF 不是模板图的强制格式，黑色透明 PNG 同样可用；选择 PNG 时将 1×／2× 作为同一图片的不同表示或通过资产目录管理，不把 36px 当成 36pt 图标。

### 应用内

SPM 直接打包 PDF 资源，经 `NSImage` / SwiftUI 展示，无需 SVG 解析依赖。SVG 可经 Xcode asset catalog 编译使用，但不能假定将裸 SVG 复制到 bundle 后，普通 `Image` / `NSImage` 加载接口就会解析它。本次未接入应用代码。

### 网站与 README

- 网站：按背景选择 `color/light.svg` 或 `color/dark.svg`，阴影交给页面样式。
- README：使用 `<picture>` 的 `prefers-color-scheme` 为深浅背景选不同文件。
- 黑色 mono SVG 使用 `currentColor`，内联时可继承文字颜色；通过 `<img>` 引用时不会继承宿主页面颜色。
- `-white.svg` 使用配置中的反色（默认为白色），适合深色背景的外部图片引用。
- SVG 内部 ID 保持母版语义；多份 SVG 内联到同一页面时，调用方需为各实例添加唯一 ID 前缀。通过 `<img>` 引用不需要，预览同样使用独立 SVG 图片文档隔离 ID。

### Icon Composer

同一主题下的 `waves.svg` 与 `orb.svg` 都是 1024 × 1024 透明画布，直接作为对齐图层导入，便于分别设置材质。不要逐层裁切或分别缩放。也可直接导入 `color/light.svg` / `dark.svg` 作为单一前景。

SVG 优先；如果导入环境对波浪裁剪支持不完整，同目录提供几何一致的透明 PNG。背景、材质、高光、阴影及最终 `.icon` 项目由用户在 Icon Composer 制作；本目录不包含成品 Dock 图标。

## 修改母版

- 改造型：编辑对应的 `sources/*.svg`。`solid.svg` 驱动主标记、两套彩色版与 Composer 分层；`outline.svg` 驱动备选；`menubar.svg` 独立承载小尺寸设计。三者不是彼此自动推导。
- 改配色：只编辑 `sources/palettes.json`。主题颜色使用 `#RRGGBB`；mono 可使用 `currentColor` 继承调用方颜色。
- 所有 `mono/`、`color/`、`menubar/`、`composer/`、`previews/` 文件都是生成产物，不能手改；生成时整目录替换，废弃的旧产物也会清理。

### SVG 母版契约

任意路径、基本形状、变换和裁剪都由 librsvg 处理，脚本不识别圆盘半径或波浪坐标。替换母版时保留以下结构：

1. 使用 SVG 命名空间与有效 `viewBox`，所有可见内容放在根下两个直接子组 `id="waves"` 与 `id="orb"`。图层绘制顺序沿用母版；共享引用放在 `defs`，图层不要互相引用。
2. 根必须显式设置 `fill="none"` 或 `fill="currentColor"`；其他 `fill` / `stroke` 也使用 `currentColor` 或 `none` 的表现属性，颜色由图层继承。不写 `color`、CSS 或字面颜色，以确保所有主题真正来自配色表。
3. 保持自包含、透明留边的纯矢量素材。文字转路径；不包含字体、位图、滤镜、脚本、外部资源或 DTD，不在根设置整体透明度；图层内部可设置透明度。

例如只更换 `orb` 组里的圆形为其他路径，无需调整导出代码。独立画布、裁剪定义与变换会原样保留到衍生 SVG，Composer 两层不会裁切到各自包围盒。

## 一键导出与验证

开发工具依赖：Node、系统 Swift、macOS 自带 `xsltproc` / `xmllint`，以及通过 `brew install librsvg` 安装的 `rsvg-convert`。已验证 librsvg 2.62.3；不增加应用运行时依赖或 npm 包。

在项目根目录执行：

```sh
node tools/export-brand.mjs
```

同一次执行生成全部 SVG、12 份素材 PNG、7 份矢量 PDF，以及两张预览的 SVG／PNG，并自动验证后替换成品。临时文件和 Swift 模块缓存位于项目 `.build/`；生成或验证失败不覆盖已有成品，普通发布错误会恢复已有目录。它不是进程中断／断电下的整树原子事务，勿并发导出。

应用内资源同步单独执行，不由品牌生成脚本隐式触发：

```sh
node tools/sync-brand-resources.mjs
```

该命令只将已生成的菜单栏、浅色和深色 PDF 同步到 `Sources/TideBar/Resources/Brand/`，不修改其他品牌成品或预览。

工具分工：

- `export-brand.mjs`：读取母版和配色，编排 XSLT、librsvg、预览与验证。
- `brand-transform.xsl`：使用标准 XML 变换校验母版、设置图层颜色、提取图层；检查本地引用目标存在且分层后仍保留，不维护几何。
- `build-brand-preview.mjs`：只维护预览排版，以自包含 SVG 图片引用成品，不维护图形副本。
- `verify-brand.swift`：读取实际 PNG / PDF 验证尺寸、透明背景、模板纯黑、主题几何和 Composer 按母版顺序合成；不含品牌几何坐标或绘图代码。

PDF 的 `SOURCE_DATE_EPOCH` 固定为 0，避免重复导出只改变时间戳。同一工具链与字体环境下，相同输入产生相同文件；预览文字使用本机字体，跨机器／渲染器版本不保证字节一致。标记本体不依赖字体。

回归测试：

```sh
node --test tools/export-brand.test.mjs
```

覆盖重复导出的字节一致性、配色传播、替换几何与非方形视口、命名空间、相交图层的顺序合成、独立母版更新、无效输入保留成品与旧产物清理。测试在项目 `.build/` 内使用隔离副本，不修改正式母版或成品。

`previews/mono.*` 保留实心／空心的对照布局，其小尺寸样本为标准版直接缩放；菜单栏校正版见 `previews/color.*`。实际菜单栏显示与 Icon Composer 导入由用户操作确认；预览中的 2× 样本按 18pt 展示，1× PNG 预览不能替代真实 Retina 检查。

## 格式依据

- [librsvg：rsvg-convert 尺寸、透明背景、PDF 与可复现导出](https://github.com/GNOME/librsvg/blob/main/rsvg-convert.rst)
- [W3C：XSLT 1.0](https://www.w3.org/TR/xslt-10/)
- [Apple：NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate)
- [Apple：Icon Composer 导入与分层](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Apple：Xcode 12 SVG 资产支持](https://developer.apple.com/documentation/xcode-release-notes/xcode-12-release-notes)

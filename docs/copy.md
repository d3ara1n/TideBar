# 对外话术（参考）

面向开发者的对外话术参考：沉淀产品定位、slogan、功能命名与双语行文口径，供 README、官网、Releases 说明、软件 UI 等载体保持话术一致。**英文（EN）为第一语言，中文（zh-Hans）为自带第二语言**；两个语言版本在此并排沉淀，话术演进时同步更新。

命名：英文行文用 TideBar（首次可作 TideBar 汐）；中文行文首次出现「汐 TideBar」，其后用「汐」。概念词对照：汐线 Tide Line · 点点 Dots · 潮涌 Surge · 涟漪 Ripple。

## 一、定位与受众

- **EN**：A zero-footprint window taskbar for macOS — give the screen its bottom edge back, and manage windows better than the Dock ever did. Audience: small-screen MacBook users; heavy multi-window workers who resent permanent UI.
- **zh**：macOS 零占用窗口任务栏——把 Dock 占的空间还给屏幕，把窗口管理做得比 Dock 更好。受众：屏幕空间紧张的小屏 MacBook 用户；多窗口多任务、讨厌常驻界面噪音的人。
- 差异一句话：市面 Dock 类产品都在做「更好的 Dock」，汐做「消失的 Dock」——细线收起态没有先例。／ Every Dock alternative builds a better Dock; TideBar builds a Dock that disappears — the hairline rest state has no precedent.

## 二、Slogan

- **EN 主推**：A hairline at rest, a sea of windows at hand.
- EN 备选：The dock that fades into a line. ／ Tide up your windows.
- **zh 主推**：平时是一条线，需要时是一片海。
- zh 备选：把 Dock 收成一条线。／ Dock 退成一条线，窗口如潮可达。

## 三、一段话 pitch

- **EN**：TideBar (汐) is a zero-footprint window taskbar for macOS. At rest, it is a hairline tucked against the bottom edge of the screen; move the cursor close and it tides up into an app bar — every window's state visible as a dot, one click away. Press and hold any icon and the Surge list lays out all of that app's windows, minimized ones included, each a click from restoration. Turn on takeover and the system Dock steps aside, leaving nothing on screen but the line — a whole row back on small MacBook displays. One permission (Accessibility), no screen recording, no network.
- **zh**：汐 TideBar 是一款 macOS 窗口任务栏。平时，它只是屏幕底部一条若隐若现的细线；鼠标靠近，便如潮汐般展开为应用栏——每个窗口的状态点点可见，点击即达。长按任意图标，「潮涌」展开该应用的全部窗口，连最小化的也能一键还原。开启接管，系统 Dock 隐去，屏幕底部只剩这条线，小屏 MacBook 也能多出一整行空间。只需辅助功能一项权限，不读屏幕内容，不联网。

## 四、核心功能

### 汐线 · Tide Line — Zero footprint

- **EN**：At rest, a 2–3 pt hairline hugs the bottom edge, adapting to light and dark mode — nearly invisible. Approach and it rises like a tide; move away and it settles.
- **zh**：空闲时是贴着屏幕底边的一条 2~3pt 细线，随亮暗模式自适应，几乎不可见；鼠标靠近即潮汐般展开，离开即收。

### 点点 · Dots — Window state, visible

- **EN**：Small dots under each icon mirror your windows: filled for the active window, hollow for minimized. They answer not "which apps are running" but "where every window is".
- **zh**：图标下的小点如实反映窗口：实心是活跃窗口，空心是最小化。回答的不是「哪些 app 在运行」，而是「每个窗口都在哪」。

### 潮涌 · Surge — Reach any window

- **EN**：Press and hold (or ⌥-click) an icon to fan out its window list; jump straight to any window by title, minimized ones restore on a click. When the Dock hides, minimized windows finally have a home.
- **zh**：长按（或 ⌥+点击）图标展开窗口列表，按窗口标题直达，最小化的点击即还原。隐藏 Dock 后无处安放的最小化窗口，在这里有了落点。

### 涟漪 · Ripple — Considerate notifications

- **EN**：A new badge nudges the line once; unread, it keeps gently rippling; opening the bar settles it. It doesn't shout "you have unread things" — it quietly says "not yet seen".
- **zh**：新角标到达时细线轻涌一次；未被查看就持续微微荡漾，展开即确认。不靠抢占注意力说「有事」，靠持续在场说「还没被知道」。

## 五、权限与隐私（标准话术）

- **EN**：One permission only: Accessibility — used to list and restore windows and detect fullscreen state. ／ No screen recording: TideBar shows no window thumbnails and never reads your screen. ／ No network: no tracking, no telemetry, no account.
- **zh**：只要一项权限：辅助功能——用于列出与还原窗口，以及识别全屏状态。／ 不请求屏幕录制：汐不显示窗口缩略图，不读屏幕内容。／ 零网络：不联网、无遥测、无账号。

> 发布前整体复核一次：新增功能若改变上述承诺，先改这里再对外。

## 六、命名故事

- **EN**：Xī (汐) is the evening tide. At rest the app contracts to a line — the ebb; summoned, windows surge forward — the tidal bore. Ebb and surge: two states of the tide, and of this app.
- **zh**：汐，傍晚的潮。安静时收敛成一条线，是汐；需要时窗口铺开而来，是潮涌。收与放，是潮汐的两种形态，也是这款软件的两种状态。

概念词与代码标识见 [product.md](product.md)（汐线 / 潮涌 Surge）。

## 七、FAQ

**EN**
- *How does TideBar relate to the macOS Dock?* A replacement, not an add-on. With takeover on, TideBar hides the Dock's visible entry and takes its place; without it, the two coexist.
- *Where did my minimized windows go?* In the hollow dot under the app icon. Press and hold (or ⌥-click) the icon for the Surge list; click to restore.
- *Why the Accessibility permission?* Listing and restoring windows and detecting fullscreen state rely on the macOS Accessibility API — the only permission TideBar asks for.
- *Does it show window thumbnails?* No. TideBar never reads your screen, so it never needs Screen Recording.
- *Does it get in the way in fullscreen?* By default, click the tide line to expand; moving nearby does not open it. Settings also lets you keep normal hover behavior or hide it completely.
- *Is TideBar free?* Yes — open source under the MIT License (see LICENSE).

**zh**
- **汐和系统 Dock 什么关系？** 替代而非增强。开启「接管」后，汐隐藏系统 Dock 的可见入口并接替它；不开启也可以共存使用。
- **最小化的窗口去哪了？** 图标下的空心点就是。长按或 ⌥+点击图标展开潮涌列表，点击即还原。
- **为什么要辅助功能权限？** 列出与还原窗口、识别全屏状态依赖 macOS 辅助功能 API。这是汐请求的唯一权限。
- **会显示窗口缩略图吗？** 不会。汐不读屏幕内容，因此永远不需要屏幕录制权限。
- **全屏应用下会打扰吗？** 默认需点击汐线才展开，鼠标靠近不会打开。也可在设置中选择正常悬停展开或完全隐藏。
- **汐收费吗？** 开源软件，MIT 许可证，免费使用；见仓库 LICENSE。

## 八、对比（官网/README 备用）

| | macOS Dock | uBar | DockDoor | TideBar 汐 |
|---|---|---|---|---|
| Idle footprint 空闲占用 | Permanent bar 常驻一整条 | Permanent bar 常驻一整条 | None (on demand) 按需悬浮 | A hairline 一条细线 |
| Window granularity 窗口粒度 | Apps + running dots 运行点 | One cell per window 每窗口一格 | Hover thumbnails 悬停预览 | Dots + Surge 点点/潮涌 |
| Minimized windows 最小化窗口 | Piled right, hard to tell 堆右侧难辨认 | Shown 有显示 | Visible & clickable 可见可点 | Hollow dot + Surge 空心点+潮涌直达 |
| Permissions 权限 | — | — | Screen Recording 屏幕录制 | Accessibility only 仅辅助功能 |

> 对外发布前复核竞品行描述与当期版本行为，避免失实。

## 九、载体派生规则

| 载体 | 语言 | 取材 |
|---|---|---|
| README.md | EN（主） | EN slogan + pitch + 功能四条 + 权限话术 + 下载 + 文档 + LICENSE |
| README.zh-CN.md | zh | zh 列同上 |
| 官网 tidebar.dearain.dev | EN 主 + zh 切换 | 同 README，另加对比表与 FAQ |
| Releases 说明 | EN 主 + zh 附 | 按版本列变化，沿用功能名（Tide Line/潮涌 等） |
| 设置「关于」页 | 跟随系统语言 | 图标 + 名称 + slogan + 版本 + 版权 + 反馈渠道（UI 本地化由 localization 立案承接） |

## 十、待定项

- 演示素材：GIF/截图待录屏；如需文字标注，EN 为主、另出 zh 版。
- App UI 本地化：en + zh-Hans 已完成；应用显示名（`CFBundleDisplayName`）随 app-bundle 打包收尾，由 [todo-2026-09-05-localization.md](../plans/todo-2026-09-05-localization.md) 承接——**转 public 前必须完成**。
- 官网落地页：双语（EN 主 + zh 切换），随 branding 立案产出。

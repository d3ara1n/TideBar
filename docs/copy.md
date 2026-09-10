# 对外话术（参考）

> 状态：**占位初稿，未经审核**。现有内容由 AI 补品牌材料时一次性生成，不作为话术真值；结构与口径仅作参考，人工审核定稿后本档才成为对外话术源头。与 decisions.md 冲突时以后者为准。

定位是对外话术的源头：沉淀产品定位、slogan、功能命名与双语行文口径，供 README、官网、Releases 说明、软件 UI 等载体保持话术一致。**英文（EN）为第一语言，中文（zh-Hans）为自带第二语言**；两个语言版本在此并排沉淀，审核定稿后随话术演进同步更新。

命名：英文行文用 TideBar（首次可作 TideBar 汐）；中文行文首次出现「汐 TideBar」，其后用「汐」。概念词对照：汐线 Tide Line · 图标栏 Icon Bar · 点点 Dots · 潮涌 Surge · 涟漪 Ripple。展开态一律写「图标栏 / icon bar」，不用「应用栏 / app bar」。定位短语对照：A zero-footprint window taskbar ↔「不占屏幕的窗口任务栏」。

## 一、定位与受众

- **EN**：A zero-footprint window taskbar for macOS — give the screen its bottom edge back, and put every window one move away. Audience: small-screen MacBook users; anyone who resents permanent UI.
- **zh**：macOS 不占屏幕的窗口任务栏——把屏幕底边还给桌面，让每个窗口一触即达。受众：屏幕空间紧张的小屏 MacBook 用户；讨厌常驻界面噪音的人。
- 自身特点一句话：收起态是一条细线，不是缩小版的 Dock；唤起后是完整的图标栏，应用与窗口都从这条线抵达。／ The rest state is a hairline, not a shrunken Dock; called up, it is a complete icon bar — apps and windows, all reached from that line.

## 二、Slogan

- **EN 主推**：A hairline at rest, every window at hand.
- EN 备选：The Dock that fades into a line. ／ The Dock you only see when you need it.
- **zh 主推**：平时是一条线，需要时每个窗口触手可及。
- zh 备选：把 Dock 收成一条线。／ Dock 退成一线，需要时再展开。

## 三、一段话 pitch

- **EN**：TideBar (汐) is a zero-footprint window taskbar for macOS. At rest, it is a hairline tucked against the bottom edge of the screen; move the cursor close and it tides up into an icon bar — every window's state visible as a dot, one click away. Click and hold (or ⌥-click) any icon and the Surge list lays out all of that app's windows, minimized ones included — one click brings any of them back. Turn on takeover and the system Dock steps aside, leaving nothing on screen but the line — a whole row of screen back on small MacBook displays. One permission (Accessibility), no screen recording, no tracking or account.
- **zh**：汐 TideBar 是一款 macOS 不占屏幕的窗口任务栏。平时，它只是屏幕底部一条若隐若现的细线；光标靠近，便如潮汐般展开为图标栏——每个窗口的状态点点可见，点击即达。按住任意图标（或 ⌥+点击），「潮涌」展开该应用的全部窗口，连最小化的也能一键还原。开启接管，系统 Dock 隐去，屏幕底部只剩这条线，小屏 MacBook 也能多出一整行空间。只需辅助功能一项权限，不申请屏幕录制，无追踪、无账号。

## 四、核心功能

### 汐线 · Tide Line — Zero footprint

- **EN**：At rest, a 2–3 pt hairline hugs the bottom edge, adapting to light and dark mode — nearly invisible. Approach and it rises like a tide; move away and it settles.
- **zh**：空闲时是贴着屏幕底边的一条 2–3pt 细线，随浅色／深色模式自适应，几乎不可见；光标靠近即潮汐般展开为图标栏，离开即收。

### 点点 · Dots — Window state, visible

- **EN**：Small dots under each icon mirror your windows: filled for the active window, hollow for minimized. They answer not "which apps are running" but "where every window is".
- **zh**：图标下的小点如实反映窗口：实心是活跃窗口，空心是最小化。回答的不是「哪些 app 在运行」，而是「每个窗口在哪」。

### 潮涌 · Surge — Reach any window

- **EN**：Click and hold (or ⌥-click) an icon to fan out its window list; jump straight to any window by title, minimized ones restore on a click. When the Dock hides, minimized windows finally have a home.
- **zh**：按住（或 ⌥+点击）图标展开窗口列表，按窗口标题直达，最小化的点击即还原。隐藏 Dock 后无处安放的最小化窗口，在这里有了落点。

### 涟漪 · Ripple — Considerate notifications

- **EN**：A new badge nudges the line once; unread, it keeps gently rippling; opening the bar settles it. It doesn't shout "you have unread things" — it quietly says "not yet seen".
- **zh**：新角标到达时细线轻涌一次；未被查看就持续微微荡漾，展开即确认。不靠抢占注意力说「有事」，靠持续在场说「还没看」。

## 五、权限与隐私（标准话术）

- **EN**：One permission only: Accessibility — used to list and restore windows and detect fullscreen state, so TideBar can step back in fullscreen apps. ／ No screen recording: TideBar shows no window thumbnails and asks for no Screen Recording permission. ／ No telemetry: no tracking, no account, no analytics.
- **zh**：只要一项权限：辅助功能——用于列出与还原窗口、识别全屏状态，让汐在全屏应用下自动退让。／ 不申请屏幕录制：汐不显示窗口缩略图，也不申请屏幕录制权限。／ 无遥测：无追踪、无账号、无行为分析。

> 发布前整体复核一次：新增功能若改变上述承诺，先改这里再对外。

## 六、命名故事

- **EN**：Xī (汐) is the evening tide. Quiet, the app ebbs to a single line; called up, apps and windows surge back onto the screen. Ebb and surge: two states of the tide, and of this app.
- **zh**：汐，傍晚的潮。安静时收成一条线，是退潮；需要时图标与窗口涌上屏幕，是涨潮。收与放，是潮汐的两种形态，也是这款软件的两种状态。

概念词与代码标识见 [product.md](product.md)（汐线 Tide Line / 图标栏 icon bar / 潮涌 Surge）。

## 七、FAQ

**EN**
- *How does TideBar relate to the macOS Dock?* A replacement, not an add-on. With takeover on, TideBar hides the Dock's visible entry and takes its place; without it, the two coexist.
- *Where did my minimized windows go?* In the hollow dot under the app icon. Click and hold (or ⌥-click) the icon for the Surge list; click to restore.
- *Why the Accessibility permission?* Listing and restoring windows and detecting fullscreen state rely on the macOS Accessibility API — the only permission TideBar asks for.
- *Does it show window thumbnails?* No. TideBar shows no window thumbnails and asks for no Screen Recording permission.
- *Does it get in the way in fullscreen?* By default, click the tide line to expand; moving nearby does not open it. Settings also lets you keep normal hover behavior or hide it completely.
- *Is TideBar free?* Yes — open source under the MIT License (see LICENSE).

**zh**
- **汐和系统 Dock 什么关系？** 替代而非增强。开启「接管」后，汐隐藏系统 Dock 的可见入口并接替它；不开启也可以共存使用。
- **最小化的窗口去哪了？** 图标下的空心点就是。按住或 ⌥+点击图标展开潮涌列表，点击即还原。
- **为什么要辅助功能权限？** 列出与还原窗口、识别全屏状态依赖 macOS 辅助功能 API。这是汐请求的唯一权限。
- **会显示窗口缩略图吗？** 不会。汐不显示窗口缩略图，也不申请屏幕录制权限。
- **全屏应用下会打扰吗？** 默认需点击汐线才展开，光标靠近不会打开。也可在设置中选择正常悬停展开或完全隐藏。
- **汐收费吗？** 开源软件，MIT 许可证，免费使用；见仓库 LICENSE。

## 八、自身优势要点（对外自述）

只讲自身行为，不横向对比，不出现竞品名。

- **收起态是一条细线**：2–3pt 贴屏幕底边，随浅色／深色模式自适应，几乎不可见。／ A rest state that is a hairline — 2–3 pt at the bottom edge, nearly invisible, adapting to light and dark mode.
- **每个窗口都有交代**：实心点是活跃窗口，空心点是最小化；回答「每个窗口在哪」，不只是「哪些 app 开着」。／ Every window accounted for — filled dots for active windows, hollow for minimized.
- **任意窗口一触即达**：潮涌按标题列出该应用全部窗口，含最小化，点击即还原。／ Any window one click away — Surge lists an app's windows by title, minimized ones restored in a click.
- **把屏幕底边还给你**：开启接管，系统 Dock 隐去，底部只剩这条线，小屏 MacBook 多出一整行。／ Your bottom edge back — with takeover on, the system Dock hides and only the line remains.
- **只要一项权限**：仅辅助功能，不申请屏幕录制；无追踪、无账号。／ One permission only — Accessibility; no Screen Recording, no tracking, no account.
- **免费开源**：MIT 许可证。／ Free and open source under the MIT License.

> 不要写成横向对比或「别人都在做 X，我们在做 Y」；只陈述汐自身的行为与收益。

## 九、载体派生规则

| 载体 | 语言 | 取材 |
|---|---|---|
| README.md | EN（主） | EN slogan + pitch + 功能四条 + 权限话术 + 下载 + 文档 + LICENSE |
| README.zh-CN.md | zh | zh 列同上 |
| 官网 tidebar.dearain.dev | EN 主 + zh 切换 | hero 用 slogan + 定位与接管收益；features 四条即功能话术；privacy 用权限话术；下载段用安装 + 开源；注意事项（全屏默认点击展开）作 features 脚注——不设独立 FAQ 或对比页 |
| Releases 说明 | EN 主 + zh 附 | 按版本列变化，沿用功能名（Tide Line/潮涌 等） |
| App UI（引导 / 设置 / 菜单 / 关于） | 跟随系统语言 | 功能名与权限话术取自本档；关于页用 slogan + 定位一句 + 版本 + 版权 + 反馈渠道（本地化由 localization 立案承接） |

## 十、待定项

- **全文人工审核定稿**：定稿前本档仅为占位初稿，不作为话术真值。
- 演示素材：README 为占位行，官网 `demo.webp` 仍是占位图（图上写着 placeholder）；真实录屏产出后替换，并同步图注与 alt。
- 社交分享预览：`og:image` 指向 GitHub 仓库卡 `https://opengraph.githubassets.com/1/d3ara1n/TideBar`（1200×630），仓库转 public 后自动生效；想换更好的图，在仓库 Settings → General → Social preview 上传即可，地址不变、不用改代码。注意两点：它是 GitHub 无文档承诺的内部端点；仓库 private 期间只回通用占位卡。`og:title` / `og:description` 已就位。
- App UI 本地化：en + zh-Hans 已完成；应用显示名（`CFBundleDisplayName`）随 app-bundle 打包收尾，由 [todo-2026-09-05-localization.md](../plans/todo-2026-09-05-localization.md) 承接——**转 public 前必须完成**。
- 官网落地页：双语（EN 主 + zh 切换）已产出，后续随本档演进同步。

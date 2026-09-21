# 涟漪跟随触发者（todo-2026-09-21）

## 背景

QQ 来消息 → 涟漪启动；用户从横幅/其他入口打开 QQ，通知消除、QQ 角标清掉，但涟漪不停。

根因：`TideBarController.appsDidChange` 的停住条件是全局的——`!registry.entries.contains(where: { $0.badge != nil })`（所有 app 的角标都消失）。机器上任何一个其他 app 挂着常驻角标（未读计数类），涟漪就永远等不到停。

调研结论（已否决的路）：读系统通知库 `~/Library/Group Containers/group.com.apple.usernoted/db2/db` 可得通知中心真值，但 macOS 27 实测无完全磁盘访问（FDA）时静默 `authorization denied`；FDA 违反「主动申请的权限仅辅助功能」的既有决策。角标即真值，无需另取数据源。

## 改动

1. **TideBarController**：新增 `rippleSources: Set<String>`（Dock 标题小写，来自 onPulse）。
   - `badgePulse`：仅在有可见收起屏时记入触发者；全部屏展开/隐藏则不记。
   - `appsDidChange`：停住条件改为「触发者里还有角标的 app 为空」——`registry.hasBadge(named:)` 逐个判定，空则全屏停涟漪；其他 app 的常驻角标不再挟持。
   - `expand`：任意一次展开 = 全局确认（对齐 decisions.md 既有表述「任意一次展开（用户已知）」，原实现只停当前屏）——清空触发者并停全部屏涟漪。
2. **BadgeStore / AppRegistry**：涟漪观察档 `setRippleWatch`——收起态仍有未确认涟漪时轮询保持展开档 1s（角标消失一拍内可见），触发者清空或展开确认后回落 4s；`detectPulse` 返回本轮全部触发者（同轮多 app 各自入集合）；`start` 注册间隔按当前组合态取值。
   - review 补充：面板重建（显示器插拔）在重建后对账涟漪——未确认触发者在新收起屏恢复涟漪；接管退场整体复位触发者与观察档，防 1s 空转。
3. **文档**：decisions.md 汛线通知语言停住条件、glossary 涟漪词条、README 对应句。

## 验收

- `swift build --build-system native` 通过。
- 用户实测：A app 常驻角标在场时，QQ 消息触发涟漪 → 打开 QQ 读完（角标清）→ 涟漪约 1–1.5s 内停。

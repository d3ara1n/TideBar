import AppKit
import ApplicationServices
import TideBarCore

/// Dock 角标镜像：轮询系统 Dock 进程 AX 树的 `AXDockItem.AXStatusLabel`。
///
/// 「藏 UI、留进程」架构下 Dock 仍维护角标真值，接管态（Dock 隐藏）读取照常；
/// 覆盖面 = Dock 角标的镜像，与系统设置中各 app 的角标开关天然一致。
/// 无变更推送只能轮询——经 `PollScheduler` 驱动（展开态加速、收起态降频），
/// AX 读取在后台串行队列执行，pid 是唯一跨线程载荷（值类型），
/// 每轮现建 `AXUIElement`（一次 mach 分配，相对几十次属性读取可忽略），
/// 模型更新经 `MainThreadBridge` 回主线程。
@MainActor
final class BadgeStore {
    private static let badgeDemand = "dock.badges"
    /// 连续失败上限：超过后清空角标（Dock 重启期间短暂保留旧值，真挂了不放僵尸数字）
    private static let failureLimit = 3

    /// 键 = 规范化显示名（小写），与 `AXDockItem` 的 AXTitle 对位
    private var values: [String: BadgeValue] = [:]
    /// 首次成功采样只建基线不脉冲——启动时已存在的角标不是「新事件」
    private var hasBaseline = false
    private var dockPID: pid_t?
    private var busy = false
    private var consecutiveFailures = 0
    private let readQueue = DispatchQueue(label: "dev.dearain.TideBar.badges", qos: .utility)

    /// 角标集合变化（Registry 去抖后刷新模型）
    var onUpdate: (() -> Void)?
    /// 新角标出现或计数增长（合并为一次事件；仅收起态消费）
    var onPulse: (() -> Void)?

    func start() {
        guard AXIsProcessTrusted() else {
            NSLog("TideBar BadgeStore inactive: accessibility not granted")
            return
        }
        PollScheduler.shared.register(Self.badgeDemand, interval: Layout.badgePollCollapsed) { [weak self] in
            self?.poll()
        }
    }

    /// 展开/收起切换节奏：展开加速 + 立即全量读（新鲜角标随去抖落进视图）
    func setExpanded(_ expanded: Bool) {
        PollScheduler.shared.updateInterval(
            Self.badgeDemand,
            interval: expanded ? Layout.badgePollExpanded : Layout.badgePollCollapsed
        )
        if expanded { poll() }
    }

    func value(named displayName: String) -> BadgeValue? {
        values[displayName.lowercased()]
    }

    // MARK: 轮询执行

    private func poll() {
        // 系统 Dock 可见时自带角标，镜像无意义，不花这份足迹
        guard AppConfiguration.shared.isTakeoverEnabled else { return }
        guard !busy else { return }
        if dockPID == nil {
            dockPID = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
        }
        guard let pid = dockPID else { return }
        busy = true
        readQueue.async { [weak self] in
            let snapshot = Self.readDockBadges(pid: pid)
            MainThreadBridge { [weak self] in
                self?.apply(snapshot)
            }.call()
        }
    }

    private func apply(_ snapshot: [String: String]?) {
        busy = false
        guard let snapshot else {
            // Dock 重启（pid 失效）或读取失败：下轮重解析 pid，短期保留旧值防闪烁
            dockPID = nil
            consecutiveFailures += 1
            if consecutiveFailures > Self.failureLimit, !values.isEmpty {
                values = [:]
                onUpdate?()
            }
            return
        }
        consecutiveFailures = 0
        // 键统一小写规范化：查询侧（displayName.lowercased()）与 Dock 原始标题对位
        var parsed: [String: BadgeValue] = [:]
        for (title, raw) in snapshot {
            if let value = BadgeValue.parse(raw) {
                parsed[title.lowercased()] = value
            }
        }
        let baselineJustEstablished = !hasBaseline
        hasBaseline = true
        let pulsed = !baselineJustEstablished && Self.detectPulse(old: values, new: parsed)
        guard parsed != values else { return }
        values = parsed
        onUpdate?()
        if pulsed { onPulse?() }
    }

    /// 脉冲判定：出现（无→有）或计数增长。数值回落、形态切换不脉冲。
    private static func detectPulse(old: [String: BadgeValue], new: [String: BadgeValue]) -> Bool {
        for (name, value) in new {
            switch (old[name], value) {
            case (nil, _):
                return true
            case (.count(let previous), .count(let current)) where current > previous:
                return true
            default:
                continue
            }
        }
        return false
    }

    // MARK: AX 读取（后台队列；纯 C API，不触主线程状态）

    /// 深度受限遍历 Dock AX 树，收集 AXDockItem 的 title → AXStatusLabel。
    nonisolated private static func readDockBadges(pid: pid_t) -> [String: String]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        func attribute(_ element: AXUIElement, _ name: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
                return nil
            }
            return value as? String
        }
        func children(_ element: AXUIElement) -> [AXUIElement]? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
                  let array = value as? [Any] else {
                return nil
            }
            var elements: [AXUIElement] = []
            for case let child as AXUIElement in array { elements.append(child) }
            return elements
        }

        guard let roots = children(app) else { return nil }
        var stack: [(AXUIElement, Int)] = roots.map { ($0, 0) }
        var badges: [String: String] = [:]
        var visited = 0
        while let (element, depth) = stack.popLast() {
            visited += 1
            guard depth < 8, visited < 256 else { continue }
            if attribute(element, kAXRoleAttribute as String) == "AXDockItem" {
                let title = attribute(element, kAXTitleAttribute as String) ?? ""
                if !title.isEmpty {
                    badges[title] = attribute(element, "AXStatusLabel" as String) ?? ""
                }
            }
            for child in children(element) ?? [] {
                stack.append((child, depth + 1))
            }
        }
        return badges
    }
}

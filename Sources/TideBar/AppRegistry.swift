import AppKit
import Darwin
import TideBarCore
import UniformTypeIdentifiers

/// 应用身份的快照：固定与临时应用 item 共享同一份进程、窗口和动作语义。
struct AppEntry: Identifiable {
    let identity: AppIdentity
    /// 固定配置保留采集到的原始 bundle identifier，不用规范化身份代替 locator。
    /// 裸进程（无 bundle 的 regular GUI）为 nil，此时身份由可执行路径派生，不支持固定。
    let bundleIdentifier: String?
    /// 启动、显示安装位置等系统操作使用解析后的 URL，不反查规范化身份。
    let applicationURL: URL?
    let name: String
    let icon: NSImage

    let isPinned: Bool
    let preferredProcessIdentifier: pid_t?
    let runningAppsByPID: [pid_t: NSRunningApplication]
    let windowKnowledge: WindowKnowledge<WindowSnapshot>
    let isHidden: Bool
    let canTerminate: Bool
    /// Dock 角标镜像值（nil = 无角标）；随模型真值 diff 驱动 UI 与汐线脉冲
    let badge: BadgeValue?

    var id: AppIdentity { identity }
    /// Finder 的常驻桌面进程不计运行；只有收录到资源管理窗口才算逻辑运行。
    var isRunning: Bool {
        AppBehavior.resolve(for: identity).logicalIsRunning(
            processIsRunning: !runningAppsByPID.isEmpty,
            knownWindowCount: windowKnowledge.elements?.count
        )
    }
    var runningApp: NSRunningApplication? {
        preferredProcessIdentifier.flatMap { runningAppsByPID[$0] }
    }
    /// nil = 窗口知识未知；[] = 已确认零收录窗口。
    var windows: [WindowSnapshot]? { windowKnowledge.elements }
    var windowRevision: WindowKnowledge<WindowContentRevision> {
        windowKnowledge.map {
            WindowContentRevision(ownerProcessIdentifier: $0.ownerPID,
                                  elementIdentifier: $0.elementIdentifier,
                                  title: $0.title,
                                  document: $0.document,
                                  isMinimized: $0.isMinimized,
                                  isActive: $0.isActive,
                                  screenID: $0.screenID)
        }
    }
    var contentRevision: AppContentRevision {
        AppContentRevision(identity: identity,
                           name: name,
                           applicationPath: applicationURL?.path,
                           isPinned: isPinned,
                           preferredProcessIdentifier: preferredProcessIdentifier,
                           processIdentifiers: Array(runningAppsByPID.keys),
                           isHidden: isHidden,
                           canTerminate: canTerminate,
                           badge: badge,
                           windows: windowRevision)
    }

    func runningApp(for window: WindowSnapshot) -> NSRunningApplication? {
        runningAppsByPID[window.ownerPID]
    }

    /// 点点状态摘要（逐窗：聚焦、最小化、归属屏，nil=不画），供变更判定；
    /// 归属入摘要使跨屏移动在重枚举后能刷新各屏点色（同屏重算为 no-op）
    var dotSignature: String {
        guard isRunning, let windows else { return "nil" }
        return windows.map { window in
            (window.isActive ? "f" : "") + (window.isMinimized ? "m" : "a")
                + "@" + (window.screenID.map(String.init) ?? "?")
        }.joined(separator: ",")
    }

    /// 主点击：仅剩最小化窗口 → 还原最近一个；否则 activate
    /// （activate 隐含 raise 最近窗口，与 Dock 一致；无 AX 信息时退化为纯激活）
    func primaryClick() {
        if let app = runningApp {
            // 垂死实例（挂起期间进程已死、刷新未及消费）：不动作，等对账清场
            guard app.isProcessAlive else { return }
            if let windows, !windows.isEmpty, windows.allSatisfy(\.isMinimized),
               let window = windows.last, let owner = runningApp(for: window) {
                AXReader.raise(window, app: owner)
                return
            }
            activate()
        } else if let applicationURL {
            launch(applicationURL)
        }
    }

    /// 点击：运行中 → 激活 + 补发 reopen（对齐 Dock：无窗口时 app 会新开窗口）；
    /// 固定未运行 → 启动。reopen 事件若需 TCC 授权则静默跳过（零权限原则）
    func activate() {
        if let app = runningApp {
            // 垂死实例：不激活、不发事件，避免向死 pid 报 procNotFound
            guard app.isProcessAlive else { return }
            _ = app.activate()
            sendReopen(to: app)
        } else if let applicationURL {
            launch(applicationURL)
        }
    }

    private func launch(_ url: URL) {
        Task { @MainActor in
            do { try await NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            catch { ItemErrors.report(error) }
        }
    }

    private func sendReopen(to app: NSRunningApplication) {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                           eventID: AEEventID(kAEReopenApplication),
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        // kAEDoNotPromptForUserConsent：免授权事件（reopen 属 Dock 同款）直接送达；
        // 若被拦则抛错，保持仅激活的降级行为，绝不弹授权框
        let options: NSAppleEventDescriptor.SendOptions = [.noReply,
                                                            .init(rawValue: UInt(kAEDoNotPromptForUserConsent))]
        do {
            _ = try event.sendEvent(options: options, timeout: 3)
        } catch {
            NSLog("TideBar reopen event not sent for %@: %@", app.bundleIdentifier ?? "?", String(describing: error))
        }
    }
}

extension NSRunningApplication {
    /// 进程仍在运行：LS 未标记垂死，且 pid 探测存在（kill 0 探测；
    /// 僵尸态短窗口内探测为活，可接受——彼时 LS 同样未标记）。
    var isProcessAlive: Bool {
        !isTerminated && kill(processIdentifier, 0) == 0
    }
}

/// 固定 + 运行 app 的合并视图：图标、点点（窗口状态）、点击切换/还原
@MainActor
final class AppRegistry {
    /// 不进任务栏的系统进程
    private static let hiddenApps: Set<AppIdentity> = [AppIdentity("com.apple.dock")]

    private(set) var entries: [AppEntry] = []
    var onChange: (() -> Void)?
    /// 本轮确认的逻辑启动合并为一次收纳事件，初始快照只建立基线。
    var onApplicationsStarted: (() -> Void)?
    private var hasRunningBaseline = false
    private var lastKnownRunning: [AppIdentity: Bool] = [:]

    private let windowStore = WindowStore()
    private let badgeStore = BadgeStore()
    /// 新角标出现/增长（携带显示名；收起态由控制器消费为汐线脉冲）
    var onBadgePulse: ((String) -> Void)?
    private var refreshDebounce: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let bridge = MainThreadBridge { [weak self] in self?.refreshSoon() }
        for name: Notification.Name in [NSWorkspace.didLaunchApplicationNotification,
                                         NSWorkspace.didTerminateApplicationNotification,
                                         NSWorkspace.didHideApplicationNotification,
                                         NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                bridge()
            })
        }
        let pinnedBridge = MainThreadBridge { [weak self] in self?.refresh() }
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.pinnedDidChange, object: nil, queue: .main
        ) { _ in
            pinnedBridge()
        })
        windowStore.onUpdate = { [weak self] _ in self?.refreshSoon() }
        windowStore.start()
        badgeStore.onUpdate = { [weak self] in self?.refreshSoon() }
        badgeStore.onPulse = { [weak self] name in self?.onBadgePulse?(name) }
        badgeStore.start()
        refresh()
    }

    /// 展开/收起切换角标轮询节奏（展开加速 + 立即全量读）
    func setBadgeCadence(expanded: Bool) {
        badgeStore.setExpanded(expanded)
    }

    /// 重读全部窗口知识（frame→屏归属）；展开时消费，保证点色反映最新窗口位置
    func refreshWindows() {
        windowStore.refreshAll()
    }

    /// AX 授权到位后的（重）启动入口：幂等，已激活的 store 短路；
    /// 消费方为授权恢复广播，与启动时的 start 同一入口
    func activateWindowKnowledge() {
        windowStore.start()
        badgeStore.start()
    }

    /// 展开/收起切换窗口内容维护范围（title/document 停更/恢复），与角标节奏同源切换
    func setWindowCadence(expanded: Bool) {
        windowStore.setExpanded(expanded)
    }

    /// 250ms 去抖，合并应用启停风暴
    func refreshSoon() {
        refreshDebounce?.cancel()
        let bridge = MainThreadBridge { [weak self] in self?.refresh() }
        let work = DispatchWorkItem { bridge() }
        refreshDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func requestSetHidden(_ hidden: Bool, of identity: AppIdentity) {
        refresh()
        guard let entry = entries.first(where: { $0.identity == identity }) else {
            NSLog("TideBar visibility change ignored for unavailable app: %@", identity.bundleIdentifier)
            return
        }
        AppActionDispatcher.setHidden(hidden, for: entry)
    }

    func requestTermination(of identity: AppIdentity) {
        refresh()
        guard let entry = entries.first(where: { $0.identity == identity }) else {
            NSLog("TideBar termination ignored for unavailable app: %@", identity.bundleIdentifier)
            return
        }
        AppActionDispatcher.terminate(entry)
    }

    func refresh() {
        let workspace = NSWorkspace.shared
        let pinned = AppConfiguration.shared.effectivePinnedBundleIDs
        let running = workspace.runningApplications.filter {
            guard !$0.isTerminated, $0.activationPolicy == .regular else { return false }
            // 裸进程（无 bundle 的 regular GUI）照收，身份由可执行路径派生；
            // 系统 Dock 对 regular 进程来者不拒，这里对齐它
            guard let bundleIdentifier = $0.bundleIdentifier else { return true }
            return !Self.hiddenApps.contains(AppIdentity(bundleIdentifier))
        }
        let descriptions = running.compactMap { app -> RunningAppDescription? in
            if let bundleIdentifier = app.bundleIdentifier {
                return RunningAppDescription(bundleIdentifier: bundleIdentifier,
                                             processIdentifier: app.processIdentifier)
            }
            guard let executablePath = app.executablePath else { return nil }
            return RunningAppDescription(executablePath: executablePath,
                                         processIdentifier: app.processIdentifier)
        }
        let composed = AppListComposer.compose(pinnedBundleIdentifiers: pinned,
                                               runningApps: descriptions)
        let runningByPID = Dictionary(uniqueKeysWithValues: running.map {
            ($0.processIdentifier, $0)
        })
        windowStore.reconcile(aliveProcessIdentifiers: Set(runningByPID.keys))

        func icon(app: NSRunningApplication?, applicationURL: URL?) -> NSImage {
            if let image = app?.icon { return image }
            if let applicationURL { return workspace.icon(forFile: applicationURL.path) }
            return workspace.icon(for: UTType.application)
        }
        func name(locator: String?, app: NSRunningApplication?, applicationURL: URL?) -> String {
            if let name = app?.localizedName { return name }
            if let applicationURL { return applicationURL.deletingPathExtension().lastPathComponent }
            return locator ?? "?"
        }

        var pinnedEntries: [AppEntry] = []
        var runningEntries: [AppEntry] = []
        var knownRunning: [AppIdentity: Bool] = [:]
        var applicationsStarted = false
        for description in composed {
            let apps = description.runningInstances.compactMap {
                runningByPID[pid_t($0.processIdentifier)]
            }
            let appsByPID = Dictionary(uniqueKeysWithValues: apps.map {
                ($0.processIdentifier, $0)
            })
            let windowKnowledge = WindowKnowledge.aggregate(apps.map {
                windowStore.knowledge(for: $0.processIdentifier)
            })
            // 在可见性过滤前记录运行状态：未固定且没有窗口的 Finder 也需保留基线。
            let requiresWindows = description.behavior.visibility == .whenHasKnownWindows
            if requiresWindows, !apps.isEmpty, windowKnowledge.elements == nil {
                // 未知不是退出；恢复读取时沿用上次已确认状态。
                knownRunning[description.identity] = lastKnownRunning[description.identity]
            } else {
                let isRunning = description.behavior.logicalIsRunning(
                    processIsRunning: !apps.isEmpty,
                    knownWindowCount: windowKnowledge.elements?.count
                )
                let previous = lastKnownRunning[description.identity]
                knownRunning[description.identity] = isRunning
                // 窗口驱动的应用首次获得知识只建基线，不把 AX 就绪当作启动。
                if hasRunningBaseline, isRunning, previous != true,
                   !requiresWindows || previous != nil {
                    applicationsStarted = true
                }
            }
            guard description.behavior.isVisible(
                isPinned: description.isPinned,
                processIsRunning: !apps.isEmpty,
                knownWindowCount: windowKnowledge.elements?.count
            ) else { continue }

            let app = apps.first
            let bundleIdentifier = app?.bundleIdentifier ?? description.pinnedBundleIdentifier
            let pinnedReference = PinnedItemStore.shared.records.first {
                $0.id == .application(description.identity) && $0.kind == .application
            }?.reference
            let applicationURL = app?.bundleURL
                ?? pinnedReference.flatMap(ItemReferences.applicationURL)
                ?? bundleIdentifier.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
                ?? app?.executablePath.map { URL(fileURLWithPath: $0) }
            guard app != nil || applicationURL != nil else { continue }

            let displayName = name(locator: bundleIdentifier, app: app, applicationURL: applicationURL)
            let entry = AppEntry(identity: description.identity,
                                 bundleIdentifier: bundleIdentifier,
                                 applicationURL: applicationURL,
                                 name: displayName,
                                 icon: icon(app: app, applicationURL: applicationURL),
                                 isPinned: description.isPinned,
                                 preferredProcessIdentifier: app?.processIdentifier,
                                 runningAppsByPID: appsByPID,
                                 windowKnowledge: windowKnowledge,
                                 isHidden: !apps.isEmpty && apps.allSatisfy(\.isHidden),
                                 canTerminate: description.behavior.canTerminate,
                                 badge: badgeStore.value(named: displayName))
            if description.isPinned {
                pinnedEntries.append(entry)
            } else {
                runningEntries.append(entry)
            }
        }
        runningEntries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let newEntries = pinnedEntries + runningEntries
        // identity 决定视图复用；进程、能力或窗口内容变化均发布最新模型。
        // 与条目无关的 helper 子进程噪音仍在组合层被吸收。
        let oldRevision = entries.map(\.contentRevision)
        let newRevision = newEntries.map(\.contentRevision)
        let iconChanged = entries.count == newEntries.count
            && zip(entries, newEntries).contains { !$0.icon.isEqual($1.icon) }
        entries = newEntries
        lastKnownRunning = knownRunning
        hasRunningBaseline = true
        if oldRevision != newRevision || iconChanged {
            onChange?()
        }
        // 先提交模型与几何，再发送视觉反馈。
        if applicationsStarted { onApplicationsStarted?() }
    }
}

import AppKit
import TideBarCore
import UniformTypeIdentifiers

/// 图标栏的一个条目：固定项与运行项去重合并后的视图模型
struct AppEntry: Identifiable {
    let identity: AppIdentity
    /// 启动、显示安装位置等系统操作使用解析后的 URL，不反查规范化身份。
    let applicationURL: URL?
    let name: String
    let icon: NSImage

    let preferredProcessIdentifier: pid_t?
    let runningAppsByPID: [pid_t: NSRunningApplication]
    let windowKnowledge: WindowKnowledge<WindowSnapshot>
    let canTerminate: Bool

    var id: AppIdentity { identity }
    var isRunning: Bool { !runningAppsByPID.isEmpty }
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
                                  isMinimized: $0.isMinimized)
        }
    }
    var contentRevision: AppContentRevision {
        AppContentRevision(identity: identity,
                           name: name,
                           applicationPath: applicationURL?.path,
                           preferredProcessIdentifier: preferredProcessIdentifier,
                           processIdentifiers: Array(runningAppsByPID.keys),
                           canTerminate: canTerminate,
                           windows: windowRevision)
    }

    func runningApp(for window: WindowSnapshot) -> NSRunningApplication? {
        runningAppsByPID[window.ownerPID]
    }

    /// 点点状态摘要（活跃数/最小化数，nil=不画），供变更判定
    var dotSignature: String {
        guard isRunning, let windows else { return "nil" }
        let mini = windows.filter(\.isMinimized).count
        return "\(windows.count - mini)/\(mini)"
    }

    /// 主点击：仅剩最小化窗口 → 还原最近一个；否则 activate
    /// （activate 隐含 raise 最近窗口，与 Dock 一致；无 AX 信息时退化为纯激活）
    func primaryClick() {
        if runningApp != nil {
            if let windows, !windows.isEmpty, windows.allSatisfy(\.isMinimized),
               let window = windows.last, let owner = runningApp(for: window) {
                AXReader.raise(window, app: owner)
                return
            }
            activate()
        } else if let applicationURL {
            let config = NSWorkspace.OpenConfiguration()
            Task { try? await NSWorkspace.shared.openApplication(at: applicationURL, configuration: config) }
        }
    }

    /// 点击：运行中 → 激活 + 补发 reopen（对齐 Dock：无窗口时 app 会新开窗口）；
    /// 固定未运行 → 启动。reopen 事件若需 TCC 授权则静默跳过（零权限原则）
    func activate() {
        if let app = runningApp {
            _ = app.activate()
            sendReopen(to: app)
        } else if let applicationURL {
            let config = NSWorkspace.OpenConfiguration()
            Task { try? await NSWorkspace.shared.openApplication(at: applicationURL, configuration: config) }
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

/// 固定 + 运行 app 的合并视图：图标、点点（窗口状态）、点击切换/还原
@MainActor
final class AppRegistry {
    /// 默认固定项（bundle id），UserDefaults `tidebar.pinned`（[String]）可覆盖
    private static let defaultPinned = ["com.apple.Finder", "com.apple.Safari", "com.apple.mail",
                                        "com.apple.Notes", "com.apple.Music", "com.apple.Terminal"]
    /// 不进任务栏的系统进程
    private static let hiddenApps: Set<AppIdentity> = [AppIdentity("com.apple.dock")]

    private(set) var entries: [AppEntry] = []
    var onChange: (() -> Void)?

    private let windowStore = WindowStore()
    private var refreshDebounce: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let bridge = MainThreadBridge { [weak self] in self?.refreshSoon() }
        for name: Notification.Name in [NSWorkspace.didLaunchApplicationNotification,
                                         NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                bridge()
            })
        }
        windowStore.onUpdate = { [weak self] _ in self?.refreshSoon() }
        windowStore.start()
        refresh()
    }

    /// 250ms 去抖，合并应用启停风暴
    func refreshSoon() {
        refreshDebounce?.cancel()
        let bridge = MainThreadBridge { [weak self] in self?.refresh() }
        let work = DispatchWorkItem { bridge() }
        refreshDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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
        let pinned = AppConfiguration.shared.pinnedBundleIDs ?? Self.defaultPinned
        let running = workspace.runningApplications.filter {
            guard $0.activationPolicy == .regular, let bundleIdentifier = $0.bundleIdentifier else {
                return false
            }
            return !Self.hiddenApps.contains(AppIdentity(bundleIdentifier))
        }
        let descriptions = running.compactMap { app -> RunningAppDescription? in
            guard let bundleIdentifier = app.bundleIdentifier else { return nil }
            return RunningAppDescription(bundleIdentifier: bundleIdentifier,
                                         processIdentifier: app.processIdentifier)
        }
        let composed = AppListComposer.compose(pinnedBundleIdentifiers: pinned,
                                               runningApps: descriptions)
        let runningByPID = Dictionary(uniqueKeysWithValues: running.map {
            ($0.processIdentifier, $0)
        })

        func icon(app: NSRunningApplication?, applicationURL: URL?) -> NSImage {
            if let image = app?.icon { return image }
            if let applicationURL { return workspace.icon(forFile: applicationURL.path) }
            return workspace.icon(for: UTType.application)
        }
        func name(locator: String, app: NSRunningApplication?, applicationURL: URL?) -> String {
            if let name = app?.localizedName { return name }
            if let applicationURL { return applicationURL.deletingPathExtension().lastPathComponent }
            return locator
        }

        var pinnedEntries: [AppEntry] = []
        var runningEntries: [AppEntry] = []
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
            guard description.behavior.isVisible(isPinned: description.isPinned,
                                                  isRunning: !apps.isEmpty,
                                                  knownWindowCount: windowKnowledge.elements?.count)
            else { continue }

            let app = apps.first
            guard let locator = app?.bundleIdentifier ?? description.pinnedBundleIdentifier else { continue }
            let applicationURL = app?.bundleURL
                ?? workspace.urlForApplication(withBundleIdentifier: locator)
            guard app != nil || applicationURL != nil else { continue }

            let entry = AppEntry(identity: description.identity,
                                 applicationURL: applicationURL,
                                 name: name(locator: locator, app: app, applicationURL: applicationURL),
                                 icon: icon(app: app, applicationURL: applicationURL),
                                 preferredProcessIdentifier: app?.processIdentifier,
                                 runningAppsByPID: appsByPID,
                                 windowKnowledge: windowKnowledge,
                                 canTerminate: description.behavior.canTerminate)
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
        if oldRevision != newRevision || iconChanged {
            onChange?()
        }
    }
}

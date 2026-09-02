import AppKit
import UniformTypeIdentifiers

/// 图标栏的一个条目：固定项与运行项去重合并后的视图模型
struct AppEntry: Identifiable {
    let id: String                    // bundle id
    let name: String
    let icon: NSImage
    let isRunning: Bool
    let runningApp: NSRunningApplication?
    /// 窗口快照：nil = 无 AX 信息（降级）或未运行；[] = 运行中零收录窗口
    let windows: [WindowSnapshot]?

    /// 点点状态摘要（活跃数/最小化数，nil=不画），供变更判定
    var dotSignature: String {
        guard isRunning, let windows else { return "nil" }
        let mini = windows.filter(\.isMinimized).count
        return "\(windows.count - mini)/\(mini)"
    }

    /// 主点击：仅剩最小化窗口 → 还原最近一个；否则 activate
    /// （activate 隐含 raise 最近窗口，与 Dock 一致；无 AX 信息时退化为纯激活）
    func primaryClick() {
        if let app = runningApp {
            if let windows, !windows.isEmpty, windows.allSatisfy(\.isMinimized) {
                AXReader.raise(windows.last!, app: app)
                return
            }
            activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let config = NSWorkspace.OpenConfiguration()
            Task { try? await NSWorkspace.shared.openApplication(at: url, configuration: config) }
        }
    }

    /// 点击：运行中 → 激活 + 补发 reopen（对齐 Dock：无窗口时 app 会新开窗口）；
    /// 固定未运行 → 启动。reopen 事件若需 TCC 授权则静默跳过（零权限原则）
    func activate() {
        if let app = runningApp {
            _ = app.activate()
            sendReopen(to: app)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let config = NSWorkspace.OpenConfiguration()
            Task { try? await NSWorkspace.shared.openApplication(at: url, configuration: config) }
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
    private static let hiddenBundles: Set<String> = ["com.apple.dock"]

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

    func refresh() {
        let pinned = AppConfiguration.shared.pinnedBundleIDs ?? Self.defaultPinned
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && !Self.hiddenBundles.contains($0.bundleIdentifier!)
        }

        func icon(for bundleID: String, app: NSRunningApplication?) -> NSImage {
            if let image = app?.icon { return image }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSWorkspace.shared.icon(for: UTType.application)
        }
        func name(for bundleID: String, app: NSRunningApplication?) -> String {
            if let name = app?.localizedName { return name }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url.deletingPathExtension().lastPathComponent
            }
            return bundleID
        }

        var seen = Set<String>()
        var pinnedEntries: [AppEntry] = []
        for bundleID in pinned {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            let app = running.first { $0.bundleIdentifier == bundleID }
            pinnedEntries.append(AppEntry(id: bundleID,
                                          name: name(for: bundleID, app: app),
                                          icon: icon(for: bundleID, app: app),
                                          isRunning: app != nil,
                                          runningApp: app,
                                          windows: app != nil ? windowStore.snapshots(for: bundleID) : nil))
            seen.insert(bundleID)
        }
        var runningEntries: [AppEntry] = []
        for app in running where app.bundleIdentifier.map({ !seen.contains($0) }) ?? false {
            let bundleID = app.bundleIdentifier!
            runningEntries.append(AppEntry(id: bundleID,
                                           name: name(for: bundleID, app: app),
                                           icon: icon(for: bundleID, app: app),
                                           isRunning: true,
                                           runningApp: app,
                                           windows: windowStore.snapshots(for: bundleID)))
        }
        runningEntries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let newEntries = pinnedEntries + runningEntries
        // 仅在可见内容变化（增删项、运行状态翻转、点点状态变化）时通知 UI；
        // helper 子进程的启停噪音在此被吸收，不触发图标栏重建
        let oldSignature = entries.map { "\($0.id):\($0.isRunning):\($0.dotSignature)" }
        let newSignature = newEntries.map { "\($0.id):\($0.isRunning):\($0.dotSignature)" }
        entries = newEntries
        if oldSignature != newSignature {
            onChange?()
        }
    }
}

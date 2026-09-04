import AppKit
import ApplicationServices
import TideBarCore

/// 单个收录窗口的快照（数据层最小集；潮涌/右键菜单消费）
struct WindowSnapshot {
    let ownerPID: pid_t
    let elementIdentifier: Int
    let element: AXUIElement
    let title: String?
    /// 文档路径或 URL 字符串（kAXDocument，稀疏，展示层负责回退）
    let document: String?
    let isMinimized: Bool
    let frame: CGRect?
}

// MARK: - AX 读取（元素级超时防挂起）

enum AXReader {
    enum AttributeState<Value> {
        case value(Value)
        case unavailable
        case failed
    }

    static func setWindowElementTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 0.5)
    }

    static func readStringState(_ element: AXUIElement, _ attribute: String) -> AttributeState<String> {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return .unavailable }
        guard error == .success, let string = value as? String else { return .failed }
        return .value(string)
    }

    static func readBoolState(_ element: AXUIElement, _ attribute: String) -> AttributeState<Bool> {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return .unavailable }
        guard error == .success, let number = value as? NSNumber else { return .failed }
        return .value(number.boolValue)
    }

    static func readString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let url = value as? URL { return url.path }
        return value as? String
    }

    static func readBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    static func readFrame(_ element: AXUIElement) -> CGRect? {
        var origin: AnyObject?
        var size: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &origin) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let originAny = origin, let sizeAny = size
        else { return nil }
        // CF 引用无动态类型检查，实际类型由 AXValueGetType 校验
        let originValue = originAny as! AXValue
        let sizeValue = sizeAny as! AXValue
        guard AXValueGetType(originValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var cgSize = CGSize.zero
        guard AXValueGetValue(originValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &cgSize) else { return nil }
        return CGRect(origin: point, size: cgSize)
    }

    /// kAXWindows 列表（一次重试：app 冷启动/忙碌时偶发 cannotComplete）
    static func readWindows(of appElement: AXUIElement) -> [AXUIElement]? {
        var result: [AXUIElement]?
        for _ in 0..<2 where result == nil {
            var value: AnyObject?
            let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
            if error == .success, let array = value as? [AnyObject] {
                result = array.map { $0 as! AXUIElement }
            }
        }
        return result
    }

    /// 前置一个窗口；最小化则先还原（minimized=false + raise + activate）
    static func raise(_ window: WindowSnapshot, app: NSRunningApplication) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        _ = app.activate()
    }
}

// MARK: - 窗口数据层

/// 按 pid 观测各 app 的窗口集合：kAXWindows 惰性枚举 + AXObserver 订阅变更，
/// 收录规则 = subrole 标准或 minimized（最小化窗口 subrole 不可靠，实测）。
/// 无法完整确认窗口集合与最小化态的 app 标记 degraded（交互退化为纯图标 + 激活）。
@MainActor
final class WindowStore {
    private struct Watch {
        let identity: AppIdentity
        let bundleIdentifier: String
        var observer: AXObserver?
        /// nil = 窗口集合无法完整确认（降级）；否则为当前收录快照
        var snapshots: [WindowSnapshot]?
        var reenumerateWork: DispatchWorkItem?
        var retryAttempt = 0
    }

    private static let retryDelays: [TimeInterval] = [0.25, 0.5, 1, 2, 4]

    private var watches: [pid_t: Watch] = [:]
    private var observers: [NSObjectProtocol] = []
    private var loggedNoPermission = false
    /// 快照集合变化（应用身份粒度）
    var onUpdate: ((AppIdentity) -> Void)?

    func start() {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            // 零权限安全态：不注册任何观测，交互退化为纯图标 + 激活（授权入口在设置界面）
            if !loggedNoPermission {
                NSLog("TideBar WindowStore inactive: accessibility not granted")
                loggedNoPermission = true
            }
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainThreadBridge { [weak self] in self?.addWatch(app, delay: 1.0) }.call()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainThreadBridge { [weak self] in self?.removeWatch(pid: app.processIdentifier) }.call()
        })

        for app in NSWorkspace.shared.runningApplications where isWatchable(app) {
            addWatch(app, delay: 0)
        }
        NSLog("TideBar WindowStore started, axTrusted=1, watching %d apps", watches.count)
    }

    private func isWatchable(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier else {
            return false
        }
        return AppIdentity(bundleIdentifier) != AppIdentity("com.apple.dock")
    }

    /// 运行实例 → 窗口知识。无观测或读取降级为 unknown。
    func knowledge(for processIdentifier: pid_t) -> WindowKnowledge<WindowSnapshot> {
        guard let snapshots = watches[processIdentifier]?.snapshots else { return .unknown }
        return .known(snapshots)
    }

    // MARK: 观测生命周期

    /// 对账：移除 pid 已不存在的观测（挂起期间终止通知迟到的兜底）
    func reconcile(aliveProcessIdentifiers: Set<pid_t>) {
        for pid in watches.keys where !aliveProcessIdentifiers.contains(pid) {
            removeWatch(pid: pid)
        }
    }

    private func addWatch(_ app: NSRunningApplication, delay: TimeInterval) {
        guard isWatchable(app) else { return }
        let pid = app.processIdentifier
        guard watches[pid] == nil else { return }
        let bundleIdentifier = app.bundleIdentifier!
        watches[pid] = Watch(identity: AppIdentity(bundleIdentifier),
                             bundleIdentifier: bundleIdentifier,
                             snapshots: nil)
        scheduleReenumerate(pid: pid, after: delay)
    }

    private func removeWatch(pid: pid_t) {
        guard var watch = watches.removeValue(forKey: pid) else { return }
        watch.reenumerateWork?.cancel()
        detachObserver(&watch)
    }

    /// 事件统一汇入：去抖后全量重枚举（简单可靠，事件风暴被 150ms 吸收）
    private func scheduleReenumerate(pid: pid_t, after delay: TimeInterval) {
        if let work = watches[pid]?.reenumerateWork {
            work.cancel()
        }
        let bridge = MainThreadBridge { [weak self] in self?.reenumerate(pid: pid) }
        let work = DispatchWorkItem { bridge() }
        watches[pid]?.reenumerateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @discardableResult
    private func scheduleRetry(pid: pid_t) -> Bool {
        guard var watch = watches[pid], watch.retryAttempt < Self.retryDelays.count else {
            return false
        }
        let delay = Self.retryDelays[watch.retryAttempt]
        watch.retryAttempt += 1
        watches[pid] = watch
        scheduleReenumerate(pid: pid, after: delay)
        return true
    }

    private func reenumerate(pid: pid_t) {
        guard var watch = watches[pid] else { return }
        watch.reenumerateWork = nil

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let elements = AXReader.readWindows(of: appElement) else {
            let degraded = watch.snapshots != nil
            watch.snapshots = nil
            watches[pid] = watch
            if degraded {
                NSLog("TideBar WindowStore degraded: %@ (pid %d) kAXWindows unreadable",
                      watch.bundleIdentifier, pid)
                onUpdate?(watch.identity)
            }
            _ = attachObserver(pid: pid, appElement: appElement, windows: [])
            scheduleRetry(pid: pid)
            return
        }

        var snapshots: [WindowSnapshot] = []
        var complete = true
        elementLoop: for element in elements {
            AXReader.setWindowElementTimeout(element)

            let subrole: String?
            switch AXReader.readStringState(element, kAXSubroleAttribute as String) {
            case let .value(value): subrole = value
            case .unavailable: subrole = nil
            case .failed:
                complete = false
                break elementLoop
            }

            let minimized: Bool
            switch AXReader.readBoolState(element, kAXMinimizedAttribute as String) {
            case let .value(value): minimized = value
            case .unavailable:
                // 标准窗口缺少最小化态会使点点语义不完整；非标准元素可确定排除。
                if subrole == (kAXStandardWindowSubrole as String) {
                    complete = false
                    break elementLoop
                }
                continue elementLoop
            case .failed:
                complete = false
                break elementLoop
            }

            // 收录规则：标准窗口，或已最小化（最小化时 subrole 不可靠，min 兜底；
            // 对话框/桌面元素两者皆不满足，天然排除）
            guard subrole == (kAXStandardWindowSubrole as String) || minimized else { continue }
            snapshots.append(WindowSnapshot(
                ownerPID: pid,
                elementIdentifier: Int(bitPattern: CFHash(element)),
                element: element,
                title: AXReader.readString(element, kAXTitleAttribute as String),
                document: AXReader.readString(element, kAXDocumentAttribute as String),
                isMinimized: minimized,
                frame: AXReader.readFrame(element)
            ))
        }

        guard complete else {
            let degraded = watch.snapshots != nil
            watch.snapshots = nil
            watches[pid] = watch
            if degraded {
                NSLog("TideBar WindowStore degraded: %@ (pid %d) window attributes incomplete",
                      watch.bundleIdentifier, pid)
                onUpdate?(watch.identity)
            }
            _ = attachObserver(pid: pid, appElement: appElement, windows: [])
            scheduleRetry(pid: pid)
            return
        }

        let changed = watch.snapshots.map { Self.signature($0) } != Self.signature(snapshots)
        watch.snapshots = snapshots
        watches[pid] = watch
        let observing = attachObserver(pid: pid, appElement: appElement, windows: snapshots)
        if observing {
            watches[pid]?.retryAttempt = 0
        } else if !scheduleRetry(pid: pid), var degradedWatch = watches[pid] {
            degradedWatch.snapshots = nil
            watches[pid] = degradedWatch
            NSLog("TideBar WindowStore degraded: %@ (pid %d) AX notifications incomplete",
                  degradedWatch.bundleIdentifier, pid)
            onUpdate?(degradedWatch.identity)
        }
        if changed {
            let mini = snapshots.filter(\.isMinimized).count
            NSLog("TideBar WindowStore %@ (pid %d): %d windows (%d minimized)",
                  watch.bundleIdentifier, pid, snapshots.count, mini)
            onUpdate?(watch.identity)
        }
    }

    /// frame 变动不触发；窗口身份、标题、文档和最小化态共同决定内容修订。
    private static func signature(_ snapshots: [WindowSnapshot]) -> [WindowContentRevision] {
        snapshots.map {
            WindowContentRevision(ownerProcessIdentifier: $0.ownerPID,
                                  elementIdentifier: $0.elementIdentifier,
                                  title: $0.title,
                                  document: $0.document,
                                  isMinimized: $0.isMinimized)
        }
    }

    // MARK: AXObserver

    /// 每轮重枚举后整体重建 observer：旧窗口的通知随旧 observer 一并失效，无悬挂
    private func attachObserver(pid: pid_t, appElement: AXUIElement,
                                windows: [WindowSnapshot]) -> Bool {
        guard var watch = watches[pid] else { return false }
        detachObserver(&watch)

        var error = AXError.failure
        var observer: AXObserver?
        error = AXObserverCreate(pid, axObserverCallback, &observer)
        guard error == .success, let observer else {
            NSLog("TideBar AXObserver create failed for pid %d: %d", pid, error.rawValue)
            watches[pid] = watch
            return false
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        func add(_ element: AXUIElement, _ notification: String) -> Bool {
            AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success
        }

        // 窗口集合与最小化态决定 Finder 可见性和点点，相关通知必须完整安装。
        var essentialInstalled = add(appElement, kAXWindowCreatedNotification as String)
        for window in windows {
            let destroyed = add(window.element, kAXUIElementDestroyedNotification as String)
            let minimized = add(window.element, kAXWindowMiniaturizedNotification as String)
            let restored = add(window.element, kAXWindowDeminiaturizedNotification as String)
            essentialInstalled = essentialInstalled && destroyed && minimized && restored
            // 标题通知只增强菜单与潮涌的实时内容；不支持时不抹掉已确认的窗口知识。
            _ = add(window.element, kAXTitleChangedNotification as String)
        }
        guard essentialInstalled else {
            NSLog("TideBar AXObserver missing essential notification for pid %d", pid)
            watches[pid] = watch
            return false
        }
        CFRunLoopAddSource(RunLoop.main.getCFRunLoop(),
                          AXObserverGetRunLoopSource(observer),
                          CFRunLoopMode.defaultMode)
        watch.observer = observer
        watches[pid] = watch
        return true
    }

    private func detachObserver(_ watch: inout Watch) {
        if let observer = watch.observer {
            CFRunLoopRemoveSource(RunLoop.main.getCFRunLoop(),
                                  AXObserverGetRunLoopSource(observer),
                                  CFRunLoopMode.defaultMode)
        }
        watch.observer = nil
    }

    /// AX 回调落点：仅重排去抖，不做重活
    func handleAXEvent(pid: pid_t, notification: String) {
        guard watches[pid] != nil else { return }
        scheduleReenumerate(pid: pid, after: 0.15)
    }
}

/// C 回调不能捕获上下文，经 refcon 取回 store；observer 挂在主 runloop，回调即主线程。
/// AXUIElement 非 Sendable，pid 在回调现场解析后再过桥。
private func axObserverCallback(_ observer: AXObserver,
                                _ element: AXUIElement,
                                _ notification: CFString,
                                _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    let name = notification as String
    let store = Unmanaged<WindowStore>.fromOpaque(refcon).takeUnretainedValue()
    MainThreadBridge { store.handleAXEvent(pid: pid, notification: name) }.call()
}

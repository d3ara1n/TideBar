import AppKit
import ApplicationServices

/// 单个收录窗口的快照（数据层最小集；潮涌/右键菜单消费）
struct WindowSnapshot {
    let element: AXUIElement
    let title: String?
    /// 文档路径或 URL 字符串（kAXDocument，稀疏，展示层负责回退）
    let document: String?
    let isMinimized: Bool
    let frame: CGRect?
}

// MARK: - AX 读取（元素级超时防挂起；复用探针验证过的读取模式）

enum AXReader {
    static func setWindowElementTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 0.5)
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
/// 收录规则 = subrole 标准或 minimized（最小化窗口 subrole 不可靠，探针实测）。
/// 读不到 kAXWindows 的 app 标记 degraded，快照返回 nil（M1 行为）。
@MainActor
final class WindowStore {
    private struct Watch {
        let bundleID: String
        var observer: AXObserver?
        /// nil = kAXWindows 读不到（降级）；否则为当前收录快照
        var snapshots: [WindowSnapshot]?
        var reenumerateWork: DispatchWorkItem?
    }

    private var watches: [pid_t: Watch] = [:]
    private var observers: [NSObjectProtocol] = []
    private var loggedNoPermission = false
    /// 快照集合变化（bundleID 粒度）
    var onUpdate: ((String) -> Void)?

    func start() {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            // 零权限安全态：全部走 M1 行为，不注册任何观测（授权引导属 M3 向导）
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
        app.activationPolicy == .regular && app.bundleIdentifier != nil
            && app.bundleIdentifier != "com.apple.dock"
    }

    /// bundleID → 快照。nil = 无观测 / 降级；[] = 运行中零收录窗口
    func snapshots(for bundleID: String) -> [WindowSnapshot]? {
        guard let watch = watches.values.first(where: { $0.bundleID == bundleID }) else { return nil }
        return watch.snapshots
    }

    // MARK: 观测生命周期

    private func addWatch(_ app: NSRunningApplication, delay: TimeInterval) {
        guard isWatchable(app) else { return }
        let pid = app.processIdentifier
        guard watches[pid] == nil else { return }
        watches[pid] = Watch(bundleID: app.bundleIdentifier!, snapshots: nil)
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

    private func reenumerate(pid: pid_t) {
        guard var watch = watches[pid] else { return }
        watch.reenumerateWork = nil

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let elements = AXReader.readWindows(of: appElement) else {
            // 降级：读不到窗口列表。保留 observer——app 稍后 AX 就绪时
            // kAXWindowCreated 仍会触发重试
            let degraded = watch.snapshots != nil
            watch.snapshots = nil
            watches[pid] = watch
            if degraded {
                NSLog("TideBar WindowStore degraded: %@ (pid %d) kAXWindows unreadable", watch.bundleID, pid)
                onUpdate?(watch.bundleID)
            }
            attachObserver(pid: pid, appElement: appElement, windows: [])
            return
        }

        var snapshots: [WindowSnapshot] = []
        for element in elements {
            AXReader.setWindowElementTimeout(element)
            let subrole = AXReader.readString(element, kAXSubroleAttribute as String)
            let minimized = AXReader.readBool(element, kAXMinimizedAttribute as String) ?? false
            // 收录规则：标准窗口，或已最小化（最小化时 subrole 不可靠，min 兜底；
            // 对话框/桌面元素两者皆不满足，天然排除）
            guard subrole == (kAXStandardWindowSubrole as String) || minimized else { continue }
            snapshots.append(WindowSnapshot(
                element: element,
                title: AXReader.readString(element, kAXTitleAttribute as String),
                document: AXReader.readString(element, kAXDocumentAttribute as String),
                isMinimized: minimized,
                frame: AXReader.readFrame(element)
            ))
        }

        let changed = watch.snapshots.map { Self.signature($0) } != Self.signature(snapshots)
        watch.snapshots = snapshots
        watches[pid] = watch
        attachObserver(pid: pid, appElement: appElement, windows: snapshots)
        if changed {
            let mini = snapshots.filter(\.isMinimized).count
            NSLog("TideBar WindowStore %@ (pid %d): %d windows (%d minimized)",
                  watch.bundleID, pid, snapshots.count, mini)
            onUpdate?(watch.bundleID)
        }
    }

    /// 快照集合变化判定（标题/文档/最小化态/数量；frame 变动不触发——窗口拖动不该惊动点点）
    private static func signature(_ snapshots: [WindowSnapshot]) -> [String] {
        snapshots.map { "\($0.title ?? "")|\($0.isMinimized ? 1 : 0)|\($0.document ?? "")" }
    }

    // MARK: AXObserver

    /// 每轮重枚举后整体重建 observer：旧窗口的通知随旧 observer 一并失效，无悬挂
    private func attachObserver(pid: pid_t, appElement: AXUIElement, windows: [WindowSnapshot]) {
        guard var watch = watches[pid] else { return }
        detachObserver(&watch)

        var error = AXError.failure
        var observer: AXObserver?
        error = AXObserverCreate(pid, axObserverCallback, &observer)
        guard error == .success, let observer else {
            NSLog("TideBar AXObserver create failed for pid %d: %d", pid, error.rawValue)
            watches[pid] = watch
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var installed = false

        func add(_ element: AXUIElement, _ notification: String) {
            if AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success {
                installed = true
            }
        }
        // app 级：窗口诞生、焦点转移（备用，兼顾将来潮涌的「最近」语义）
        add(appElement, kAXWindowCreatedNotification as String)
        // 窗口级：销毁 / 最小化 / 还原 / 改标题
        for window in windows {
            add(window.element, kAXUIElementDestroyedNotification as String)
            add(window.element, kAXWindowMiniaturizedNotification as String)
            add(window.element, kAXWindowDeminiaturizedNotification as String)
            add(window.element, kAXTitleChangedNotification as String)
        }
        guard installed else {
            NSLog("TideBar AXObserver installed no notification for pid %d", pid)
            watches[pid] = watch
            return
        }
        CFRunLoopAddSource(RunLoop.main.getCFRunLoop(),
                          AXObserverGetRunLoopSource(observer),
                          CFRunLoopMode.defaultMode)
        watch.observer = observer
        watches[pid] = watch
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

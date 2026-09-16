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
    /// 窗口归属显示器（交集面积最大者）；最小化或 frame 不可读时保留旧值，
    /// nil = 未知（冷启动即最小化等），呈现层按本屏处理
    let screenID: CGDirectDisplayID?
    /// 该窗口为当前聚焦窗口（点点强调色）；采集基准见 WindowStore 的前台基准
    let isActive: Bool
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

    /// 元素型属性（如 kAXFocusedWindow）；无值或非元素型返回 nil
    static func readElement(_ appElement: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
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

// MARK: - 后台采集契约（纯值进出，主线程 ↔ axQueue）

/// 调度时的采集输入快照：除 refcon 外全为纯值；AXUIElement 在采集现场创建，
/// 不跨线程产生。refcon 为指回 WindowStore 的不透明指针（与 AXObserver refcon
/// 同源，仅在回传时取回），以 @unchecked 承载。
private struct AXEnumerationRequest: @unchecked Sendable {
    let pid: pid_t
    let generation: Int
    let identity: AppIdentity
    /// 前台基准命中（聚焦窗口仅前台 app 读取）
    let isFrontmost: Bool
    /// 上一轮收录次序（elementIdentifier 序列，窗口序稳定化用）
    let previousOrder: [Int]
    /// 上一轮屏归属（缺键 = 未知，最小化/不可读帧沿用）
    let previousScreens: [Int: CGDirectDisplayID]
    let displays: [FullscreenDisplay]
    /// 指回 WindowStore 的裸指针（与 AXObserver refcon 同源，回传时取回）
    let refcon: UnsafeMutableRawPointer
}

/// 采集结果：快照与 observer 为 AX 引用，跨线程传递安全（AX API 线程安全），
/// 以 @unchecked Sendable 承载；责任边界 = 引用仅作透传。
private struct AXEnumerationOutcome: @unchecked Sendable {
    enum Content {
        /// kAXWindows 列表不可读（observer 为空窗口兜底，仅 windowCreated）
        case unreadable(observer: AXObserver?)
        /// 属性采集不完整（observer 同上）
        case incomplete(observer: AXObserver?)
        /// 采集完成；observer nil = 通知安装失败
        case snapshots([WindowSnapshot], observer: AXObserver?)
    }
    let content: Content
}

// MARK: - 窗口数据层

/// 按 pid 观测各 app 的窗口集合：kAXWindows 惰性枚举 + AXObserver 订阅变更，
/// 收录规则 = subrole 标准或 minimized（最小化窗口 subrole 不可靠，实测）。
/// 无法完整确认窗口集合与最小化态的 app 标记 degraded（交互退化为纯图标 + 激活）。
/// AX IPC 全部在后台串行队列执行（忙碌目标 app 烧满超时不再冻结主线程），
/// 调度与结果应用在主线程，以代数丢弃过期结果。
@MainActor
final class WindowStore {
    private struct Watch {
        let identity: AppIdentity
        var observer: AXObserver?
        /// nil = 窗口集合无法完整确认（降级）；否则为当前收录快照
        var snapshots: [WindowSnapshot]?
        var reenumerateWork: DispatchWorkItem?
        var retryAttempt = 0
        /// 调度代数：每次 scheduleReenumerate 递增；后台结果带回代数，不匹配即丢弃
        var generation = 0
    }

    private static let retryDelays: [TimeInterval] = [0.25, 0.5, 1, 2, 4]

    /// AX IPC 串行采集队列（逐 app 一轮，不并发：避免 AX 风暴进一步压垮忙碌目标）。
    /// 全部 AX 调用（属性采集与 observer 通知安装）在此执行，主线程只做调度与应用。
    private nonisolated static let axQueue = DispatchQueue(
        label: "dev.dearain.TideBar.ax", qos: .userInitiated)

    private var watches: [pid_t: Watch] = [:]
    private var observers: [NSObjectProtocol] = []
    private var loggedNoPermission = false
    /// 已激活观测（幂等重入的恢复入口用）
    private var activated = false
    /// 展开态才响应 title 通知（见 setExpanded）
    private var maintainsTitles = false
    /// 聚焦标记的前台基准：最近的非自身前台 app。面板成为 key 时 frontmost 会
    /// 短暂指向 TideBar，跳过自身使潮涌/键盘会话不清掉真实前台 app 的标记。
    private var markingFrontmostPID: pid_t?
    /// 快照集合变化（应用身份粒度）
    var onUpdate: ((AppIdentity) -> Void)?

    func start() {
        guard !activated else { return }
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            // 主功能不空等授权：失败即停，恢复由设置/引导窗口的授权边沿广播驱动
            if !loggedNoPermission {
                NSLog("TideBar WindowStore inactive: accessibility not granted")
                loggedNoPermission = true
            }
            return
        }
        activated = true
        let center = NSWorkspace.shared.notificationCenter
        if let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           frontmost != ProcessInfo.processInfo.processIdentifier {
            markingFrontmostPID = frontmost
        }
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
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { _ in
            MainThreadBridge { [weak self] in self?.frontmostApplicationDidChange() }.call()
        })

        for app in NSWorkspace.shared.runningApplications where isWatchable(app) {
            addWatch(app, delay: 0)
        }
        NSLog("TideBar WindowStore started, axTrusted=1, watching %d apps", watches.count)
    }

    private func isWatchable(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        // 裸进程（无 bundle 的 regular GUI）同样观测；Dock 隐藏名单仅对 bundle 进程生效
        guard let bundleIdentifier = app.bundleIdentifier else { return true }
        return AppIdentity(bundleIdentifier) != AppIdentity("com.apple.dock")
    }

    /// 运行实例 → 窗口知识。无观测或读取降级为 unknown。
    func knowledge(for processIdentifier: pid_t) -> WindowKnowledge<WindowSnapshot> {
        guard let snapshots = watches[processIdentifier]?.snapshots else { return .unknown }
        return .known(snapshots)
    }

    /// 展开/收起切换窗口内容维护范围：收起时 title/document 停更
    /// （无视图消费，浏览器/编辑器的高频标题变更不再触发 AX 重读），
    /// 窗口集合与最小化态照常维护（点点与展开刷新依赖）。
    func setExpanded(_ expanded: Bool) {
        maintainsTitles = expanded
    }

    /// 展开等需要新鲜窗口知识的时机：全量重枚举，重读 frame→归属；
    /// 事件去抖统一吸收，与启动时的批量重枚举同一模式。
    func refreshAll() {
        for pid in watches.keys {
            scheduleReenumerate(pid: pid, after: 0)
        }
    }

    /// 前台切换：重算新旧 app 的聚焦标记。收起态只记基准不重枚举，
    /// 展开时的全量刷新补齐；基准未变（如自身面板短暂成为 key）则无动作。
    private func frontmostApplicationDidChange() {
        let previous = markingFrontmostPID
        if let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           frontmost != ProcessInfo.processInfo.processIdentifier {
            markingFrontmostPID = frontmost
        }
        guard maintainsTitles, markingFrontmostPID != previous else { return }
        if let previous { scheduleReenumerate(pid: previous, after: 0) }
        if let current = markingFrontmostPID { scheduleReenumerate(pid: current, after: 0) }
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
        // 身份：标准应用为 bundle identifier，裸进程为可执行路径（与 Registry 同源）
        guard let identity = app.bundleIdentifier.map(AppIdentity.init)
            ?? app.executablePath.map(AppIdentity.init) else { return }
        watches[pid] = Watch(identity: identity,
                             snapshots: nil)
        scheduleReenumerate(pid: pid, after: delay)
    }

    private func removeWatch(pid: pid_t) {
        guard var watch = watches.removeValue(forKey: pid) else { return }
        watch.reenumerateWork?.cancel()
        swapObserver(&watch, to: nil)
    }

    /// 事件统一汇入：去抖后全量重枚举（简单可靠，事件风暴被 150ms 吸收）。
    /// 调度即快照采集输入（纯值）并交付后台队列；执行线程在后台，
    /// 去抖 cancel 语义不变（未开始的 work 取消，执行中的一轮由代数校验丢弃）。
    private func scheduleReenumerate(pid: pid_t, after delay: TimeInterval) {
        guard var watch = watches[pid] else { return }
        watch.generation += 1
        if let work = watch.reenumerateWork {
            work.cancel()
        }
        // 采集输入快照：上一轮次序与屏归属、显示器列表、前台基准、refcon 指回自身
        let previous = watch.snapshots ?? []
        let request = AXEnumerationRequest(
            pid: pid,
            generation: watch.generation,
            identity: watch.identity,
            isFrontmost: markingFrontmostPID == pid,
            previousOrder: previous.map(\.elementIdentifier),
            previousScreens: previous.reduce(into: [:]) { $0[$1.elementIdentifier] = $1.screenID },
            displays: Self.currentDisplays(),
            refcon: Unmanaged.passUnretained(self).toOpaque())
        // @Sendable：剥离闭包对上下文 MainActor 隔离的继承，否则 DispatchWorkItem
        // 在后台队列执行时触发运行时隔离检查（Swift 6 动态检测刷屏）
        let work = DispatchWorkItem { @Sendable in
            let outcome = Self.enumerate(request)
            let store = Unmanaged<WindowStore>.fromOpaque(request.refcon).takeUnretainedValue()
            MainThreadBridge { store.applyEnumeration(request, outcome) }.call()
        }
        watch.reenumerateWork = work
        watches[pid] = watch
        Self.axQueue.asyncAfter(deadline: .now() + delay, execute: work)
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

    // MARK: 后台采集（axQueue）与结果应用（主线程）

    /// 后台采集入口：全部 AX IPC（窗口列表、逐属性读取、observer 创建与通知注册）
    /// 在调用线程现场执行。pid 存活校验快速失败，不烧满超时。
    private nonisolated static func enumerate(_ request: AXEnumerationRequest) -> AXEnumerationOutcome {
        if NSRunningApplication(processIdentifier: request.pid)?.isTerminated != false {
            return AXEnumerationOutcome(content: .unreadable(observer: nil))
        }
        let appElement = AXUIElementCreateApplication(request.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let elements = AXReader.readWindows(of: appElement) else {
            return AXEnumerationOutcome(content: .unreadable(
                observer: installObserver(request, appElement: appElement, windows: [])))
        }

        var snapshots: [WindowSnapshot] = []
        var complete = true
        // 聚焦窗口仅前台 app 读取；与快照比对靠 elementIdentifier（CFHash 跨查询稳定）
        let focusedWindowIdentifier: Int? = request.isFrontmost
            ? AXReader.readElement(appElement, kAXFocusedWindowAttribute as String)
                .map { Int(bitPattern: CFHash($0)) }
            : nil
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
            let elementIdentifier = Int(bitPattern: CFHash(element))
            let frame = AXReader.readFrame(element)
            snapshots.append(WindowSnapshot(
                ownerPID: request.pid,
                elementIdentifier: elementIdentifier,
                element: element,
                title: AXReader.readString(element, kAXTitleAttribute as String),
                document: AXReader.readString(element, kAXDocumentAttribute as String),
                isMinimized: minimized,
                frame: frame,
                screenID: WindowScreenAssignment.resolve(frame: frame,
                                                         isMinimized: minimized,
                                                         displays: request.displays,
                                                         previous: request.previousScreens[elementIdentifier]),
                isActive: elementIdentifier == focusedWindowIdentifier
            ))
        }

        guard complete else {
            return AXEnumerationOutcome(content: .incomplete(
                observer: installObserver(request, appElement: appElement, windows: [])))
        }

        // 窗口序稳定化：kAXWindows 返回 z 序（激活窗口恒在前、最小化恒垫底），
        // 直接沿用会让点点随焦点跳动、点击循环顺序漂移；沿用上一轮快照中已知
        // 窗口的相对次序，新窗口按枚举序追加队尾（点点、点击循环与潮涌共用）。
        let ordered = stableOrdered(snapshots, preservingOrderOf: request.previousOrder)
        return AXEnumerationOutcome(content: .snapshots(
            ordered, observer: installObserver(request, appElement: appElement, windows: ordered)))
    }

    /// 采集结果应用：代数或 pid 失配即丢弃（app 退出、被新调度取代、重复回传）。
    /// degraded 判定、快照更新、observer swap 与重试梯语义与迁移前一致。
    private func applyEnumeration(_ request: AXEnumerationRequest, _ outcome: AXEnumerationOutcome) {
        guard var watch = watches[request.pid], watch.generation == request.generation else { return }
        watch.reenumerateWork = nil

        switch outcome.content {
        case let .unreadable(observer):
            degrade(&watch, request, observer: observer, reason: "kAXWindows unreadable")
        case let .incomplete(observer):
            degrade(&watch, request, observer: observer, reason: "window attributes incomplete")
        case let .snapshots(snapshots, observer):
            let changed = watch.snapshots.map { Self.signature($0) } != Self.signature(snapshots)
            watch.snapshots = snapshots
            swapObserver(&watch, to: observer)
            watches[request.pid] = watch
            if observer != nil {
                watches[request.pid]?.retryAttempt = 0
            } else if !scheduleRetry(pid: request.pid), var degradedWatch = watches[request.pid] {
                degradedWatch.snapshots = nil
                watches[request.pid] = degradedWatch
                NSLog("TideBar WindowStore degraded: %@ (pid %d) AX notifications incomplete",
                      degradedWatch.identity.bundleIdentifier, request.pid)
                onUpdate?(degradedWatch.identity)
            }
            if changed {
                let mini = snapshots.filter(\.isMinimized).count
                NSLog("TideBar WindowStore %@ (pid %d): %d windows (%d minimized)",
                      request.identity.bundleIdentifier, request.pid, snapshots.count, mini)
                onUpdate?(request.identity)
            }
        }
    }

    /// 降级应用：有旧知识才报 degraded；空窗口 observer 兑新窗口事件，重试梯继续爬
    private func degrade(_ watch: inout Watch, _ request: AXEnumerationRequest,
                         observer: AXObserver?, reason: String) {
        let degraded = watch.snapshots != nil
        watch.snapshots = nil
        swapObserver(&watch, to: observer)
        watches[request.pid] = watch
        if degraded {
            NSLog("TideBar WindowStore degraded: %@ (pid %d) %@",
                  request.identity.bundleIdentifier, request.pid, reason)
            onUpdate?(request.identity)
        }
        scheduleRetry(pid: request.pid)
    }

    /// 每轮重建 observer：主线程只挂/摘 runloop source（纯本地，CFRunLoop 非线程
    /// 安全）；通知注册已在后台完成。新者为 nil 即保持无 observer（靠重试梯与
    /// 展开全量刷新兑底）。
    private func swapObserver(_ watch: inout Watch, to observer: AXObserver?) {
        if let old = watch.observer {
            CFRunLoopRemoveSource(RunLoop.main.getCFRunLoop(),
                                  AXObserverGetRunLoopSource(old),
                                  CFRunLoopMode.defaultMode)
        }
        watch.observer = nil
        if let observer {
            CFRunLoopAddSource(RunLoop.main.getCFRunLoop(),
                              AXObserverGetRunLoopSource(observer),
                              CFRunLoopMode.defaultMode)
            watch.observer = observer
        }
    }

    /// 后台安装 observer（创建 + 逐通知注册均为 AX IPC）；runloop source 挂载由
    /// 主线程应用段完成——回调线程 = source 所挂 runloop，保持主线程回调链路。
    /// 返回 nil = 创建失败或必要通知缺失（调用方按通知缺失处理）。
    private nonisolated static func installObserver(_ request: AXEnumerationRequest,
                                                    appElement: AXUIElement,
                                                    windows: [WindowSnapshot]) -> AXObserver? {
        var error = AXError.failure
        var observer: AXObserver?
        error = AXObserverCreate(request.pid, axObserverCallback, &observer)
        guard error == .success, let observer else {
            NSLog("TideBar AXObserver create failed for pid %d: %d", request.pid, error.rawValue)
            return nil
        }

        func add(_ element: AXUIElement, _ notification: String) -> Bool {
            AXObserverAddNotification(observer, element, notification as CFString, request.refcon) == .success
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
        // 聚焦切换（应用内 Cmd+` 等）驱动点点强调色；安装失败不降级，
        // 焦点漂移由前台切换与展开全量刷新兑底。
        _ = add(appElement, kAXFocusedWindowChangedNotification as String)
        guard essentialInstalled else {
            NSLog("TideBar AXObserver missing essential notification for pid %d", request.pid)
            return nil
        }
        return observer
    }

    /// 窗口序稳定化：已知窗口沿用上轮次序，新窗口按本轮枚举序续到队尾；无上轮时保持枚举序
    private nonisolated static func stableOrdered(_ snapshots: [WindowSnapshot],
                                                  preservingOrderOf previousOrder: [Int]) -> [WindowSnapshot] {
        guard !previousOrder.isEmpty else { return snapshots }
        let currentByID = Dictionary(snapshots.map { ($0.elementIdentifier, $0) },
                                     uniquingKeysWith: { first, _ in first })
        var matched = Set<Int>()
        var ordered: [WindowSnapshot] = []
        for identifier in previousOrder {
            guard let current = currentByID[identifier] else { continue }
            ordered.append(current)
            matched.insert(identifier)
        }
        ordered.append(contentsOf: snapshots.filter { !matched.contains($0.elementIdentifier) })
        return ordered
    }

    /// frame 变动不触发；窗口身份、标题、文档、最小化态、聚焦态与屏归属共同决定内容修订。
    private static func signature(_ snapshots: [WindowSnapshot]) -> [WindowContentRevision] {
        snapshots.map {
            WindowContentRevision(ownerProcessIdentifier: $0.ownerPID,
                                  elementIdentifier: $0.elementIdentifier,
                                  title: $0.title,
                                  document: $0.document,
                                  isMinimized: $0.isMinimized,
                                  isActive: $0.isActive,
                                  screenID: $0.screenID)
        }
    }

    // MARK: AXObserver

    private static func currentDisplays() -> [FullscreenDisplay] {
        NSScreen.screens.compactMap { screen -> FullscreenDisplay? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
                return nil
            }
            return FullscreenDisplay(id: id, bounds: CGDisplayBounds(id))
        }
    }

    /// AX 回调落点：仅重排去抖，不做重活。
    /// 收起态丢弃 title 与聚焦通知：重枚举的全窗口 AX 重读无人消费，
    /// 停滞的 title 与过期的聚焦标记由展开时的全量重枚举补齐。
    func handleAXEvent(pid: pid_t, notification: String) {
        guard watches[pid] != nil else { return }
        if !maintainsTitles {
            let title = kAXTitleChangedNotification as String
            let focusedWindow = kAXFocusedWindowChangedNotification as String
            guard notification != title, notification != focusedWindow else { return }
        }
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

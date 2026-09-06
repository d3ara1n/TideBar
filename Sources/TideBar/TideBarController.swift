import AppKit
import CoreGraphics
import TideBarCore

/// 编排者：每屏一个 panel；接近检测三重兜底（全局 monitor + local monitor + 统一调度器轮询）；
/// 展开/收起状态机与 300ms 防抖；全屏 Space 抑制展开
@MainActor
final class TideBarController {
    @MainActor
    private final class ScreenState {
        let screen: NSScreen
        let panel: TidePanel
        let view: TideBarView
        var isExpanded = false
        var collapseDebounce: DispatchWorkItem?
        var collapseHeldUntilMouseMoves = false
        /// 快捷键会话收起后，直到下一次真实鼠标移动前抑制热区重开。
        var suppressExpandUntilMouseMove = false
        /// 使延迟的面板缩宽在后续应用变化后自动失效。
        var appTransitionGeneration = 0
        var hiddenForFullscreen = false

        init(screen: NSScreen, panel: TidePanel, view: TideBarView) {
            self.screen = screen
            self.panel = panel
            self.view = view
        }
    }

    private var screens: [CGDirectDisplayID: ScreenState] = [:]
    private let registry = AppRegistry()
    private static let mouseDemand = "mouse.proximity"
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyboardMonitor: Any?
    private var barSession: BarSessionState?
    private var switcherCommitWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var lastSampleTime: CFTimeInterval = 0
    private var fullscreenCache: [CGDirectDisplayID: (time: CFTimeInterval, value: Bool)] = [:]

    // 潮涌：同一时刻只存在一个，归属于触发它的屏
    private var surgePanel: SurgePanel?
    private var surgeIdentity: AppIdentity?
    private var surgeWindowRevision: WindowKnowledge<WindowContentRevision>?
    private var surgeOriginDisplayID: CGDirectDisplayID?
    private var surgeDismissWork: DispatchWorkItem?

    func start() {
        registry.onChange = { [weak self] in self?.appsDidChange() }
        registry.onBadgePulse = { [weak self] in self?.badgePulse() }
        registry.start()
        if AppConfiguration.shared.isTakeoverEnabled {
            rebuildPanels()
        }

        // 接近检测：全局 monitor 为主，local monitor 兜自家激活，轮询兜静止光标。
        // 真实移动与轮询分流，菜单动作可保持展开直到用户再次移动鼠标。
        let movementSample = MainThreadBridge { [weak self] in self?.sampleMouse(isMovement: true) }
        let pollSample = MainThreadBridge { [weak self] in self?.sampleMouse(isMovement: false) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            movementSample()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            movementSample()
            return event
        }
        PollScheduler.shared.register(Self.mouseDemand, interval: Layout.pollInterval) {
            pollSample()
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        let screenBridge = MainThreadBridge { [weak self] in self?.screensChanged() }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            screenBridge()
        })
        let spaceBridge = MainThreadBridge { [weak self] in self?.activeSpaceChanged() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            spaceBridge()
        })

        NSLog("TideBar started: screens=%d", screens.count)
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        PollScheduler.shared.unregister(Self.mouseDemand)
        globalMonitor = nil
        localMonitor = nil
        keyboardMonitor = nil
        endBarSession(collapse: false, suppressMouse: false)
    }

    // MARK: - 快捷键与键盘导航

    func handleShortcut(_ action: ShortcutManager.Action) {
        switch action {
        case .toggleBar:
            togglePersistentSession()
        case .cycleApplication:
            cycleSwitcherSession()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, surgePanel != nil {
            guard var session = barSession else {
                dismissSurge(animated: true)
                return true
            }
            if case .windows = session.level {
                _ = session.escape()
                barSession = session
                dismissSurge(animated: true)
                if let state = screens[session.displayID] {
                    state.view.setKeyboardSelection(session.selectedApplication)
                }
            } else {
                cancelBarSession()
            }
            return true
        }
        guard barSession != nil else { return false }
        switch event.keyCode {
        case 123: // left
            guard barSession?.level == .applications else { return false }
            moveApplication(by: -1)
        case 124: // right
            guard barSession?.level == .applications else { return false }
            moveApplication(by: 1)
        case 125: // down
            if barSession?.level == .applications {
                openSelectedSurge()
            } else if case .windows = barSession?.level {
                moveWindow(by: 1)
            } else {
                return false
            }
        case 126: // up
            guard case .windows = barSession?.level else { return false }
            moveWindow(by: -1)
        case 36, 76: // return / enter
            commitBarSession()
        case 53: // escape
            if let session = barSession, case .windows = session.level {
                var updated = session
                _ = updated.escape()
                barSession = updated
                dismissSurge(animated: true)
                if let state = screens[updated.displayID] {
                    state.view.setKeyboardSelection(updated.selectedApplication)
                }
            } else {
                cancelBarSession()
            }
        default:
            return false
        }
        touchSwitcherTimeout()
        return true
    }

    private var switcherTimeout: TimeInterval { AppConfiguration.shared.switcherCommitDelay }

    private func togglePersistentSession() {
        guard AppConfiguration.shared.isTakeoverEnabled,
              let state = targetScreenState(),
              !state.hiddenForFullscreen else { return }
        if let session = barSession {
            guard session.displayID == displayID(of: state.screen) else { return }
            cancelBarSession()
            return
        }
        // 必须在展开面板前读取，避免 key 面板改变 frontmostApplication。
        let initialApplication = preferredInitialApplication()
        let openedBySession = !state.isExpanded
        if !state.isExpanded { expand(state) }
        beginSession(mode: .persistent, on: state, openedBySession: openedBySession,
                     initialApplication: initialApplication)
    }

    private func cycleSwitcherSession() {
        guard AppConfiguration.shared.isTakeoverEnabled else { return }
        let state: ScreenState?
        if let session = barSession {
            state = screens[session.displayID]
        } else {
            state = targetScreenState()
        }
        guard let state, !state.hiddenForFullscreen else { return }

        if let session = barSession, session.isPersistent {
            moveApplication(by: 1)
            return
        }
        if barSession == nil {
            // 必须在展开面板前读取，避免 key 面板改变 frontmostApplication。
            let initialApplication = preferredInitialApplication()
            let openedBySession = !state.isExpanded
            if !state.isExpanded { expand(state) }
            beginSession(mode: .switcher, on: state, openedBySession: openedBySession,
                         initialApplication: initialApplication)
        } else {
            moveApplication(by: 1)
            armSwitcherTimeout()
        }
    }

    private func frontmostIdentity() -> AppIdentity? {
        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return AppIdentity(bundleIdentifier)
    }

    private func preferredInitialApplication() -> AppIdentity? {
        if let frontmost = frontmostIdentity(),
           registry.entries.contains(where: { $0.identity == frontmost }) {
            return frontmost
        }
        return registry.entries.first?.identity
    }

    private func beginSession(mode: BarSessionMode, on state: ScreenState,
                              openedBySession: Bool,
                              initialApplication: AppIdentity?) {
        guard let displayID = displayID(of: state.screen) else { return }
        barSession = BarSessionState(mode: mode,
                                     displayID: displayID,
                                     openedBySession: openedBySession,
                                     firstApplication: initialApplication,
                                     now: CACurrentMediaTime(),
                                     timeout: switcherTimeout)
        state.view.setKeyboardSelection(barSession?.selectedApplication)
        if mode == .switcher { armSwitcherTimeout() }
    }

    private func isKeyboardHolding(_ state: ScreenState) -> Bool {
        guard let session = barSession,
              session.displayID == self.displayID(of: state.screen) else { return false }
        return true
    }

    private func targetScreenState() -> ScreenState? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        guard let screen, let id = displayID(of: screen) else { return nil }
        return screens[id]
    }

    private func selectApplication(_ identity: AppIdentity) {
        guard var session = barSession else { return }
        session.selectApplication(identity,
                                  now: CACurrentMediaTime(),
                                  timeout: switcherTimeout)
        barSession = session
        if let state = screens[session.displayID] {
            state.view.setKeyboardSelection(identity)
        }
    }

    private func moveApplication(by offset: Int) {
        guard !registry.entries.isEmpty, var session = barSession else { return }
        if case .windows = session.level {
            _ = session.escape()
            dismissSurge(animated: true)
        }
        let current = session.selectedApplication
        let index = current.flatMap { identity in registry.entries.firstIndex { $0.identity == identity } } ?? 0
        let next = (index + offset + registry.entries.count) % registry.entries.count
        session.selectApplication(registry.entries[next].identity,
                                  now: CACurrentMediaTime(),
                                  timeout: switcherTimeout)
        barSession = session
        if let state = screens[session.displayID] {
            state.view.setKeyboardSelection(session.selectedApplication)
        }
        if session.isSwitcher { armSwitcherTimeout() }
    }

    private func openSelectedSurge() {
        guard let session = barSession,
              let state = screens[session.displayID],
              let identity = session.selectedApplication,
              let entry = registry.entries.first(where: { $0.identity == identity }),
              let iconFrame = state.view.iconFrame(for: identity) else { return }
        showSurge(entry: entry, state: state, iconFrame: iconFrame, fromKeyboard: true)
        cancelSwitcherTimeout()
    }

    private func moveWindow(by offset: Int) {
        guard let session = barSession,
              case let .windows(identity) = session.level,
              let entry = registry.entries.first(where: { $0.identity == identity }),
              let windows = entry.windows, !windows.isEmpty else { return }
        let ids = windows.map(\.elementIdentifier)
        let index = session.selectedWindowIdentifier.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = (index + offset + ids.count) % ids.count
        var updated = session
        updated.selectWindow(ids[next], now: nil, timeout: nil)
        barSession = updated
        (surgePanel?.contentView as? SurgeView)?.setKeyboardSelection(ids[next])
    }

    private func commitBarSession() {
        guard let session = barSession,
              let state = screens[session.displayID] else { return }
        cancelSwitcherTimeout()
        switch session.level {
        case .inactive:
            endBarSession(collapse: true, suppressMouse: true)
        case .applications:
            if let identity = session.selectedApplication,
               let entry = registry.entries.first(where: { $0.identity == identity }) {
                entry.primaryClick()
            }
            endBarSession(collapse: session.isPersistent || session.openedBySession,
                          suppressMouse: session.openedBySession)
        case .windows(let identity):
            if let entry = registry.entries.first(where: { $0.identity == identity }),
               let identifier = session.selectedWindowIdentifier,
               let window = entry.windows?.first(where: { $0.elementIdentifier == identifier }),
               let app = entry.runningApp(for: window) {
                AXReader.raise(window, app: app)
            } else if let entry = registry.entries.first(where: { $0.identity == identity }) {
                entry.activate()
            }
            endBarSession(collapse: session.isPersistent || session.openedBySession,
                          suppressMouse: session.openedBySession)
        }
        _ = state
    }

    private func cancelBarSession() {
        guard let session = barSession else {
            dismissSurge(animated: true)
            return
        }
        endBarSession(collapse: session.isPersistent || session.openedBySession,
                      suppressMouse: session.openedBySession)
    }

    private func endBarSession(collapse shouldCollapse: Bool, suppressMouse: Bool) {
        cancelSwitcherTimeout()
        let session = barSession
        barSession = nil
        dismissSurge(animated: true)
        guard let session, let state = screens[session.displayID] else { return }
        state.view.setKeyboardSelection(nil)
        if shouldCollapse && state.isExpanded {
            collapse(state, animated: true, suppressReexpand: suppressMouse)
        }
    }

    private func armSwitcherTimeout() {
        cancelSwitcherTimeout()
        guard barSession?.isSwitcher == true else { return }
        let bridge = MainThreadBridge { [weak self] in self?.commitSwitcherIfIdle() }
        let work = DispatchWorkItem { bridge() }
        switcherCommitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + switcherTimeout, execute: work)
    }

    private func cancelSwitcherTimeout() {
        switcherCommitWork?.cancel()
        switcherCommitWork = nil
    }

    private func touchSwitcherTimeout() {
        guard barSession?.isSwitcher == true else { return }
        if case .windows = barSession?.level { return }
        armSwitcherTimeout()
    }

    private func commitSwitcherIfIdle() {
        switcherCommitWork = nil
        guard barSession?.isSwitcher == true else { return }
        commitBarSession()
    }

    // MARK: - 面板生命周期

    /// 接管状态变化时启动或停止底部面板；固定列表变化则刷新现有模型。
    func configurationDidChange() {
        guard AppConfiguration.shared.isTakeoverEnabled else {
            endBarSession(collapse: false, suppressMouse: false)
            dismissSurge(animated: false)
            for state in screens.values {
                state.collapseDebounce?.cancel()
                state.panel.orderOut(nil)
                state.panel.close()
            }
            screens.removeAll()
            return
        }
        registry.refresh()
        rebuildPanels()
    }

    private func rebuildPanels() {
        guard AppConfiguration.shared.isTakeoverEnabled else { return }
        endBarSession(collapse: false, suppressMouse: false)
        dismissSurge(animated: false)
        for state in screens.values {
            state.collapseDebounce?.cancel()
            state.panel.orderOut(nil)
            state.panel.close()
        }
        screens.removeAll()

        for screen in NSScreen.screens {
            guard let displayID = displayID(of: screen) else { continue }
            let frame = barFrame(for: screen)
            let panel = TidePanel(contentRect: frame)
            let view = TideBarView(frame: NSRect(origin: .zero, size: frame.size))
            panel.contentView = view
            let state = ScreenState(screen: screen, panel: panel, view: view)
            view.onUserLaunch = { [weak self] in
                guard let self, self.barSession != nil else { return }
                self.cancelBarSession()
            }
            view.onSetHidden = { [weak self] identity, hidden in
                self?.registry.requestSetHidden(hidden, of: identity)
            }
            view.onTerminate = { [weak self] identity in
                self?.registry.requestTermination(of: identity)
            }
            view.onSetPinned = { [weak self, weak state] identity, pinned in
                guard let self, let state else { return }
                state.collapseHeldUntilMouseMoves = true
                self.cancelCollapse(state)
                self.registry.setPinned(pinned, for: identity)
            }
            view.onSurge = { [weak self, weak state] entry, iconFrame in
                guard let self, let state else { return }
                self.showSurge(entry: entry, state: state, iconFrame: iconFrame)
            }
            panel.orderFrontRegardless()
            screens[displayID] = state
        }
        behaviorDidChange()
    }

    // MARK: - 几何

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return id.uint32Value
    }

    private func barBottom(for screen: NSScreen) -> CGFloat {
        screen.frame.minY
    }

    private func barFrame(for screen: NSScreen) -> NSRect {
        let count = max(registry.entries.count, 1)
        let width = min(Layout.barHPadding * 2 + CGFloat(count) * Layout.iconSlot,
                        screen.frame.width * 0.9)
        return NSRect(x: screen.frame.midX - width / 2,
                      y: barBottom(for: screen),
                      width: width,
                      height: Layout.expandedHeight)
    }

    /// 收起态接近热区：胶囊外扩
    private func hotZone(for screen: NSScreen) -> NSRect {
        let capsule = NSRect(x: screen.frame.midX - Layout.capsuleWidth / 2,
                             y: barBottom(for: screen) + 2,
                             width: Layout.capsuleWidth,
                             height: Layout.capsuleHeight)
        return NSRect(x: capsule.minX - Layout.hotMarginX,
                      y: capsule.minY - Layout.hotMarginBelow,
                      width: capsule.width + Layout.hotMarginX * 2,
                      height: capsule.height + Layout.hotMarginBelow + Layout.hotMarginAbove)
    }

    // MARK: - 鼠标采样与状态机

    private func sampleMouse(isMovement: Bool) {
        if isMovement {
            for state in screens.values {
                state.collapseHeldUntilMouseMoves = false
                state.suppressExpandUntilMouseMove = false
            }
        }

        let now = CACurrentMediaTime()
        guard now - lastSampleTime >= Layout.mouseSampleThrottle else { return }
        lastSampleTime = now

        let location = NSEvent.mouseLocation
        for state in screens.values {
            let fullscreen = isFullscreenNow(state.screen)
            if applyFullscreenBehavior(state, fullscreen: fullscreen) {
                continue
            }
            if state.isExpanded {
                if state.collapseHeldUntilMouseMoves || isKeyboardHolding(state) {
                    cancelCollapse(state)
                    state.view.updateHover(atScreen: location)
                    continue
                }
                var keep = state.panel.frame.insetBy(dx: -Layout.keepMargin, dy: -Layout.keepMargin)
                // 潮涌在场时滞留区并入潮涌面板，鼠标在列表上不触发收起
                if let surge = surgePanel, surgeOriginDisplayID == displayID(of: state.screen) {
                    keep = keep.union(surge.frame)
                }
                if keep.contains(location) {
                    cancelCollapse(state)
                } else {
                    scheduleCollapse(state)
                }
                state.view.updateHover(atScreen: location)
            } else if !state.suppressExpandUntilMouseMove,
                      hotZone(for: state.screen).contains(location) {
                expand(state)
            }
        }
        updateSurgeHover(at: location)
    }

    /// 潮涌悬停与离场判定：命中面板内则行高亮 + 取消收起；否则重排收起防抖
    private func updateSurgeHover(at location: NSPoint) {
        guard let panel = surgePanel, panel.isVisible else { return }
        if barSession != nil { return }
        guard panel.frame.contains(location) else {
            scheduleSurgeDismiss()
            return
        }
        cancelSurgeDismiss()
        if let list = panel.contentView as? SurgeView {
            let local = list.convert(panel.convertPoint(fromScreen: location), from: nil)
            list.setHover(at: local)
        }
    }

    private func expand(_ state: ScreenState) {
        guard !state.hiddenForFullscreen else { return }
        state.suppressExpandUntilMouseMove = false
        state.isExpanded = true
        cancelCollapse(state)
        state.panel.ignoresMouseEvents = false
        // WindowServer 对非 key 窗口会降级玻璃的背景采样（退化为纯模糊）——
        // 展开期间保持 key，材质层全质量常驻；nonactivating 面板不夺取系统焦点
        state.panel.makeKey()
        // 挂起期间积压的终止通知可能尚未消费；展开即用户可见时刻，先同步对账
        registry.refresh()
        syncBadgeCadence()
        state.view.setExpanded(true, apps: registry.entries)
        NSLog("TideBar expanded on screen %u", displayID(of: state.screen) ?? 0)
    }

    private func collapse(_ state: ScreenState, animated: Bool, suppressReexpand: Bool = false) {
        state.isExpanded = false
        state.collapseHeldUntilMouseMoves = false
        if suppressReexpand { state.suppressExpandUntilMouseMove = true }
        cancelCollapse(state)
        if surgeOriginDisplayID == displayID(of: state.screen) {
            dismissSurge(animated: animated)
        }
        state.panel.ignoresMouseEvents = true
        state.view.setExpanded(false, immediate: !animated)
        syncBadgeCadence()
    }

    // MARK: 角标节奏与汐线脉冲

    /// 任一屏展开即加速角标轮询；全部收起则降频（足迹最小）
    private func syncBadgeCadence() {
        registry.setBadgeCadence(expanded: screens.values.contains { $0.isExpanded })
    }

    /// 新角标事件：收起态的汐线轻涌一次并启动持久波纹（展开即确认停住）。
    /// 展开态不脉冲，角标本身即反馈。
    private func badgePulse() {
        for state in screens.values where !state.isExpanded && !state.hiddenForFullscreen {
            state.view.pulseTideline()
            state.view.startTidelineRipple()
        }
    }

    /// 收起防抖：mouse exited 后延迟收起，期间 re-enter 取消
    private func scheduleCollapse(_ state: ScreenState) {
        guard state.collapseDebounce == nil else { return }
        let bridge = MainThreadBridge { [weak self, weak state] in
            guard let self, let state else { return }
            state.collapseDebounce = nil
            if state.isExpanded {
                self.collapse(state, animated: true)
            }
        }
        let work = DispatchWorkItem { bridge() }
        state.collapseDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.collapseDebounce, execute: work)
    }

    private func cancelCollapse(_ state: ScreenState) {
        state.collapseDebounce?.cancel()
        state.collapseDebounce = nil
    }

    // MARK: - 全屏

    func behaviorDidChange() {
        fullscreenCache.removeAll()
        for state in screens.values {
            _ = applyFullscreenBehavior(state, fullscreen: isFullscreenNow(state.screen))
        }
    }

    private func applyFullscreenBehavior(_ state: ScreenState, fullscreen: Bool) -> Bool {
        if fullscreen {
            switch AppConfiguration.shared.fullscreenBehavior {
            case .normal:
                if state.hiddenForFullscreen {
                    state.hiddenForFullscreen = false
                    state.panel.orderFrontRegardless()
                    state.panel.ignoresMouseEvents = !state.isExpanded
                }
                return false
            case .lineOnly:
                if state.hiddenForFullscreen {
                    state.hiddenForFullscreen = false
                    state.panel.orderFrontRegardless()
                    state.panel.ignoresMouseEvents = !state.isExpanded
                }
                if state.isExpanded { collapse(state, animated: false) }
                if barSession?.displayID == displayID(of: state.screen) {
                    endBarSession(collapse: false, suppressMouse: false)
                }
                return true
            case .hidden:
                if state.isExpanded { collapse(state, animated: false) }
                if barSession?.displayID == displayID(of: state.screen) {
                    endBarSession(collapse: false, suppressMouse: false)
                }
                state.panel.ignoresMouseEvents = true
                if !state.hiddenForFullscreen {
                    state.hiddenForFullscreen = true
                    state.panel.orderOut(nil)
                }
                return true
            }
        }

        if state.hiddenForFullscreen {
            state.hiddenForFullscreen = false
            state.panel.orderFrontRegardless()
            state.panel.ignoresMouseEvents = !state.isExpanded
        }
        return false
    }

    private func isFullscreenNow(_ screen: NSScreen) -> Bool {
        guard let key = displayID(of: screen) else { return false }
        let now = CACurrentMediaTime()
        if let cached = fullscreenCache[key], now - cached.time < Layout.fullscreenCacheTTL {
            return cached.value
        }
        let value = FullscreenDetector.isFullscreen(screen: screen)
        if fullscreenCache[key]?.value != value {
            NSLog("TideBar fullscreen state on screen %u -> %d", key, value ? 1 : 0)
        }
        fullscreenCache[key] = (now, value)
        return value
    }

    private func activeSpaceChanged() {
        fullscreenCache.removeAll()
        for state in screens.values {
            _ = applyFullscreenBehavior(state, fullscreen: isFullscreenNow(state.screen))
        }
    }

    func layoutDidChange() {
        for state in screens.values {
            state.appTransitionGeneration += 1
            state.view.refreshLayout()
            state.panel.setFrame(barFrame(for: state.screen), display: true)
        }
    }

    func languageDidChange() {
        (surgePanel?.contentView as? SurgeView)?.refreshLocalizedText()
    }

    func appearanceDidChange() {
        for state in screens.values {
            state.view.refreshAppearance()
        }
    }

    // MARK: - 数据与屏幕变更

    private func appsDidChange() {
        // 全部角标消失（如从横幅点开读完）：未确认提醒失去载体，波纹停住
        if !registry.entries.contains(where: { $0.badge != nil }) {
            for state in screens.values {
                state.view.stopTidelineRipple()
            }
        }
        // 条目消失、窗口知识降级或任意窗口内容变化时，现有潮涌模型即过期。
        if let surgeIdentity {
            let currentRevision = registry.entries.first(where: { $0.id == surgeIdentity })?.windowRevision
            if currentRevision != surgeWindowRevision {
                dismissSurge(animated: true)
            }
        }
        for state in screens.values {
            state.appTransitionGeneration += 1
            let generation = state.appTransitionGeneration
            let target = barFrame(for: state.screen)
            if state.isExpanded {
                let transition = state.view.refreshApps(registry.entries)
                if transition.hasRemovals, target.width < state.panel.frame.width {
                    // 离场项仍位于旧面板边缘；动画结束后再缩宽，避免被窗口边界裁掉。
                    DispatchQueue.main.asyncAfter(deadline: .now() + transition.removalDuration) {
                        [weak self, weak state] in
                        MainActor.assumeIsolated {
                            guard let self, let state,
                                  state.appTransitionGeneration == generation else { return }
                            if state.isExpanded {
                                self.animatePanel(state.panel, to: target)
                            } else {
                                state.panel.setFrame(target, display: true)
                            }
                        }
                    }
                } else {
                    // 扩宽与新增项上涌并行；新增项自身稍后显影，避免面板边缘裁剪。
                    animatePanel(state.panel, to: target)
                }
            } else {
                // 收起态窗口透明，宽度变化无声跟随
                state.panel.setFrame(target, display: true)
            }
        }
        syncKeyboardSelection()
    }

    private func syncKeyboardSelection() {
        guard var session = barSession,
              let state = screens[session.displayID] else {
            return
        }
        let applications = Set(registry.entries.map(\.identity))
        let windowIDs: Set<Int>?
        if case let .windows(identity) = session.level,
           let entry = registry.entries.first(where: { $0.identity == identity }),
           let windows = entry.windows {
            windowIDs = Set(windows.map(\.elementIdentifier))
        } else {
            windowIDs = nil
        }
        session.reconcile(applications: applications, windowIdentifiers: windowIDs)
        barSession = session
        state.view.setKeyboardSelection(session.selectedApplication)
        if case .windows = session.level {
            (surgePanel?.contentView as? SurgeView)?.setKeyboardSelection(session.selectedWindowIdentifier)
        }
    }

    private func animatePanel(_ panel: NSPanel, to frame: NSRect) {
        guard panel.frame != frame else { return }
        guard !Motion.shouldReduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.listResizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func screensChanged() {
        fullscreenCache.removeAll()
        rebuildPanels()
    }

    // MARK: - 潮涌

    private func showSurge(entry: AppEntry, state: ScreenState, iconFrame: NSRect,
                           fromKeyboard: Bool = false) {
        guard let windows = entry.windows, !windows.isEmpty else { return }
        dismissSurge(animated: false)

        let list = SurgeView(windows: windows, screen: state.screen, appIcon: entry.icon)
        list.onPick = { [weak self] window in
            guard let self else { return }
            self.dismissSurge(animated: true)
            if let app = entry.runningApp(for: window) {
                AXReader.raise(window, app: app)
            }
            if self.barSession != nil {
                self.cancelBarSession()
            }
        }

        let height = CGFloat(windows.count) * Layout.surgeRowHeight + Layout.surgeVPadding * 2
        let anchor = state.panel.convertToScreen(state.view.convert(iconFrame, to: nil))
        let visible = state.screen.visibleFrame
        let x = min(max(anchor.midX - Layout.surgeWidth / 2, visible.minX + 8),
                    visible.maxX - Layout.surgeWidth - 8)
        let y = state.panel.frame.maxY + Layout.surgeGap

        let panel = SurgePanel(contentRect: NSRect(x: x, y: y,
                                                   width: Layout.surgeWidth,
                                                   height: min(height, visible.maxY - y)))
        panel.contentView = list
        panel.orderFrontRegardless()
        panel.makeKey()   // 玻璃采样需要 key（同汐线展开的理由）
        surgePanel = panel
        surgeIdentity = entry.id
        surgeWindowRevision = entry.windowRevision
        surgeOriginDisplayID = displayID(of: state.screen)
        if fromKeyboard, var session = barSession {
            _ = session.enterWindows(for: entry.identity,
                                     firstWindowIdentifier: list.rowIdentifiers().first)
            barSession = session
            list.setKeyboardSelection(session.selectedWindowIdentifier)
        }
        list.riseRows()
        NSLog("TideBar surge shown for %@ (%d windows)", entry.id.bundleIdentifier, windows.count)
    }

    private func dismissSurge(animated: Bool) {
        cancelSurgeDismiss()
        guard let panel = surgePanel else { return }
        let originDisplayID = surgeOriginDisplayID
        surgePanel = nil
        surgeIdentity = nil
        surgeWindowRevision = nil
        surgeOriginDisplayID = nil
        // key 还给原屏的汐线面板（玻璃采样），若它仍展开
        if let id = originDisplayID, let state = screens[id], state.isExpanded {
            state.panel.makeKey()
        }
        if animated, let list = panel.contentView as? SurgeView {
            let total = list.dropRows()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = total
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    panel.close()
                }
            })
        } else {
            panel.orderOut(nil)
            panel.close()
        }
    }

    /// 离开潮涌面板后的收起防抖（与汐线收起同律）
    private func scheduleSurgeDismiss() {
        surgeDismissWork?.cancel()
        let bridge = MainThreadBridge { [weak self] in self?.dismissSurge(animated: true) }
        let work = DispatchWorkItem { bridge() }
        surgeDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.surgeDismissDebounce, execute: work)
    }

    private func cancelSurgeDismiss() {
        surgeDismissWork?.cancel()
        surgeDismissWork = nil
    }
}

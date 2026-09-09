import AppKit
import CoreGraphics
import TideBarCore

extension Notification.Name {
    /// AX 授权到位（设置/引导窗口的权限轮询在 false→true 边沿广播）：
    /// 主功能侧无权限即停摆不空等，靠此信号恢复观测
    static let axPermissionGranted = Notification.Name("TideBar.axPermissionGranted")
}

/// 编排者：每屏一个 panel；接近检测三重兜底（全局 monitor + local monitor + 统一调度器轮询）；
/// 展开/收起状态机与 300ms 防抖；全屏 Space 抑制展开
@MainActor
final class TideBarController {
    @MainActor
    private final class ScreenState {
        let screen: NSScreen
        let panel: TidePanel
        let clickPanel: TidelineClickPanel
        let view: TideBarView
        var isExpanded = false
        var collapseDebounce: DispatchWorkItem?
        var collapseHeldUntilMouseMoves = false
        /// 快捷键会话收起后，直到下一次真实鼠标移动前抑制热区重开。
        var suppressExpandUntilMouseMove = false
        /// 使延迟的面板缩宽在后续应用变化后自动失效。
        var appTransitionGeneration = 0
        var hiddenForFullscreen = false
        var effectiveFullscreenBehavior: FullscreenBehavior = .normal

        init(screen: NSScreen, panel: TidePanel, clickPanel: TidelineClickPanel, view: TideBarView) {
            self.screen = screen
            self.panel = panel
            self.clickPanel = clickPanel
            self.view = view
        }
    }

    private var screens: [CGDirectDisplayID: ScreenState] = [:]
    private let items = ItemRegistry()
    private var registry: AppRegistry { items.applications }
    private var navigationApplications: [AppEntry] { items.entries.compactMap(\.application) }
    private lazy var dragCoordinator = ItemDragCoordinator(registry: items)
    private static let mouseDemand = "mouse.proximity"
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyboardMonitor: Any?
    private var barSession: BarSessionState?
    private var switcherCommitWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var lastSampleTime: CFTimeInterval = 0
    private var lastSampledMouseLocation: NSPoint?
    private let fullscreenDetector = FullscreenDetector()
    private var fullscreenStates: [CGDirectDisplayID: FullscreenState] = [:]

    // 潮涌：同一时刻只存在一个，归属于触发它的屏
    private var surgePanel: SurgePanel?
    private var surgeIdentity: AppIdentity?
    private var surgeWindowRevision: WindowKnowledge<WindowContentRevision>?
    private var surgeOriginDisplayID: CGDirectDisplayID?
    private var surgeDismissWork: DispatchWorkItem?
    private var nameBubblePanel: NameBubblePanel?
    private var nameBubbleTarget: ItemID?
    private var nameBubbleShowWork: DispatchWorkItem?

    func start() {
        dragCoordinator.onBegin = { [weak self] in
            self?.endBarSession(collapse: false, suppressMouse: false)
            self?.hideNameBubble()
        }
        dragCoordinator.onMovement = { [weak self] in self?.sampleMouse(isMovement: true) }
        dragCoordinator.onSessionChange = { [weak self] in
            guard let self else { return }
            for state in self.screens.values { state.view.syncDragContext() }
        }
        dragCoordinator.allowsRemovalAt = { [weak self] point in
            guard let self, AppConfiguration.shared.isTakeoverEnabled, !self.screens.isEmpty else { return false }
            return self.screens.values.allSatisfy {
                !$0.panel.frame.insetBy(dx: -Layout.keepMargin, dy: -Layout.keepMargin).contains(point)
                    && !self.hotZone(for: $0.screen).contains(point)
            }
        }
        fullscreenDetector.onChange = { [weak self] in self?.applyFullscreenStates() }
        items.onChange = { [weak self] in self?.appsDidChange() }
        registry.onBadgePulse = { [weak self] name in self?.badgePulse(named: name) }
        registry.onApplicationsStarted = { [weak self] in self?.applicationsStarted() }
        items.start()
        if AppConfiguration.shared.isTakeoverEnabled {
            rebuildPanels()
        }

        // 接近检测：全局 monitor 为主，local monitor 兜自家激活，轮询兜静止光标。
        // 真实移动与轮询分流，菜单动作可保持展开直到用户再次移动鼠标。
        let movementSample = MainThreadBridge { [weak self] in self?.sampleMouse(isMovement: true) }
        let pollSample = MainThreadBridge { [weak self] in self?.sampleMouse(isMovement: false) }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            movementSample()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
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
        let activationBridge = MainThreadBridge { [weak self] in self?.behaviorDidChange() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            activationBridge()
        })

        let permissionBridge = MainThreadBridge { [weak self] in self?.axPermissionRestored() }
        observers.append(NotificationCenter.default.addObserver(
            forName: .axPermissionGranted, object: nil, queue: .main) { _ in
                permissionBridge()
            })

        NSLog("TideBar started: screens=%d", screens.count)
    }

    /// AX 授权到位（设置/引导窗口广播）：主功能无权限时停摆，这里一次性恢复。
    /// 重复广播无害——各 start 幂等，detector 已在跑则直接短路。
    private func axPermissionRestored() {
        NSLog("TideBar AX permission granted: window knowledge resuming")
        registry.activateWindowKnowledge()
        fullscreenDetector.permissionRestored()
    }

    func stop() {
        NSLog("TideBar stopped")
        dragCoordinator.invalidate(reason: "controller-stopped")
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        PollScheduler.shared.unregister(Self.mouseDemand)
        fullscreenDetector.reset()
        fullscreenDetector.onChange = nil
        for state in screens.values { state.clickPanel.setEnabled(false, above: state.panel) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        globalMonitor = nil
        localMonitor = nil
        keyboardMonitor = nil
        endBarSession(collapse: false, suppressMouse: false)
    }

    // MARK: - 快捷键与键盘导航

    func handleShortcut(_ action: ShortcutManager.Action) {
        guard !dragCoordinator.isDragging else { return }
        switch action {
        case .toggleBar:
            togglePersistentSession()
        case .cycleApplication:
            cycleSwitcherSession()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 系统拖拽拥有 Esc；不让潮涌或键盘会话抢先吞掉取消事件。
        guard !dragCoordinator.isDragging else { return false }
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
              allowsExpansion(state) else { return }
        if let session = barSession {
            guard session.displayID == displayID(of: state.screen) else { return }
            cancelBarSession()
            return
        }
        let openedBySession = !state.isExpanded
        if !state.isExpanded, !expand(state) { return }
        beginSession(mode: .persistent, on: state, openedBySession: openedBySession)
    }

    private func cycleSwitcherSession() {
        guard AppConfiguration.shared.isTakeoverEnabled else { return }
        let state: ScreenState?
        if let session = barSession {
            state = screens[session.displayID]
        } else {
            state = targetScreenState()
        }
        guard let state, allowsExpansion(state) else { return }

        if let session = barSession, session.isPersistent {
            moveApplication(by: 1)
            return
        }
        if barSession == nil {
            let openedBySession = !state.isExpanded
            if !state.isExpanded, !expand(state) { return }
            beginSession(mode: .switcher, on: state, openedBySession: openedBySession)
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
           navigationApplications.contains(where: { $0.identity == frontmost }) {
            return frontmost
        }
        return navigationApplications.first?.identity
    }

    private func beginSession(mode: BarSessionMode, on state: ScreenState,
                              openedBySession: Bool) {
        guard let displayID = displayID(of: state.screen) else { return }
        // frontmost 需在 makeKey 前读取：面板成为 key 后 TideBar 即为 frontmost
        let initialApplication = preferredInitialApplication()
        // 键盘会话拥有键盘：面板成为 key，方向键/回车才经 local monitor 进入本 app
        state.panel.makeKey()
        barSession = BarSessionState(mode: mode,
                                     displayID: displayID,
                                     openedBySession: openedBySession,
                                     firstApplication: initialApplication,
                                     now: CACurrentMediaTime(),
                                     timeout: switcherTimeout)
        state.view.setKeyboardSelection(barSession?.selectedApplication)
        if mode == .switcher { armSwitcherTimeout() }
        NSLog("TideBar keyboard session began (mode: %@, screen %u)",
              mode == .switcher ? "switcher" : "persistent", displayID)
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
        let applications = navigationApplications
        guard !applications.isEmpty, var session = barSession else { return }
        if case .windows = session.level {
            _ = session.escape()
            dismissSurge(animated: true)
        }
        let current = session.selectedApplication
        let index = current.flatMap { identity in applications.firstIndex { $0.identity == identity } } ?? 0
        let next = (index + offset + applications.count) % applications.count
        session.selectApplication(applications[next].identity,
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
              let entry = navigationApplications.first(where: { $0.identity == identity }),
              let iconFrame = state.view.iconFrame(for: identity) else { return }
        showSurge(entry: entry, state: state, iconFrame: iconFrame, fromKeyboard: true)
        cancelSwitcherTimeout()
    }

    private func moveWindow(by offset: Int) {
        guard let session = barSession,
              case let .windows(identity) = session.level,
              let entry = navigationApplications.first(where: { $0.identity == identity }),
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
            NSLog("TideBar keyboard session committed (level: inactive)")
            endBarSession(collapse: true, suppressMouse: true)
        case .applications:
            if let identity = session.selectedApplication,
               let entry = navigationApplications.first(where: { $0.identity == identity }) {
                NSLog("TideBar keyboard session committed (application: %@)", identity.bundleIdentifier)
                entry.primaryClick()
            }
            endBarSession(collapse: session.isPersistent || session.openedBySession,
                          suppressMouse: session.openedBySession)
        case .windows(let identity):
            NSLog("TideBar keyboard session committed (windows: %@)", identity.bundleIdentifier)
            if let entry = navigationApplications.first(where: { $0.identity == identity }),
               let identifier = session.selectedWindowIdentifier,
               let window = entry.windows?.first(where: { $0.elementIdentifier == identifier }),
               let app = entry.runningApp(for: window) {
                AXReader.raise(window, app: app)
            } else if let entry = navigationApplications.first(where: { $0.identity == identity }) {
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
        NSLog("TideBar keyboard session cancelled")
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
            dragCoordinator.invalidate(reason: "takeover-disabled")
            endBarSession(collapse: false, suppressMouse: false)
            dismissSurge(animated: false)
            hideNameBubble(animated: false)
            for state in screens.values {
                state.collapseDebounce?.cancel()
                state.clickPanel.setEnabled(false, above: state.panel)
                state.clickPanel.close()
                state.panel.orderOut(nil)
                state.panel.close()
            }
            screens.removeAll()
            fullscreenDetector.reset()
            fullscreenStates.removeAll()
            NSLog("TideBar takeover disabled: panels closed")
            return
        }
        items.refresh()
        rebuildPanels()
    }

    private func rebuildPanels() {
        guard AppConfiguration.shared.isTakeoverEnabled else { return }
        dragCoordinator.invalidate(reason: "panels-rebuilt")
        endBarSession(collapse: false, suppressMouse: false)
        dismissSurge(animated: false)
        hideNameBubble(animated: false)
        for state in screens.values {
            state.collapseDebounce?.cancel()
            state.clickPanel.setEnabled(false, above: state.panel)
            state.clickPanel.close()
            state.panel.orderOut(nil)
            state.panel.close()
        }
        screens.removeAll()

        for screen in NSScreen.screens {
            guard let displayID = displayID(of: screen) else { continue }
            let frame = barFrame(for: screen)
            let panel = TidePanel(contentRect: frame)
            let view = TideBarView(frame: NSRect(origin: .zero, size: frame.size))
            view.dragCoordinator = dragCoordinator
            panel.contentView = view
            let clickPanel = TidelineClickPanel(contentRect: tidelineClickFrame(for: screen))
            let state = ScreenState(screen: screen, panel: panel, clickPanel: clickPanel, view: view)
            view.onPreviewWidthChange = { [weak self, weak state] in
                guard let self, let state else { return }
                state.appTransitionGeneration += 1
                let target = self.barFrame(for: state.screen, extraSlots: state.view.extraPreviewSlots)
                self.animatePanel(state.panel, to: target)
            }
            clickPanel.onClick = { [weak self, weak state] in
                guard let self, let state, !state.isExpanded else { return }
                self.expand(state, clickedTideline: true)
            }
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
                self.items.setPinned(pinned, for: identity)
            }
            view.onSurge = { [weak self, weak state] entry, iconFrame in
                guard let self, let state else { return }
                self.showSurge(entry: entry, state: state, iconFrame: iconFrame)
            }
            view.onHoverItem = { [weak self, weak state] entry, iconFrame in
                guard let self, let state else { return }
                self.updateNameBubble(entry: entry, iconFrame: iconFrame, state: state)
            }
            view.onHoverClear = { [weak self] in self?.hideNameBubble() }
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

    private func barFrame(for screen: NSScreen, extraSlots: Int = 0) -> NSRect {
        let count = max(items.entries.count + extraSlots, 1)
        let width = min(Layout.barHPadding * 2 + CGFloat(count) * Layout.iconSlot,
                        screen.frame.width * 0.9)
        return NSRect(x: screen.frame.midX - width / 2,
                      y: barBottom(for: screen),
                      width: width,
                      height: Layout.expandedHeight)
    }

    private func tidelineClickFrame(for screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - Layout.tidelineClickWidth / 2,
               y: barBottom(for: screen),
               width: Layout.tidelineClickWidth,
               height: Layout.tidelineClickHeight)
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
        let location = NSEvent.mouseLocation
        // 拖拽追踪不保证 mouseMoved 送达；轮询只在左键按住且位置确实变化时
        // 补足真实移动语义，静止轮询仍不能解除菜单保持或键盘抑制。
        let dragMoved = NSEvent.pressedMouseButtons & 1 != 0
            && lastSampledMouseLocation.map { $0 != location } == true
        lastSampledMouseLocation = location
        if isMovement || dragMoved {
            for state in screens.values {
                state.collapseHeldUntilMouseMoves = false
                state.suppressExpandUntilMouseMove = false
            }
        }

        let now = CACurrentMediaTime()
        guard now - lastSampleTime >= Layout.mouseSampleThrottle else { return }
        lastSampleTime = now

        fullscreenDetector.refresh(screens: screens.values.map(\.screen))
        for state in screens.values {
            let fullscreen = fullscreenState(state.screen)
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
            } else if state.effectiveFullscreenBehavior == .normal,
                      !state.suppressExpandUntilMouseMove,
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

    @discardableResult
    private func expand(_ state: ScreenState, clickedTideline: Bool = false) -> Bool {
        guard allowsExpansion(state, clickedTideline: clickedTideline) else { return false }
        state.suppressExpandUntilMouseMove = false
        state.isExpanded = true
        syncTidelineClickTarget(state)
        cancelCollapse(state)
        state.panel.ignoresMouseEvents = false
        // 挂起期间积压的终止通知可能尚未消费；展开即用户可见时刻，先同步对账
        items.refresh()
        // 重读窗口 frame→屏归属：跨屏移动发生在收起期无通知，展开时拉一次新鲜值
        registry.refreshWindows()
        syncBadgeCadence()
        state.view.setExpanded(true, apps: items.entries)
        NSLog("TideBar expanded on screen %u", displayID(of: state.screen) ?? 0)
        return true
    }

    private func collapse(_ state: ScreenState, animated: Bool, suppressReexpand: Bool = false) {
        state.isExpanded = false
        state.collapseHeldUntilMouseMoves = false
        if suppressReexpand { state.suppressExpandUntilMouseMove = true }
        cancelCollapse(state)
        hideNameBubble(animated: animated)
        if surgeOriginDisplayID == displayID(of: state.screen) {
            dismissSurge(animated: animated)
        }
        state.panel.ignoresMouseEvents = true
        state.view.setExpanded(false, immediate: !animated)
        syncTidelineClickTarget(state)
        syncBadgeCadence()
        NSLog("TideBar collapsed on screen %u (animated: %d)", displayID(of: state.screen) ?? 0, animated)
    }

    // MARK: 展开态节奏与汐线脉冲

    /// 任一屏展开即切展开节奏（角标加速轮询、窗口 title 恢复维护）；
    /// 全部收起则降频/停更（足迹最小）
    private func syncBadgeCadence() {
        let anyExpanded = screens.values.contains { $0.isExpanded }
        registry.setBadgeCadence(expanded: anyExpanded)
        registry.setWindowCadence(expanded: anyExpanded)
    }

    /// 逻辑启动只在当前可见的折叠汐线上反馈，不积压到下次折叠或显示。
    private func applicationsStarted() {
        let targets = screens.values.filter { !$0.isExpanded && !$0.hiddenForFullscreen }
        if !targets.isEmpty {
            NSLog("TideBar applications started: intake wave on %d screen(s)", targets.count)
        }
        for state in targets {
            state.view.intakeApplications()
        }
    }

    /// 新角标事件：收起态的汐线轻涌一次并启动持久波纹（展开即确认停住）。
    /// 展开态不脉冲，角标本身即反馈。
    private func badgePulse(named name: String) {
        NSLog("TideBar badge pulse: %@", name)
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
        fullscreenDetector.refresh(screens: screens.values.map(\.screen), force: true)
        applyFullscreenStates()
    }

    private func applyFullscreenStates() {
        for state in screens.values {
            _ = applyFullscreenBehavior(state, fullscreen: fullscreenState(state.screen))
        }
    }

    private func allowsExpansion(_ state: ScreenState, clickedTideline: Bool = false) -> Bool {
        fullscreenDetector.refresh(screens: screens.values.map(\.screen))
        _ = applyFullscreenBehavior(state, fullscreen: fullscreenState(state.screen))
        return state.effectiveFullscreenBehavior.allowsExpansion(isExpanded: state.isExpanded,
                                                                 clickedTideline: clickedTideline)
    }

    /// 返回 true 表示整屏面板隐藏，不参与鼠标采样；点击模式展开后仍走正常离场收起。
    private func applyFullscreenBehavior(_ state: ScreenState, fullscreen: FullscreenState) -> Bool {
        // 持续未知时保持普通交互可用；检测真值仍为 unknown。
        let behavior = fullscreen == .fullscreen ? AppConfiguration.shared.fullscreenBehavior : .normal
        let previous = state.effectiveFullscreenBehavior
        state.effectiveFullscreenBehavior = behavior
        if behavior != previous, behavior != .normal {
            dragCoordinator.invalidate(reason: "fullscreen-policy-changed")
        }

        if behavior == .hidden {
            if state.isExpanded { collapse(state, animated: false) }
            if barSession?.displayID == displayID(of: state.screen) {
                endBarSession(collapse: false, suppressMouse: false)
            }
            state.panel.ignoresMouseEvents = true
            if !state.hiddenForFullscreen {
                state.hiddenForFullscreen = true
                state.view.cancelApplicationIntake()
                state.panel.orderOut(nil)
            }
        } else {
            if state.hiddenForFullscreen {
                state.hiddenForFullscreen = false
                state.panel.orderFrontRegardless()
                state.panel.ignoresMouseEvents = !state.isExpanded
            }
            // 只在进入点击模式时收起；成功点击后的展开不能被后续全屏轮询撤销。
            if behavior == .clickToExpand, previous != .clickToExpand {
                if state.isExpanded { collapse(state, animated: false) }
                if barSession?.displayID == displayID(of: state.screen) {
                    endBarSession(collapse: false, suppressMouse: false)
                }
            }
        }
        syncTidelineClickTarget(state)
        return behavior == .hidden
    }

    private func syncTidelineClickTarget(_ state: ScreenState) {
        state.clickPanel.setEnabled(state.effectiveFullscreenBehavior == .clickToExpand
                                    && !state.isExpanded && !state.hiddenForFullscreen,
                                    above: state.panel)
    }

    private func fullscreenState(_ screen: NSScreen) -> FullscreenState {
        guard let key = displayID(of: screen) else { return .unknown }
        let value = fullscreenDetector.state(on: key)
        if fullscreenStates[key] != value {
            NSLog("TideBar fullscreen state on screen %u -> %@", key, value.rawValue)
            fullscreenStates[key] = value
        }
        return value
    }

    private func activeSpaceChanged() {
        dragCoordinator.invalidate(reason: "space-changed")
        fullscreenDetector.invalidateContext()
        behaviorDidChange()
    }

    func layoutDidChange() {
        dragCoordinator.invalidate(reason: "layout-changed")
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
            let currentRevision = navigationApplications.first(where: { $0.id == surgeIdentity })?.windowRevision
            if currentRevision != surgeWindowRevision {
                dismissSurge(animated: true)
            }
        }
        for state in screens.values {
            state.appTransitionGeneration += 1
            let generation = state.appTransitionGeneration
            if state.isExpanded {
                let transition = state.view.refreshApps(items.entries)
                let target = barFrame(for: state.screen, extraSlots: state.view.extraPreviewSlots)
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
                // TidePanel 同步窗口与内容布局，收起态汐线保持屏幕居中。
                state.panel.setFrame(barFrame(for: state.screen), display: true)
            }
        }
        syncKeyboardSelection()
    }

    private func syncKeyboardSelection() {
        guard var session = barSession,
              let state = screens[session.displayID] else {
            return
        }
        let applications = Set(navigationApplications.map(\.identity))
        let windowIDs: Set<Int>?
        if case let .windows(identity) = session.level,
           let entry = navigationApplications.first(where: { $0.identity == identity }),
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
        fullscreenDetector.reset()
        fullscreenStates.removeAll()
        rebuildPanels()
        NSLog("TideBar screens changed: %d screen(s)", screens.count)
    }

    // MARK: - 潮涌

    private func showSurge(entry: AppEntry, state: ScreenState, iconFrame: NSRect,
                           fromKeyboard: Bool = false) {
        guard allowsExpansion(state),
              let windows = entry.windows, !windows.isEmpty else { return }
        dismissSurge(animated: false)
        hideNameBubble()

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
        surgePanel = nil
        surgeIdentity = nil
        surgeWindowRevision = nil
        surgeOriginDisplayID = nil
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

    // MARK: - 名字气泡

    /// 悬停目标变化：首入延迟出泡，泡在场时换目标即时切换（原生 Dock 同律）
    private func updateNameBubble(entry: ItemEntry, iconFrame: NSRect, state: ScreenState) {
        guard nameBubbleTarget != entry.id else { return }
        nameBubbleTarget = entry.id
        nameBubbleShowWork?.cancel()
        nameBubbleShowWork = nil
        if nameBubblePanel?.isVisible == true {
            presentNameBubble(entry: entry, iconFrame: iconFrame, state: state)
            return
        }
        let bridge = MainThreadBridge { [weak self, weak state] in
            guard let self, let state else { return }
            guard self.nameBubbleTarget == entry.id else { return }
            self.presentNameBubble(entry: entry, iconFrame: iconFrame, state: state)
        }
        let work = DispatchWorkItem { bridge() }
        nameBubbleShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.nameBubbleShowDelay, execute: work)
    }

    private func presentNameBubble(entry: ItemEntry, iconFrame: NSRect, state: ScreenState) {
        hideNameBubble(animated: false)
        let content = NameBubbleView(name: entry.name)
        let size = NSSize(width: NameBubbleView.preferredWidth(for: entry.name),
                          height: NameBubbleView.preferredHeight)
        let anchor = state.panel.convertToScreen(state.view.convert(iconFrame, to: nil))
        let visible = state.screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8),
                    visible.maxX - size.width - 8)
        let y = state.panel.frame.maxY + Layout.nameBubbleGap
        let panel = NameBubblePanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size))
        panel.contentView = content
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        content.setScrollingAllowed(true)
        nameBubblePanel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.shouldReduceMotion
                ? Motion.reducedMotionFadeDuration : Layout.nameBubbleFadeDuration
            panel.animator().alphaValue = 1
        }
    }

    private func hideNameBubble(animated: Bool = true) {
        nameBubbleShowWork?.cancel()
        nameBubbleShowWork = nil
        nameBubbleTarget = nil
        guard let panel = nameBubblePanel else { return }
        nameBubblePanel = nil
        (panel.contentView as? NameBubbleView)?.setScrollingAllowed(false)
        guard animated else {
            panel.orderOut(nil)
            panel.close()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.shouldReduceMotion
                ? Motion.reducedMotionFadeDuration : Layout.nameBubbleFadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.close()
            }
        })
    }
}

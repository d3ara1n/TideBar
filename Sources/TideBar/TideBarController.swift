import AppKit
import CoreGraphics
import TideBarCore

/// 编排者：每屏一个 panel；接近检测三重兜底（全局 monitor + local monitor + 低频轮询）；
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
        /// 使延迟的面板缩宽在后续应用变化后自动失效。
        var appTransitionGeneration = 0

        init(screen: NSScreen, panel: TidePanel, view: TideBarView) {
            self.screen = screen
            self.panel = panel
            self.view = view
        }
    }

    private var screens: [CGDirectDisplayID: ScreenState] = [:]
    private let registry = AppRegistry()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
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
        registry.start()
        rebuildPanels()

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
        pollTimer = Timer.scheduledTimer(withTimeInterval: Layout.pollInterval, repeats: true) { _ in
            pollSample()
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

        NSLog("TideBar started: offsetY=%.0f, screens=%d", AppConfiguration.shared.verticalOffset, screens.count)
    }

    // MARK: - 面板生命周期

    /// 结构配置变化先刷新应用模型，再按最新配置重建面板；固定列表单独原地刷新。
    func configurationDidChange() {
        registry.refresh()
        rebuildPanels()
    }

    private func rebuildPanels() {
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
            view.onHide = { [weak self] identity in
                self?.registry.requestHide(of: identity)
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
    }

    // MARK: - 几何

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return id.uint32Value
    }

    private func barBottom(for screen: NSScreen) -> CGFloat {
        screen.frame.minY + AppConfiguration.shared.verticalOffset
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
            }
        }

        let now = CACurrentMediaTime()
        guard now - lastSampleTime >= Layout.mouseSampleThrottle else { return }
        lastSampleTime = now

        let location = NSEvent.mouseLocation
        for state in screens.values {
            if isFullscreenNow(state.screen) {
                if state.isExpanded {
                    collapse(state, animated: false)
                }
                continue
            }
            if state.isExpanded {
                if state.collapseHeldUntilMouseMoves {
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
            } else if hotZone(for: state.screen).contains(location) {
                expand(state)
            }
        }
        updateSurgeHover(at: location)
    }

    /// 潮涌悬停与离场判定：命中面板内则行高亮 + 取消收起；否则重排收起防抖
    private func updateSurgeHover(at location: NSPoint) {
        guard let panel = surgePanel, panel.isVisible else { return }
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
        state.isExpanded = true
        cancelCollapse(state)
        state.panel.ignoresMouseEvents = false
        // WindowServer 对非 key 窗口会降级玻璃的背景采样（退化为纯模糊）——
        // 展开期间保持 key，材质层全质量常驻；nonactivating 面板不夺取系统焦点
        state.panel.makeKey()
        state.view.setExpanded(true, apps: registry.entries)
        NSLog("TideBar expanded on screen %u", displayID(of: state.screen) ?? 0)
    }

    private func collapse(_ state: ScreenState, animated: Bool) {
        state.isExpanded = false
        state.collapseHeldUntilMouseMoves = false
        cancelCollapse(state)
        if surgeOriginDisplayID == displayID(of: state.screen) {
            dismissSurge(animated: animated)
        }
        state.panel.ignoresMouseEvents = true
        state.view.setExpanded(false, immediate: !animated)
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
        for state in screens.values where state.isExpanded && isFullscreenNow(state.screen) {
            collapse(state, animated: false)
        }
    }

    // MARK: - 数据与屏幕变更

    private func appsDidChange() {
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
    }

    private func animatePanel(_ panel: NSPanel, to frame: NSRect) {
        guard panel.frame != frame else { return }
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

    private func showSurge(entry: AppEntry, state: ScreenState, iconFrame: NSRect) {
        guard let windows = entry.windows, !windows.isEmpty else { return }
        dismissSurge(animated: false)

        let list = SurgeView(windows: windows, screen: state.screen, appIcon: entry.icon)
        list.onPick = { [weak self] window in
            self?.dismissSurge(animated: true)
            if let app = entry.runningApp(for: window) {
                AXReader.raise(window, app: app)
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

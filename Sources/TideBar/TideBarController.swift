import AppKit
import CoreGraphics

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

    func start() {
        registry.onChange = { [weak self] in self?.appsDidChange() }
        registry.start()
        rebuildPanels()

        // 接近检测：全局 monitor 为主，local monitor 兜自家激活，轮询兜静止光标（decisions 修订条目 3）
        let sample = MainThreadBridge { [weak self] in self?.sampleMouse() }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            sample()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            sample()
            return event
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Layout.pollInterval, repeats: true) { _ in
            sample()
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

        NSLog("TideBar started: offsetY=%.0f, screens=%d", Layout.offsetY, screens.count)
    }

    // MARK: - 面板生命周期

    private func rebuildPanels() {
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
            panel.orderFrontRegardless()
            screens[displayID] = ScreenState(screen: screen, panel: panel, view: view)
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
        screen.frame.minY + Layout.offsetY
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

    private func sampleMouse() {
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
                let keep = state.panel.frame.insetBy(dx: -Layout.keepMargin, dy: -Layout.keepMargin)
                if keep.contains(location) {
                    cancelCollapse(state)
                } else {
                    scheduleCollapse(state)
                }
            } else if hotZone(for: state.screen).contains(location) {
                expand(state)
            }
        }
    }

    private func expand(_ state: ScreenState) {
        state.isExpanded = true
        cancelCollapse(state)
        state.panel.ignoresMouseEvents = false
        state.panel.hasShadow = true
        state.view.setExpanded(true, apps: registry.entries)
        NSLog("TideBar expanded on screen %u", displayID(of: state.screen) ?? 0)
    }

    private func collapse(_ state: ScreenState, animated: Bool) {
        state.isExpanded = false
        cancelCollapse(state)
        state.panel.ignoresMouseEvents = true
        state.panel.hasShadow = false
        state.view.setExpanded(false, immediate: !animated)
    }

    /// 收起防抖：mouse exited 后延迟收起，期间 re-enter 取消（decisions「交互与技术约定」）
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
        for state in screens.values {
            let target = barFrame(for: state.screen)
            if state.isExpanded {
                state.view.refreshApps(registry.entries)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    state.panel.animator().setFrame(target, display: true)
                }
            } else {
                // 收起态窗口透明，宽度变化无声跟随
                state.panel.setFrame(target, display: true)
            }
        }
    }

    private func screensChanged() {
        fullscreenCache.removeAll()
        rebuildPanels()
    }
}

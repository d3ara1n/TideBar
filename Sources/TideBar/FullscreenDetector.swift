import AppKit
import ApplicationServices
import CoreGraphics

/// 按屏幕采集 AXFullScreen；由控制器现有轮询驱动，跨进程读取全部在后台串行执行。
@MainActor
final class FullscreenDetector {
    private let readQueue = DispatchQueue(label: "dev.dearain.TideBar.fullscreen", qos: .userInitiated)
    private var displays: [FullscreenDisplay] = []
    private var observations = FullscreenObservations()
    private var lastRequest: CFTimeInterval?
    private var busy = false
    private var samplingOffset = 0
    /// 权限丢失后停摆：无权限不再逐 tick 清理与广播，恢复靠授权边沿广播
    private var permissionLost = false
    var onChange: (() -> Void)?

    func state(on displayID: CGDirectDisplayID) -> FullscreenState {
        observations.state(on: displayID, at: CACurrentMediaTime(),
                           gracePeriod: Layout.fullscreenFailureGracePeriod)
    }

    /// 设置、Space、前台应用与显示器变更使在途快照失效；繁忙时只保留一次待刷新需求。
    func refresh(screens: [NSScreen], force: Bool = false) {
        let targets = screens.compactMap { screen -> FullscreenDisplay? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
                return nil
            }
            return FullscreenDisplay(id: id, bounds: CGDisplayBounds(id))
        }.sorted { $0.id < $1.id }
        if force || targets != displays {
            observations.invalidate(clearConfirmed: targets != displays)
            lastRequest = nil
            displays = targets
        }
        guard !busy, !displays.isEmpty else { return }
        let now = CACurrentMediaTime()
        if let lastRequest, now - lastRequest < Layout.fullscreenPollInterval { return }
        lastRequest = now
        guard AXIsProcessTrusted() else {
            // 主功能不空等授权：丢失瞬间清理一次并停摆，不逐 tick 空转；
            // 恢复由设置/引导窗口的授权边沿广播驱动（permissionRestored）
            if !permissionLost {
                permissionLost = true
                observations.invalidate(clearConfirmed: true)
                onChange?()
                NSLog("TideBar fullscreen detection paused: accessibility not granted")
            }
            return
        }
        let excludedPIDs = Set([ProcessInfo.processInfo.processIdentifier]
            + NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == "com.apple.dock" }
                .map(\.processIdentifier))
        let requestGeneration = observations.generation
        let offset = samplingOffset
        samplingOffset += 1
        busy = true
        readQueue.async { [weak self] in
            let snapshot = Self.read(displays: targets, excludedPIDs: excludedPIDs, samplingOffset: offset)
            MainThreadBridge { [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.observations.record(snapshot, at: now, generation: requestGeneration) else {
                    // 过期结果不落地；下一轮读取使用最新的屏幕集合。
                    if !self.displays.isEmpty { self.refresh(screens: NSScreen.screens) }
                    return
                }
                self.onChange?()
            }.call()
        }
    }

    func invalidateContext() {
        observations.invalidate(clearConfirmed: true)
        lastRequest = nil
    }

    /// 授权恢复（设置/引导窗口广播）：解除停摆，清节流让下一拍立即重读
    func permissionRestored() {
        guard permissionLost else { return }
        permissionLost = false
        lastRequest = nil
    }

    func reset() {
        invalidateContext()
        displays = []
    }

    // MARK: 后台采集

    nonisolated private static func read(displays: [FullscreenDisplay], excludedPIDs: Set<pid_t>,
                                        samplingOffset: Int)
        -> [CGDirectDisplayID: FullscreenState] {
        guard let before = visibleWindows(excluding: excludedPIDs) else { return [:] }
        let visible = before.filter { FullscreenResolver.display(for: $0.frame, in: displays) != nil }
        var windowsByPID: [pid_t: [AXFullscreenWindow]] = [:]
        let pids = Set(visible.map(\.pid)).sorted()
        // 限制单轮工作量并轮换起点，避免慢进程使排序靠后的应用始终得不到采样。
        let deadline = CACurrentMediaTime() + 1
        for index in pids.indices {
            guard CACurrentMediaTime() < deadline else { break }
            let pid = pids[(index + (samplingOffset % pids.count)) % pids.count]
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            guard let elements = AXReader.readWindows(of: app) else { continue }
            let appDeadline = min(deadline, CACurrentMediaTime() + 0.25)
            var snapshots: [AXFullscreenWindow] = []
            var complete = true
            for element in elements {
                guard CACurrentMediaTime() < appDeadline else {
                    complete = false
                    break
                }
                AXUIElementSetMessagingTimeout(element, 0.1)
                if AXReader.readBool(element, kAXMinimizedAttribute as String) == true { continue }
                let frame = AXReader.readFrame(element)
                let fullscreen = AXReader.readBool(element, "AXFullScreen")
                snapshots.append(AXFullscreenWindow(frame: frame, isFullscreen: fullscreen))
            }
            if complete { windowsByPID[pid] = snapshots }
        }
        // AX 读取期间可能切换 Space / 关闭窗口 / 移动窗口；按屏幕丢弃不一致结果。
        guard let after = visibleWindows(excluding: excludedPIDs) else { return [:] }
        return FullscreenResolver.resolve(displays: displays, visibleWindows: visible,
                                          windowsByPID: windowsByPID, currentVisibleWindows: after)
    }

    nonisolated private static func visibleWindows(excluding excludedPIDs: Set<pid_t>)
        -> [VisibleFullscreenWindow]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return nil }
        var windows: [VisibleFullscreenWindow] = []
        for window in list {
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            if excludedPIDs.contains(pid) { continue }
            if (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 0 { continue }
            guard let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return nil }
            windows.append(VisibleFullscreenWindow(id: id, pid: pid, frame: frame))
        }
        // z-order 变化不改变窗口是否在屏；稳定顺序用于采集前后的一致性校验。
        return windows.sorted { $0.id < $1.id }
    }
}

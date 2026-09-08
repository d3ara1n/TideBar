import CoreGraphics
import Foundation

/// 未授权、属性缺失、窗口无法匹配或读取超时均为未知，不等同于非全屏。
enum FullscreenState: String, Sendable {
    case unknown
    case windowed
    case fullscreen
}

struct FullscreenDisplay: Equatable, Sendable {
    let id: CGDirectDisplayID
    /// 与 CGWindow / AXPosition 同属左上原点的全局坐标系。
    let bounds: CGRect
}

struct VisibleFullscreenWindow: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

struct AXFullscreenWindow: Sendable {
    let frame: CGRect?
    let isFullscreen: Bool?
}

/// CG 只提供可见性和屏幕归属，AXFullScreen 是全屏状态的唯一来源。
enum FullscreenResolver {
    static func resolve(displays: [FullscreenDisplay], visibleWindows: [VisibleFullscreenWindow],
                        windowsByPID: [pid_t: [AXFullscreenWindow]],
                        currentVisibleWindows: [VisibleFullscreenWindow]? = nil) -> [CGDirectDisplayID: FullscreenState] {
        var states = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, FullscreenState.windowed) })
        for window in visibleWindows {
            guard let display = display(for: window.frame, in: displays) else { continue }
            let state = match(window, against: windowsByPID[window.pid] ?? [])
            // 任一已确认全屏窗口即成立（包括 Split View）；否则未知不能被普通窗口覆盖。
            if state == .fullscreen || states[display.id] == .fullscreen {
                states[display.id] = .fullscreen
            } else if state == .unknown {
                states[display.id] = .unknown
            }
        }
        if let currentVisibleWindows {
            for target in displays {
                let before = visibleWindows.filter { display(for: $0.frame, in: displays)?.id == target.id }
                let after = currentVisibleWindows.filter { display(for: $0.frame, in: displays)?.id == target.id }
                if before.sorted(by: { $0.id < $1.id }) != after.sorted(by: { $0.id < $1.id }) {
                    states[target.id] = .unknown
                }
            }
        }
        return states
    }

    static func display(for frame: CGRect, in displays: [FullscreenDisplay]) -> FullscreenDisplay? {
        displays.compactMap { display -> (FullscreenDisplay, CGFloat)? in
            let intersection = frame.intersection(display.bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            return (display, intersection.width * intersection.height)
        }.max { $0.1 < $1.1 }?.0
    }

    private static func match(_ window: VisibleFullscreenWindow,
                              against candidates: [AXFullscreenWindow]) -> FullscreenState {
        // 无需窗口标题或私有窗口 ID API；坐标只用于匹配同一窗口，容忍坐标取整。
        let matches = candidates.filter { candidate in
            guard let frame = candidate.frame else { return false }
            return abs(frame.minX - window.frame.minX) <= 1
                && abs(frame.minY - window.frame.minY) <= 1
                && abs(frame.width - window.frame.width) <= 1
                && abs(frame.height - window.frame.height) <= 1
        }
        guard !matches.isEmpty else { return .unknown }
        if matches.allSatisfy({ $0.isFullscreen == true }) { return .fullscreen }
        if matches.allSatisfy({ $0.isFullscreen == false }) { return .windowed }
        // 同进程不同 Space 的同尺寸窗口无法唯一匹配时，保留未知。
        return .unknown
    }
}

/// 观察值绑定采集上下文；重新采样可以保留确认值，切换 Space / 屏幕则必须清空。
struct FullscreenObservations {
    private(set) var generation = 0
    private var values: [CGDirectDisplayID: FullscreenObservation] = [:]

    mutating func invalidate(clearConfirmed: Bool) {
        generation += 1
        if clearConfirmed { values.removeAll() }
    }

    @discardableResult
    mutating func record(_ states: [CGDirectDisplayID: FullscreenState], at time: CFTimeInterval,
                         generation requestGeneration: Int) -> Bool {
        guard requestGeneration == generation else { return false }
        for (id, state) in states {
            values[id, default: FullscreenObservation()].record(state, at: time)
        }
        return true
    }

    func state(on id: CGDirectDisplayID, at time: CFTimeInterval,
               gracePeriod: TimeInterval) -> FullscreenState {
        values[id]?.state(at: time, gracePeriod: gracePeriod) ?? .unknown
    }
}

/// 短暂失败保留最近一次确认；超期后恢复未知，避免不可读应用让面板永久隐藏。
struct FullscreenObservation {
    private var confirmed: (state: FullscreenState, time: CFTimeInterval)?

    mutating func record(_ state: FullscreenState, at time: CFTimeInterval) {
        if state != .unknown { confirmed = (state, time) }
    }

    func state(at time: CFTimeInterval, gracePeriod: TimeInterval) -> FullscreenState {
        guard let confirmed, time - confirmed.time <= gracePeriod else { return .unknown }
        return confirmed.state
    }
}

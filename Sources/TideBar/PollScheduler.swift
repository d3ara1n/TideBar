import Foundation
import QuartzCore

/// 统一轮询调度器：单一基频 Timer 承载全部常驻轮询需求。
///
/// - 需求按名注册（重名覆盖），各自持有间隔与到期时刻；基频取全体最小间隔，
///   需求增删或改间隔自动重算 Timer。
/// - 分片：新需求按注册序错开四分之一基频起步，削弱多需求在同一 tick 突发叠加；
///   到期即跑、从执行时刻重新排程，主线程繁忙导致的迟到不积压。
/// - 主线程 tick 只做触发（亚毫秒级），重活（AX 读取等）由需求自行调度后台队列，
///   经 `MainThreadBridge` 回主线程改模型。
/// - 容差 = 基频/5，允许系统合并唤醒；轮询是兜底与新鲜度通道，不承诺精确定时。
@MainActor
final class PollScheduler {
    static let shared = PollScheduler()

    private struct Demand {
        let name: String
        var interval: TimeInterval
        var nextDue: CFTimeInterval
        let work: @MainActor () -> Void
    }

    private var demands: [String: Demand] = [:]
    private var timer: Timer?
    private var phaseCursor = 0

    /// 注册（或覆盖）一个轮询需求。首个到期 ≈ 注册时刻 + 相位偏移。
    func register(_ name: String, interval: TimeInterval, work: @escaping @MainActor () -> Void) {
        let base = min(interval, demands.values.map(\.interval).min() ?? interval)
        let offset = Double(phaseCursor % 4) * base / 4
        phaseCursor += 1
        demands[name] = Demand(name: name,
                               interval: interval,
                               nextDue: CACurrentMediaTime() + offset,
                               work: work)
        rebuildTimer()
    }

    /// 调整间隔：收紧立即生效（收起→展开要新鲜），放宽让既有节奏自然过渡。
    func updateInterval(_ name: String, interval: TimeInterval) {
        guard var demand = demands[name] else { return }
        guard demand.interval != interval else { return }
        demand.interval = interval
        let now = CACurrentMediaTime()
        if demand.nextDue > now + interval {
            demand.nextDue = now + interval
        }
        demands[name] = demand
        rebuildTimer()
    }

    func unregister(_ name: String) {
        demands.removeValue(forKey: name)
        rebuildTimer()
    }

    private func rebuildTimer() {
        timer?.invalidate()
        timer = nil
        guard let base = demands.values.map(\.interval).min() else { return }
        let sweep = MainThreadBridge { [weak self] in self?.sweep() }
        let timer = Timer(timeInterval: base, repeats: true) { _ in
            sweep()
        }
        timer.tolerance = base / 5
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }

    private func sweep() {
        let now = CACurrentMediaTime()
        let due = demands.values.filter { $0.nextDue <= now }
        guard !due.isEmpty else { return }
        // 先统一排下次到期再执行 work——work 内部允许再操作调度器（注册/注销/改间隔）
        for demand in due {
            demands[demand.name]?.nextDue = now + demand.interval
        }
        for demand in due {
            demand.work()
        }
    }
}

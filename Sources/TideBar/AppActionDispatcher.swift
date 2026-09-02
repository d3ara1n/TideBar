import AppKit
import TideBarCore

/// 应用级系统动作的唯一入口。UI 能力只负责展示，执行前再次按统一身份校验策略。
@MainActor
enum AppActionDispatcher {
    static func terminate(_ entry: AppEntry) {
        let behavior = AppBehavior.resolve(for: entry.identity)
        guard entry.canTerminate, behavior.canTerminate else {
            NSLog("TideBar termination denied by app behavior: %@", entry.identity.bundleIdentifier)
            return
        }

        for (pid, app) in entry.runningAppsByPID.sorted(by: { $0.key < $1.key }) {
            guard let bundleIdentifier = app.bundleIdentifier,
                  AppIdentity(bundleIdentifier) == entry.identity
            else {
                NSLog("TideBar termination skipped for mismatched pid %d", pid)
                continue
            }
            if !app.terminate() {
                NSLog("TideBar termination request failed: %@ (pid %d)", bundleIdentifier, pid)
            }
        }
    }
}

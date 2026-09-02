import AppKit
import TideBarCore

/// 应用级系统动作的唯一入口。UI 能力只负责展示，执行前再次按统一身份校验策略。
@MainActor
enum AppActionDispatcher {
    static func setHidden(_ hidden: Bool, for entry: AppEntry) {
        let apps = validatedRunningApps(for: entry, action: "visibility change")
        guard !apps.isEmpty else { return }

        for (pid, app, bundleIdentifier) in apps {
            let succeeded = hidden ? app.hide() : app.unhide()
            if !succeeded {
                NSLog("TideBar %@ request failed: %@ (pid %d)",
                      hidden ? "hide" : "show", bundleIdentifier, pid)
            }
        }
        if !hidden {
            let preferred = apps.first { $0.pid == entry.preferredProcessIdentifier } ?? apps[0]
            _ = preferred.app.activate()
        }
    }

    static func terminate(_ entry: AppEntry) {
        let behavior = AppBehavior.resolve(for: entry.identity)
        guard entry.canTerminate, behavior.canTerminate else {
            NSLog("TideBar termination denied by app behavior: %@", entry.identity.bundleIdentifier)
            return
        }

        for (pid, app, bundleIdentifier) in validatedRunningApps(for: entry, action: "termination") {
            if !app.terminate() {
                NSLog("TideBar termination request failed: %@ (pid %d)", bundleIdentifier, pid)
            }
        }
    }

    private static func validatedRunningApps(
        for entry: AppEntry,
        action: String
    ) -> [(pid: pid_t, app: NSRunningApplication, bundleIdentifier: String)] {
        entry.runningAppsByPID.sorted(by: { $0.key < $1.key }).compactMap { pid, app in
            guard let bundleIdentifier = app.bundleIdentifier,
                  AppIdentity(bundleIdentifier) == entry.identity
            else {
                NSLog("TideBar %@ skipped for mismatched pid %d", action, pid)
                return nil
            }
            return (pid, app, bundleIdentifier)
        }
    }
}

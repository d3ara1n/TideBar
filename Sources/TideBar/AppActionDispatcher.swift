import AppKit
import TideBarCore

/// 应用级系统动作的唯一入口。UI 能力只负责展示，执行前再次按统一身份校验策略。
@MainActor
enum AppActionDispatcher {
    static func setHidden(_ hidden: Bool, for entry: AppEntry) {
        let apps = validatedRunningApps(for: entry, action: "visibility change")
        guard !apps.isEmpty else { return }

        for (pid, app, identityLabel) in apps {
            let succeeded = hidden ? app.hide() : app.unhide()
            if !succeeded {
                NSLog("TideBar %@ request failed: %@ (pid %d)",
                      hidden ? "hide" : "show", identityLabel, pid)
            }
        }
        if !hidden {
            let preferred = apps.first { $0.pid == entry.preferredProcessIdentifier } ?? apps[0]
            _ = preferred.app.activate()
        }
    }

    static func terminate(_ entry: AppEntry) -> Bool {
        let behavior = AppBehavior.resolve(for: entry.identity)
        guard entry.canTerminate, behavior.canTerminate else {
            NSLog("TideBar termination denied by app behavior: %@", entry.identity.bundleIdentifier)
            return false
        }

        var requested = false
        for (pid, app, identityLabel) in validatedRunningApps(for: entry, action: "termination") {
            if app.terminate() {
                requested = true
            } else {
                NSLog("TideBar termination request failed: %@ (pid %d)", identityLabel, pid)
            }
        }
        return requested
    }

    private static func validatedRunningApps(
        for entry: AppEntry,
        action: String
    ) -> [(pid: pid_t, app: NSRunningApplication, identityLabel: String)] {
        entry.runningAppsByPID.sorted(by: { $0.key < $1.key }).compactMap { pid, app in
            // 身份对账：标准应用按 bundle identifier，裸进程按可执行路径，均与条目规范化身份比对
            let identity: AppIdentity?
            let label: String
            if let bundleIdentifier = app.bundleIdentifier {
                identity = AppIdentity(bundleIdentifier)
                label = bundleIdentifier
            } else if let executablePath = app.executablePath {
                identity = AppIdentity(executablePath)
                label = executablePath
            } else {
                identity = nil
                label = "?"
            }
            guard identity == entry.identity else {
                NSLog("TideBar %@ skipped for mismatched pid %d", action, pid)
                return nil
            }
            return (pid, app, label)
        }
    }
}

import AppKit
import TideBarCore

/// 系统启动请求与短期反馈。资源路径是身份，反馈超时不取消系统启动。
@MainActor
final class ApplicationLaunchStore {
    static let shared = ApplicationLaunchStore()
    static let didChange = Notification.Name("TideBar.applicationLaunchDidChange")
    private static let pollDemand = "application.launch"
    private static let timeout: TimeInterval = 5

    private struct Request {
        let token = UUID()
        let deadline: CFTimeInterval
        let showsFeedback: Bool
        var completions: [() -> Void]
    }

    private var requests: [ApplicationItemIdentity: Request] = [:]
    private var observers: [NSObjectProtocol] = []

    static func identity(for url: URL) -> ApplicationItemIdentity {
        ApplicationItemIdentity(bundleIdentifier: nil, applicationPath: url.path)
    }

    func isLaunching(_ url: URL) -> Bool {
        requests[Self.identity(for: url)]?.showsFeedback == true
    }

    /// 相同资源的在途请求合并；调用方各自等本次反馈结束，不重复启动进程。
    func open(_ url: URL, completion: (() -> Void)? = nil) {
        let identity = Self.identity(for: url)
        if requests[identity] != nil {
            if let completion { requests[identity]?.completions.append(completion) }
            return
        }
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleURL.map(Self.identity(for:)) == identity
        }
        let request = Request(deadline: CACurrentMediaTime() + Self.timeout,
                              showsFeedback: !running.contains(where: \.isFinishedLaunching),
                              completions: completion.map { [$0] } ?? [])
        requests[identity] = request
        if requests.count == 1 { startObserving() }
        publishChange()

        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
                finish(identity, token: request.token)
            } catch {
                finish(identity, token: request.token)
                ItemErrors.report(error)
            }
        }
    }

    /// 已有窗口也是可用信号，复用 Registry 的窗口知识，不增加 AX 读取。
    func observeWindows(in entries: [AppEntry]) {
        for entry in entries where entry.windows?.isEmpty == false {
            if let request = requests[entry.itemIdentity] {
                finish(entry.itemIdentity, token: request.token)
            }
        }
    }

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let url = app.bundleURL else { return }
                MainThreadBridge { [weak self] in
                    guard let self else { return }
                    let identity = Self.identity(for: url)
                    if let request = self.requests[identity] {
                        self.finish(identity, token: request.token)
                    }
                }.call()
            })
        }
        // 仅在请求存活期间采样，覆盖不发送工作区启动通知的应用。
        PollScheduler.shared.register(Self.pollDemand, interval: 0.1) { [weak self] in
            self?.checkRunningApplications()
        }
    }

    private func checkRunningApplications() {
        let finished = Set(NSWorkspace.shared.runningApplications.compactMap { app in
            !app.isTerminated && app.isFinishedLaunching
                ? app.bundleURL.map(Self.identity(for:)) : nil
        })
        let now = CACurrentMediaTime()
        let settled = requests.filter {
            now >= $0.value.deadline || ($0.value.showsFeedback && finished.contains($0.key))
        }
        for (identity, request) in settled { finish(identity, token: request.token) }
    }

    private func finish(_ identity: ApplicationItemIdentity, token: UUID) {
        guard let request = requests[identity], request.token == token else { return }
        requests.removeValue(forKey: identity)
        if requests.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for observer in observers { center.removeObserver(observer) }
            observers.removeAll()
            PollScheduler.shared.unregister(Self.pollDemand)
        }
        publishChange()
        for completion in request.completions { completion() }
    }

    private func publishChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

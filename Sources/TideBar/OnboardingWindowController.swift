import AppKit
import SwiftUI

/// 首次启动引导向导：非模态独立窗口，替代旧的阻塞式 NSAlert。
/// AX 授权没有通知渠道：窗口可见期间自持 PollScheduler 需求轮询并经通知送达模型，
/// 生命周期跟窗口走（关窗即注销），不与设置中心共享监控。
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let permissionTick = Notification.Name("TideBar.onboardingPermissionTick")
    private static let permissionDemand = "onboarding.permission"

    private let model: OnboardingModel

    init() {
        let model = OnboardingModel()
        let hosting = NSHostingController(rootView: OnboardingRootView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        // 全幅内容 + 隐藏标题：保留关闭按钮，观感向系统安装器靠拢
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 640, height: 500))
        window.isReleasedWhenClosed = false
        self.model = model
        super.init(window: window)
        model.onFinish = { [weak self] in self?.close() }
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        model.reset()
        // 开窗先送一拍，展示不等人；此后每秒轮询（关窗即注销）
        PollScheduler.shared.register(Self.permissionDemand, interval: 1) {
            NotificationCenter.default.post(name: Self.permissionTick, object: nil)
        }
        NotificationCenter.default.post(name: Self.permissionTick, object: nil)
        DockController.shared.checkStatus()

        // 居中略偏上：底部留出汐线区域，启用接管后真实汐线可直接亮相
        window?.center()
        if let window, let visible = NSScreen.main?.visibleFrame {
            var origin = window.frame.origin
            origin.y = min(origin.y + 48, visible.maxY - window.frame.height - 12)
            window.setFrameOrigin(origin)
        }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        PollScheduler.shared.unregister(Self.permissionDemand)
    }
}

// MARK: - 状态模型

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case intro
        case permission
        case takeover
        case finish
    }

    enum DockOperation: Equatable {
        case idle
        case working
        case success(String)
        case failure(String)
    }

    @Published private(set) var step = Step.intro
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var dockState: DockController.State = .notEnabled
    @Published private(set) var dockOperation: DockOperation = .idle

    /// 「开始使用」「跳过引导」后由控制器关闭窗口。
    var onFinish: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let permissionBridge = MainThreadBridge { [weak self] in self?.refreshPermission() }
        observers.append(NotificationCenter.default.addObserver(
            forName: OnboardingWindowController.permissionTick, object: nil, queue: .main
        ) { _ in permissionBridge() })

        let dockBridge = MainThreadBridge { [weak self] in self?.refreshDock() }
        observers.append(NotificationCenter.default.addObserver(
            forName: DockController.didChange, object: nil, queue: .main
        ) { _ in dockBridge() })
    }

    var canGoBack: Bool { step != .intro }
    var isLastStep: Bool { step == .finish }
    var isTakeoverEnabled: Bool { AppConfiguration.shared.isTakeoverEnabled }

    /// 重看引导时从头开始；系统状态实时重查，不读历史存档。
    func reset() {
        step = .intro
        dockOperation = .idle
        refreshPermission()
        refreshDock()
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// 未授权允许继续：窗口列表降级运行，稍后可在设置中心补授权。
    func refreshPermissionNow() {
        refreshPermission()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Dock 操作复用 DockController：快照、接管、失败回滚全部由其负责，向导只如实展示结果。
    func enableTakeover() {
        dockOperation = .working
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            DockController.shared.applyTakeover()
            refreshDock()
            switch dockState {
            case .takeover:
                dockOperation = .success("TideBar 已启用，汐线正在屏幕底部待命。")
            case .failed(let message):
                dockOperation = .failure(message)
            default:
                dockOperation = .failure("启用未能完成，请重试或到设置中心检查。")
            }
        }
    }

    /// 「跳过引导」与「开始使用」同等对待：只有用户明确结束向导才写入完成标记；
    /// 中途关窗不写，下次启动重新打开向导。
    func finish() {
        AppConfiguration.shared.onboardingCompleted = true
        onFinish?()
    }

    private func refreshPermission() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshDock() {
        dockState = DockController.shared.state
    }
}

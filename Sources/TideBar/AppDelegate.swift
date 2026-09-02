import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = TideBarController()
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var configurationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        DockController.shared.start()
        controller.start()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.controller.configurationDidChange() }.call()
        }

        if !AppConfiguration.shared.onboardingCompleted {
            showOnboarding()
        }
        NSLog("TideBar application shell ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if AppConfiguration.shared.isTakeoverEnabled {
            DockController.shared.restore()
        }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "TideBar")
            button.toolTip = "TideBar"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "检查 Dock 状态", action: #selector(checkDock), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 TideBar", action: #selector(terminate), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        item.menu = menu
        statusItem = item
    }

    private func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = "欢迎使用 TideBar"
        alert.informativeText = "TideBar 会以底部汐线和窗口管理栏替代系统 Dock 的可见入口。默认先使用悬浮测试模式，不会修改系统设置。"
        alert.addButton(withTitle: "开始使用悬浮模式")
        alert.addButton(withTitle: "接管系统 Dock")
        alert.addButton(withTitle: "稍后设置")
        alert.alertStyle = .informational
        let response = alert.runModal()
        switch response {
        case .alertSecondButtonReturn:
            DockController.shared.applyTakeover()
        default:
            break
        }
        AppConfiguration.shared.onboardingCompleted = true
    }

    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.showWindow(self)
    }

    @objc private func checkDock() {
        DockController.shared.checkStatus()
        openSettings()
    }

    @objc private func terminate() {
        NSApp.terminate(self)
    }
}

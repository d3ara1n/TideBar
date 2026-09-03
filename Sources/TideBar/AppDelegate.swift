import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = TideBarController()
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var configurationObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        configureStatusItem()
        DockController.shared.start()
        controller.start()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.controller.configurationDidChange() }.call()
        }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.appearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.applyAppearance() }.call()
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
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    private func applyAppearance() {
        NSApp.appearance = AppConfiguration.shared.appearance.appearance
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
        menu.addItem(NSMenuItem(title: "检查 TideBar 状态", action: #selector(checkDock), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出 TideBar", action: #selector(terminate), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        item.menu = menu
        statusItem = item
    }

    private func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = "欢迎使用汐 TideBar"
        alert.informativeText = "汐会隐藏系统 Dock 的可见入口，并在屏幕底部提供应用与窗口访问。启用前会保存当前 Dock 设置，之后可以随时恢复。启用过程中系统 Dock 会重新启动一次，不会关闭已打开的应用。"
        alert.addButton(withTitle: "启用 TideBar")
        alert.addButton(withTitle: "稍后设置")
        alert.alertStyle = .informational
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            DockController.shared.applyTakeover()
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

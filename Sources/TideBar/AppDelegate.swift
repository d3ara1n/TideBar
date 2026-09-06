import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = TideBarController()
    private let shortcutManager = ShortcutManager()
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var statusItem: NSStatusItem?
    private var configurationObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var layoutObserver: NSObjectProtocol?
    private var behaviorObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        configureStatusItem()
        DockController.shared.start()
        controller.start()
        shortcutManager.onAction = { [weak self] action in
            self?.controller.handleShortcut(action)
        }
        shortcutManager.start()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.controller.configurationDidChange() }.call()
        }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.appearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in
                self?.applyAppearance()
                self?.controller.appearanceDidChange()
            }.call()
        }
        layoutObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.layoutDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.controller.layoutDidChange() }.call()
        }
        behaviorObserver = NotificationCenter.default.addObserver(
            forName: AppConfiguration.behaviorDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.controller.behaviorDidChange() }.call()
        }
        languageObserver = NotificationCenter.default.addObserver(
            forName: L10nManager.languageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainThreadBridge { [weak self] in
                self?.rebuildStatusItemText()
                self?.controller.languageDidChange()
            }.call()
        }

        if !AppConfiguration.shared.onboardingCompleted {
            showOnboarding()
        }
        NSLog("TideBar application shell ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutManager.stop()
        controller.stop()
        if AppConfiguration.shared.isTakeoverEnabled {
            DockController.shared.restore()
        }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
        if let layoutObserver {
            NotificationCenter.default.removeObserver(layoutObserver)
        }
        if let behaviorObserver {
            NotificationCenter.default.removeObserver(behaviorObserver)
        }
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }

    }

    private func applyAppearance() {
        NSApp.appearance = AppConfiguration.shared.appearance.appearance
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: nil)
        }
        statusItem = item
        rebuildStatusItemText()
    }

    /// 状态栏按钮文案与菜单词条化；语言切换时整体重建。
    private func rebuildStatusItemText() {
        guard let item = statusItem else { return }
        if let button = item.button {
            let name = L10nManager.shared.current.string("statusBar.name", table: .menus)
            button.setAccessibilityLabel(name)
            button.toolTip = name
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10nManager.shared.current.string("statusBar.openSettings", table: .menus),
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L10nManager.shared.current.string("statusBar.replayOnboarding", table: .menus),
                                action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10nManager.shared.current.string("statusBar.checkStatus", table: .menus),
                                action: #selector(checkDock), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10nManager.shared.current.string("statusBar.quit", table: .menus),
                                action: #selector(terminate), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
    }

    @objc private func showOnboarding() {
        if onboardingWindow == nil { onboardingWindow = OnboardingWindowController() }
        onboardingWindow?.showWindow(self)
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

import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let viewController = SettingsViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "TideBar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 390))
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        DockController.shared.checkStatus()
        (window?.contentViewController as? SettingsViewController)?.refresh()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class SettingsViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "")
    private let takeoverButton = NSButton(title: "接管系统 Dock", target: nil, action: nil)
    private var observer: NSObjectProtocol?

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        let title = NSTextField(labelWithString: "TideBar")
        title.font = .boldSystemFont(ofSize: 22)
        let subtitle = NSTextField(labelWithString: "系统级窗口任务栏")
        subtitle.textColor = .secondaryLabelColor

        let modeTitle = NSTextField(labelWithString: "运行模式")
        modeTitle.font = .boldSystemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping

        takeoverButton.target = self
        takeoverButton.action = #selector(toggleTakeover)
        takeoverButton.bezelStyle = .rounded

        let restoreButton = NSButton(title: "恢复系统 Dock", target: self, action: #selector(restoreDock))
        restoreButton.bezelStyle = .rounded
        let repairButton = NSButton(title: "立即检查并修复", target: self, action: #selector(repairDock))
        repairButton.bezelStyle = .rounded

        let permissionsTitle = NSTextField(labelWithString: "权限")
        permissionsTitle.font = .boldSystemFont(ofSize: 13)
        let permissionLabel = NSTextField(labelWithString: AXIsProcessTrusted()
                                          ? "辅助功能：已授权"
                                          : "辅助功能：未授权（窗口列表将降级为应用激活）")
        permissionLabel.textColor = .secondaryLabelColor
        let permissionButton = NSButton(title: "打开辅助功能设置", target: self, action: #selector(openAccessibilitySettings))
        permissionButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [takeoverButton, restoreButton, repairButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let firstSeparator = NSBox()
        firstSeparator.boxType = .separator
        let secondSeparator = NSBox()
        secondSeparator.boxType = .separator
        let stack = NSStackView(views: [title, subtitle, firstSeparator, modeTitle, statusLabel,
                                        buttons, secondSeparator, permissionsTitle,
                                        permissionLabel, permissionButton])
        stack.orientation = NSUserInterfaceLayoutOrientation.vertical
        stack.alignment = NSLayoutConstraint.Attribute.leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        observer = NotificationCenter.default.addObserver(forName: DockController.didChange, object: nil,
                                                            queue: .main) { [weak self] _ in
            MainThreadBridge { [weak self] in self?.refresh() }.call()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func refresh() {
        let config = AppConfiguration.shared
        statusLabel.drawsBackground = true
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 8
        switch DockController.shared.state {
        case .floating:
            statusLabel.stringValue = "当前为悬浮测试模式，系统 Dock 未被接管。"
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.backgroundColor = .clear
            takeoverButton.title = "接管系统 Dock"
        case .takeover:
            statusLabel.stringValue = "当前已接管系统 Dock，TideBar 贴底运行。"
            statusLabel.textColor = .systemGreen
            statusLabel.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.10)
            takeoverButton.title = "关闭接管并恢复"
        case .drifted:
            statusLabel.stringValue = "⚠ Dock 配置已被外部修改。请检查后手动修复。"
            statusLabel.textColor = .systemOrange
            statusLabel.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12)
            takeoverButton.title = "关闭接管并恢复"
        case .failed(let message):
            statusLabel.stringValue = "⚠ 操作失败：\(message)"
            statusLabel.textColor = .systemRed
            statusLabel.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10)
            takeoverButton.title = config.isTakeoverEnabled ? "关闭接管并恢复" : "接管系统 Dock"
        }
        takeoverButton.isEnabled = true
        statusLabel.needsDisplay = true
    }

    @objc private func toggleTakeover() {
        if AppConfiguration.shared.isTakeoverEnabled {
            DockController.shared.restore()
        } else {
            DockController.shared.applyTakeover()
        }
        refresh()
    }

    @objc private func restoreDock() {
        DockController.shared.restore()
        refresh()
    }

    @objc private func repairDock() {
        DockController.shared.repair()
        refresh()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

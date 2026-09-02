import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let viewController = SettingsViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "TideBar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 620))
        window.minSize = NSSize(width: 760, height: 520)
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
    private enum Section: Int, CaseIterable {
        case general
        case appearance
        case windows
        case pinned
        case permissions
        case about

        var title: String {
            switch self {
            case .general: return "通用"
            case .appearance: return "外观"
            case .windows: return "窗口"
            case .pinned: return "固定项目"
            case .permissions: return "权限与系统"
            case .about: return "关于"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .appearance: return "paintbrush"
            case .windows: return "macwindow.on.rectangle"
            case .pinned: return "pin"
            case .permissions: return "checkmark.shield"
            case .about: return "info.circle"
            }
        }
    }

    private let sidebar = NSVisualEffectView()
    private let contentScrollView = NSScrollView()
    private let contentView = NSView()
    private let contentStack = NSStackView()
    private var sidebarButtons: [NSButton] = []
    private var selectedSection: Section = .general
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let takeoverButton = NSButton(title: "接管系统 Dock", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root

        configureSidebar()
        configureContent()

        root.addSubview(sidebar)
        root.addSubview(contentScrollView)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 198),
            contentScrollView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentScrollView.topAnchor.constraint(equalTo: root.topAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        setSelectedSection(.general)
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshPermission()
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
        updateStatusBanner()
        refreshPermission()
    }

    private func configureSidebar() {
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active

        let brandIcon = NSImageView(image: NSImage(systemSymbolName: "water.waves", accessibilityDescription: "TideBar") ?? NSImage())
        brandIcon.contentTintColor = .controlAccentColor
        brandIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        brandIcon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let brandTitle = NSTextField(labelWithString: "汐 TideBar")
        brandTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        let brandSubtitle = NSTextField(labelWithString: "窗口任务栏")
        brandSubtitle.font = .systemFont(ofSize: 11)
        brandSubtitle.textColor = .secondaryLabelColor

        let brandText = NSStackView(views: [brandTitle, brandSubtitle])
        brandText.orientation = .vertical
        brandText.spacing = 2
        let brand = NSStackView(views: [brandIcon, brandText])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 10

        let sectionStack = NSStackView()
        sectionStack.orientation = .vertical
        sectionStack.spacing = 4
        sectionStack.alignment = .leading

        for section in Section.allCases {
            let button = NSButton(title: section.title, target: self, action: #selector(selectSectionButton(_:)))
            button.tag = section.rawValue
            button.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)
            button.imagePosition = .imageLeading
            button.contentTintColor = .secondaryLabelColor
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.alignment = .left
            button.bezelStyle = .rounded
            button.isBordered = false
            button.setButtonType(.momentaryPushIn)
            button.controlSize = .large
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 174).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            sectionStack.addArrangedSubview(button)
            sidebarButtons.append(button)
        }

        let footer = NSTextField(labelWithString: "macOS 原生体验 · 持续进化")
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor

        let layout = NSStackView(views: [brand, sectionStack, footer])
        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 18
        layout.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            layout.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            layout.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 22),
            layout.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor, constant: -18),
        ])
    }

    private func configureContent() {
        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.borderType = .noBorder
        contentScrollView.documentView = contentView

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 34),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -34),
            contentView.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),
        ])
    }

    private func setSelectedSection(_ section: Section) {
        selectedSection = section
        for button in sidebarButtons {
            let isSelected = button.tag == section.rawValue
            button.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .clear).cgColor
        }
        rebuildContent()
    }

    @objc private func selectSectionButton(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        setSelectedSection(section)
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch selectedSection {
        case .general: buildGeneralPage()
        case .appearance: buildPlaceholderPage(title: "外观", description: "让汐线与潮涌更贴合你的桌面。")
        case .windows: buildPlaceholderPage(title: "窗口", description: "决定窗口状态如何被发现、切换与还原。")
        case .pinned: buildPlaceholderPage(title: "固定项目", description: "管理你希望始终出现在 TideBar 中的应用。")
        case .permissions: buildPermissionsPage()
        case .about: buildAboutPage()
        }
    }

    private func buildGeneralPage() {
        addPageHeader(title: "通用", subtitle: "TideBar 的核心运行方式")
        addStatusCard()

        let offset = AppConfiguration.shared.verticalOffset
        let offsetValue = String(format: "%.0f pt", offset)
        let card = SettingsCard(title: "快速设置", subtitle: "常用选项会随着 TideBar 的能力逐步开放。")
        card.addRow(SettingsRow(icon: "pin", title: "固定项目", detail: "管理固定应用", accessory: .button("打开", enabled: false)))
        card.addRow(SettingsRow(icon: "arrow.up.and.down", title: "贴底偏移", detail: AppConfiguration.shared.isTakeoverEnabled ? "接管模式下自动贴底" : "当前值：\(offsetValue)", accessory: .button("调整", enabled: false)))
        card.addRow(SettingsRow(icon: "power", title: "登录时启动", detail: "让 TideBar 随 macOS 一起运行", accessory: .badge("即将支持")))
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func buildPermissionsPage() {
        addPageHeader(title: "权限与系统", subtitle: "确保 TideBar 能稳定接管并管理窗口")
        addStatusCard()

        let card = SettingsCard(title: "辅助功能", subtitle: "用于读取窗口列表并将窗口带回前台。")
        let permissionButton = NSButton(title: "打开系统设置", target: self, action: #selector(openAccessibilitySettings))
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .large
        card.addRow(SettingsRow(icon: "accessibility", title: "辅助功能权限", detail: permissionLabel.stringValue, accessory: .custom(permissionButton)))
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        let systemCard = SettingsCard(title: "系统 Dock", subtitle: "所有操作都可以安全恢复 macOS 原始配置。")
        let restoreButton = NSButton(title: "恢复系统 Dock", target: self, action: #selector(restoreDock))
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .large
        let repairButton = NSButton(title: "检查并修复", target: self, action: #selector(repairDock))
        repairButton.bezelStyle = .rounded
        repairButton.controlSize = .large
        systemCard.addRow(SettingsRow(icon: "arrow.counterclockwise", title: "恢复配置", detail: "关闭接管并恢复原始 Dock 设置", accessory: .custom(restoreButton)))
        systemCard.addRow(SettingsRow(icon: "wrench.and.screwdriver", title: "配置检查", detail: "检测外部修改并尝试修复", accessory: .custom(repairButton)))
        contentStack.addArrangedSubview(systemCard)
        systemCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func buildAboutPage() {
        addPageHeader(title: "关于", subtitle: "零存在感的窗口任务栏")
        let card = SettingsCard(title: "汐 TideBar", subtitle: "让窗口回到它们应该在的地方。")
        card.addRow(SettingsRow(icon: "sparkles", title: "版本", detail: "开发预览版", accessory: .badge("macOS 14+")))
        card.addRow(SettingsRow(icon: "book", title: "产品理念", detail: "细线收起，靠近展开；窗口状态一目了然。", accessory: .none))
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func buildPlaceholderPage(title: String, description: String) {
        addPageHeader(title: title, subtitle: description)
        let card = SettingsCard(title: "准备中", subtitle: "设置框架已经就绪，相关能力会在后续版本中开放。")
        card.addRow(SettingsRow(icon: "hammer", title: "功能开发中", detail: "你可以先在“通用”和“权限与系统”中管理当前可用能力。", accessory: .badge("即将支持")))
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func addPageHeader(title: String, subtitle: String) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.spacing = 5
        header.alignment = .leading
        contentStack.addArrangedSubview(header)
    }

    private func addStatusCard() {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        statusIcon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 26).isActive = true

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        takeoverButton.target = self
        takeoverButton.action = #selector(toggleTakeover)
        takeoverButton.bezelStyle = .rounded
        takeoverButton.controlSize = .large
        takeoverButton.setContentHuggingPriority(.required, for: .horizontal)

        let text = NSStackView(views: [statusLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [statusIcon, text, takeoverButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func updateStatusBanner() {
        switch DockController.shared.state {
        case .floating:
            statusLabel.stringValue = "悬浮测试模式 · 系统 Dock 未被接管"
            statusLabel.textColor = .secondaryLabelColor
            statusIcon.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "悬浮测试模式")
            statusIcon.contentTintColor = .secondaryLabelColor
            takeoverButton.title = "接管系统 Dock"
        case .takeover:
            statusLabel.stringValue = "已接管系统 Dock · TideBar 正在贴底运行"
            statusLabel.textColor = .systemGreen
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已接管")
            statusIcon.contentTintColor = .systemGreen
            takeoverButton.title = "关闭接管并恢复"
        case .drifted:
            statusLabel.stringValue = "Dock 配置已被外部修改 · 建议立即检查"
            statusLabel.textColor = .systemOrange
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "配置有变化")
            statusIcon.contentTintColor = .systemOrange
            takeoverButton.title = "关闭接管并恢复"
        case .failed(let message):
            statusLabel.stringValue = "操作失败：\(message)"
            statusLabel.textColor = .systemRed
            statusIcon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "操作失败")
            statusIcon.contentTintColor = .systemRed
            takeoverButton.title = AppConfiguration.shared.isTakeoverEnabled ? "关闭接管并恢复" : "接管系统 Dock"
        }
        takeoverButton.isEnabled = true
    }

    private func refreshPermission() {
        permissionLabel.stringValue = AXIsProcessTrusted()
            ? "已授权 · 可读取窗口列表"
            : "未授权 · 窗口列表将降级为应用激活"
        permissionLabel.textColor = AXIsProcessTrusted() ? .systemGreen : .secondaryLabelColor
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class SettingsCard: NSView {
    private let stack = NSStackView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.spacing = 3
        header.alignment = .leading

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func addRow(_ row: SettingsRow) {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

@MainActor
private final class SettingsRow: NSView {
    enum Accessory {
        case none
        case badge(String)
        case button(String, enabled: Bool)
        case custom(NSView)
    }

    init(icon: String, title: String, detail: String, accessory: Accessory) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: title) ?? NSImage())
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3

        let row = NSStackView(views: [iconView, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        switch accessory {
        case .none:
            break
        case .badge(let value):
            let badge = NSTextField(labelWithString: value)
            badge.font = .systemFont(ofSize: 11, weight: .medium)
            badge.textColor = .secondaryLabelColor
            badge.alignment = .center
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 6
            badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor
            badge.drawsBackground = true
            badge.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
            badge.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(badge)
        case .button(let title, let enabled):
            let button = NSButton(title: title, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.isEnabled = enabled
            button.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(button)
        case .custom(let view):
            view.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(view)
        }

        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

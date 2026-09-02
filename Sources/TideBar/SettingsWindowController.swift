import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let viewController = SettingsViewController()
        let window = NSWindow(contentViewController: viewController)
        window.title = "TideBar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.initialFirstResponder = viewController.sidebarTableView
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        DockController.shared.checkStatus()
        (window?.contentViewController as? SettingsViewController)?.refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class SettingsViewController: NSViewController {
    fileprivate enum Section: Int, CaseIterable {
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
    fileprivate let sidebarTableView = NSTableView()
    private let contentScrollView = NSScrollView()
    private let contentView = NSView()
    private let contentStack = NSStackView()

    private var statusCards: [StatusCard] = []
    private weak var permissionValueLabel: NSTextField?
    private weak var offsetSlider: NSSlider?
    private weak var offsetValueLabel: NSTextField?

    private var observer: NSObjectProtocol?

    override func loadView() {
        view = NSView()

        configureSidebar()
        configureContent()

        view.addSubview(sidebar)
        view.addSubview(contentScrollView)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 218),
            contentScrollView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        sidebarTableView.reloadData()
        sidebarTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let bridge = MainThreadBridge { [weak self] in self?.refresh() }
        observer = NotificationCenter.default.addObserver(
            forName: DockController.didChange, object: nil, queue: .main
        ) { _ in
            bridge()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshPermission()
    }

    func refresh() {
        for card in statusCards {
            card.update(for: DockController.shared.state,
                        takeoverEnabled: AppConfiguration.shared.isTakeoverEnabled)
        }
        refreshPermission()
        updateOffsetRow()
    }

    // MARK: - 布局

    private func configureSidebar() {
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active

        sidebarTableView.style = .sourceList
        sidebarTableView.headerView = nil
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.rowHeight = 34
        sidebarTableView.allowsEmptySelection = false
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        sidebarTableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.documentView = sidebarTableView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),
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
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -30),
            contentView.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),
        ])
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        statusCards = []

        let section = Section.allCases[sidebarTableView.selectedRow]
        switch section {
        case .general: buildGeneralPage()
        case .appearance:
            buildPlaceholderPage(title: "外观", description: "让汐线与潮涌更贴合你的桌面,相关能力将在后续版本开放。")
        case .windows:
            buildPlaceholderPage(title: "窗口", description: "决定窗口状态如何被发现、切换与还原,相关能力将在后续版本开放。")
        case .pinned:
            buildPlaceholderPage(title: "固定项目", description: "管理你希望始终出现在 TideBar 中的应用,相关能力将在后续版本开放。")
        case .permissions: buildPermissionsPage()
        case .about: buildAboutPage()
        }

        contentScrollView.contentView.scroll(to: .zero)
        contentScrollView.reflectScrolledClipView(contentScrollView.contentView)
        refresh()
    }

    // MARK: - 页面构建

    private func buildGeneralPage() {
        addPageHeader(title: "通用")

        let status = StatusCard()
        status.button.target = self
        status.button.action = #selector(toggleTakeover)
        statusCards.append(status)
        addArranged(status, spacingAfter: 22)

        addGroupHeader("运行方式")
        let group = SettingsGroupBox()
        let slider = NSSlider(value: Double(AppConfiguration.shared.verticalOffset),
                              minValue: 0, maxValue: 300,
                              target: self, action: #selector(offsetChanged(_:)))
        slider.isContinuous = true
        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let control = NSStackView(views: [slider, valueLabel])
        control.orientation = .horizontal
        control.spacing = 12
        control.alignment = .centerY
        group.addRow(makeSettingRow(
            title: "贴底偏移",
            detail: "悬浮测试模式下与屏幕底边的距离;接管模式自动贴底",
            control: control))
        offsetSlider = slider
        offsetValueLabel = valueLabel
        addArranged(group)
    }

    private func buildPermissionsPage() {
        addPageHeader(title: "权限与系统")

        let status = StatusCard()
        status.button.target = self
        status.button.action = #selector(toggleTakeover)
        statusCards.append(status)
        addArranged(status, spacingAfter: 22)

        addGroupHeader("辅助功能")
        let permissionGroup = SettingsGroupBox()
        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.maximumNumberOfLines = 2
        valueLabel.lineBreakMode = .byWordWrapping
        let openButton = NSButton(title: "打开系统设置", target: self, action: #selector(openAccessibilitySettings))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .regular
        permissionGroup.addRow(makeSettingRow(
            title: "辅助功能权限",
            detail: "用于读取窗口列表并将窗口带回前台",
            control: NSStackView(views: [valueLabel, openButton])) { stack in
                stack.orientation = .horizontal
                stack.spacing = 12
                stack.alignment = .centerY
            })
        permissionValueLabel = valueLabel
        addArranged(permissionGroup, spacingAfter: 22)

        addGroupHeader("系统 Dock")
        let dockGroup = SettingsGroupBox()
        let restoreButton = NSButton(title: "恢复系统 Dock", target: self, action: #selector(restoreDock))
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .regular
        dockGroup.addRow(makeSettingRow(
            title: "恢复配置",
            detail: "关闭接管并恢复 macOS 原始 Dock 设置",
            control: restoreButton))
        let repairButton = NSButton(title: "检查并修复", target: self, action: #selector(repairDock))
        repairButton.bezelStyle = .rounded
        repairButton.controlSize = .regular
        dockGroup.addRow(makeSettingRow(
            title: "配置检查",
            detail: "检测外部修改并尝试修复",
            control: repairButton))
        addArranged(dockGroup)
    }

    private func buildAboutPage() {
        addPageHeader(title: "关于")

        addGroupHeader("汐 TideBar")
        let group = SettingsGroupBox()
        group.addRow(makeSettingRow(title: "版本", detail: "开发预览版 · 支持 macOS 14 及以上"))
        group.addRow(makeSettingRow(title: "产品理念", detail: "细线收起,靠近展开;窗口状态一目了然。"))
        addArranged(group)
    }

    private func buildPlaceholderPage(title: String, description: String) {
        addPageHeader(title: title)
        addGroupHeader("即将推出")
        let group = SettingsGroupBox()
        group.addRow(makeSettingRow(title: description))
        addArranged(group)
    }

    // MARK: - 页面构件

    private func addPageHeader(title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 22, weight: .bold)
        contentStack.addArrangedSubview(label)
        contentStack.setCustomSpacing(20, after: label)
    }

    private func addGroupHeader(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .bold)
        contentStack.addArrangedSubview(label)
        contentStack.setCustomSpacing(8, after: label)
    }

    private func addArranged(_ view: NSView, spacingAfter: CGFloat = 0) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        if spacingAfter > 0 {
            contentStack.setCustomSpacing(spacingAfter, after: view)
        }
    }

    private func makeSettingRow(title: String, detail: String? = nil,
                                control: NSView? = nil,
                                configureControl: ((NSStackView) -> Void)? = nil) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)
        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .systemFont(ofSize: 11)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.maximumNumberOfLines = 3
            detailLabel.lineBreakMode = .byWordWrapping
            textStack.addArrangedSubview(detailLabel)
        }

        let body: NSView
        if let control {
            let stack = NSStackView(views: [textStack, control])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 12
            configureControl?(stack)
            control.setContentHuggingPriority(.required, for: .horizontal)
            body = stack
        } else {
            body = textStack
        }

        let container = NSView()
        body.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(body)
        let trailing = control == nil
            ? body.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
            : body.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailing,
            body.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            body.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        return container
    }

    // MARK: - 状态刷新

    private func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        let label = permissionValueLabel
        label?.stringValue = trusted ? "已授权" : "未授权"
        label?.textColor = trusted ? .systemGreen : .secondaryLabelColor
    }

    private func updateOffsetRow() {
        let takeover = AppConfiguration.shared.isTakeoverEnabled
        let offset = AppConfiguration.shared.verticalOffset
        offsetSlider?.isEnabled = !takeover
        offsetSlider?.doubleValue = Double(offset)
        offsetValueLabel?.stringValue = takeover ? "已贴底" : String(format: "%.0f pt", offset)
    }

    // MARK: - 动作

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

    @objc private func offsetChanged(_ sender: NSSlider) {
        AppConfiguration.shared.setFloatingOffset(CGFloat(sender.doubleValue))
        updateOffsetRow()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - NSTableView 数据源与代理

extension SettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = Section.allCases[row]
        return SidebarCellView(title: section.title, symbolName: section.symbolName)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard sidebarTableView.selectedRow >= 0 else { return }
        rebuildContent()
    }
}

// MARK: - 侧边栏单元格

@MainActor
private final class SidebarCellView: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyBackgroundStyle() }
    }

    init(title: String, symbolName: String) {
        super.init(frame: .zero)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        imageView = icon
        textField = label

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyBackgroundStyle() {
        let emphasized = backgroundStyle == .emphasized
        let color: NSColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        textField?.textColor = color
        imageView?.contentTintColor = emphasized ? .alternateSelectedControlTextColor : .controlAccentColor
    }
}

// MARK: - 状态卡片

@MainActor
private final class StatusCard: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    let button = NSButton(title: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping

        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [iconView, label, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(for state: DockController.State, takeoverEnabled: Bool) {
        switch state {
        case .floating:
            label.stringValue = "悬浮测试模式 · 系统 Dock 未被接管"
            label.textColor = .secondaryLabelColor
            setIcon("circle.dashed", color: .secondaryLabelColor, description: "悬浮测试模式")
            button.title = "接管系统 Dock"
        case .takeover:
            label.stringValue = "已接管系统 Dock · TideBar 正在贴底运行"
            label.textColor = .systemGreen
            setIcon("checkmark.circle.fill", color: .systemGreen, description: "已接管")
            button.title = "关闭接管并恢复"
        case .drifted:
            label.stringValue = "Dock 配置已被外部修改 · 建议立即检查"
            label.textColor = .systemOrange
            setIcon("exclamationmark.triangle.fill", color: .systemOrange, description: "配置有变化")
            button.title = "关闭接管并恢复"
        case .failed(let message):
            label.stringValue = "操作失败：\(message)"
            label.textColor = .systemRed
            setIcon("xmark.circle.fill", color: .systemRed, description: "操作失败")
            button.title = takeoverEnabled ? "关闭接管并恢复" : "接管系统 Dock"
        }
        button.isEnabled = true
    }

    private func setIcon(_ name: String, color: NSColor, description: String) {
        iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        iconView.contentTintColor = color
    }
}

// MARK: - 分组圆角盒与分隔线

@MainActor
private final class SettingsGroupBox: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func addRow(_ row: NSView) {
        if !stack.arrangedSubviews.isEmpty {
            let separator = SeparatorView()
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

private final class SeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

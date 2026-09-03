import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "汐 TideBar"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // unified 标题栏与内容区融合，保留 macOS 26 的玻璃窗口观感。
        window.toolbar = NSToolbar(identifier: "TideBar.settings")
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 860, height: 600))
        window.minSize = NSSize(width: 720, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TideBar.SettingsWindow")
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        DockController.shared.checkStatus()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 状态模型

@MainActor
private final class SettingsModel: ObservableObject {
    enum Operation: Equatable {
        case idle
        case working(String)
        case success(String)
        case failure(String)
    }

    @Published private(set) var dockState: DockController.State = .notEnabled
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var pinnedApps: [PinnedApplication] = []
    @Published private(set) var operation: Operation = .idle
    @Published private(set) var applicationTheme: ApplicationTheme = .system

    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?

    init() {
        refresh()

        let dockBridge = MainThreadBridge { [weak self] in self?.refreshDock() }
        observers.append(NotificationCenter.default.addObserver(
            forName: DockController.didChange, object: nil, queue: .main
        ) { _ in dockBridge() })

        let configBridge = MainThreadBridge { [weak self] in self?.refresh() }
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.didChange, object: nil, queue: .main
        ) { _ in configBridge() })
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.pinnedDidChange, object: nil, queue: .main
        ) { _ in configBridge() })
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.appearanceDidChange, object: nil, queue: .main
        ) { _ in configBridge() })

        // AX 授权没有通知渠道，只在设置窗口存活期间低频刷新展示状态。
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainThreadBridge { self?.refreshPermission() }()
        }
    }

    func refresh() {
        refreshDock()
        refreshPermission()
        refreshPinnedApps()
        applicationTheme = AppConfiguration.shared.appearance
    }

    func refreshDock() {
        dockState = DockController.shared.state
    }

    private func refreshPermission() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func setApplicationTheme(_ theme: ApplicationTheme) {
        applicationTheme = theme
        AppConfiguration.shared.appearance = theme
    }

    func enableTakeover() {
        perform("正在启用 TideBar…") {
            DockController.shared.applyTakeover()
        }
    }

    func restoreDock() {
        perform("正在恢复 macOS Dock…") {
            DockController.shared.restore()
        }
    }

    func repairDock() {
        perform("正在重新应用 TideBar 设置…") {
            DockController.shared.repair()
        }
    }

    func checkDock() {
        operation = .working("正在检查系统 Dock…")
        DockController.shared.checkStatus()
        refreshDock()
        switch dockState {
        case .takeover:
            operation = .success("系统 Dock 设置正常。")
        case .notEnabled:
            operation = .success("TideBar 尚未启用。")
        case .drifted:
            operation = .failure("系统 Dock 设置已发生变化。")
        case .manualRecoveryRequired:
            operation = .failure("缺少接管前保存的 Dock 配置，无法自动恢复。")
        case .failed(let message):
            operation = .failure(message)
        }
    }

    private func perform(_ message: String, action: @escaping () -> Void) {
        operation = .working(message)
        Task { @MainActor [weak self] in
            await Task.yield()
            action()
            self?.refreshDock()
            guard let self else { return }
            switch self.dockState {
            case .takeover:
                self.operation = .success("TideBar 已启用，系统 Dock 设置正常。")
            case .notEnabled:
                self.operation = .success("已关闭 TideBar，macOS Dock 已恢复。")
            case .drifted:
                self.operation = .failure("系统 Dock 设置仍不一致，请重新检查。")
            case .manualRecoveryRequired:
                self.operation = .failure("缺少接管前保存的 Dock 配置，无法自动恢复。")
            case .failed(let message):
                self.operation = .failure(message)
            }
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshPinnedApps() {
        let workspace = NSWorkspace.shared
        pinnedApps = AppConfiguration.shared.effectivePinnedBundleIDs.map { bundleIdentifier in
            let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            let name = url.flatMap { Bundle(url: $0)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String }
                ?? url?.deletingPathExtension().lastPathComponent
                ?? bundleIdentifier
            let icon = url.map { workspace.icon(forFile: $0.path) } ?? workspace.icon(for: .application)
            return PinnedApplication(bundleIdentifier: bundleIdentifier,
                                     name: name,
                                     icon: icon,
                                     isInstalled: url != nil)
        }
    }

    func addApplications() {
        let panel = NSOpenPanel()
        panel.title = "添加应用到 TideBar"
        panel.message = "选择要固定到 TideBar 的应用。"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { continue }
            AppConfiguration.shared.setPinned(true, bundleIdentifier: bundleIdentifier)
        }
        refreshPinnedApps()
    }

    func removePinned(at offsets: IndexSet) {
        let values = offsets.compactMap { pinnedApps.indices.contains($0) ? pinnedApps[$0] : nil }
        for value in values {
            AppConfiguration.shared.setPinned(false, bundleIdentifier: value.bundleIdentifier)
        }
        refreshPinnedApps()
    }

    func movePinned(from offsets: IndexSet, to destination: Int) {
        AppConfiguration.shared.movePinned(from: offsets, to: destination)
        refreshPinnedApps()
    }

    func removePinned(_ app: PinnedApplication) {
        guard let index = pinnedApps.firstIndex(of: app) else { return }
        removePinned(at: IndexSet(integer: index))
    }

    func movePinnedItem(_ app: PinnedApplication, by offset: Int) {
        guard let index = pinnedApps.firstIndex(of: app) else { return }
        let destination = min(max(index + offset, 0), pinnedApps.count - 1)
        guard destination != index else { return }
        movePinned(from: IndexSet(integer: index),
                   to: offset > 0 ? destination + 1 : destination)
    }

    func restoreDefaultPinned() {
        AppConfiguration.shared.restoreDefaultPinned()
        refreshPinnedApps()
    }

    var isTakeoverEnabled: Bool { AppConfiguration.shared.isTakeoverEnabled }
}

private struct PinnedApplication: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    let isInstalled: Bool

    var id: String { bundleIdentifier.lowercased() }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.isInstalled == rhs.isInstalled
    }
}

// MARK: - 导航

private enum SettingsPage: String, CaseIterable, Identifiable {
    case overview
    case pinned
    case windows
    case appearance
    case dock
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .pinned: return "固定项目"
        case .windows: return "窗口管理"
        case .appearance: return "外观与交互"
        case .dock: return "Dock 与恢复"
        case .permissions: return "权限"
        case .about: return "关于"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "rectangle.grid.1x2"
        case .pinned: return "pin"
        case .windows: return "macwindow.on.rectangle"
        case .appearance: return "paintbrush"
        case .dock: return "dock.rectangle"
        case .permissions: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsRootView: View {
    @StateObject private var model = SettingsModel()
    @State private var selection: SettingsPage? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("汐 TideBar") {
                    pageRow(.overview)
                    pageRow(.pinned)
                    pageRow(.windows)
                    pageRow(.appearance)
                }
                Section("系统") {
                    pageRow(.dock)
                    pageRow(.permissions)
                }
                Section {
                    pageRow(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewPage(model: model)
                case .pinned: PinnedPage(model: model)
                case .windows: WindowsPage(model: model)
                case .appearance: AppearancePage(model: model)
                case .dock: DockPage(model: model)
                case .permissions: PermissionsPage(model: model)
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func pageRow(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.symbolName).tag(page)
    }
}

// MARK: - 通用组件

private struct PageHeader: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold))
            Text(description).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct OperationBanner: View {
    let operation: SettingsModel.Operation

    var body: some View {
        switch operation {
        case .idle:
            EmptyView()
        case .working(let message):
            Label(message, systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct StatusCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 概览

private struct OverviewPage: View {
    @ObservedObject var model: SettingsModel
    @State private var showEnableConfirmation = false
    @State private var showRestoreConfirmation = false

    var body: some View {
        Form {
            PageHeader(title: "概览", description: "查看汐的运行状态，并管理系统 Dock 的接管关系。")

            Section {
                statusCard
            }

            Section {
                OperationBanner(operation: model.operation)
            } header: {
                Text("最近操作")
            }
            .opacity(model.operation == .idle ? 0 : 1)
        }
        .formStyle(.grouped)
        .navigationTitle("概览")
        .confirmationDialog("启用 TideBar？", isPresented: $showEnableConfirmation) {
            Button("启用 TideBar") { model.enableTakeover() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("汐会保存当前 Dock 设置、应用接管配置并重新启动系统 Dock。已打开的应用不会关闭。")
        }
        .confirmationDialog("关闭 TideBar 并恢复 macOS Dock？", isPresented: $showRestoreConfirmation) {
            Button("关闭并恢复", role: .destructive) { model.restoreDock() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("汐会恢复启用前保存的 Dock 设置，并停止底部 TideBar 面板。")
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch model.dockState {
        case .notEnabled:
            StatusCard(symbol: "circle.dashed", tint: .secondary,
                       title: "TideBar 尚未启用",
                       message: "启用后，汐会隐藏系统 Dock 的可见入口，并在屏幕底部提供应用与窗口访问。",
                       actionTitle: "启用 TideBar", action: { showEnableConfirmation = true })
        case .takeover:
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: "TideBar 正在运行",
                       message: "系统 Dock 的可见入口已由汐接替。汐线会在屏幕底部收起，靠近时展开。",
                       actionTitle: "关闭并恢复 macOS Dock", action: { showRestoreConfirmation = true })
        case .drifted:
            StatusCard(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       title: "系统 Dock 设置已发生变化",
                       message: "汐发现当前 Dock 设置与接管配置不一致。你可以重新应用汐的设置，或关闭汐并恢复原始配置。",
                       actionTitle: "重新应用 TideBar 设置", action: { model.repairDock() })
        case .manualRecoveryRequired:
            StatusCard(symbol: "exclamationmark.octagon.fill", tint: .red,
                       title: "无法自动恢复 macOS Dock",
                       message: "汐找不到启用前保存的 Dock 设置，因此无法安全执行自动恢复。请查看恢复说明，或联系支持以获取手动恢复步骤。",
                       actionTitle: "重新检查", action: { model.checkDock() })
        case .failed(let message):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: "需要处理系统 Dock",
                       message: message,
                       actionTitle: "重新检查", action: { model.checkDock() })
        }
    }
}

// MARK: - 固定项目

private struct PinnedPage: View {
    @ObservedObject var model: SettingsModel
    @State private var showResetConfirmation = false
    @State private var isEditing = false

    var body: some View {
        Form {
            PageHeader(title: "固定项目", description: "选择始终显示在汐中的应用。运行中的其他应用会在固定项目之后自动出现。")

            Section {
                if model.pinnedApps.isEmpty {
                    Text("还没有固定项目。")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(Array(model.pinnedApps.enumerated()), id: \.element.id) { index, app in
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                    if !app.isInstalled {
                                        Text("应用未安装或已移动")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if isEditing {
                                    Button { model.movePinnedItem(app, by: -1) } label: {
                                        Image(systemName: "chevron.up")
                                    }
                                    .disabled(index == 0)
                                    .buttonStyle(.borderless)
                                    Button { model.movePinnedItem(app, by: 1) } label: {
                                        Image(systemName: "chevron.down")
                                    }
                                    .disabled(index == model.pinnedApps.count - 1)
                                    .buttonStyle(.borderless)
                                    Button("移除", role: .destructive) {
                                        model.removePinned(app)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 300)
                }

                HStack {
                    Button("添加应用…", action: model.addApplications)
                    Button(isEditing ? "完成" : "编辑") {
                        isEditing.toggle()
                    }
                    Spacer()
                    Button("恢复默认", action: { showResetConfirmation = true })
                }
            } header: {
                Text("固定到 TideBar")
            } footer: {
                Text("点击“编辑”可以移除或重新排序固定项目。固定项目只决定应用在汐中的位置，不会阻止应用自动显示或隐藏。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("固定项目")
        .confirmationDialog("恢复默认固定项目？", isPresented: $showResetConfirmation) {
            Button("恢复默认", role: .destructive, action: model.restoreDefaultPinned)
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 窗口管理

private struct WindowsPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: "窗口管理", description: "汐的核心能力：让最小化窗口和多个窗口都能被直接找到。")

            Section {
                CapabilityRow(title: "窗口列表", description: "按应用展开该应用的全部窗口。", state: model.accessibilityTrusted ? "可用" : "等待授权", tint: model.accessibilityTrusted ? .green : .orange)
                CapabilityRow(title: "最小化窗口还原", description: "点击窗口后自动还原并置前。", state: model.accessibilityTrusted ? "可用" : "等待授权", tint: model.accessibilityTrusted ? .green : .orange)
                CapabilityRow(title: "窗口预览", description: "悬停时查看窗口缩略图。", state: "即将推出", tint: .secondary)
            } header: {
                Text("能力")
            }

            Section {
                LabeledContent("辅助功能权限") {
                    Text(model.accessibilityTrusted ? "已授权" : "未授权")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                if !model.accessibilityTrusted {
                    Button("打开系统设置", action: model.openAccessibilitySettings)
                }
            } header: {
                Text("运行条件")
            } footer: {
                Text(model.accessibilityTrusted
                     ? "窗口管理已具备运行条件。若刚刚完成授权，请重新启动汐以开始观察已有应用。"
                     : "辅助功能权限用于读取窗口列表、识别最小化状态并将窗口带回前台。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("窗口管理")
    }
}

private struct CapabilityRow: View {
    let title: String
    let description: String
    let state: String
    let tint: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(state).foregroundStyle(tint)
        }
    }
}

// MARK: - 外观与交互

private struct AppearancePage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: "外观与交互", description: "调整主题、汐线、展开动画和应用栏的表现。")

            Section {
                Picker("主题", selection: Binding(
                    get: { model.applicationTheme },
                    set: { model.setApplicationTheme($0) }
                )) {
                    ForEach(ApplicationTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("外观")
            } footer: {
                Text("所选主题会应用到设置窗口、汐线、潮涌和应用菜单。")
            }

            Section {
                ComingSoonRow(title: "汐线亮度", description: "让收起态在不同桌面背景上保持清晰。")
                ComingSoonRow(title: "展开动画", description: "调整潮涌展开与退回的动态节奏。")
                ComingSoonRow(title: "应用图标大小", description: "选择更紧凑或更舒展的应用栏密度。")
            } header: {
                Text("汐线与应用栏")
            }

            Section {
                ComingSoonRow(title: "全屏应用中的显示行为", description: "决定全屏空间中是否保留汐线。")
                ComingSoonRow(title: "减少动态效果", description: "跟随 macOS 的减少动态效果设置。")
            } header: {
                Text("行为")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("外观与交互")
    }
}

private struct ComingSoonRow: View {
    let title: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("即将推出")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .opacity(0.72)
    }
}

// MARK: - Dock 与恢复

private struct DockPage: View {
    @ObservedObject var model: SettingsModel
    @State private var showRestoreConfirmation = false

    var body: some View {
        Form {
            PageHeader(title: "Dock 与恢复", description: "查看系统 Dock 的接管配置，并在需要时检查、修复或恢复。")

            Section {
                LabeledContent("当前状态") {
                    Text(statusText).foregroundStyle(statusColor)
                }
                Button("立即检查", action: model.checkDock)
            } header: {
                Text("系统 Dock")
            }

            Section {
                Button("重新应用 TideBar 设置", action: model.repairDock)
                    .disabled(model.dockState != .drifted)
                Button("关闭 TideBar 并恢复 macOS Dock", role: .destructive) {
                    showRestoreConfirmation = true
                }
                .disabled(model.dockState == .notEnabled)
            } header: {
                Text("维护与恢复")
            } footer: {
                Text("重新应用会覆盖汐所需的 Dock 设置并重新启动 Dock。恢复会使用启用前保存的设置。")
            }

            Section {
                OperationBanner(operation: model.operation)
            }
            .opacity(model.operation == .idle ? 0 : 1)
        }
        .formStyle(.grouped)
        .navigationTitle("Dock 与恢复")
        .confirmationDialog("关闭 TideBar 并恢复 macOS Dock？", isPresented: $showRestoreConfirmation) {
            Button("关闭并恢复", role: .destructive, action: model.restoreDock)
            Button("取消", role: .cancel) {}
        } message: {
            Text("汐会恢复启用前保存的 Dock 设置，并停止底部 TideBar 面板。")
        }
    }

    private var statusText: String {
        switch model.dockState {
        case .notEnabled: return "尚未启用"
        case .takeover: return "正常运行"
        case .drifted: return "设置不一致"
        case .manualRecoveryRequired: return "无法自动恢复"
        case .failed: return "需要处理"
        }
    }

    private var statusColor: Color {
        switch model.dockState {
        case .notEnabled: return .secondary
        case .takeover: return .green
        case .drifted: return .orange
        case .manualRecoveryRequired: return .red
        case .failed: return .red
        }
    }
}

// MARK: - 权限

private struct PermissionsPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: "权限", description: "汐只在需要时请求系统能力，并清楚说明每项权限的用途。")

            Section {
                LabeledContent("辅助功能") {
                    Text(model.accessibilityTrusted ? "已授权" : "未授权")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                if !model.accessibilityTrusted {
                    Button("打开系统设置", action: model.openAccessibilitySettings)
                }
            } header: {
                Text("窗口管理")
            } footer: {
                Text("用于读取窗口列表、识别最小化状态，并将选中的窗口带回前台。")
            }

            Section {
                Text("汐不会请求屏幕录制权限。窗口预览功能开放后，会在启用前单独说明用途。")
                    .foregroundStyle(.secondary)
            } header: {
                Text("隐私")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("权限")
    }
}

// MARK: - 关于

private struct AboutPage: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        Form {
            PageHeader(title: "关于汐", description: "细线收起，靠近展开；窗口状态一目了然。")

            Section {
                HStack(spacing: 14) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("汐 TideBar").font(.headline)
                        Text("版本 \(version)（Build \(build)）")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("系统要求", value: "macOS 14 或更高版本")
                LabeledContent("产品定位", value: "窗口任务栏与 Dock 替代")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("关于")
    }
}

import AppKit
import KeyboardShortcuts
import SwiftUI
import TideBarCore

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: LocalizedContent { SettingsRootView() })
        let window = NSWindow(contentViewController: hosting)
        window.title = L10nManager.shared.current.string("window.title", table: .settings)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // unified 标题栏与内容区融合，保留玻璃窗口观感。
        window.toolbar = NSToolbar(identifier: "TideBar.settings")
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 860, height: 600))
        window.minSize = NSSize(width: 720, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TideBar.SettingsWindow")
        self.init(window: window)
        window.delegate = self
    }

    private static let permissionDemand = "settings.permission"
    private var languageObserver: NSObjectProtocol?

    override func showWindow(_ sender: Any?) {
        // 窗口标题与语言同步：开窗时重设并在可见期间随语言变化更新（关窗即注销）
        window?.title = L10nManager.shared.current.string("window.title", table: .settings)
        if languageObserver == nil {
            languageObserver = NotificationCenter.default.addObserver(
                forName: L10nManager.languageDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainThreadBridge { [weak self] in
                    self?.window?.title = L10nManager.shared.current.string("window.title", table: .settings)
                }.call()
            }
        }
        // AX 授权没有通知渠道：窗口可见期间注册轮询需求（关窗即注销），
        // 经通知送达状态模型；开窗先送一拍，展示不等人
        PollScheduler.shared.register(Self.permissionDemand, interval: 1) {
            NotificationCenter.default.post(name: .settingsPermissionTick, object: nil)
        }
        NotificationCenter.default.post(name: .settingsPermissionTick, object: nil)
        DockController.shared.checkStatus()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func windowWillClose(_ notification: Notification) {
        PollScheduler.shared.unregister(Self.permissionDemand)
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {}

private extension Notification.Name {
    /// 设置窗口可见期间的 AX 授权状态刷新节拍（PollScheduler 需求驱动）
    static let settingsPermissionTick = Notification.Name("TideBar.settingsPermissionTick")
}

// MARK: - 状态模型
@MainActor
private final class SettingsModel: ObservableObject {
    /// 操作的阶段语义；文案由视图层按语言环境解析。
    enum OperationKind: String {
        case enabling, restoring, repairing, checking
        case takeoverActive, restored, checkHealthy, checkNotEnabled
    }

    /// 保留失败语义，文案只在展示时解析。
    enum OperationFailure: Equatable {
        case dock(DockFailure)
        case drifted
        case manualRecovery
    }

    enum Operation: Equatable {
        case idle
        case working(OperationKind)
        case success(OperationKind)
        case failure(OperationFailure)
    }

    @Published private(set) var dockState: DockController.State = .notEnabled
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var pinnedApps: [PinnedApplication] = []
    @Published private(set) var operation: Operation = .idle
    @Published private(set) var applicationTheme: ApplicationTheme = .system
    @Published private(set) var iconSize: IconSizePreset = .standard
    @Published private(set) var tidelineBrightness: TideLineBrightness = .automatic
    @Published private(set) var animation: AnimationPreset = .standard
    @Published private(set) var reducedMotion: ReducedMotionPreference = .automatic
    @Published private(set) var fullscreenBehavior: FullscreenBehavior = .clickToExpand
    @Published private(set) var switcherCommitDelay: Double = 0.9

    private var observers: [NSObjectProtocol] = []

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
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.layoutDidChange, object: nil, queue: .main
        ) { _ in configBridge() })
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.behaviorDidChange, object: nil, queue: .main
        ) { _ in configBridge() })

        // AX 授权没有通知渠道：控制器在窗口可见期间驱动的权限刷新经通知送达
        let permissionBridge = MainThreadBridge { [weak self] in self?.refreshPermission() }
        observers.append(NotificationCenter.default.addObserver(
            forName: .settingsPermissionTick, object: nil, queue: .main
        ) { _ in permissionBridge() })
    }

    func refresh() {
        refreshDock()
        refreshPermission()
        refreshPinnedApps()
        let configuration = AppConfiguration.shared
        applicationTheme = configuration.appearance
        iconSize = configuration.iconSize
        tidelineBrightness = configuration.tidelineBrightness
        animation = configuration.animation
        reducedMotion = configuration.reducedMotion
        fullscreenBehavior = configuration.fullscreenBehavior
        switcherCommitDelay = configuration.switcherCommitDelay
    }

    func refreshDock() {
        dockState = DockController.shared.state
    }

    private func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        guard trusted != accessibilityTrusted else { return }
        accessibilityTrusted = trusted
        // 授权边沿顺便驱动主功能恢复：UI 轮询已在跑，零新增轮询
        if trusted {
            NotificationCenter.default.post(name: .axPermissionGranted, object: nil)
        }
    }

    func setApplicationTheme(_ theme: ApplicationTheme) {
        applicationTheme = theme
        AppConfiguration.shared.appearance = theme
    }

    func setIconSize(_ value: IconSizePreset) {
        iconSize = value
        AppConfiguration.shared.iconSize = value
    }

    func setTidelineBrightness(_ value: TideLineBrightness) {
        tidelineBrightness = value
        AppConfiguration.shared.tidelineBrightness = value
    }

    func setAnimation(_ value: AnimationPreset) {
        animation = value
        AppConfiguration.shared.animation = value
    }

    func setReducedMotion(_ value: ReducedMotionPreference) {
        reducedMotion = value
        AppConfiguration.shared.reducedMotion = value
    }

    func setFullscreenBehavior(_ value: FullscreenBehavior) {
        fullscreenBehavior = value
        AppConfiguration.shared.fullscreenBehavior = value
    }

    func setSwitcherCommitDelay(_ value: Double) {
        switcherCommitDelay = value
        AppConfiguration.shared.switcherCommitDelay = value
    }

    func restoreDefaultShortcuts() {
        KeyboardShortcuts.reset(.toggleTideBar, .cycleTideBarApplication)
        AppConfiguration.shared.restoreDefaultSwitcherDelay()
        refresh()
    }

    func enableTakeover() {
        perform(.enabling) {
            DockController.shared.applyTakeover()
        }
    }

    func restoreDock() {
        perform(.restoring) {
            DockController.shared.restore()
        }
    }

    func repairDock() {
        perform(.repairing) {
            DockController.shared.repair()
        }
    }

    func checkDock() {
        operation = .working(.checking)
        DockController.shared.checkStatus()
        refreshDock()
        switch dockState {
        case .takeover:
            operation = .success(.checkHealthy)
        case .notEnabled:
            operation = .success(.checkNotEnabled)
        case .drifted:
            operation = .failure(.drifted)
        case .manualRecoveryRequired:
            operation = .failure(.manualRecovery)
        case .failed(let failure):
            operation = .failure(.dock(failure))
        }
    }

    private func perform(_ workingKind: OperationKind, action: @escaping () -> Void) {
        operation = .working(workingKind)
        Task { @MainActor [weak self] in
            await Task.yield()
            action()
            self?.refreshDock()
            guard let self else { return }
            switch self.dockState {
            case .takeover:
                self.operation = .success(.takeoverActive)
            case .notEnabled:
                self.operation = .success(.restored)
            case .drifted:
                self.operation = .failure(.drifted)
            case .manualRecoveryRequired:
                self.operation = .failure(.manualRecovery)
            case .failed(let failure):
                self.operation = .failure(.dock(failure))
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

    func addPinned(bundleIdentifiers: [String]) {
        for bundleIdentifier in bundleIdentifiers {
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
    case shortcuts
    case dock
    case permissions
    case about

    var id: String { rawValue }

    var titleKey: String { "page.\(rawValue)" }

    var symbolName: String {
        switch self {
        case .overview: return "rectangle.grid.1x2"
        case .pinned: return "pin"
        case .windows: return "macwindow.on.rectangle"
        case .appearance: return "paintbrush"
        case .shortcuts: return "keyboard"
        case .dock: return "dock.rectangle"
        case .permissions: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsRootView: View {
    @StateObject private var model = SettingsModel()
    @Environment(\.l10n) private var l10n
    @State private var selection: SettingsPage? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(l10n.string("sidebar.section.app", table: .settings)) {
                    pageRow(.overview)
                    pageRow(.pinned)
                    pageRow(.windows)
                    pageRow(.appearance)
                    pageRow(.shortcuts)
                }
                Section(l10n.string("sidebar.section.system", table: .settings)) {
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
                case .shortcuts: ShortcutsPage(model: model)
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
        Label(l10n.string(page.titleKey, table: .settings), systemImage: page.symbolName).tag(page)
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
    @Environment(\.l10n) private var l10n
    let operation: SettingsModel.Operation

    var body: some View {
        switch operation {
        case .idle:
            EmptyView()
        case .working(let kind):
            Label(l10n.string("op.working.\(kind.rawValue)", table: .settings),
                  systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .success(let kind):
            Label(l10n.string("op.success.\(kind.rawValue)", table: .settings),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let failure):
            Label(failureText(failure), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func failureText(_ failure: SettingsModel.OperationFailure) -> String {
        switch failure {
        case .dock(let failure): failure.message(in: l10n)
        case .drifted: l10n.string("op.failure.drifted", table: .settings)
        case .manualRecovery: l10n.string("op.failure.manualRecovery", table: .settings)
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
    }
}

// MARK: - 概览

private struct OverviewPage: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel
    @State private var showEnableConfirmation = false
    @State private var showRestoreConfirmation = false

    var body: some View {
        Form {
            PageHeader(title: l10n.string("overview.header.title", table: .settings),
                       description: l10n.string("overview.header.description", table: .settings))

            Section {
                statusCard
            }

            Section {
                OperationBanner(operation: model.operation)
            } header: {
                Text(l10n.string("overview.section.recent", table: .settings))
            }
            .opacity(model.operation == .idle ? 0 : 1)
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.overview", table: .settings))
        .confirmationDialog(l10n.string("takeover.confirmTitle", table: .settings), isPresented: $showEnableConfirmation) {
            Button(l10n.string("takeover.confirmEnable", table: .settings)) { model.enableTakeover() }
            Button(l10n.string("action.cancel", table: .settings), role: .cancel) {}
        } message: {
            Text(l10n.string("takeover.confirmMessage", table: .settings))
        }
        .confirmationDialog(l10n.string("restore.confirmTitle", table: .settings), isPresented: $showRestoreConfirmation) {
            Button(l10n.string("restore.confirmAction", table: .settings), role: .destructive) { model.restoreDock() }
            Button(l10n.string("action.cancel", table: .settings), role: .cancel) {}
        } message: {
            Text(l10n.string("restore.confirmMessage", table: .settings))
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch model.dockState {
        case .notEnabled:
            StatusCard(symbol: "circle.dashed", tint: .secondary,
                       title: l10n.string("overview.state.notEnabled.title", table: .settings),
                       message: l10n.string("overview.state.notEnabled.message", table: .settings),
                       actionTitle: l10n.string("takeover.confirmEnable", table: .settings),
                       action: { showEnableConfirmation = true })
        case .takeover:
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: l10n.string("overview.state.takeover.title", table: .settings),
                       message: l10n.string("overview.state.takeover.message", table: .settings),
                       actionTitle: l10n.string("restore.action", table: .settings),
                       action: { showRestoreConfirmation = true })
        case .drifted:
            StatusCard(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       title: l10n.string("overview.state.drifted.title", table: .settings),
                       message: l10n.string("overview.state.drifted.message", table: .settings),
                       actionTitle: l10n.string("dock.reapply", table: .settings),
                       action: { model.repairDock() })
        case .manualRecoveryRequired:
            StatusCard(symbol: "exclamationmark.octagon.fill", tint: .red,
                       title: l10n.string("overview.state.manualRecovery.title", table: .settings),
                       message: l10n.string("overview.state.manualRecovery.message", table: .settings),
                       actionTitle: l10n.string("action.checkNow", table: .settings),
                       action: { model.checkDock() })
        case .failed(let failure):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: l10n.string("overview.state.failed.title", table: .settings),
                       message: failure.message(in: l10n),
                       actionTitle: l10n.string("action.checkNow", table: .settings),
                       action: { model.checkDock() })
        }
    }
}

// MARK: - 固定项目

private struct PinnedPage: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel
    @State private var showResetConfirmation = false
    @State private var isShowingApplicationPicker = false

    var body: some View {
        Form {
            PageHeader(title: l10n.string("page.pinned", table: .settings),
                       description: l10n.string("pinned.header.description", table: .settings))

            Section {
                if model.pinnedApps.isEmpty {
                    Text(l10n.string("pinned.empty", table: .settings))
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(model.pinnedApps) { app in
                            PinnedRow(app: app) {
                                model.removePinned(app)
                            }
                        }
                        .onMove { offsets, destination in
                            model.movePinned(from: offsets, to: destination)
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 300)
                }

                HStack {
                    Button(l10n.string("pinned.add", table: .settings), action: { isShowingApplicationPicker = true })
                    Spacer()
                    Button(l10n.string("pinned.reset", table: .settings), action: { showResetConfirmation = true })
                }
            } header: {
                Text(l10n.string("pinned.section.header", table: .settings))
            } footer: {
                Text(l10n.string("pinned.section.footer", table: .settings))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.pinned", table: .settings))
        .sheet(isPresented: $isShowingApplicationPicker) {
            ApplicationPickerSheet(model: model)
        }
        .confirmationDialog(l10n.string("pinned.resetConfirmTitle", table: .settings), isPresented: $showResetConfirmation) {
            Button(l10n.string("pinned.reset", table: .settings), role: .destructive, action: model.restoreDefaultPinned)
            Button(l10n.string("action.cancel", table: .settings), role: .cancel) {}
        }
    }
}

private struct PinnedRow: View {
    @Environment(\.l10n) private var l10n
    let app: PinnedApplication
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                if !app.isInstalled {
                    Text(l10n.string("pinned.notInstalled", table: .settings))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.red))
                }
                .buttonStyle(.plain)
                .help(l10n.string("action.remove", table: .settings))
                .transition(.opacity)
            }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help(l10n.string("pinned.dragHelp", table: .settings))
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button(l10n.string("action.remove", table: .settings), role: .destructive, action: onRemove)
        }
    }
}

private struct InstalledApplicationInfo: Sendable {
    let bundleIdentifier: String
    let name: String
    let path: String
}

private enum ApplicationScanner {
    static func scanInstalledApplications() -> [InstalledApplicationInfo] {
        let roots = ["/Applications", "/System/Applications",
                     NSString(string: "~/Applications").expandingTildeInPath]
        let fileManager = FileManager.default
        var urls: [URL] = []
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                urls.append(URL(fileURLWithPath: root).appendingPathComponent(entry))
            }
            for entry in entries {
                guard !entry.hasSuffix(".app") else { continue }
                let directory = URL(fileURLWithPath: root).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      let subEntries = try? fileManager.contentsOfDirectory(atPath: directory.path)
                else { continue }
                urls.append(contentsOf: subEntries
                    .filter { $0.hasSuffix(".app") }
                    .map { directory.appendingPathComponent($0) })
            }
        }

        var seenBundleIdentifiers = Set<String>()
        var infos: [InstalledApplicationInfo] = []
        for url in urls {
            guard let bundle = Bundle(url: url),
                  let bundleIdentifier = bundle.bundleIdentifier,
                  seenBundleIdentifiers.insert(bundleIdentifier).inserted
            else { continue }
            let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            infos.append(InstalledApplicationInfo(bundleIdentifier: bundleIdentifier,
                                                  name: name,
                                                  path: url.path))
        }
        infos.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return infos
    }
}

private struct ApplicationPickerSheet: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var installedApps: [PinnedApplication] = []
    @State private var isScanning = true
    @State private var searchText = ""
    @State private var selectedBundleIdentifiers: Set<String> = []

    private var filteredApps: [PinnedApplication] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return installedApps }
        return installedApps.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    private var pinnedBundleIdentifiers: Set<String> {
        Set(model.pinnedApps.map(\.bundleIdentifier))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(l10n.string("pinned.searchPlaceholder", table: .settings), text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)

            Divider()

            List(filteredApps) { app in
                ApplicationPickerRow(app: app,
                                     isPinned: pinnedBundleIdentifiers.contains(app.bundleIdentifier),
                                     isSelected: selectedBundleIdentifiers.contains(app.bundleIdentifier)) {
                    toggleSelection(app)
                }
            }
            .listStyle(.inset)
            .overlay {
                if isScanning {
                    ProgressView(l10n.string("pinned.scanning", table: .settings))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            HStack {
                Text(l10n.string("pinned.selectedCount", table: .settings, arguments: selectedBundleIdentifiers.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n.string("action.cancel", table: .settings), action: { dismiss() })
                Button(l10n.string("pinned.addShort", table: .settings), action: confirmAdd)
                    .disabled(selectedBundleIdentifiers.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 460, idealWidth: 460, minHeight: 420, idealHeight: 480)
        .task {
            guard installedApps.isEmpty else { return }
            let infos = await Task.detached(priority: .userInitiated) {
                ApplicationScanner.scanInstalledApplications()
            }.value
            installedApps = Self.pinnedApplications(from: infos)
            isScanning = false
        }
    }

    private static func pinnedApplications(from infos: [InstalledApplicationInfo]) -> [PinnedApplication] {
        let workspace = NSWorkspace.shared
        return infos.map { info in
            PinnedApplication(bundleIdentifier: info.bundleIdentifier,
                              name: info.name,
                              icon: workspace.icon(forFile: info.path),
                              isInstalled: true)
        }
    }

    private func toggleSelection(_ app: PinnedApplication) {
        if !selectedBundleIdentifiers.insert(app.bundleIdentifier).inserted {
            selectedBundleIdentifiers.remove(app.bundleIdentifier)
        }
    }

    private func confirmAdd() {
        let bundleIdentifiers = installedApps
            .filter { selectedBundleIdentifiers.contains($0.bundleIdentifier) }
            .map(\.bundleIdentifier)
        model.addPinned(bundleIdentifiers: bundleIdentifiers)
        dismiss()
    }
}

private struct ApplicationPickerRow: View {
    @Environment(\.l10n) private var l10n
    let app: PinnedApplication
    let isPinned: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name)
                .foregroundStyle(isPinned ? .secondary : .primary)
            Spacer()
            if isPinned {
                Text(l10n.string("pinned.pinnedBadge", table: .settings))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPinned { onToggle() }
        }
    }
}

// MARK: - 窗口管理

private struct WindowsPage: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: l10n.string("page.windows", table: .settings),
                       description: l10n.string("windows.header.description", table: .settings))

            Section {
                CapabilityRow(title: l10n.string("windows.cap.windowList.title", table: .settings),
                              description: l10n.string("windows.cap.windowList.description", table: .settings),
                              state: l10n.string(model.accessibilityTrusted ? "state.available" : "state.pending", table: .settings),
                              tint: model.accessibilityTrusted ? .green : .orange)
                CapabilityRow(title: l10n.string("windows.cap.minimizeRestore.title", table: .settings),
                              description: l10n.string("windows.cap.minimizeRestore.description", table: .settings),
                              state: l10n.string(model.accessibilityTrusted ? "state.available" : "state.pending", table: .settings),
                              tint: model.accessibilityTrusted ? .green : .orange)
                CapabilityRow(title: l10n.string("windows.cap.preview.title", table: .settings),
                              description: l10n.string("windows.cap.preview.description", table: .settings),
                              state: l10n.string("state.comingSoon", table: .settings), tint: .secondary)
            } header: {
                Text(l10n.string("windows.section.capabilities", table: .settings))
            }

            Section {
                LabeledContent(l10n.string("windows.accessibilityLabel", table: .settings)) {
                    Text(l10n.string(model.accessibilityTrusted ? "state.granted" : "state.notGranted", table: .settings))
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                if !model.accessibilityTrusted {
                    Button(l10n.string("action.openSystemSettings", table: .settings), action: model.openAccessibilitySettings)
                }
            } header: {
                Text(l10n.string("windows.section.requirements", table: .settings))
            } footer: {
                Text(l10n.string(model.accessibilityTrusted ? "windows.footer.granted" : "windows.footer.notGranted", table: .settings))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.windows", table: .settings))
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
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: l10n.string("page.appearance", table: .settings),
                       description: l10n.string("appearance.header.description", table: .settings))

            Section {
                LanguagePicker(title: l10n.string("appearance.language", table: .settings))
            } header: {
                Text(l10n.string("appearance.section.language", table: .settings))
            } footer: {
                Text(l10n.string("appearance.language.footer", table: .settings))
            }

            Section {
                Picker(l10n.string("appearance.theme", table: .settings), selection: Binding(
                    get: { model.applicationTheme },
                    set: { model.setApplicationTheme($0) }
                )) {
                    ForEach(ApplicationTheme.allCases) { theme in
                        LocalizedText(theme.titleKey, table: .labels).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(l10n.string("appearance.section.theme", table: .settings))
            } footer: {
                Text(l10n.string("appearance.theme.footer", table: .settings))
            }

            Section {
                Picker(l10n.string("appearance.iconSize", table: .settings), selection: Binding(
                    get: { model.iconSize },
                    set: { model.setIconSize($0) }
                )) {
                    ForEach(IconSizePreset.allCases) { value in
                        LocalizedText(value.titleKey, table: .labels).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Picker(l10n.string("appearance.brightness", table: .settings), selection: Binding(
                    get: { model.tidelineBrightness },
                    set: { model.setTidelineBrightness($0) }
                )) {
                    ForEach(TideLineBrightness.allCases) { value in
                        LocalizedText(value.titleKey, table: .labels).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(l10n.string("appearance.section.tideline", table: .settings))
            } footer: {
                Text(l10n.string("appearance.tideline.footer", table: .settings))
            }

            Section {
                Picker(l10n.string("appearance.animation", table: .settings), selection: Binding(
                    get: { model.animation },
                    set: { model.setAnimation($0) }
                )) {
                    ForEach(AnimationPreset.allCases) { value in
                        LocalizedText(value.titleKey, table: .labels).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Picker(l10n.string("appearance.reducedMotion", table: .settings), selection: Binding(
                    get: { model.reducedMotion },
                    set: { model.setReducedMotion($0) }
                )) {
                    ForEach(ReducedMotionPreference.allCases) { value in
                        LocalizedText(value.titleKey, table: .labels).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(l10n.string("appearance.section.animation", table: .settings))
            } footer: {
                Text(l10n.string("appearance.animation.footer", table: .settings))
            }

            Section {
                Picker(l10n.string("appearance.fullscreen", table: .settings), selection: Binding(
                    get: { model.fullscreenBehavior },
                    set: { model.setFullscreenBehavior($0) }
                )) {
                    ForEach(FullscreenBehavior.allCases) { value in
                        LocalizedText(value.titleKey, table: .labels).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(l10n.string("appearance.section.fullscreen", table: .settings))
            } footer: {
                Text(l10n.string("appearance.fullscreen.footer", table: .settings))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.appearance", table: .settings))
    }
}

// MARK: - 快捷键

private struct ShortcutsPage: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: l10n.string("page.shortcuts", table: .settings),
                       description: l10n.string("shortcuts.header.description", table: .settings))

            Section {
                KeyboardShortcuts.Recorder(l10n.string("shortcuts.toggle", table: .settings), name: .toggleTideBar)
                KeyboardShortcuts.Recorder(l10n.string("shortcuts.cycle", table: .settings), name: .cycleTideBarApplication)
            } header: {
                Text(l10n.string("shortcuts.section.global", table: .settings))
            } footer: {
                Text(l10n.string("shortcuts.global.footer", table: .settings))
            }

            Section {
                HStack {
                    Text(l10n.string("shortcuts.commitDelay", table: .settings))
                    Slider(value: Binding(
                        get: { model.switcherCommitDelay },
                        set: { model.setSwitcherCommitDelay($0) }
                    ), in: 0.2...5.0, step: 0.1)
                    Text(l10n.string("shortcuts.delayValue", table: .settings, arguments: model.switcherCommitDelay))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
            } header: {
                Text(l10n.string("shortcuts.section.switcher", table: .settings))
            } footer: {
                Text(l10n.string("shortcuts.switcher.footer", table: .settings))
            }

            Section {
                Button(l10n.string("shortcuts.resetDefaults", table: .settings)) {
                    model.restoreDefaultShortcuts()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.shortcuts", table: .settings))
    }
}

// MARK: - Dock 与恢复

private struct DockPage: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel
    @State private var showRestoreConfirmation = false

    var body: some View {
        Form {
            PageHeader(title: l10n.string("page.dock", table: .settings),
                       description: l10n.string("dock.header.description", table: .settings))

            Section {
                LabeledContent(l10n.string("dock.currentState", table: .settings)) {
                    Text(statusText).foregroundStyle(statusColor)
                }
                Button(l10n.string("action.checkNow", table: .settings), action: model.checkDock)
            } header: {
                Text(l10n.string("dock.section.dock", table: .settings))
            }

            Section {
                Button(l10n.string("dock.reapply", table: .settings), action: model.repairDock)
                    .disabled(model.dockState != .drifted)
                Button(l10n.string("restore.action", table: .settings), role: .destructive) {
                    showRestoreConfirmation = true
                }
                .disabled(model.dockState == .notEnabled)
            } header: {
                Text(l10n.string("dock.section.maintenance", table: .settings))
            } footer: {
                Text(l10n.string("dock.maintenance.footer", table: .settings))
            }

            Section {
                OperationBanner(operation: model.operation)
            }
            .opacity(model.operation == .idle ? 0 : 1)
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.dock", table: .settings))
        .confirmationDialog(l10n.string("restore.confirmTitle", table: .settings), isPresented: $showRestoreConfirmation) {
            Button(l10n.string("restore.confirmAction", table: .settings), role: .destructive, action: model.restoreDock)
            Button(l10n.string("action.cancel", table: .settings), role: .cancel) {}
        } message: {
            Text(l10n.string("restore.confirmMessage", table: .settings))
        }
    }

    private var statusText: String {
        switch model.dockState {
        case .notEnabled: l10n.string("dock.status.notEnabled", table: .settings)
        case .takeover: l10n.string("dock.status.takeover", table: .settings)
        case .drifted: l10n.string("dock.status.drifted", table: .settings)
        case .manualRecoveryRequired: l10n.string("dock.status.manualRecovery", table: .settings)
        case .failed: l10n.string("dock.status.failed", table: .settings)
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
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            PageHeader(title: l10n.string("page.permissions", table: .settings),
                       description: l10n.string("permissions.header.description", table: .settings))

            Section {
                LabeledContent(l10n.string("permissions.accessibility", table: .settings)) {
                    Text(l10n.string(model.accessibilityTrusted ? "state.granted" : "state.notGranted", table: .settings))
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                if !model.accessibilityTrusted {
                    Button(l10n.string("action.openSystemSettings", table: .settings), action: model.openAccessibilitySettings)
                }
            } header: {
                Text(l10n.string("permissions.section.windows", table: .settings))
            } footer: {
                Text(l10n.string("permissions.windows.footer", table: .settings))
            }

            Section {
                Text(l10n.string("permissions.privacy.note", table: .settings))
                    .foregroundStyle(.secondary)
            } header: {
                Text(l10n.string("permissions.section.privacy", table: .settings))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.permissions", table: .settings))
    }
}

// MARK: - 关于

private struct AboutPage: View {
    @Environment(\.l10n) private var l10n
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? l10n.string("about.devVersion", table: .settings)
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var feedbackURL: URL {
        URL(string: "https://github.com/d3ara1n/TideBar/issues")!
    }

    var body: some View {
        Form {
            PageHeader(title: l10n.string("about.header.title", table: .settings),
                       description: l10n.string("about.header.description", table: .settings))

            Section {
                HStack(spacing: 14) {
                    BrandMark()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.string("about.name", table: .settings)).font(.headline)
                        Text(l10n.string("about.tagline", table: .settings))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(l10n.string("about.version", table: .settings, arguments: version, build))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent(l10n.string("about.systemRequirements", table: .settings),
                               value: l10n.string("about.requirementsValue", table: .settings))
                LabeledContent(l10n.string("about.copyright", table: .settings), value: "© 2026 Chien Zhang")
                LabeledContent(l10n.string("about.feedback", table: .settings)) {
                    Link("GitHub Issues", destination: feedbackURL)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n.string("page.about", table: .settings))
    }
}

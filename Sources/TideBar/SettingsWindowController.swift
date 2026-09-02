import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "TideBar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // 空 toolbar + unified 样式:红绿灯并入内容区上方的自定义标题栏
        window.toolbar = NSToolbar(identifier: "TideBar.settings")
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 840, height: 560))
        window.minSize = NSSize(width: 700, height: 460)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        // checkStatus 必然触发 didChange 通知,模型据此刷新
        DockController.shared.checkStatus()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 状态模型

@MainActor
private final class SettingsModel: ObservableObject {
    @Published private(set) var dockState: DockController.State = .floating
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var floatingOffset: Double

    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?

    init() {
        floatingOffset = Double(AppConfiguration.shared.verticalOffset)
        refresh()

        let dockBridge = MainThreadBridge { [weak self] in self?.refresh() }
        observers.append(NotificationCenter.default.addObserver(
            forName: DockController.didChange, object: nil, queue: .main
        ) { _ in dockBridge() })
        let configBridge = MainThreadBridge { [weak self] in self?.refresh() }
        observers.append(NotificationCenter.default.addObserver(
            forName: AppConfiguration.didChange, object: nil, queue: .main
        ) { _ in configBridge() })

        // AX 授权无通知渠道,用户回授权后需在合理延迟内自动翻转状态
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainThreadBridge { self?.refreshPermission() }()
        }
    }

    func refresh() {
        dockState = DockController.shared.state
        floatingOffset = Double(AppConfiguration.shared.verticalOffset)
        refreshPermission()
    }

    private func refreshPermission() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    var isTakeoverEnabled: Bool { AppConfiguration.shared.isTakeoverEnabled }

    func statusContent() -> (symbol: String, color: Color, text: String, button: String) {
        switch dockState {
        case .floating:
            return ("circle.dashed", .secondary, "悬浮测试模式 · 系统 Dock 未被接管", "接管系统 Dock")
        case .takeover:
            return ("checkmark.circle.fill", .green, "已接管系统 Dock · TideBar 正在贴底运行", "关闭接管并恢复")
        case .drifted:
            return ("exclamationmark.triangle.fill", .orange, "Dock 配置已被外部修改 · 建议检查", "关闭接管并恢复")
        case .failed(let message):
            return ("xmark.circle.fill", .red, "操作失败:\(message)",
                    isTakeoverEnabled ? "关闭接管并恢复" : "接管系统 Dock")
        }
    }

    func toggleTakeover() {
        if isTakeoverEnabled {
            DockController.shared.restore()
        } else {
            DockController.shared.applyTakeover()
        }
        refresh()
    }

    func restoreDock() {
        DockController.shared.restore()
        refresh()
    }

    func repairDock() {
        DockController.shared.repair()
        refresh()
    }

    func setFloatingOffset(_ value: Double) {
        AppConfiguration.shared.setFloatingOffset(CGFloat(value))
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 根视图

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case appearance
    case windows
    case pinned
    case permissions
    case about

    var id: String { rawValue }

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

private struct SettingsRootView: View {
    @ObservedObject private var model: SettingsModel
    @State private var selection: SettingsPage? = .general

    init() {
        model = SettingsModel()
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.symbolName)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralPage(model: model)
                case .appearance:
                    PlaceholderPage(title: "外观",
                                    description: "让汐线与潮涌更贴合你的桌面,相关能力将在后续版本开放。")
                case .windows:
                    PlaceholderPage(title: "窗口",
                                    description: "决定窗口状态如何被发现、切换与还原,相关能力将在后续版本开放。")
                case .pinned:
                    PlaceholderPage(title: "固定项目",
                                    description: "管理你希望始终出现在 TideBar 中的应用,相关能力将在后续版本开放。")
                case .permissions:
                    PermissionsPage(model: model)
                case .about:
                    AboutPage()
                }
            }
        }
    }
}

// MARK: - 通用

private struct GeneralPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    let status = model.statusContent()
                    Image(systemName: status.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(status.color)
                    Text(status.text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(status.button) { model.toggleTakeover() }
                }
            }

            Section {
                LabeledContent("贴底偏移") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { model.floatingOffset },
                                              set: { model.setFloatingOffset($0) }), in: 0...300)
                            .disabled(model.isTakeoverEnabled)
                        Text(model.isTakeoverEnabled ? "已贴底" : "\(Int(model.floatingOffset)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } header: {
                Text("运行方式")
            } footer: {
                Text("悬浮测试模式下与屏幕底边的距离;接管模式自动贴底。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 权限与系统

private struct PermissionsPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("辅助功能权限") {
                    HStack(spacing: 12) {
                        Text(model.accessibilityTrusted ? "已授权" : "未授权")
                            .foregroundStyle(model.accessibilityTrusted ? Color.green : .secondary)
                        Button("打开系统设置") { model.openAccessibilitySettings() }
                    }
                }
            } footer: {
                Text("用于读取窗口列表并将窗口带回前台。")
            }

            Section {
                LabeledContent("恢复配置") {
                    Button("恢复系统 Dock") { model.restoreDock() }
                }
                LabeledContent("配置检查") {
                    Button("检查并修复") { model.repairDock() }
                }
            } header: {
                Text("系统 Dock")
            } footer: {
                Text("「恢复配置」关闭接管并还原 macOS 原始 Dock 设置;「配置检查」检测外部修改并尝试修复。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 关于

private struct AboutPage: View {
    var body: some View {
        Form {
            Section("汐 TideBar") {
                LabeledContent("版本", value: "开发预览版 · 支持 macOS 14 及以上")
                VStack(alignment: .leading, spacing: 2) {
                    Text("产品理念")
                    Text("细线收起,靠近展开;窗口状态一目了然。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 占位页

private struct PlaceholderPage: View {
    let title: String
    let description: String

    var body: some View {
        Form {
            Section {
                Text(description)
                    .foregroundStyle(.secondary)
            } header: {
                Text(title)
            }
        }
        .formStyle(.grouped)
    }
}

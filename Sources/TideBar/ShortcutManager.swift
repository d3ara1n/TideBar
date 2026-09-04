import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTideBar = Self("toggleTideBar",
                                    initial: .init(.space, modifiers: [.option]))
    static let cycleTideBarApplication = Self("cycleTideBarApplication",
                                              initial: .init(.tab, modifiers: [.option]))
}

/// 统一管理 TideBar 的全局快捷键；录制期间由 KeyboardShortcuts 自动暂停热键匹配。
@MainActor
final class ShortcutManager {
    enum Action {
        case toggleBar
        case cycleApplication
    }

    var onAction: ((Action) -> Void)?
    private var eventTasks: [Task<Void, Never>] = []

    func start() {
        stop()
        eventTasks = [
            observe(.toggleTideBar, action: .toggleBar),
            observe(.cycleTideBarApplication, action: .cycleApplication),
        ]
        NSLog("TideBar global hotkeys registered")
    }

    func stop() {
        eventTasks.forEach { $0.cancel() }
        eventTasks.removeAll()
        KeyboardShortcuts.removeAllHandlers()
    }

    private func observe(_ name: KeyboardShortcuts.Name, action: Action) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await event in KeyboardShortcuts.events(for: name) {
                guard !Task.isCancelled, event == .keyDown else { continue }
                self?.onAction?(action)
            }
        }
    }
}

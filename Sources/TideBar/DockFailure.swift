import Foundation

/// TideBar 自有的 Dock 配置错误；状态只保存语义，日志描述固定为英文。
enum DockError: Error, Equatable, Sendable {
    case unsupportedValue(String)
    case synchronizeFailed
    case verificationFailed
    case restartFailed

    var logDescription: String {
        switch self {
        case .unsupportedValue(let key): "unsupported value for key \(key)"
        case .synchronizeFailed: "failed to synchronize Dock preferences"
        case .verificationFailed: "failed to verify Dock configuration"
        case .restartFailed: "failed to restart Dock"
        }
    }
}

/// 系统错误保持系统描述，自有错误在展示时按当前语言解析。
enum DockFailure: Equatable, Sendable {
    case configuration(DockError)
    case system(String)

    func message(in localization: Localization) -> String {
        switch self {
        case .system(let message): return message
        case .configuration(let error):
            switch error {
            case .unsupportedValue(let key):
                return localization.string("dock.error.unsupportedValue", table: .runtime, arguments: key)
            case .synchronizeFailed:
                return localization.string("dock.error.synchronizeFailed", table: .runtime)
            case .verificationFailed:
                return localization.string("dock.error.verificationFailed", table: .runtime)
            case .restartFailed:
                return localization.string("dock.error.restartFailed", table: .runtime)
            }
        }
    }
}

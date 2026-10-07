/// 应用级展示与动作约束。固定配置只决定标准应用的位置，不能覆盖系统行为保护。
public struct AppBehavior: Equatable, Sendable {
    public static let finderIdentity = AppIdentity("com.apple.finder")
    public enum Visibility: Equatable, Sendable {
        case standard
        case whenHasKnownWindows
    }

    public enum Termination: Equatable, Sendable {
        case allowed
        case forbidden
    }

    /// 点击已运行 app 时的窗口前置通道
    public enum WindowRaising: Equatable, Sendable {
        /// 纯进程激活即抬升最近窗口；不发 reopen，防个别 app 借 reopen 误开新窗口
        case viaActivation
        /// 资源管理窗口不随进程激活自动前置，须随激活补发 reopen（Dock 同款通道）
        /// 才抬升；该类 app 有窗口时收到 reopen 只抬升不新开
        case viaReopen
    }

    public let visibility: Visibility
    public let termination: Termination
    public let windowRaising: WindowRaising

    public var canTerminate: Bool { termination == .allowed }

    public func logicalIsRunning(processIsRunning: Bool, knownWindowCount: Int?) -> Bool {
        switch visibility {
        case .standard:
            return processIsRunning
        case .whenHasKnownWindows:
            return processIsRunning && (knownWindowCount ?? 0) > 0
        }
    }

    public func isVisible(isPinned: Bool, processIsRunning: Bool, knownWindowCount: Int?) -> Bool {
        isPinned || logicalIsRunning(processIsRunning: processIsRunning,
                                     knownWindowCount: knownWindowCount)
    }

    public static func resolve(for identity: AppIdentity) -> Self {
        if identity == Self.finderIdentity {
            return Self(visibility: .whenHasKnownWindows, termination: .forbidden,
                        windowRaising: .viaReopen)
        }
        return Self(visibility: .standard, termination: .allowed, windowRaising: .viaActivation)
    }
}

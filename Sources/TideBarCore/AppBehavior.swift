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

    public let visibility: Visibility
    public let termination: Termination

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
            return Self(visibility: .whenHasKnownWindows, termination: .forbidden)
        }
        return Self(visibility: .standard, termination: .allowed)
    }
}

/// 应用级展示与动作约束。固定配置只决定标准应用的位置，不能覆盖系统行为保护。
public struct AppBehavior: Equatable, Sendable {
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

    public func isVisible(isPinned: Bool, isRunning: Bool, knownWindowCount: Int?) -> Bool {
        switch visibility {
        case .standard:
            return isPinned || isRunning
        case .whenHasKnownWindows:
            guard isRunning, let knownWindowCount else { return false }
            return knownWindowCount > 0
        }
    }

    public static func resolve(for identity: AppIdentity) -> Self {
        if identity == AppIdentity("com.apple.finder") {
            return Self(visibility: .whenHasKnownWindows, termination: .forbidden)
        }
        return Self(visibility: .standard, termination: .allowed)
    }
}

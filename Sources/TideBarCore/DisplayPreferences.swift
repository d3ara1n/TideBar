import Foundation

public enum IconSizePreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case spacious

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .spacious: return "宽松"
        }
    }

    public var iconSide: Double {
        switch self {
        case .compact: return 32
        case .standard: return 40
        case .spacious: return 48
        }
    }

    public var iconSlot: Double {
        switch self {
        case .compact: return 44
        case .standard: return 52
        case .spacious: return 60
        }
    }

    public var expandedHeight: Double {
        max(64, iconSide + 24)
    }
}

public enum TideLineBrightness: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case low
    case standard
    case high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "自动"
        case .low: return "低"
        case .standard: return "标准"
        case .high: return "高"
        }
    }

    public func opacity(isDark: Bool) -> Double {
        switch self {
        case .automatic: return isDark ? 0.78 : 0.92
        case .low: return 0.55
        case .standard: return 0.82
        case .high: return 1.0
        }
    }
}

public enum AnimationPreset: String, CaseIterable, Identifiable, Sendable {
    case standard
    case gentle
    case fast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "标准"
        case .gentle: return "柔和"
        case .fast: return "快速"
        }
    }

    public var speedFactor: Double {
        switch self {
        case .standard: return 1.0
        case .gentle: return 0.78
        case .fast: return 1.35
        }
    }
}

public enum ReducedMotionPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case alwaysOff
    case alwaysOn

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "跟随系统"
        case .alwaysOff: return "始终关闭"
        case .alwaysOn: return "始终开启"
        }
    }

    public func isEnabled(systemValue: Bool) -> Bool {
        switch self {
        case .automatic: return systemValue
        case .alwaysOff: return false
        case .alwaysOn: return true
        }
    }
}

public enum FullscreenBehavior: String, CaseIterable, Identifiable, Sendable {
    case lineOnly
    case normal
    case hidden

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lineOnly: return "仅显示汐线"
        case .normal: return "正常显示"
        case .hidden: return "完全隐藏"
        }
    }
}

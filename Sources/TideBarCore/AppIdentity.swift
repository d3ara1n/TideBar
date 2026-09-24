import Foundation

/// 应用运行策略身份。bundle identifier 按 ASCII 不区分大小写比较；它不是栏内资源 item 的唯一身份。
public struct AppIdentity: Hashable, Sendable, CustomStringConvertible {
    public let bundleIdentifier: String

    public init(_ bundleIdentifier: String) {
        self.bundleIdentifier = Self.asciiLowercased(bundleIdentifier)
    }

    public var description: String { bundleIdentifier }

    private static func asciiLowercased(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar in
            guard scalar.value >= 65, scalar.value <= 90,
                  let lowered = UnicodeScalar(scalar.value + 32)
            else { return Character(String(scalar)) }
            return Character(String(lowered))
        })
    }
}

/// 应用资源在 TideBar 中的身份：优先按实际 .app 位置区分，只有无法获得位置时才退化为 bundle ID。
/// 它不承担运行策略、Finder 特判或进程聚合；这些仍由 AppIdentity 表达。
public struct ApplicationItemIdentity: Hashable, Sendable, CustomStringConvertible {
    public let bundleIdentifier: String?
    public let applicationPath: String?

    public init(bundleIdentifier: String?, applicationPath: String?) {
        self.bundleIdentifier = bundleIdentifier.map { AppIdentity($0).bundleIdentifier }
        if let applicationPath {
            self.applicationPath = URL(fileURLWithPath: applicationPath)
                .standardizedFileURL.resolvingSymlinksInPath().path
        } else {
            self.applicationPath = nil
        }
    }

    public var runtimeIdentity: AppIdentity? {
        bundleIdentifier.map(AppIdentity.init)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.applicationPath, rhs.applicationPath) {
        case let (left?, right?):
            return left == right
        case (nil, nil):
            return lhs.bundleIdentifier == rhs.bundleIdentifier
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        if let applicationPath {
            hasher.combine("path")
            hasher.combine(applicationPath)
        } else {
            hasher.combine("bundle")
            hasher.combine(bundleIdentifier)
        }
    }

    public var key: String {
        if let applicationPath {
            return "path:\(applicationPath)"
        }
        if let bundleIdentifier {
            // 保持旧 bundle-only ItemID 的持久化编码兼容。
            return AppIdentity(bundleIdentifier).bundleIdentifier
        }
        return "unknown"
    }

    public var description: String { key }
}

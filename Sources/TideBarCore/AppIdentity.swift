/// 应用在 TideBar 内部的唯一身份。bundle identifier 按 ASCII 不区分大小写比较。
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

/// 窗口观测结果。unknown 表示无法确认，known([]) 表示已确认没有收录窗口。
public enum WindowKnowledge<Element> {
    case unknown
    case known([Element])

    public var elements: [Element]? {
        guard case let .known(elements) = self else { return nil }
        return elements
    }

    public func map<NewElement>(_ transform: (Element) -> NewElement) -> WindowKnowledge<NewElement> {
        switch self {
        case .unknown:
            return .unknown
        case let .known(elements):
            return .known(elements.map(transform))
        }
    }

    /// 聚合多个运行实例；任一实例未知时，整体未知，避免报告不完整窗口数。
    public static func aggregate(_ knowledge: [Self]) -> Self {
        var result: [Element] = []
        for item in knowledge {
            guard case let .known(elements) = item else { return .unknown }
            result += elements
        }
        return .known(result)
    }
}

extension WindowKnowledge: Equatable where Element: Equatable {}
extension WindowKnowledge: Sendable where Element: Sendable {}

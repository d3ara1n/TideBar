import Foundation

/// 可扩展的类型键；未知类型仍能保留持久化内容，不要求它对应文件或进程。
public struct ItemKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let application = Self(rawValue: "application")
    public static let file = Self(rawValue: "file")
    public static let directory = Self(rawValue: "directory")
}

public struct ItemID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func application(_ identity: AppIdentity) -> Self {
        Self(rawValue: "application:\(identity.bundleIdentifier)")
    }
    public static func resource() -> Self { Self(rawValue: "resource:\(UUID().uuidString)") }
}

/// 不透明引用：schema 的解释权属于操作实现。拖拽路由不解码，更不统一 resolve。
public struct ItemReference: Codable, Hashable, Sendable {
    public let scheme: String
    public let payload: Data
    public init(scheme: String, payload: Data) {
        self.scheme = scheme
        self.payload = payload
    }
}

public struct PinnedItemRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: ItemID
    public let kind: ItemKind
    public var reference: ItemReference
    public var fallbackName: String
    public init(id: ItemID, kind: ItemKind, reference: ItemReference, fallbackName: String) {
        self.id = id
        self.kind = kind
        self.reference = reference
        self.fallbackName = fallbackName
    }
}

public struct PinnedItemDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var records: [PinnedItemRecord]
    public init(records: [PinnedItemRecord]) {
        version = 1
        self.records = records
    }
}

public enum ItemDragPayload: Equatable, Sendable {
    case internalItem(ItemID)
    case externalReferences([ItemReference])
}

/// 图标中心可成为接收目标；before 是同一位置用于引用重排的插入锚点。
public struct ItemDropLocation: Equatable, Sendable {
    public let target: ItemID?
    public let before: ItemID?
    public init(target: ItemID?, before: ItemID?) {
        self.target = target
        self.before = before
    }
}

public enum ItemDropIntent: Equatable, Sendable {
    case reorder(ItemID, before: ItemID?)
    case insert([ItemReference], before: ItemID?)
    case deliver([ItemReference], to: ItemID)

    public static func route(_ payload: ItemDragPayload, at location: ItemDropLocation) -> Self {
        switch payload {
        case .internalItem(let id):
            // 内部引用永不转换为外部资源，即使目标拥有接收能力。
            return .reorder(id, before: location.before)
        case .externalReferences(let references):
            if let target = location.target { return .deliver(references, to: target) }
            return .insert(references, before: location.before)
        }
    }
}

/// 按身份移动，不使用可能因窗口／应用变化而失效的下标；不存在的锚点拒绝提交。
public enum ItemOrdering {
    public static func moving(_ moving: [ItemID], before anchor: ItemID?, in order: [ItemID]) -> [ItemID]? {
        let ids = Set(moving)
        guard ids.count == moving.count, ids.isSubset(of: Set(order)) else { return nil }
        var insertionAnchor = anchor
        if let anchor {
            guard let index = order.firstIndex(of: anchor) else { return nil }
            if ids.contains(anchor) {
                insertionAnchor = order[index...].first { !ids.contains($0) }
            }
        }
        var result = order.filter { !ids.contains($0) }
        let index = insertionAnchor.flatMap { result.firstIndex(of: $0) } ?? result.endIndex
        result.insert(contentsOf: moving, at: index)
        return result
    }
}

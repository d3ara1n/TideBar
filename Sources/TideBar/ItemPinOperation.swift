import Foundation
import TideBarCore

/// 创建关联操作共享于栏与设置页；只有这个操作解释可固定资源的引用。
enum ItemPinOperation {
    private static let factories: [String: @Sendable (ItemReference) throws -> PinnedItemRecord] = [
        "file-url": { try ItemReferences.record(for: $0) }
    ]

    static func accepts(_ references: [ItemReference]) -> Bool {
        !references.isEmpty && references.allSatisfy { factories[$0.scheme] != nil }
    }

    static func prepare(_ references: [ItemReference], existing: [PinnedItemRecord]) throws
        -> (records: [PinnedItemRecord], inserted: [ItemID]) {
        var records = existing
        var inserted: [ItemID] = []
        for reference in references {
            guard let factory = factories[reference.scheme] else { throw ItemFailure("item.error.reference") }
            let candidate = try factory(reference)
            if let index = records.firstIndex(where: {
                $0.id == candidate.id || ($0.kind != .application && candidate.kind != .application
                                          && ItemReferences.sameFile($0.reference, candidate.reference))
            }) {
                let id = records[index].id
                records[index] = PinnedItemRecord(id: id, kind: candidate.kind,
                                                 reference: candidate.reference, fallbackName: candidate.fallbackName)
                if !inserted.contains(id) { inserted.append(id) }
            } else {
                records.append(candidate)
                inserted.append(candidate.id)
            }
        }
        return (records, inserted)
    }
}

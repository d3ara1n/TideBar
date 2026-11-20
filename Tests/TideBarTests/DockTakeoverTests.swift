import Foundation
import Testing
@testable import TideBar

private typealias Snapshot = DockController.Snapshot
private typealias Value = DockController.StoredValue

@Test @MainActor
func takeoverManagesOnlyNonAppearancePreferences() {
    let managedKeys = Set(DockController.Key.allCases.map(\.rawValue))
    #expect(managedKeys == ["autohide", "autohide-delay", "autohide-time-modifier", "no-bouncing", "mineffect"])
    #expect(Set(DockController.target.keys.map(\.rawValue)) == managedKeys)
}

@Test
func legacyAppearanceRestoresOriginalValuesAndRemovesPreviouslyAbsentKeys() {
    let snapshot = Snapshot(version: 1, createdAt: .distantPast, values: [
        "tilesize": .integer(54), "magnification": .bool(true),
    ])
    let current: [String: Value] = [
        "tilesize": .real(16), "magnification": .bool(false), "largesize": .integer(16),
    ]
    let changes = snapshot.legacyAppearanceRestoration { current[$0] }
    #expect(changes.count == 3)
    #expect(changes.contains { $0.key == "tilesize" && $0.value == .integer(54) })
    #expect(changes.contains { $0.key == "magnification" && $0.value == .bool(true) })
    #expect(changes.contains { $0.key == "largesize" && $0.value == nil })
}

@Test
func legacyAppearanceDoesNotOverwriteUserChangesOrRestoreDeletedKeys() {
    let snapshot = Snapshot(version: 1, createdAt: .distantPast, values: [
        "tilesize": .integer(48), "magnification": .bool(false), "largesize": .integer(72),
    ])
    let current: [String: Value] = ["tilesize": .integer(60), "magnification": .bool(true)]
    #expect(snapshot.legacyAppearanceRestoration { current[$0] }.isEmpty)

    let partial: [String: Value] = ["tilesize": .integer(16), "magnification": .bool(true)]
    let changes = snapshot.legacyAppearanceRestoration { partial[$0] }
    #expect(changes.count == 1)
    #expect(changes.first?.key == "tilesize")
    #expect(changes.first?.value == .integer(48))
}

@Test
func storedValueDistinguishesBooleansFromZeroAndOne() {
    #expect(Value(object: NSNumber(value: true)) == .bool(true))
    #expect(Value(object: NSNumber(value: false)) == .bool(false))
    #expect(Value(object: NSNumber(value: 1)) == .integer(1))
    #expect(Value(object: NSNumber(value: 0)) == .integer(0))
    #expect(!Value.bool(true).matches(.integer(16)))
}

@Test
func migratedSnapshotRetainsOnlyManagedOriginalValues() throws {
    let legacy = Snapshot(version: 1, createdAt: .distantPast, values: [
        "tilesize": .integer(48), "magnification": .bool(true), "largesize": .integer(72),
        "autohide": .bool(false), "mineffect": .string("genie"),
    ])
    let oldData = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(Snapshot.self, from: oldData)
    let migrated = try decoded.checkpointLegacyAppearance(restore: {}, save: { _ in })
    #expect(migrated.version == Snapshot.currentVersion)
    #expect(migrated.createdAt == legacy.createdAt)
    #expect(migrated.values == ["autohide": .bool(false), "mineffect": .string("genie")])
    #expect(migrated.legacyAppearanceRestoration { _ in
        Issue.record("A migrated snapshot must not read or change Dock appearance preferences")
        return nil
    }.isEmpty)
}

@Test
func retryingDockReloadDoesNotOverwriteEditsAfterMigration() throws {
    var persisted = Snapshot(version: 1, createdAt: .distantPast, values: ["magnification": .bool(true)])
    var dock: [String: Value] = ["magnification": .bool(false)]
    var appearanceWrites = 0
    func save(_ snapshot: Snapshot) throws {
        // 模拟重启后从持久化数据读取，不依赖内存标记。
        persisted = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
    }
    func releaseAppearance() throws -> Snapshot {
        let snapshot = persisted
        return try snapshot.checkpointLegacyAppearance(restore: {
            for (key, value) in snapshot.legacyAppearanceRestoration(read: { dock[$0] }) {
                dock[key] = value
                appearanceWrites += 1
            }
        }, save: save)
    }

    let checkpoint = try releaseAppearance()
    #expect(dock["magnification"] == .bool(true))
    #expect(throws: DockError.restartFailed) {
        try checkpoint.reloadDockIfNeeded(reload: { throw DockError.restartFailed }, save: save)
    }
    #expect(persisted.needsDockReload == true)

    dock["magnification"] = .bool(false)
    let retry = try releaseAppearance()
    var reloads = 0
    try retry.reloadDockIfNeeded(reload: { reloads += 1 }, save: save)
    try persisted.reloadDockIfNeeded(reload: { reloads += 1 }, save: save)
    #expect(dock["magnification"] == .bool(false))
    #expect(appearanceWrites == 1)
    #expect(reloads == 1)
    #expect(persisted.needsDockReload == nil)
}

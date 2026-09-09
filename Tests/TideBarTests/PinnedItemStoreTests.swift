import Foundation
import Testing
import TideBarCore
@testable import TideBar

@MainActor
private func withPinnedDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let name = "dev.dearain.TideBar.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Test @MainActor func legacyPinsMigrateInOrderWithoutDuplicates() throws {
    try withPinnedDefaults { defaults in
        defaults.set(["Com.Example.One", "com.example.one", "com.example.two"], forKey: "tidebar.pinned")
        let store = PinnedItemStore(defaults: defaults)
        #expect(store.loadError == nil)
        #expect(store.applicationBundleIdentifiers == ["Com.Example.One", "com.example.two"])
        #expect(defaults.data(forKey: "tidebar.pinnedItems.v1") != nil)
        #expect(PinnedItemStore(defaults: defaults).records == store.records)
    }
}

@Test @MainActor func explicitEmptyLegacyPinsStayEmpty() throws {
    try withPinnedDefaults { defaults in
        defaults.set([String](), forKey: "tidebar.pinned")
        #expect(PinnedItemStore(defaults: defaults).records.isEmpty)
    }
}

@Test @MainActor func corruptPinnedDocumentIsNotOverwritten() throws {
    try withPinnedDefaults { defaults in
        let data = Data("not a document".utf8)
        defaults.set(data, forKey: "tidebar.pinnedItems.v1")
        let store = PinnedItemStore(defaults: defaults)
        #expect(store.loadError != nil)
        #expect(throws: (any Error).self) { try store.setPinned(true, bundleIdentifier: "com.example.app") }
        #expect(defaults.data(forKey: "tidebar.pinnedItems.v1") == data)
        try store.restoreDefaults()
        #expect(store.loadError == nil)
        #expect(!store.records.isEmpty)
    }
}

@Test @MainActor func unknownItemKindsSurviveStorageAndReordering() throws {
    try withPinnedDefaults { defaults in
        let store = PinnedItemStore(defaults: defaults)
        let widget = PinnedItemRecord(id: .resource(), kind: .init(rawValue: "widget"),
                                      reference: .init(scheme: "opaque", payload: Data([7])), fallbackName: "Widget")
        let file = PinnedItemRecord(id: .resource(), kind: .file,
                                    reference: .init(scheme: "opaque-file", payload: Data([8])), fallbackName: "File")
        try store.replace([widget, file])
        try store.move(from: [0], to: 2)
        #expect(store.records == [file, widget])
        #expect(PinnedItemStore(defaults: defaults).records == [file, widget])
    }
}

@Test @MainActor func unsupportedVersionIsPreserved() throws {
    try withPinnedDefaults { defaults in
        var document = PinnedItemDocument(records: [])
        document.version = 99
        let data = try JSONEncoder().encode(document)
        defaults.set(data, forKey: "tidebar.pinnedItems.v1")
        let store = PinnedItemStore(defaults: defaults)
        #expect(store.loadError != nil)
        #expect(defaults.data(forKey: "tidebar.pinnedItems.v1") == data)
    }
}

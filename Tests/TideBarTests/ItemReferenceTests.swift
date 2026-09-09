import Foundation
import Testing
import TideBarCore
@testable import TideBar

private func withItemFiles(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/item-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

@Test func fixedFileReferencesDeduplicateWithoutMovingTheirSources() throws {
    try withItemFiles { root in
        let file = root.appendingPathComponent("File.txt")
        try Data("content".utf8).write(to: file)
        let reference = ItemReferences.externalFile(file)
        let first = try ItemPinOperation.prepare([reference], existing: [])
        let second = try ItemPinOperation.prepare([reference, reference], existing: first.records)
        #expect(second.records.count == 1)
        #expect(second.records[0].id == first.records[0].id)
        #expect(second.records[0].kind == .file)
        #expect(try ItemReferences.fileURL(second.records[0].reference) == file)
        #expect(try Data(contentsOf: file) == Data("content".utf8))
    }
}

@Test func directoryMovePreflightRejectsConflictsAndSelfContainment() throws {
    try withItemFiles { root in
        let directory = root.appendingPathComponent("Destination", isDirectory: true)
        let child = directory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("File.txt")
        try Data().write(to: file)
        try Data().write(to: directory.appendingPathComponent("File.txt"))
        #expect(throws: (any Error).self) {
            try FileMoveOperation.preflight([ItemReferences.externalFile(file)], target: ItemReferences.externalFile(directory))
        }
        #expect(throws: (any Error).self) {
            try FileMoveOperation.preflight([ItemReferences.externalFile(directory)], target: ItemReferences.externalFile(child))
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: child.path))
    }
}

@Test func directoryPreflightDoesNotMoveFiles() throws {
    try withItemFiles { root in
        let directory = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("File.txt")
        try Data().write(to: file)
        let pairs = try FileMoveOperation.preflight([ItemReferences.externalFile(file)],
                                                   target: ItemReferences.externalFile(directory))
        #expect(pairs.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("File.txt").path))
    }
}

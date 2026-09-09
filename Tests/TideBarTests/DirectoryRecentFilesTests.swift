import Foundation
import Testing
import TideBarCore
@testable import TideBar

/// 目录最近文件数据源：排序、截取、预算封顶与状态判定。
/// 潮涌体状态呈现（空／不可读／截断）由这些真值驱动。
final class DirectoryRecentFilesTests {
    private var counter = 0

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidebar-surge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 目录枚举返回 /private/var 实路径而 temporaryDirectory 是 firmlink 路径，
    /// 不比较 URL 字符串，按文件名断言顺序。
    private func rowNames(_ outcome: DirectoryRecentFiles.Outcome) -> [String] {
        guard case .rows(let urls) = outcome.state else { return [] }
        return urls.map(\.lastPathComponent)
    }

    @discardableResult
    private func writeFile(named name: String, in directory: URL,
                           modifiedDaysAgo days: Double) throws -> URL {
        counter += 1
        let url = directory.appendingPathComponent(name)
        try Data("v\(counter)".utf8).write(to: url)
        let date = Date(timeIntervalSinceNow: -days * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    @Test func sortsByModificationDateDescending() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try writeFile(named: "a-old.txt", in: directory, modifiedDaysAgo: 5)
        let newest = try writeFile(named: "b-newest.txt", in: directory, modifiedDaysAgo: 0.5)
        let middle = try writeFile(named: "c-middle.txt", in: directory, modifiedDaysAgo: 2)

        let outcome = DirectoryRecentFiles.load(from: directory, limit: 8, entryBudget: 20_000)

        #expect(rowNames(outcome) == ["b-newest.txt", "c-middle.txt", "a-old.txt"])
        #expect(!outcome.isPartial)
    }

    @Test func limitCapsRowsToMostRecent() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<5 {
            try writeFile(named: "file-\(index).txt", in: directory, modifiedDaysAgo: Double(index))
        }

        let outcome = DirectoryRecentFiles.load(from: directory, limit: 2, entryBudget: 20_000)

        #expect(rowNames(outcome) == ["file-0.txt", "file-1.txt"])
        #expect(!outcome.isPartial)
    }

    @Test func entryBudgetMarksPartialAndCapsProcessedEntries() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 目录迭代顺序任意：不断言具体哪些条目被处理，只断言封顶与部分标记
        for index in 0..<3 {
            try writeFile(named: "file-\(index).txt", in: directory, modifiedDaysAgo: Double(index))
        }

        let outcome = DirectoryRecentFiles.load(from: directory, limit: 8, entryBudget: 2)

        #expect(outcome.isPartial)
        guard case .rows(let urls) = outcome.state else {
            Issue.record("expected rows")
            return
        }
        #expect(urls.count == 2)

        // 部分视图下显示上限依旧生效
        let capped = DirectoryRecentFiles.load(from: directory, limit: 1, entryBudget: 2)
        #expect(capped.isPartial)
        guard case .rows(let cappedURLs) = capped.state else {
            Issue.record("expected rows")
            return
        }
        #expect(cappedURLs.count == 1)
    }

    @Test func emptyDirectoryReportsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(named: ".hidden", in: directory, modifiedDaysAgo: 0)

        // 隐藏文件被跳过后等同空目录
        let outcome = DirectoryRecentFiles.load(from: directory, limit: 8, entryBudget: 20_000)

        #expect(outcome.state == .empty)
        #expect(!outcome.isPartial)
    }

    @Test func missingDirectoryReportsFailed() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidebar-surge-missing-\(UUID().uuidString)", isDirectory: true)

        let outcome = DirectoryRecentFiles.load(from: missing, limit: 8, entryBudget: 20_000)

        #expect(outcome.state == .failed)
        #expect(!outcome.isPartial)
    }
}

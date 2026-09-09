import AppKit
import TideBarCore
import UniformTypeIdentifiers

/// 仅文件／应用相关操作解释这些 schema；其他 item 的操作可以直接消费自己的引用。
enum ItemReferences {
    struct ApplicationLocator: Codable, Hashable {
        let bundleIdentifier: String
        let bookmark: Data?
    }

    static func externalFile(_ url: URL) -> ItemReference {
        ItemReference(scheme: "file-url", payload: Data(url.absoluteString.utf8))
    }

    static func application(_ bundleIdentifier: String, url: URL? = nil) throws -> ItemReference {
        let locator = ApplicationLocator(bundleIdentifier: bundleIdentifier,
                                         bookmark: try url?.bookmarkData(options: .minimalBookmark))
        return ItemReference(scheme: "application", payload: try JSONEncoder().encode(locator))
    }

    static func applicationLocator(_ reference: ItemReference) -> ApplicationLocator? {
        guard reference.scheme == "application" else { return nil }
        return try? JSONDecoder().decode(ApplicationLocator.self, from: reference.payload)
    }

    static func fileURL(_ reference: ItemReference) throws -> URL {
        let url: URL
        switch reference.scheme {
        case "file-url":
            guard let string = String(data: reference.payload, encoding: .utf8),
                  let value = URL(string: string), value.isFileURL else { throw ItemFailure("item.error.reference") }
            url = value
        case "file-bookmark":
            var stale = false
            url = try URL(resolvingBookmarkData: reference.payload, options: [.withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        default:
            throw ItemFailure("item.error.reference")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw ItemFailure("item.error.missing") }
        return url
    }

    static func refreshBookmark(_ reference: ItemReference) throws -> ItemReference {
        guard reference.scheme == "file-bookmark" else { return reference }
        var stale = false
        let url = try URL(resolvingBookmarkData: reference.payload, options: [.withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        guard stale, FileManager.default.fileExists(atPath: url.path) else { return reference }
        return ItemReference(scheme: "file-bookmark", payload: try url.bookmarkData(options: .minimalBookmark))
    }

    @MainActor
    static func applicationURL(_ reference: ItemReference) -> URL? {
        guard let locator = applicationLocator(reference) else { return nil }
        if let bookmark = locator.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               let actualID = Bundle(url: url)?.bundleIdentifier,
               AppIdentity(actualID) == AppIdentity(locator.bundleIdentifier) { return url }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: locator.bundleIdentifier)
    }

    /// 创建关联是一个具体操作；在这里识别文件类型并持久化定位，不在拖拽路由中 resolve。
    static func record(for reference: ItemReference) throws -> PinnedItemRecord {
        let url = try fileURL(reference)
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .localizedNameKey])
        if values.contentType?.conforms(to: .applicationBundle) == true {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { throw ItemFailure("item.error.reference") }
            return PinnedItemRecord(id: .application(AppIdentity(bundleID)), kind: .application,
                                    reference: try application(bundleID, url: url),
                                    fallbackName: url.deletingPathExtension().lastPathComponent)
        }
        return PinnedItemRecord(id: .resource(), kind: values.isDirectory == true ? .directory : .file,
                                reference: ItemReference(scheme: "file-bookmark",
                                                         payload: try url.bookmarkData(options: .minimalBookmark)),
                                fallbackName: values.localizedName ?? url.lastPathComponent)
    }

    static func sameFile(_ a: ItemReference, _ b: ItemReference) -> Bool {
        guard let first = try? fileURL(a), let second = try? fileURL(b) else { return false }
        if first.standardizedFileURL == second.standardizedFileURL { return true }
        guard let firstID = try? first.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]),
              let secondID = try? second.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]),
              let fileA = firstID.fileResourceIdentifier as? NSObject,
              let fileB = secondID.fileResourceIdentifier as? NSObject,
              let volumeA = firstID.volumeIdentifier as? NSObject,
              let volumeB = secondID.volumeIdentifier as? NSObject else { return false }
        return fileA == fileB && volumeA == volumeB
    }
}

struct ItemFailure: Error, Sendable {
    let key: String
    init(_ key: String) { self.key = key }
}

@MainActor
enum ItemErrors {
    static func report(_ error: Error) {
        NSLog("TideBar item operation failed: %@", String(describing: error))
        // 在原生 drop／菜单回调退出后显示错误，不在拖拽追踪中启动嵌套模态操作。
        DispatchQueue.main.async {
            let l10n = L10nManager.shared.current
            let alert = NSAlert()
            alert.messageText = l10n.string("item.error.title", table: .runtime)
            alert.informativeText = (error as? ItemFailure).map { l10n.string($0.key, table: .runtime) }
                ?? error.localizedDescription
            alert.addButton(withTitle: l10n.string("item.error.ok", table: .runtime))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

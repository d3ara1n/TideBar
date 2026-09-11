import AppKit
import TideBarCore
import UniformTypeIdentifiers

struct ItemCapabilities: OptionSet {
    let rawValue: Int
    static let open = Self(rawValue: 1 << 0)
    static let reveal = Self(rawValue: 1 << 1)
    static let receive = Self(rawValue: 1 << 2)
    /// 提供长按潮涌体（应用窗口列表、目录最近文件等）
    static let surgeBody = Self(rawValue: 1 << 3)
}

struct ItemPresentation {
    let name: String
    let icon: NSImage
    let isAvailable: Bool
    /// nil 表示普通固定图标槽；小工具可声明自己的展开态宽度。
    let preferredBarWidth: CGFloat?

    init(name: String, icon: NSImage, isAvailable: Bool, preferredBarWidth: CGFloat? = nil) {
        self.name = name
        self.icon = icon
        self.isAvailable = isAvailable
        self.preferredBarWidth = preferredBarWidth
    }
}

/// 提案只声明结果和执行入口；操作是否需要 resolve 不属于调用方契约。
@MainActor
struct ItemReceiveProposal {
    let operation: NSDragOperation
    let execute: () throws -> Void
}

@MainActor
protocol ItemBehaviorProviding {
    var capabilities: ItemCapabilities { get }
    func presentation(for record: PinnedItemRecord) -> ItemPresentation
    func open(_ reference: ItemReference) async throws
    func reveal(_ reference: ItemReference) throws
    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal?
    /// 构造潮涌体；无内容返回 nil。按需计算（目录枚举等）可离主线程。
    func surgeBody(for entry: ItemEntry, on screen: NSScreen) async -> AnySurgeBody?
    /// 栏内自定义展示（小工具的图标位可完全自绘）；nil 走通用图标。
    /// 必须是 requirement：经 any 存在类型调用，extension 默认实现只给不实现者用。
    func barArtwork(for entry: ItemEntry) -> AnyBarArtwork?
}

extension ItemBehaviorProviding {
    func open(_ reference: ItemReference) async throws { throw ItemFailure("item.error.reference") }
    func reveal(_ reference: ItemReference) throws { throw ItemFailure("item.error.reference") }
    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal? { nil }
    func surgeBody(for entry: ItemEntry, on screen: NSScreen) async -> AnySurgeBody? { nil }
    /// 栏内自定义展示（小工具的图标位可完全自绘）；nil 走通用图标
    func barArtwork(for entry: ItemEntry) -> AnyBarArtwork? { nil }
}

@MainActor
enum ItemBehaviors {
    private static let providers: [ItemKind: any ItemBehaviorProviding] = [
        .application: ApplicationItemBehavior(),
        .file: FileItemBehavior(isDirectory: false),
        .directory: FileItemBehavior(isDirectory: true)
    ]
    static func provider(for kind: ItemKind) -> (any ItemBehaviorProviding)? { providers[kind] }

    static func provider(for record: PinnedItemRecord) -> (any ItemBehaviorProviding)? {
        if record.kind == .widget { return widgetProvider(for: record) }
        return provider(for: record.kind)
    }

    static func provider(for entry: ItemEntry) -> (any ItemBehaviorProviding)? {
        provider(for: PinnedItemRecord(id: entry.id, kind: entry.kind,
                                       reference: entry.reference, fallbackName: entry.name))
    }

    static func presentation(for record: PinnedItemRecord) -> ItemPresentation {
        provider(for: record)?.presentation(for: record)
            ?? ItemPresentation(name: record.fallbackName,
                                icon: NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil) ?? NSImage(),
                                isAvailable: false, preferredBarWidth: nil)
    }
}

@MainActor
private struct ApplicationItemBehavior: ItemBehaviorProviding {
    let capabilities: ItemCapabilities = [.open, .reveal, .receive, .surgeBody]
    func presentation(for record: PinnedItemRecord) -> ItemPresentation {
        let url = ItemReferences.applicationURL(record.reference)
        return ItemPresentation(name: url?.deletingPathExtension().lastPathComponent ?? record.fallbackName,
                                icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                                    ?? NSWorkspace.shared.icon(for: .application),
                                isAvailable: url != nil, preferredBarWidth: nil)
    }
    func open(_ reference: ItemReference) async throws {
        guard let url = ItemReferences.applicationURL(reference) else { throw ItemFailure("item.error.missing") }
        try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    func reveal(_ reference: ItemReference) throws {
        guard let url = ItemReferences.applicationURL(reference) else { throw ItemFailure("item.error.missing") }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func surgeBody(for entry: ItemEntry, on screen: NSScreen) async -> AnySurgeBody? {
        // 未运行或窗口知识降级的应用没有潮涌体（与既有窗口列表门槛一致）
        guard let app = entry.application, let windows = app.windows, !windows.isEmpty else { return nil }
        return AppSurgeView(windows: windows, screen: screen, appIcon: app.icon)
    }
    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal? {
        guard !references.isEmpty, let appURL = ItemReferences.applicationURL(target),
              let urls = try? references.map(ItemReferences.fileURL),
              urls.allSatisfy({ url in
                  // Launch Services 声明接收能力；不把任意文件硬塞给不支持它的应用。
                  NSWorkspace.shared.urlsForApplications(toOpen: url).contains {
                      $0.standardizedFileURL == appURL.standardizedFileURL
                  }
              }) else { return nil }
        return ItemReceiveProposal(operation: .copy) {
            guard let destination = ItemReferences.applicationURL(target) else { throw ItemFailure("item.error.missing") }
            let latestURLs = try references.map(ItemReferences.fileURL)
            Task {
                do { try await NSWorkspace.shared.open(latestURLs, withApplicationAt: destination, configuration: .init()) }
                catch { ItemErrors.report(error) }
            }
        }
    }
}

@MainActor
private struct FileItemBehavior: ItemBehaviorProviding {
    let isDirectory: Bool
    var capabilities: ItemCapabilities {
        isDirectory ? [.open, .reveal, .receive, .surgeBody] : [.open, .reveal]
    }
    func presentation(for record: PinnedItemRecord) -> ItemPresentation {
        let url = try? ItemReferences.fileURL(record.reference)
        return ItemPresentation(name: url.map { FileManager.default.displayName(atPath: $0.path) } ?? record.fallbackName,
                                icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                                    ?? NSWorkspace.shared.icon(for: isDirectory ? .folder : .data),
                                isAvailable: url != nil, preferredBarWidth: nil)
    }
    func open(_ reference: ItemReference) async throws {
        let url = try ItemReferences.fileURL(reference)
        guard NSWorkspace.shared.open(url) else { throw ItemFailure("item.error.open") }
    }
    func reveal(_ reference: ItemReference) throws {
        NSWorkspace.shared.activateFileViewerSelecting([try ItemReferences.fileURL(reference)])
    }
    func surgeBody(for entry: ItemEntry, on screen: NSScreen) async -> AnySurgeBody? {
        // 文件条目的伪预览体是下一阶段目标，本期只有目录提供最近文件体
        guard isDirectory else { return nil }
        guard let directory = try? ItemReferences.fileURL(entry.reference) else {
            return DirectorySurgeView(outcome: .init(state: .failed))
        }
        let limit = Layout.surgeRecentLimit
        let budget = Layout.surgeRecentEntryBudget
        // 病态大目录的枚举离主线程；结果回主线程装配视图
        let outcome = await Task.detached(priority: .userInitiated) {
            DirectoryRecentFiles.load(from: directory, limit: limit, entryBudget: budget)
        }.value
        return DirectorySurgeView(outcome: outcome)
    }
    func receive(_ references: [ItemReference], at target: ItemReference) -> ItemReceiveProposal? {
        guard isDirectory, !references.isEmpty,
              (try? FileMoveOperation.preflight(references, target: target)) != nil else { return nil }
        return ItemReceiveProposal(operation: .move) {
            // .move 必须在真正完成后才向系统报告成功，不能先返回 true 再异步尝试。
            // 只接受同卷重命名式移动；跨卷复制／删除不在这个同步 drop 契约内。
            let pairs = try FileMoveOperation.preflight(references, target: target)
            var completed = 0
            do {
                for (source, destination) in pairs {
                    try FileManager.default.moveItem(at: source, to: destination)
                    completed += 1
                }
            } catch {
                if completed > 0 { throw ItemFailure("item.error.partialMove") }
                throw error
            }
        }
    }
}

/// 整批先校验；执行仍可能部分失败，绝不以危险的自动回滚掩盖已发生的移动。
enum FileMoveOperation {
    static func preflight(_ references: [ItemReference], target: ItemReference) throws -> [(URL, URL)] {
        let directory = try ItemReferences.fileURL(target).resolvingSymlinksInPath().standardizedFileURL
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .volumeIdentifierKey])
        guard directoryValues.isDirectory == true else {
            throw ItemFailure("item.error.missing")
        }
        let sources = try references.map { try ItemReferences.fileURL($0).standardizedFileURL }
        var destinations = Set<URL>()
        return try sources.map { source in
            let sourceVolume = try source.resourceValues(forKeys: [.volumeIdentifierKey])
            guard let sourceID = sourceVolume.volumeIdentifier as? NSObject,
                  let destinationID = directoryValues.volumeIdentifier as? NSObject,
                  sourceID == destinationID else { throw ItemFailure("item.error.crossVolume") }
            let resolved = source.resolvingSymlinksInPath().standardizedFileURL
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            // 文件夹本身及子树不能接收自己；多源之间也不能包含父子关系。
            guard resolved != directory, !directory.path.hasPrefix(resolved.path + "/"),
                  !sources.contains(where: {
                      let other = $0.resolvingSymlinksInPath().standardizedFileURL
                      return other != resolved && resolved.path.hasPrefix(other.path + "/")
                  }),
                  destinations.insert(destination).inserted,
                  !FileManager.default.fileExists(atPath: destination.path) else {
                throw ItemFailure("item.error.moveConflict")
            }
            return (source, destination)
        }
    }
}

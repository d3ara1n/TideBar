import AppKit
import TideBarCore

/// 应用收藏夹的潮涌体。实例内容、排序、移除与改名都在这里完成。
/// 面板尺寸固定、网格内部滚动；视觉与 SurgeRowView 同套语言：
/// 玻璃上 label 色系，旧系统回退深色卡上白色系；词条 draw 时解析，语言切换即时生效。
@MainActor
final class ApplicationLauncherSurgeView: NSView, SurgeBody, NSDraggingSource, NSTextFieldDelegate {
    static let internalType = NSPasteboard.PasteboardType("dev.dearain.TideBar.application-launcher-item")

    var onOpen: ((URL) -> Void)?
    var onApplicationsChange: (([ItemReference]) -> Void)?
    var onExternalDropOperation: ((any NSDraggingInfo) -> NSDragOperation)?
    var onPerformExternalDrop: ((any NSDraggingInfo) -> Bool)?
    var onRename: ((String) -> Void)?

    private let titleField = NSTextField()
    private let editButton = NSButton()
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let emptyStateView = LauncherEmptyStateView()
    private var itemViews: [LauncherItemView] = []
    private var applicationReferences: [ItemReference]
    private var currentDisplayName: String
    private var editingTitle = false
    private var dragSourceIndex: Int?
    private var dragCommitted = false
    private var dropIndex: Int?

    private var onGlass: Bool { BarBackgroundFactory.usesGlass }
    private var gridHeight: CGFloat { CGFloat(Layout.launcherVisibleRows) * Layout.launcherCellHeight }

    var bodySize: NSSize {
        NSSize(width: Layout.launcherWidth,
               height: Layout.launcherHeaderHeight + gridHeight + Layout.launcherFooterHeight)
    }

    init(reference: ItemReference, screen: NSScreen) {
        applicationReferences = WidgetReferences.applicationLauncherConfiguration(for: reference)?.applications ?? []
        currentDisplayName = WidgetReferences.payload(for: reference)?.displayName
            ?? WidgetReferences.defaultApplicationLauncherName()
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([Self.internalType, .fileURL])
        configureTitle()
        configureScrollView()
        emptyStateView.isHidden = !applicationReferences.isEmpty
        addSubview(emptyStateView)
        reloadItems()
        frame = NSRect(origin: .zero, size: bodySize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func configureTitle() {
        titleField.stringValue = currentDisplayName
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.alignment = .center
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        // 标题默认只读：编辑由右侧铅笔按钮显式进入，开面板绝不自动进编辑态
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.delegate = self
        addSubview(titleField)

        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        editButton.imageScaling = .scaleProportionallyDown
        editButton.target = self
        editButton.action = #selector(beginTitleEditing)
        addSubview(editButton)
        refreshTitleColors()
    }

    private func refreshTitleColors() {
        let secondary = onGlass ? NSColor.secondaryLabelColor : NSColor.white.withAlphaComponent(0.55)
        titleField.textColor = onGlass ? .labelColor : NSColor.white.withAlphaComponent(0.92)
        editButton.contentTintColor = secondary
        editButton.toolTip = L10nManager.shared.current.string("surge.launcher.rename", table: .runtime)
    }

    @objc private func beginTitleEditing() {
        guard !editingTitle else { return }
        editingTitle = true
        editButton.isHidden = true
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.drawsBackground = true
        titleField.backgroundColor = onGlass ? NSColor.labelColor.withAlphaComponent(0.08)
                                             : NSColor.white.withAlphaComponent(0.1)
        needsDisplay = true
        window?.makeFirstResponder(titleField)
    }

    private func endTitleEditing(commit: Bool) {
        if commit {
            let trimmed = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != currentDisplayName {
                currentDisplayName = trimmed
                onRename?(trimmed)
            }
        }
        editingTitle = false
        titleField.stringValue = currentDisplayName
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.drawsBackground = false
        editButton.isHidden = false
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    private func reloadItems() {
        for view in itemViews { view.removeFromSuperview() }
        itemViews.removeAll()
        let unavailableName = L10nManager.shared.current.string("surge.launcher.unavailable", table: .runtime)
        for (index, reference) in applicationReferences.enumerated() {
            let item = LauncherItemView(frame: .zero)
            let url = ItemReferences.applicationURL(reference)
            let name = url?.deletingPathExtension().lastPathComponent ?? unavailableName
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: name)
                ?? NSImage()
            item.configure(name: name, icon: icon, unavailable: url == nil)
            item.onClick = { [weak self] in
                guard let self, let url = ItemReferences.applicationURL(reference) else { return }
                self.onOpen?(url)
            }
            item.onRemove = { [weak self] in self?.remove(reference) }
            item.onBeginDrag = { [weak self, weak item] event in
                guard let self, let item else { return }
                self.beginDrag(index: index, from: item, event: event)
            }
            documentView.addSubview(item)
            itemViews.append(item)
        }
        emptyStateView.isHidden = !applicationReferences.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let titleHeight = Layout.launcherHeaderHeight
        // 标题在头部整宽居中；编辑按钮钉在右缘（宽度为标题留足，避免重叠）
        titleField.frame = NSRect(x: 34, y: bounds.height - titleHeight + (titleHeight - 17) / 2,
                                  width: bounds.width - 68, height: 17)
        editButton.frame = NSRect(x: bounds.width - 30,
                                  y: bounds.height - titleHeight + (titleHeight - 18) / 2,
                                  width: 18, height: 18)
        scrollView.frame = NSRect(x: 0, y: Layout.launcherFooterHeight,
                                  width: bounds.width, height: gridHeight)
        emptyStateView.frame = scrollView.frame
        let rowCount = max(1, Int(ceil(Double(applicationReferences.count) / Double(Layout.launcherColumns))))
        let contentHeight = CGFloat(rowCount) * Layout.launcherCellHeight
        documentView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width,
                                    height: max(contentHeight, scrollView.contentSize.height))
        let totalWidth = CGFloat(Layout.launcherColumns) * Layout.launcherCellWidth
        let left = max(0, (scrollView.contentSize.width - totalWidth) / 2)
        for (index, item) in itemViews.enumerated() {
            item.frame = cellFrame(at: index, left: left)
        }
    }

    /// 网格槽位（文档坐标，左下角原点）
    private func cellFrame(at index: Int, left: CGFloat) -> NSRect {
        let row = index / Layout.launcherColumns
        let column = index % Layout.launcherColumns
        let height = max(documentView.bounds.height, CGFloat(row + 1) * Layout.launcherCellHeight)
        return NSRect(x: left + CGFloat(column) * Layout.launcherCellWidth,
                      y: height - CGFloat(row + 1) * Layout.launcherCellHeight,
                      width: Layout.launcherCellWidth, height: Layout.launcherCellHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTitleColors()
        emptyStateView.refreshColors()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // 分隔线：头部与网格、网格与脚注
        let lineColor = onGlass ? NSColor.labelColor.withAlphaComponent(0.1)
                                : NSColor.white.withAlphaComponent(0.14)
        lineColor.setFill()
        NSRect(x: 10, y: bounds.height - Layout.launcherHeaderHeight - 0.5,
               width: bounds.width - 20, height: 1).fill()
        NSRect(x: 10, y: Layout.launcherFooterHeight - 0.5,
               width: bounds.width - 20, height: 1).fill()

        // 操作提示脚注：与目录潮涌体的状态行同式
        let hint = L10nManager.shared.current.string("surge.launcher.footer", table: .runtime)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Layout.surgeFooterFontSize),
            .foregroundColor: onGlass ? NSColor.secondaryLabelColor
                                      : NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph,
        ]
        let size = (hint as NSString).size(withAttributes: attributes)
        (hint as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (Layout.launcherFooterHeight - size.height) / 2),
                                withAttributes: attributes)

        // 内部排序的落点指示（强调色短线）：追加到末位画末槽后缘，其余画目标槽前缘
        if let dropIndex, dragSourceIndex != nil {
            let totalWidth = CGFloat(Layout.launcherColumns) * Layout.launcherCellWidth
            let left = max(0, (scrollView.contentSize.width - totalWidth) / 2)
            let slot = cellFrame(at: min(dropIndex, max(0, applicationReferences.count - 1)),
                                 left: left)
            let edge = dropIndex >= applicationReferences.count ? slot.maxX : slot.minX
            let marker = convert(NSRect(x: edge - 1.5, y: slot.minY + 8,
                                        width: 3, height: slot.height - 16),
                                 from: documentView)
            let clip = scrollView.frame.insetBy(dx: 0, dy: 1)
            if marker.intersects(clip) {
                let path = NSBezierPath(roundedRect: marker, xRadius: 1.5, yRadius: 1.5)
                NSColor.controlAccentColor.setFill()
                path.fill()
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endTitleEditing(commit: true)
    }

    /// Esc 取消改名（回退为当前名并退出编辑态）
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        endTitleEditing(commit: false)
        return true
    }

    func update(reference: ItemReference) {
        applicationReferences = WidgetReferences.applicationLauncherConfiguration(for: reference)?.applications ?? []
        let payload = WidgetReferences.payload(for: reference)
        currentDisplayName = payload?.displayName ?? currentDisplayName
        titleField.stringValue = currentDisplayName
        reloadItems()
        needsLayout = true
    }

    private func remove(_ reference: ItemReference) {
        applicationReferences.removeAll { $0 == reference }
        reloadItems()
        onApplicationsChange?(applicationReferences)
    }

    private func beginDrag(index: Int, from item: LauncherItemView, event: NSEvent) {
        guard applicationReferences.indices.contains(index), dragSourceIndex == nil else { return }
        let writer = NSPasteboardItem()
        writer.setString(String(index), forType: Self.internalType)
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(item.frame, contents: item.snapshotImage())
        dragSourceIndex = index
        dragCommitted = false
        let session = documentView.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        defer { dragSourceIndex = nil; dropIndex = nil; needsDisplay = true }
        guard let source = dragSourceIndex, applicationReferences.indices.contains(source), !dragCommitted,
              window?.frame.contains(screenPoint) == false,
              NSApp.currentEvent?.type == .leftMouseUp else { return }
        let reference = applicationReferences.remove(at: source)
        reloadItems()
        onApplicationsChange?(applicationReferences)
        NSLog("TideBar launcher application removed by drag: %@", reference.scheme)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true {
            return applicationURLs(from: sender) == nil ? [] : .copy
        }
        if dragSourceIndex == nil {
            return onExternalDropOperation?(sender) ?? []
        }
        return updateDropIndex(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true {
            return applicationURLs(from: sender) == nil ? [] : .copy
        }
        if dragSourceIndex == nil {
            return onExternalDropOperation?(sender) ?? []
        }
        return updateDropIndex(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropIndex = nil
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true {
            return applicationURLs(from: sender) != nil
        }
        if dragSourceIndex == nil {
            return onExternalDropOperation?(sender) != nil
        }
        return dragSourceIndex != nil && dropIndex != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true {
            guard let urls = applicationURLs(from: sender) else { return false }
            let refs = urls.compactMap { url -> ItemReference? in
                guard let record = try? ItemReferences.record(for: ItemReferences.externalFile(url)), record.kind == .application else { return nil }
                return record.reference
            }
            guard refs.count == urls.count else { return false }
            let existing = Set(applicationReferences)
            applicationReferences += refs.filter { !existing.contains($0) }
            reloadItems()
            onApplicationsChange?(applicationReferences)
            return true
        }
        if dragSourceIndex == nil {
            return onPerformExternalDrop?(sender) ?? false
        }
        guard let source = dragSourceIndex, let destination = dropIndex,
              applicationReferences.indices.contains(source) else { return false }
        let reference = applicationReferences.remove(at: source)
        let adjusted = min(destination > source ? destination - 1 : destination, applicationReferences.count)
        applicationReferences.insert(reference, at: max(0, adjusted))
        dragCommitted = true
        dropIndex = nil
        reloadItems()
        onApplicationsChange?(applicationReferences)
        return true
    }

    private func applicationURLs(from sender: any NSDraggingInfo) -> [URL]? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty,
              urls.allSatisfy({ $0.pathExtension.lowercased() == "app" }) else { return nil }
        return urls
    }

    private func updateDropIndex(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(Self.internalType) == true,
              dragSourceIndex != nil else { return [] }
        let point = documentView.convert(sender.draggingLocation, from: nil)
        let totalWidth = CGFloat(Layout.launcherColumns) * Layout.launcherCellWidth
        let left = max(0, (documentView.bounds.width - totalWidth) / 2)
        // 半格分界：悬停在格右/下半区 = 插到该项之后，落点线与拖拽体所重量的位置一致
        let rowFromTop = max(0, Int((documentView.bounds.maxY - point.y) / Layout.launcherCellHeight + 0.5))
        let column = min(max(0, Int((point.x - left) / Layout.launcherCellWidth + 0.5)), Layout.launcherColumns)
        let next = min(rowFromTop * Layout.launcherColumns + column, applicationReferences.count)
        if next != dropIndex {
            dropIndex = next
            needsDisplay = true
        }
        return .move
    }

    func setHover(at point: NSPoint) {
        // 确定性帧命中：hitTest 会落到图标/文字子视图，拿不到单元格本体
        let documentPoint = documentView.convert(point, from: self)
        let hit = itemViews.first { $0.frame.contains(documentPoint) }
        for item in itemViews { item.setHovered(item === hit) }
    }

    func refreshLocalizedText() {
        editButton.toolTip = L10nManager.shared.current.string("surge.launcher.rename", table: .runtime)
        emptyStateView.refreshLocalizedText()
        needsDisplay = true
    }

    func rise() { SurgeMotion.rise(itemViews) }

    @discardableResult
    func drop() -> TimeInterval { SurgeMotion.drop(itemViews) }
}

// MARK: - 空状态

/// 空收藏夹占位：不占命中，避免挡住投递与悬停采样。
@MainActor
private final class LauncherEmptyStateView: NSView {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var onGlass: Bool { BarBackgroundFactory.usesGlass }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        label.font = NSFont.systemFont(ofSize: 12)
        label.alignment = .center
        refreshLocalizedText()
        refreshColors()
        addSubview(imageView)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func refreshLocalizedText() {
        label.stringValue = L10nManager.shared.current.string("surge.launcher.empty", table: .runtime)
    }

    func refreshColors() {
        let secondary = onGlass ? NSColor.secondaryLabelColor : NSColor.white.withAlphaComponent(0.55)
        imageView.contentTintColor = secondary
        label.textColor = secondary
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let iconSide: CGFloat = 26
        let labelHeight: CGFloat = 16
        let total = iconSide + 4 + labelHeight
        let top = (bounds.height + total) / 2
        imageView.frame = NSRect(x: (bounds.width - iconSide) / 2, y: top - iconSide,
                                 width: iconSide, height: iconSide)
        label.frame = NSRect(x: 10, y: top - iconSide - 4 - labelHeight,
                             width: bounds.width - 20, height: labelHeight)
    }
}

// MARK: - 网格单元

/// 收藏夹网格单元：图标 + 名称；高亮绘制与 SurgeRowView 同式（圆角行底、玻璃/回退双色路）。
@MainActor
private final class LauncherItemView: NSView {
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hovering = false
    private var unavailable = false
    private var mouseDownPoint: NSPoint?
    private var dragging = false
    var onClick: (() -> Void)?
    var onRemove: (() -> Void)?
    var onBeginDrag: ((NSEvent) -> Void)?

    private var onGlass: Bool { BarBackgroundFactory.usesGlass }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.font = NSFont.systemFont(ofSize: 11)
        label.maximumNumberOfLines = 1
        addSubview(imageView)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(name: String, icon: NSImage, unavailable: Bool) {
        label.stringValue = name
        self.unavailable = unavailable
        imageView.image = icon
        // 失效条目的 template 回退符号需显式着色随主题，否则暗色下几乎不可见
        imageView.contentTintColor = unavailable ? NSColor.labelColor.withAlphaComponent(0.45) : nil
        alphaValue = unavailable ? 0.55 : 1
        refreshColors()
    }

    private func refreshColors() {
        if unavailable {
            label.textColor = onGlass ? .secondaryLabelColor : NSColor.white.withAlphaComponent(0.55)
        } else {
            label.textColor = onGlass ? .labelColor : NSColor.white.withAlphaComponent(0.92)
        }
    }

    func setHovered(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8)
        let fill = onGlass ? NSColor.labelColor.withAlphaComponent(0.12)
                           : NSColor.white.withAlphaComponent(0.14)
        fill.setFill()
        highlight.fill()
    }

    override func layout() {
        super.layout()
        let side = Layout.launcherIconSide
        imageView.frame = NSRect(x: (bounds.width - side) / 2, y: bounds.height - 6 - side,
                                 width: side, height: side)
        label.frame = NSRect(x: 4, y: 3, width: bounds.width - 8, height: 15)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= Layout.itemDragThreshold else { return }
        dragging = true
        onBeginDrag?(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !dragging else { return }
        onClick?()
    }

    // 潮涌面板层级（statusBar+1）同样高于菜单窗口，行菜单底部重叠区的
    // 事件会被面板截走；会话期间面板临时穿透，didCloseMenu 恢复
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        window?.ignoresMouseEvents = true
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        window?.ignoresMouseEvents = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let title = L10nManager.shared.current.string("surge.launcher.remove", table: .runtime)
        let item = NSMenuItem(title: title, action: #selector(removeItem), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    /// 拖拽图像：走显示缓存，保证图标与文字都在快照里（裸 draw 画不出子视图）
    func snapshotImage() -> NSImage {
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    @objc private func removeItem() { onRemove?() }
}

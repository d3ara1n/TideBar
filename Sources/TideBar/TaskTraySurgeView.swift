import AppKit
import Combine
import TideBarCore

@MainActor
final class TaskTraySurgeView: NSView, SurgeBody, NSMenuDelegate {
    let instanceID: UUID
    var onSizeChange: (() -> Void)?
    var onControlSession: ((Bool) -> Void)?
    private(set) var isPresentingControl = false
    private let session: TaskTraySession
    private var recipe: TaskTrayRecipe?
    private var subscription: AnyCancellable?
    private let operationButton = NSButton()
    private let defaultButton = NSButton()
    private let dropZone = TaskTrayDropZone()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let quality = NSSlider(value: 90, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: "")
    private let pendingLabel = NSTextField(labelWithString: "")
    private let startButton = NSButton()
    private let discardButton = NSButton()
    private let clearButton = NSButton()
    private let scroll = NSScrollView()
    private let document = TaskTrayDocumentView()
    private var rows: [NSView] = []
    private var lastSize = NSSize.zero
    private var inlineError: String?
    private var filePicker: NSOpenPanel?
    private var operationMenu: NSMenu?

    private static let bodyWidth: CGFloat = 400
    private static let inset: CGFloat = 12
    private static let rowHeight: CGFloat = 54
    private var showsQuality: Bool { recipe?.operation == .jpeg }
    private var showsPending: Bool { !session.pending.isEmpty }
    private var hintHeight: CGFloat {
        let size = NSSize(width: Self.bodyWidth - Self.inset * 2,
                          height: .greatestFiniteMagnitude)
        return max(14, ceil(hint.attributedStringValue.boundingRect(
            with: size, options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
    }

    var bodySize: NSSize {
        let controls = 26 + (showsQuality ? 26 : 0) + 6 + 52 + 4 + hintHeight
        let pending: CGFloat = showsPending ? 32 : 0
        let tasks: CGFloat = session.jobs.isEmpty ? 0
            : 8 + CGFloat(min(session.jobs.count, 3)) * Self.rowHeight + 4 + 24
        return NSSize(width: Self.bodyWidth, height: Self.inset * 2 + controls + pending + tasks)
    }

    init(instanceID: UUID, configuration: TaskTrayConfiguration) {
        self.instanceID = instanceID
        session = TaskTrayStore.shared.session(for: instanceID)
        recipe = configuration.defaultRecipe
        super.init(frame: .zero)
        wantsLayer = true
        configure(operationButton, action: #selector(chooseOperation))
        operationButton.bezelStyle = .rounded
        operationButton.alignment = .left
        configure(defaultButton, action: #selector(saveDefault))
        defaultButton.isBordered = false
        defaultButton.imagePosition = .imageOnly
        hint.font = .systemFont(ofSize: 11)
        addSubview(hint)
        quality.target = self
        quality.action = #selector(qualityChanged)
        quality.isContinuous = true
        quality.controlSize = .small
        quality.setAccessibilityLabel(TaskTrayText.string("tray.qualityLabel"))
        addSubview(quality)
        qualityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        addSubview(qualityLabel)
        pendingLabel.font = .systemFont(ofSize: 11)
        pendingLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(pendingLabel)
        configure(startButton, action: #selector(startPending))
        configure(discardButton, action: #selector(discardPending))
        discardButton.isBordered = false
        configure(clearButton, action: #selector(clearFinished))
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11)
        dropZone.onReceive = { [weak self] urls in self?.receive(urls) ?? false }
        dropZone.accepts = { [weak self] urls in
            guard let self else { return false }
            return self.recipe.map { recipe in urls.allSatisfy { TaskTrayWorker.accepts($0, recipe: recipe) } } ?? true
        }
        dropZone.onChoose = { [weak self] in self?.chooseFiles() }
        addSubview(dropZone)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
        subscription = session.changes.sink { [weak self] in self?.reload() }
        frame = NSRect(origin: .zero, size: bodySize)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func configure(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        addSubview(button)
    }

    @objc private func chooseOperation() {
        let menu = NSMenu()
        operationMenu = menu
        menu.delegate = self
        let defaultRecipe = WidgetReferences.taskTrayDefault(instanceID: instanceID)
        for (index, operation) in TaskTrayOperation.allCases.enumerated() {
            let marker = defaultRecipe?.operation == operation ? "  ★" : ""
            let item = NSMenuItem(title: TaskTrayText.operation(operation) + marker,
                                  action: #selector(selectOperation(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = recipe?.operation == operation ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: operationButton.bounds.minY - 4), in: operationButton)
    }

    @objc private func selectOperation(_ sender: NSMenuItem) {
        let operation = TaskTrayOperation.allCases[sender.tag]
        recipe = TaskTrayRecipe(operation: operation, jpegQuality: recipe?.jpegQuality ?? 90)
        inlineError = nil
        reload()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isPresentingControl = true
        onControlSession?(true)
        // 原生菜单层低于潮涌；让出命中，沿用图标栏菜单的窗口约束。
        window?.ignoresMouseEvents = true
    }

    func menuDidClose(_ menu: NSMenu) {
        window?.ignoresMouseEvents = false
        operationMenu = nil
        isPresentingControl = false
        onControlSession?(false)
    }

    @objc private func saveDefault() {
        guard let recipe else { return }
        do {
            try WidgetReferences.saveTaskTrayDefault(recipe, instanceID: instanceID)
            inlineError = nil
        } catch { inlineError = error.localizedDescription }
        reload()
    }

    @objc private func qualityChanged() {
        recipe?.jpegQuality = quality.integerValue
        refreshControls()
    }

    @objc private func startPending() {
        guard let recipe else { return }
        do {
            try session.enqueue(session.pending, recipe: recipe)
            session.clearPending()
            inlineError = nil
        } catch {
            inlineError = TaskTrayText.string("tray.error.unsupported")
        }
        reload()
    }

    @objc private func discardPending() { session.clearPending() }
    @objc private func clearFinished() { session.clearFinished() }

    private func receive(_ urls: [URL]) -> Bool {
        do {
            if let recipe {
                try session.enqueue(urls, recipe: recipe)
            } else {
                session.stage(urls)
            }
            inlineError = nil
            reload()
            return true
        } catch {
            inlineError = TaskTrayText.string("tray.error.unsupported")
            reload()
            return false
        }
    }

    private func chooseFiles() {
        guard let window, filePicker == nil else { return }
        let panel = NSOpenPanel()
        filePicker = panel
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = recipe?.operation == .removeQuarantine || recipe == nil
        panel.canChooseFiles = true
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        isPresentingControl = true
        onControlSession?(true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.filePicker === panel else { return }
            self.filePicker = nil
            self.isPresentingControl = false
            self.onControlSession?(false)
            if response == .OK { _ = self.receive(panel.urls) }
        }
    }

    /// 屏幕重建／全屏策略等关闭宿主时，不能把原生控件会话遗留给全局控制器。
    func endControlSession() {
        if let picker = filePicker {
            filePicker = nil
            picker.sheetParent?.endSheet(picker, returnCode: .cancel)
            picker.orderOut(nil)
        }
        operationMenu?.cancelTracking()
        operationMenu = nil
        window?.ignoresMouseEvents = false
        if isPresentingControl {
            isPresentingControl = false
            onControlSession?(false)
        }
        onControlSession = nil
    }

    private func refreshControls() {
        let primary: NSColor = BarBackgroundFactory.usesGlass ? .labelColor : .white
        let secondary: NSColor = BarBackgroundFactory.usesGlass ? .secondaryLabelColor : .white.withAlphaComponent(0.7)
        operationButton.title = (recipe.map { TaskTrayText.operation($0.operation) }
                                 ?? TaskTrayText.string("tray.chooseOperation")) + "  ▾"
        operationButton.setAccessibilityLabel(TaskTrayText.string("tray.chooseOperation"))
        let isDefault = recipe != nil && recipe == WidgetReferences.taskTrayDefault(instanceID: instanceID)
        defaultButton.image = NSImage(systemSymbolName: isDefault ? "star.fill" : "star", accessibilityDescription: nil)
        defaultButton.contentTintColor = isDefault ? .controlAccentColor : secondary
        defaultButton.toolTip = TaskTrayText.string(isDefault ? "tray.isDefault" : "tray.setDefault")
        defaultButton.setAccessibilityLabel(defaultButton.toolTip)
        defaultButton.isEnabled = recipe != nil
        quality.isHidden = recipe?.operation != .jpeg
        qualityLabel.isHidden = quality.isHidden
        quality.integerValue = recipe?.jpegQuality ?? 90
        qualityLabel.stringValue = TaskTrayText.string("tray.quality", quality.integerValue)
        qualityLabel.textColor = secondary
        hint.stringValue = inlineError ?? TaskTrayText.string(
            recipe?.operation == .removeQuarantine ? "tray.quarantineHint" :
                recipe?.operation == .jpeg ? "tray.jpegHint" : "tray.outputHint")
        hint.textColor = inlineError == nil ? secondary : .systemRed
        let pendingCount = session.pending.count
        pendingLabel.stringValue = pendingCount > 0
            ? TaskTrayText.string("tray.awaitingCount", pendingCount) : TaskTrayText.string("tray.backgroundHint")
        pendingLabel.toolTip = session.pending.map(\.path).joined(separator: "\n")
        pendingLabel.textColor = secondary
        pendingLabel.isHidden = pendingCount == 0
        dropZone.toolTip = TaskTrayText.string("tray.backgroundHint")
        startButton.title = TaskTrayText.string("tray.start")
        startButton.isHidden = pendingCount == 0
        startButton.isEnabled = recipe.map { recipe in
            session.pending.allSatisfy { TaskTrayWorker.accepts($0, recipe: recipe) }
        } ?? false
        discardButton.title = TaskTrayText.string("tray.discard")
        discardButton.isHidden = pendingCount == 0
        discardButton.contentTintColor = secondary
        clearButton.title = TaskTrayText.string("tray.clearFinished")
        clearButton.contentTintColor = secondary
        clearButton.isHidden = session.jobs.isEmpty
        clearButton.isEnabled = session.jobs.contains { $0.state.isFinished }
        dropZone.refresh(primary: primary, secondary: secondary,
                         action: recipe.map { TaskTrayText.operation($0.operation) })
    }

    private func reload() {
        refreshControls()
        rows.forEach { $0.removeFromSuperview() }
        rows = session.jobs.reversed().map { job in
            let row = TaskTrayJobRow(job: job)
            row.onRetry = { [weak self] in
                guard let self else { return }
                do { try self.session.enqueue([job.source], recipe: job.recipe) }
                catch {
                    self.inlineError = TaskTrayText.string("tray.error.unsupported")
                    self.refreshControls()
                }
            }
            document.addSubview(row)
            return row
        }
        scroll.isHidden = session.jobs.isEmpty
        needsLayout = true
        if lastSize != bodySize {
            lastSize = bodySize
            onSizeChange?()
        }
    }

    override func layout() {
        super.layout()
        let inset = Self.inset
        let width = bounds.width - inset * 2
        var cursor = bounds.height - inset
        func take(_ height: CGFloat, gap: CGFloat = 0) -> NSRect {
            cursor -= gap + height
            return NSRect(x: inset, y: cursor, width: width, height: height)
        }
        let selection = take(26)
        operationButton.frame = NSRect(x: selection.minX, y: selection.minY, width: width - 36, height: 26)
        defaultButton.frame = NSRect(x: selection.maxX - 30, y: selection.minY, width: 30, height: 26)
        if showsQuality {
            let row = take(20, gap: 6)
            qualityLabel.frame = NSRect(x: row.minX + 2, y: row.minY + 1, width: 100, height: 17)
            quality.frame = NSRect(x: row.minX + 104, y: row.minY, width: width - 104, height: 20)
        }
        dropZone.frame = take(52, gap: 6)
        hint.frame = take(hintHeight, gap: 4)
        if showsPending {
            let row = take(26, gap: 6)
            pendingLabel.frame = NSRect(x: row.minX, y: row.minY + 4, width: width - 166, height: 18)
            discardButton.frame = NSRect(x: row.maxX - 156, y: row.minY, width: 70, height: 26)
            startButton.frame = NSRect(x: row.maxX - 82, y: row.minY, width: 82, height: 26)
        }
        let listBottom = inset + 24 + 4
        scroll.frame = NSRect(x: 8, y: listBottom, width: bounds.width - 16,
                              height: max(0, cursor - 8 - listBottom))
        clearButton.frame = NSRect(x: bounds.width - inset - 145, y: inset, width: 145, height: 24)
        let contentHeight = max(scroll.contentSize.height, CGFloat(rows.count) * Self.rowHeight)
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: contentHeight)
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * Self.rowHeight,
                               width: document.bounds.width, height: Self.rowHeight)
        }
    }

    func refreshLocalizedText() { reload() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reload()
    }
}

private final class TaskTrayDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class TaskTrayDropZone: NSView {
    var onReceive: (([URL]) -> Bool)?
    var accepts: (([URL]) -> Bool)?
    var onChoose: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let choose = NSButton()
    private var receiving = false
    private var rejected = false
    private var actionName: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        addSubview(label)
        choose.isBordered = false
        choose.font = .systemFont(ofSize: 11)
        choose.target = self
        choose.action = #selector(pick)
        addSubview(choose)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func refresh(primary: NSColor, secondary: NSColor, action: String?) {
        actionName = action
        label.textColor = primary
        choose.contentTintColor = secondary
        choose.title = TaskTrayText.string("tray.chooseFiles")
        updateLabel()
    }

    @objc private func pick() { onChoose?() }
    private func updateLabel() {
        label.stringValue = TaskTrayText.string(rejected ? "tray.error.unsupported" : "tray.drop")
        if receiving, let actionName { label.stringValue = actionName }
        needsDisplay = true
    }

    private func urls(_ sender: any NSDraggingInfo) -> [URL]? {
        guard sender.draggingPasteboard.types?.contains(ItemDragCoordinator.pasteboardType) != true,
              sender.draggingSource as? ItemDragCoordinator == nil,
              sender.draggingSourceOperationMask.contains(.copy),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                  options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return nil }
        return urls
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        receiving = urls(sender).map { accepts?($0) == true } ?? false
        rejected = !receiving
        updateLabel()
        return receiving ? .copy : []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        receiving = false
        rejected = false
        updateLabel()
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        urls(sender).map { accepts?($0) == true } ?? false
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { draggingExited(sender) }
        guard let urls = urls(sender) else { return false }
        return onReceive?(urls) ?? false
    }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 8, y: 28, width: bounds.width - 16, height: 18)
        choose.frame = NSRect(x: 8, y: 4, width: bounds.width - 16, height: 22)
    }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = rejected ? .systemRed : receiving ? .controlAccentColor :
            (BarBackgroundFactory.usesGlass ? .secondaryLabelColor : .white.withAlphaComponent(0.7))
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        color.withAlphaComponent(receiving ? 0.12 : 0.04).setFill()
        path.fill()
        color.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        if !receiving { path.setLineDash([4, 3], count: 2, phase: 0) }
        path.stroke()
    }
}

@MainActor
private final class TaskTrayJobRow: NSView {
    var onRetry: (() -> Void)?
    private let job: TaskTrayJob
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let action = NSButton()

    init(job: TaskTrayJob) {
        self.job = job
        super.init(frame: .zero)
        let primary: NSColor = BarBackgroundFactory.usesGlass ? .labelColor : .white
        let secondary: NSColor = BarBackgroundFactory.usesGlass ? .secondaryLabelColor : .white.withAlphaComponent(0.7)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.textColor = primary
        name.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = secondary
        detail.lineBreakMode = .byTruncatingTail
        status.font = .systemFont(ofSize: 10, weight: .medium)
        status.textColor = secondary
        name.stringValue = job.source.lastPathComponent
        detail.stringValue = TaskTrayText.operation(job.recipe.operation)
        switch job.state {
        case .queued: status.stringValue = TaskTrayText.string("tray.queued")
        case .running: status.stringValue = TaskTrayText.string("tray.running")
        case .completed(let url, let changed):
            status.stringValue = TaskTrayText.string(changed ? "tray.completed" : "tray.unchanged")
            name.stringValue = url.lastPathComponent
            action.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            action.toolTip = TaskTrayText.string("tray.reveal")
        case .failed(let failure):
            status.stringValue = TaskTrayText.string("tray.failed")
            status.textColor = .systemRed
            detail.stringValue += " · \(failure.message)"
            action.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            action.toolTip = TaskTrayText.string("tray.retry")
        }
        name.toolTip = job.source.path
        detail.toolTip = detail.stringValue
        action.isHidden = !job.state.isFinished
        action.isBordered = false
        action.contentTintColor = secondary
        action.target = self
        action.action = #selector(performAction)
        action.setAccessibilityLabel(action.toolTip)
        [name, detail, status, action].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func performAction() {
        switch job.state {
        case .completed(let url, _): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failed: onRetry?()
        default: break
        }
    }
    override func layout() {
        super.layout()
        name.frame = NSRect(x: 10, y: 35, width: bounds.width - 55, height: 17)
        detail.frame = NSRect(x: 10, y: 18, width: bounds.width - 24, height: 16)
        status.frame = NSRect(x: 10, y: 3, width: bounds.width - 24, height: 14)
        action.frame = NSRect(x: bounds.width - 38, y: 27, width: 28, height: 26)
    }
}

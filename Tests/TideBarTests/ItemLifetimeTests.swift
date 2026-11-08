import AppKit
import Testing
import TideBarCore
@testable import TideBar

/// 检查对象身份和释放，而不是把一次 RSS 降低当成生命周期正确。
@MainActor
struct ItemLifetimeTests {
    private func entry(id: ItemID = .resource(), name: String = "Item") -> ItemEntry {
        ItemEntry(id: id, kind: .file,
                  reference: ItemReference(scheme: "test", payload: Data()),
                  name: name, icon: NSImage(size: NSSize(width: 32, height: 32)),
                  preferredBarWidth: nil, isPinned: true,
                  content: .reference(isAvailable: true))
    }

    private func makeRow() -> ItemRowView {
        ItemRowView(frame: NSRect(x: 0, y: 0, width: 320, height: Layout.expandedHeight))
    }

    @Test func repeatedExpansionReusesEveryButton() throws {
        let row = makeRow()
        let entries = (0..<8).map { entry(name: "Item \($0)") }
        row.update(apps: entries, preparingExpansion: true)
        let initial = try entries.map { try #require(row.button(forItem: $0.id)) }
        for _ in 0..<200 {
            autoreleasepool {
                row.setActive(false)
                row.update(apps: entries, preparingExpansion: true)
                row.setActive(true)
            }
            #expect(row.subviews.count == entries.count)
            for (item, button) in zip(entries, initial) {
                #expect(row.button(forItem: item.id) === button)
            }
        }
    }

    @Test func reusePublishesLatestEntryAndUsesSenderFrame() throws {
        let row = makeRow()
        let id = ItemID.resource()
        let reference = try WidgetReferences.applicationLauncher(displayName: "Launcher")
        func widget(name: String) -> ItemEntry {
            ItemEntry(id: id, kind: .widget, reference: reference,
                      name: name, icon: NSImage(), preferredBarWidth: nil,
                      isPinned: true, content: .reference(isAvailable: true))
        }
        row.update(apps: [widget(name: "Before")], preparingExpansion: true)
        let button = try #require(row.button(forItem: id))
        row.update(apps: [widget(name: "After")], preparingExpansion: true)
        button.frame = NSRect(x: 10, y: 20, width: 52, height: 64)
        var received: (String, NSRect)?
        row.onSurge = { entry, frame in received = (entry.name, frame) }
        button.onClick?(button)
        #expect(received?.0 == "After")
        #expect(received?.1 == button.frame)
    }

    @Test func removedButtonsAndTheirImagesAreReleased() {
        let row = makeRow()
        weak var oldButton: ItemIconButton?
        weak var oldImage: NSImage?
        autoreleasepool {
            let item = entry()
            oldImage = item.icon
            row.update(apps: [item], preparingExpansion: true)
            oldButton = row.button(forItem: item.id)
            row.update(apps: [], preparingExpansion: true)
        }
        #expect(oldButton == nil)
        #expect(oldImage == nil)
        #expect(row.subviews.isEmpty)
    }

    @Test func releasingRowReleasesItsButtonsWithoutExplicitRemoval() {
        weak var oldButton: ItemIconButton?
        weak var oldRow: ItemRowView?
        autoreleasepool {
            let row = makeRow()
            let item = entry()
            row.update(apps: [item], preparingExpansion: true)
            oldRow = row
            oldButton = row.button(forItem: item.id)
        }
        #expect(oldRow == nil)
        #expect(oldButton == nil)
    }

    @Test func returningItemReusesDepartureAndInvalidatesOldCompletion() async throws {
        let row = makeRow()
        row.setActive(true)
        let item = entry()
        row.update(apps: [item], preparingExpansion: true)
        let button = try #require(row.button(forItem: item.id))
        for _ in 0..<20 {
            row.update(apps: [])
            row.update(apps: [item])
            #expect(row.button(forItem: item.id) === button)
        }
        let wait = max(Motion.dropDuration, Motion.reducedMotionFadeDuration) + 0.1
        try await Task.sleep(for: .seconds(wait))
        #expect(button.superview === row)
        #expect(row.subviews.count == 1)
    }

    @Test func departureEventuallyReleasesButton() async throws {
        let row = makeRow()
        weak var removed: ItemIconButton?
        autoreleasepool {
            let item = entry()
            row.update(apps: [item], preparingExpansion: true)
            removed = row.button(forItem: item.id)
            row.update(apps: [])
        }
        let wait = max(Motion.dropDuration, Motion.reducedMotionFadeDuration) + 0.1
        try await Task.sleep(for: .seconds(wait))
        #expect(removed == nil)
        #expect(row.subviews.isEmpty)
    }

    @Test func expansionRemovesStaleDepartureImmediately() {
        let row = makeRow()
        weak var removed: ItemIconButton?
        autoreleasepool {
            let item = entry()
            row.update(apps: [item], preparingExpansion: true)
            removed = row.button(forItem: item.id)
            row.update(apps: [])
            row.update(apps: [], preparingExpansion: true)
        }
        #expect(removed == nil)
        #expect(row.subviews.isEmpty)
    }

    @Test func retirementClearsOwnedCallbacks() throws {
        let row = makeRow()
        let item = entry()
        row.update(apps: [item], preparingExpansion: true)
        let button = try #require(row.button(forItem: item.id))
        #expect(button.onClick != nil)
        row.update(apps: [], preparingExpansion: true)
        #expect(button.onClick == nil)
        #expect(button.onBeginDrag == nil)
        #expect(button.onSurge == nil)
        #expect(button.superview == nil)
    }

    @Test func closingMenuKeepsSelectedActionAliveThroughDispatch() async throws {
        let button = ItemIconButton(entry: entry())
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
                                                   modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil,
                                                   eventNumber: 0, clickCount: 1, pressure: 0))
        let menu = try #require(button.menu(for: event))
        let title = L10nManager.shared.current.string("appMenu.open", table: .menus)
        let item = try #require(menu.items.first { $0.title == title })
        var clicks = 0
        button.onClick = { _ in clicks += 1 }
        weak var target: MenuAction?
        autoreleasepool { target = item.target as? MenuAction }
        button.didCloseMenu(menu, with: nil)
        #expect(target != nil)
        // 模拟 AppKit 先结束 tracking、再发送选择动作的顺序，不弹出真实菜单。
        (item.target as? MenuAction)?.run()
        #expect(clicks == 1)
        try await Task.sleep(for: .milliseconds(30))
        #expect(target == nil)
    }

    @Test func windowStoreDoesNotKeepItselfAliveAfterStarting() {
        weak var released: WindowStore?
        autoreleasepool {
            let store = WindowStore()
            // 仅读取现有授权，不申请授权；没有授权时也必须能释放。
            store.start()
            released = store
        }
        #expect(released == nil)
    }
}

@MainActor
struct IconRasterTests {
    private func image(side: CGFloat = 1024) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
    }

    @Test func rasterUsesDisplayPixelsInsteadOfOriginalResolution() throws {
        let raster = try #require(IconRaster.makeImage(image(), side: 40, scale: 2))
        #expect(raster.width == 80)
        #expect(raster.height == 80)
        #expect(raster.bytesPerRow * raster.height <= 80 * 80 * 4)
        let capped = try #require(IconRaster.makeImage(image(), side: 4096, scale: 4))
        #expect(capped.width == IconRaster.maximumPixelSide)
    }

    @Test func invalidRasterRequestsDoNotAllocateImages() {
        let icon = image()
        #expect(IconRaster.makeImage(icon, side: 0, scale: 2) == nil)
        #expect(IconRaster.makeImage(icon, side: .infinity, scale: 2) == nil)
        #expect(IconRaster.makeImage(icon, side: 40, scale: .nan) == nil)
    }

    @Test func layerContentsAreSharedAndStableAcrossLayout() throws {
        let view = ApplicationIconView(icon: image(), side: 40)
        view.frame = NSRect(x: 0, y: 0, width: 52, height: 64)
        view.layoutSubtreeIfNeeded()
        let contents = try #require(view.imageLayer.contents) as AnyObject
        for _ in 0..<100 {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            #expect(view.imageLayer.contents as AnyObject? === contents)
        }
        for child in view.layer?.sublayers ?? [] {
            #expect(child.contents as AnyObject? === contents)
        }
        view.iconSide = 24
        view.layoutSubtreeIfNeeded()
        #expect(view.imageLayer.contents as AnyObject? !== contents)
    }

    @Test func invisibleDragStatesDoNotGenerateMasks() throws {
        let effect = ItemDragIconEffect()
        let icon = image()
        for state: ItemDragIconState in [.idle, .tracking, .lifted] {
            effect.update(icon: icon, state: state)
            #expect(effect.layer.contents == nil)
        }
        effect.update(icon: icon, state: .receiving)
        let raster = try #require(effect.layer.contents) as! CGImage
        #expect(raster.width == Int(ceil(Layout.iconSize * 2)))
        effect.update(icon: icon, state: .rejected)
        let rejected = try #require(effect.layer.contents) as! CGImage
        #expect(rejected.width == raster.width)
    }

    @Test func oldFadeCompletionCannotClearReenteredDragEffect() async throws {
        let effect = ItemDragIconEffect()
        let icon = image()
        effect.update(icon: icon, state: .receiving)
        effect.update(icon: icon, state: .idle)
        effect.update(icon: icon, state: .rejected)
        let contents = try #require(effect.layer.contents) as AnyObject
        let wait = max(Motion.dragFeedbackDuration, Motion.reducedMotionFadeDuration) + 0.1
        try await Task.sleep(for: .seconds(wait))
        #expect(effect.layer.contents as AnyObject? === contents)
        #expect(effect.layer.opacity == ItemDragStyle.rejectionShade)
    }

    @Test func endingDragReleasesMaskAfterFade() async throws {
        let effect = ItemDragIconEffect()
        let icon = image()
        effect.update(icon: icon, state: .receiving)
        effect.update(icon: icon, state: .idle)
        let wait = max(Motion.dragFeedbackDuration, Motion.reducedMotionFadeDuration) + 0.1
        try await Task.sleep(for: .seconds(wait))
        #expect(effect.layer.contents == nil)
    }
}

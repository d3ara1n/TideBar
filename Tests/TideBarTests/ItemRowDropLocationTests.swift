import AppKit
import Testing
import TideBarCore
@testable import TideBar

@Test @MainActor func internalAppDragCanEnterAndLeaveWidgetReceiver() throws {
    let appID = ItemID.resource()
    let widgetID = ItemID.resource()
    let app = ItemEntry(id: appID, kind: .application,
                        reference: try ItemReferences.application("com.apple.finder"),
                        name: "Finder", icon: NSImage(), preferredBarWidth: nil,
                        isPinned: true, content: .reference(isAvailable: true))
    let widget = ItemEntry(id: widgetID, kind: .widget,
                           reference: try WidgetReferences.applicationLauncher(displayName: "Test"),
                           name: "Test", icon: NSImage(), preferredBarWidth: nil,
                           isPinned: true, content: .reference(isAvailable: true))
    let row = ItemRowView(frame: NSRect(x: 0, y: 0, width: 260, height: 64))
    row.update(apps: [app, widget], preparingExpansion: true)
    row.layoutSubtreeIfNeeded()
    row.setDragContext(active: true, source: appID)

    let widgetPoint = NSPoint(x: row.bounds.midX + Layout.iconSlot / 2, y: row.bounds.midY)
    #expect(row.dropLocation(at: widgetPoint).target == widgetID)
    row.setDragPreview(.reorder(appID, before: widgetID))
    #expect(row.dropLocation(at: widgetPoint).target == widgetID)

    row.setDragPreview(.receive(widgetID, accepted: true))
    #expect(row.dropLocation(at: widgetPoint).target == widgetID)
    #expect(row.dropLocation(at: NSPoint(x: row.bounds.maxX, y: row.bounds.midY)).target == nil)

    row.setDragPreview(.reorder(appID, before: nil))
    #expect(row.dropLocation(at: NSPoint(x: row.bounds.midX - Layout.iconSlot / 2,
                                         y: row.bounds.midY)).target == widgetID)

    row.setDragContext(active: true, source: widgetID)
    #expect(row.dropLocation(at: widgetPoint).target == nil)
}

/// 固定状态不限制插入锚点：预览前后都能落在临时项之间或整栏末尾。
@Test @MainActor func pinnedItemCanMoveBetweenAndAfterTemporaryItems() throws {
    let pinnedID = ItemID.resource()
    let tempX = ItemID.resource(), tempY = ItemID.resource()
    let reference = try ItemReferences.application("com.apple.finder")
    let entries = [pinnedID, tempX, tempY].map { id in
        ItemEntry(id: id, kind: .application, reference: reference,
                  name: id.rawValue, icon: NSImage(), preferredBarWidth: nil,
                  isPinned: id == pinnedID, content: .reference(isAvailable: true))
    }
    let row = ItemRowView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
    row.update(apps: entries, preparingExpansion: true)
    row.layoutSubtreeIfNeeded()
    row.setDragContext(active: true, source: pinnedID)

    let betweenTemps = NSPoint(x: row.bounds.midX + Layout.iconSlot / 2, y: row.bounds.maxY - 1)
    let afterAll = NSPoint(x: row.bounds.maxX, y: row.bounds.maxY - 1)
    #expect(row.dropLocation(at: betweenTemps).before == tempY)
    #expect(row.dropLocation(at: afterAll).before == nil)

    row.setDragPreview(.reorder(pinnedID, before: nil))
    #expect(row.dropLocation(at: afterAll).before == nil)
}

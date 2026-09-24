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
    row.update(apps: [app, widget], rebuildAll: true)
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

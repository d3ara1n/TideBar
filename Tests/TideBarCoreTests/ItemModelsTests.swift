import Foundation
import Testing
@testable import TideBarCore

private let itemA = ItemID(rawValue: "resource:A")
private let itemB = ItemID(rawValue: "resource:B")
private let itemC = ItemID(rawValue: "resource:C")

@Test func itemReferenceHasNoMandatoryFileLocator() throws {
    let reference = ItemReference(scheme: "widget-command", payload: Data([1, 2, 3]))
    let record = PinnedItemRecord(id: itemA, kind: ItemKind(rawValue: "widget"),
                                  reference: reference, fallbackName: "Widget")
    let document = PinnedItemDocument(records: [record])
    let decoded = try JSONDecoder().decode(PinnedItemDocument.self, from: JSONEncoder().encode(document))
    #expect(decoded == document)
}

@Test func internalDragCannotBecomeResourceDelivery() {
    let location = ItemDropLocation(target: itemB, before: itemC)
    #expect(ItemDropIntent.route(.internalItem(itemA), at: location) == .reorder(itemA, before: itemC))
}

@Test func externalReferenceRoutingDoesNotInterpretItsPayload() {
    let reference = ItemReference(scheme: "future-reference", payload: Data([9]))
    let payload = ItemDragPayload.externalReferences([reference])
    #expect(ItemDropIntent.route(payload, at: .init(target: nil, before: itemA)) == .insert([reference], before: itemA))
    #expect(ItemDropIntent.route(payload, at: .init(target: itemB, before: itemA)) == .deliver([reference], to: itemB))
}

@Test func itemOrderUsesStableAnchorsAndRejectsMissingOnes() {
    #expect(ItemOrdering.moving([itemC], before: itemA, in: [itemA, itemB, itemC]) == [itemC, itemA, itemB])
    #expect(ItemOrdering.moving([itemA], before: nil, in: [itemA, itemB, itemC]) == [itemB, itemC, itemA])
    #expect(ItemOrdering.moving([itemA], before: itemA, in: [itemA, itemB]) == [itemA, itemB])
    #expect(ItemOrdering.moving([itemA, itemC], before: itemA, in: [itemA, itemB, itemC]) == [itemA, itemC, itemB])
    #expect(ItemOrdering.moving([itemA], before: itemC, in: [itemA, itemB]) == nil)
    #expect(ItemOrdering.moving([itemC], before: nil, in: [itemA, itemB]) == nil)
    #expect(ItemOrdering.moving([itemA, itemA], before: nil, in: [itemA, itemB]) == nil)
}

@Test func applicationItemIdentityDoesNotChangeWithPinnedState() {
    #expect(ItemID.application(AppIdentity("COM.Example.App")) == .application(AppIdentity("com.example.app")))
    #expect(ItemID(rawValue: "resource:File") != ItemID(rawValue: "resource:file"))
}

@Test func onlyConfirmedOutsideReleaseMayRemoveAnItem() {
    for evidence in [ItemDragEndEvidence.cancelled, .unknown] {
        #expect(!evidence.permitsRemoval(accepted: false, invalidated: false, outsideBar: true, leftButtonStillDown: false))
    }
    #expect(ItemDragEndEvidence.mouseReleased.permitsRemoval(accepted: false, invalidated: false,
                                                             outsideBar: true, leftButtonStillDown: false))
    #expect(!ItemDragEndEvidence.mouseReleased.permitsRemoval(accepted: true, invalidated: false,
                                                              outsideBar: true, leftButtonStillDown: false))
    #expect(!ItemDragEndEvidence.mouseReleased.permitsRemoval(accepted: false, invalidated: true,
                                                              outsideBar: true, leftButtonStillDown: false))
    #expect(!ItemDragEndEvidence.mouseReleased.permitsRemoval(accepted: false, invalidated: false,
                                                              outsideBar: false, leftButtonStillDown: false))
    #expect(!ItemDragEndEvidence.mouseReleased.permitsRemoval(accepted: false, invalidated: false,
                                                              outsideBar: true, leftButtonStillDown: true))
}

/// 固定项锚点收敛：临时区恒居最右，固定项落到临时区（含越过全部）收敛到临时首项之前。
@Test func pinnedAnchorClampsToTempBoundary() {
    let pinnedA = ItemID.resource(), pinnedB = ItemID.resource()
    let temp1 = ItemID.resource(), temp2 = ItemID.resource()
    // 越过全部（nil）→ 临时区首项之前
    #expect(ItemReorderBoundary.clampPinnedAnchor(nil, temps: [temp1, temp2]) == temp1)
    // 指向临时区内后续项 → 收敛临时首项
    #expect(ItemReorderBoundary.clampPinnedAnchor(temp2, temps: [temp1, temp2]) == temp1)
    // 恰为临时首项（固定项末位边界）→ 保持
    #expect(ItemReorderBoundary.clampPinnedAnchor(temp1, temps: [temp1, temp2]) == temp1)
    // 指向固定项 → 不动
    #expect(ItemReorderBoundary.clampPinnedAnchor(pinnedB, temps: [temp1]) == pinnedB)
    // 无临时项 → 自由（nil 仍为末尾）
    #expect(ItemReorderBoundary.clampPinnedAnchor(nil, temps: []) == nil)
}

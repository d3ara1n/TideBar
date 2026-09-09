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

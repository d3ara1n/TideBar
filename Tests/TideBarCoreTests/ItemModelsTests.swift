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

@Test func refreshKeepsMixedOrderWhenPinnedItemIsRemoved() {
    let pinnedA = ItemID(rawValue: "pinned:A"), pinnedB = ItemID(rawValue: "pinned:B")
    let tempX = ItemID(rawValue: "temporary:X"), tempY = ItemID(rawValue: "temporary:Y")
    let mixed = [pinnedA, tempY, pinnedB, tempX]
    #expect(ItemOrdering.reconciling(mixed, with: [pinnedA, pinnedB, tempX, tempY]) == mixed)
    #expect(ItemOrdering.reconciling(mixed, with: [pinnedA, tempX, tempY]) == [pinnedA, tempY, tempX])
}

@Test func storedReorderAppliesOnlyToNewSession() {
    let session = [itemA, itemC, itemB]
    let stored = [itemB, itemA, itemC]
    #expect(ItemOrdering.reconciling(session, with: stored) == session)
    #expect(ItemOrdering.reconciling([], with: stored) == stored)
}

@Test func newlyVisibleItemsAppendAndDepartedItemsLoseTheirPosition() {
    let newcomer = ItemID(rawValue: "newcomer")
    let session = [itemC, itemA, itemB]
    let afterExit = ItemOrdering.reconciling(session, with: [itemA, itemB, newcomer])
    #expect(afterExit == [itemA, itemB, newcomer])
    #expect(ItemOrdering.reconciling(afterExit, with: [itemC, itemA, itemB, newcomer])
            == [itemA, itemB, newcomer, itemC])
}

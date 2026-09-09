import Foundation
import Testing
import TideBarCore

private let a = ItemID(rawValue: "a")
private let b = ItemID(rawValue: "b")
private let c = ItemID(rawValue: "c")
private let unknown = ItemID(rawValue: "missing")

@Test func reorderPreviewMatchesCommitForEverySourceAndAnchor() {
    let order = [a, b, c]
    for source in order {
        for anchor in order.map(Optional.some) + [nil] {
            let layout = ItemDragLayout(order: order, preview: .reorder(source, before: anchor))
            let displayed = layout.slots.map { slot in
                switch slot {
                case .item(let id): id
                case .placeholder: source
                }
            }
            #expect(displayed == ItemOrdering.moving([source], before: anchor, in: order))
            #expect(layout.slots.filter { if case .placeholder = $0 { true } else { false } }.count == 1)
        }
    }
}

@Test func stalePreviewCannotInventOrDeleteItems() {
    let baseline = [a, b, c].map(ItemDragLayout.Slot.item)
    #expect(ItemDragLayout(order: [a, b, c], preview: .reorder(unknown, before: b)).slots == baseline)
    #expect(ItemDragLayout(order: [a, b, c], preview: .reorder(a, before: unknown)).slots == baseline)
    #expect(ItemDragLayout(order: [a, b, c], preview: .insert(count: 2, before: unknown)).slots == baseline)
    #expect(ItemDragLayout(order: [a, b, c], preview: .insert(count: 0, before: nil)).slots == baseline)
}

@Test func insertionUsesOneGroupSlotAndPreservesReferenceCount() {
    let layout = ItemDragLayout(order: [a, b], preview: .insert(count: 4, before: b))
    #expect(layout.slots == [.item(a), .placeholder(count: 4, before: b), .item(b)])
    #expect(ItemDragLayout(order: [], preview: .insert(count: 1, before: nil)).slots == [.placeholder(count: 1, before: nil)])
}

@Test func placeholderIsAnInsertionRegionNotAnItemTarget() {
    let layout = ItemDragLayout(order: [a, b], preview: .insert(count: 2, before: b))
    for x in [1.05, 1.5, 1.95] {
        let hit = layout.hit(at: x, iconFraction: 0.8, allowsReceiving: true)
        #expect(hit.location == ItemDropLocation(target: nil, before: b))
    }
    #expect(layout.hit(at: 2.5, iconFraction: 0.8, allowsReceiving: true).location.target == b)
    #expect(layout.hit(at: 2.5, iconFraction: 0.8, allowsReceiving: false).location.target == nil)
}

@Test func edgeAndSelfAnchorPreviewStayWellDefined() {
    let selfAnchor = ItemDragLayout(order: [a, b, c], preview: .reorder(b, before: b))
    #expect(selfAnchor.slots == [.item(a), .placeholder(count: 1, before: c), .item(c)])
    #expect(selfAnchor.hit(at: -1, iconFraction: 0.8, allowsReceiving: false).location.before == a)
    #expect(selfAnchor.hit(at: 4, iconFraction: 0.8, allowsReceiving: false).location.before == nil)
}

@Test func rejectionIsNotPresentedAsInsertion() {
    let reference = ItemReference(scheme: "widget", payload: Data())
    let preview = ItemDragPreview(intent: .deliver([reference], to: b), accepted: false)
    #expect(preview == .receive(b, accepted: false))
    #expect(ItemDragLayout(order: [a, b], preview: preview).slots == [.item(a), .item(b)])
    #expect(ItemDragPreview(intent: .insert([reference], before: b), accepted: false) == .none)
}

@Test func layoutMotionCannotChangeLatchedIntentUnderStationaryPointer() {
    var latch = ItemDragHitLatch()
    let location = ItemDropLocation(target: b, before: b)
    latch.capture(location, region: CGRect(x: -120, y: 0, width: 20, height: 40))
    latch.accommodate(CGRect(x: -145, y: 0, width: 40, height: 40))
    #expect(latch.retained(at: CGPoint(x: -110, y: 20)) == location)
    #expect(latch.retained(at: CGPoint(x: -140, y: 20)) == location)
    // 已进入真实新位置后，旧容错区必须释放，不能霸占相邻的插入空隙。
    #expect(latch.retained(at: CGPoint(x: -102, y: 20)) == nil)
    #expect(latch.retained(at: CGPoint(x: -90, y: 20)) == nil)
    latch.reset()
    #expect(latch.retained(at: CGPoint(x: -110, y: 20)) == nil)
}

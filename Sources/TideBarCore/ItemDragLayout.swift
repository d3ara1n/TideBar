import Foundation

/// 纯展示语义：不携带资源、不执行操作，也不规定颜色、形状或动画。
public enum ItemDragPreview: Equatable, Sendable {
    case none
    case reorder(ItemID, before: ItemID?)
    case insert(count: Int, before: ItemID?)
    case receive(ItemID, accepted: Bool)

    public init(intent: ItemDropIntent?, accepted: Bool) {
        switch intent {
        case .reorder(let id, let before) where accepted: self = .reorder(id, before: before)
        case .insert(let references, let before) where accepted: self = .insert(count: references.count, before: before)
        case .deliver(_, let id): self = .receive(id, accepted: accepted)
        default: self = .none
        }
    }
}

/// 临时排位投射。一个单位是一格；渲染器决定格子的实际尺寸与样式。
/// 命中使用目标布局，不读取动画的 presentation frame；占位是明确的插入区。
public struct ItemDragLayout: Equatable, Sendable {
    public enum Slot: Equatable, Sendable {
        case item(ItemID)
        case placeholder(count: Int, before: ItemID?)
    }
    public struct Hit: Equatable, Sendable {
        public let location: ItemDropLocation
        public let lower: Double
        public let upper: Double
    }
    public let slots: [Slot]

    public init(order: [ItemID], preview: ItemDragPreview) {
        switch preview {
        case .reorder(let source, let before):
            guard let moved = ItemOrdering.moving([source], before: before, in: order) else {
                slots = order.map(Slot.item)
                return
            }
            // 即使锚点是 source 自身，也使用其后的真实身份表达占位，避免悬空锚点。
            let sourceIndex = moved.firstIndex(of: source)!
            let next = moved.dropFirst(sourceIndex + 1).first
            slots = moved.map { $0 == source ? .placeholder(count: 1, before: next) : .item($0) }
        case .insert(let count, let before):
            guard count > 0, before == nil || order.contains(before!) else {
                slots = order.map(Slot.item)
                return
            }
            var result = order.map(Slot.item)
            let index = before.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
            result.insert(.placeholder(count: count, before: before), at: index)
            slots = result
        default: slots = order.map(Slot.item)
        }
    }

    public func hit(at x: Double, iconFraction: Double, allowsReceiving: Bool) -> Hit {
        let items: [(index: Int, id: ItemID)] = slots.enumerated().compactMap {
            if case .item(let id) = $0.element { return ($0.offset, id) }
            return nil
        }
        if allowsReceiving {
            let half = min(max(iconFraction, 0), 1) / 2
            for item in items {
                let center = Double(item.index) + 0.5
                if x >= center - half, x <= center + half {
                    return Hit(location: .init(target: item.id, before: x < center ? item.id : nextItem(after: item.index)),
                               lower: center - half, upper: center + half)
                }
            }
            let right = items.first { Double($0.index) + 0.5 > x }
            let left = items.last { Double($0.index) + 0.5 < x }
            return Hit(location: .init(target: nil, before: right?.id),
                       lower: left.map { Double($0.index) + 0.5 + half } ?? -.infinity,
                       upper: right.map { Double($0.index) + 0.5 - half } ?? .infinity)
        }
        // 内部重排使用中心分界；占位区域不可能被解释成接收另一个 item。
        let right = items.first { Double($0.index) + 0.5 > x }
        let left = items.last { Double($0.index) + 0.5 <= x }
        return Hit(location: .init(target: nil, before: right?.id),
                   lower: left.map { Double($0.index) + 0.5 } ?? -.infinity,
                   upper: right.map { Double($0.index) + 0.5 } ?? .infinity)
    }

    private func nextItem(after index: Int) -> ItemID? {
        slots.dropFirst(index + 1).compactMap { slot in
            if case .item(let id) = slot { return id }
            return nil
        }.first
    }
}

/// 占位让位期间保留已命中的区域，并容纳同一目标的新位置。
/// 使用屏幕坐标；窗口居中扩宽或动画本身不能伪造一次鼠标移动。
public struct ItemDragHitLatch: Sendable {
    private var location: ItemDropLocation?
    private var region = CGRect.zero
    private var currentRegion: CGRect?
    public init() {}
    public mutating func retained(at point: CGPoint) -> ItemDropLocation? {
        // 光标进入目标的真实新位置后，归还旧位置的容错区，不长期占用相邻空隙。
        if let currentRegion, currentRegion.contains(point) { region = currentRegion }
        return region.contains(point) ? location : nil
    }
    public mutating func capture(_ location: ItemDropLocation, region: CGRect) {
        self.location = location
        self.region = region
        currentRegion = nil
    }
    public mutating func accommodate(_ region: CGRect) {
        guard location != nil else { return }
        currentRegion = region
        self.region = self.region.union(region)
    }
    public mutating func reset() {
        location = nil
        region = .zero
        currentRegion = nil
    }
}

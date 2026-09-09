/// 原生事件适配后的终止证据。未知不等于释放；来源无终止证据时不能删除引用。
public enum ItemDragEndEvidence: Equatable, Sendable {
    case mouseReleased
    case cancelled
    case unknown

    public func permitsRemoval(accepted: Bool, invalidated: Bool, outsideBar: Bool,
                               leftButtonStillDown: Bool) -> Bool {
        self == .mouseReleased && !accepted && !invalidated && outsideBar && !leftButtonStillDown
    }
}

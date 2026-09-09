import CoreGraphics

/// 会影响潮涌与状态标记的窗口内容修订。
public struct WindowContentRevision: Equatable, Sendable {
    public let ownerProcessIdentifier: Int32
    public let elementIdentifier: Int
    public let title: String?
    public let document: String?
    public let isMinimized: Bool
    /// 该窗口为当前聚焦窗口（点点强调色）；进入修订使焦点切换驱动 UI 刷新
    public let isActive: Bool
    public let screenID: CGDirectDisplayID?

    public init(ownerProcessIdentifier: Int32,
                elementIdentifier: Int,
                title: String?,
                document: String?,
                isMinimized: Bool,
                isActive: Bool,
                screenID: CGDirectDisplayID?) {
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.elementIdentifier = elementIdentifier
        self.title = title
        self.document = document
        self.isMinimized = isMinimized
        self.isActive = isActive
        self.screenID = screenID
    }
}

/// UI 条目的完整内容修订；identity 负责视图复用，revision 负责判定模型是否过期。
/// badge 参与过期判定（驱动角标显示与汐线脉冲），但不进入窗口知识——
/// 角标变化不触发潮涌失效（非窗口内容修订）。
public struct AppContentRevision: Equatable, Sendable {
    public let identity: AppIdentity
    public let name: String
    public let applicationPath: String?
    public let isPinned: Bool
    public let preferredProcessIdentifier: Int32?
    public let processIdentifiers: [Int32]
    public let isHidden: Bool
    public let canTerminate: Bool
    public let badge: BadgeValue?
    public let windows: WindowKnowledge<WindowContentRevision>

    public init(identity: AppIdentity,
                name: String,
                applicationPath: String?,
                isPinned: Bool,
                preferredProcessIdentifier: Int32?,
                processIdentifiers: [Int32],
                isHidden: Bool,
                canTerminate: Bool,
                badge: BadgeValue?,
                windows: WindowKnowledge<WindowContentRevision>) {
        self.identity = identity
        self.name = name
        self.applicationPath = applicationPath
        self.isPinned = isPinned
        self.preferredProcessIdentifier = preferredProcessIdentifier
        self.processIdentifiers = processIdentifiers.sorted()
        self.isHidden = isHidden
        self.canTerminate = canTerminate
        self.badge = badge
        self.windows = windows
    }
}

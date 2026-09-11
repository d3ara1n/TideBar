import Foundation

/// TideBar 小工具的具体类型键；TideBar 只负责保存和路由，不解释实例配置。
public enum WidgetType: String, Codable, CaseIterable, Sendable {
    case applicationLauncher
}

/// 小工具实例的通用外壳。configuration 由具体 widget 类型解释。
public struct WidgetPayload: Codable, Hashable, Sendable {
    /// 实例身份参与 payload，确保两个空白 widget 的引用也不会相同。
    public var instanceID: UUID
    public var type: WidgetType
    public var displayName: String
    public var configuration: Data

    public init(instanceID: UUID = UUID(), type: WidgetType, displayName: String, configuration: Data = Data()) {
        self.instanceID = instanceID
        self.type = type
        self.displayName = displayName
        self.configuration = configuration
    }

    private enum CodingKeys: String, CodingKey { case instanceID, type, displayName, configuration }

    /// 兼容早期开发快照：缺失实例 ID 时生成一次新的 ID，随后由正常编辑路径持久化。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instanceID = try container.decodeIfPresent(UUID.self, forKey: .instanceID) ?? UUID()
        type = try container.decode(WidgetType.self, forKey: .type)
        displayName = try container.decode(String.self, forKey: .displayName)
        configuration = try container.decode(Data.self, forKey: .configuration)
    }
}

/// 应用收藏夹的实例配置。应用引用本身仍使用 ItemReference，避免引入统一 URL 约束。
public struct ApplicationLauncherConfiguration: Codable, Hashable, Sendable {
    public var applications: [ItemReference]

    public init(applications: [ItemReference] = []) {
        self.applications = applications
    }
}

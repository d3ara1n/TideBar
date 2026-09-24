/// 一个可参与应用列表组合的运行实例。系统对象仍由 TideBar 进程以 PID 映射持有。
/// 运行策略身份与资源 item 身份分离：同 bundle ID 的不同 .app 路径属于不同 item。
public struct RunningAppDescription: Equatable, Sendable {
    /// 运行策略、Finder 特判和进程能力使用的身份。
    public let identity: AppIdentity
    /// 标准应用的原始 bundle identifier；裸进程为 nil。
    public let bundleIdentifier: String?
    /// 裸进程的可执行路径；标准应用为 nil。
    public let executablePath: String?
    /// 标准应用的实际 bundle 路径。
    public let applicationPath: String?
    public let processIdentifier: Int32

    public init(bundleIdentifier: String,
                processIdentifier: Int32,
                applicationPath: String? = nil) {
        self.identity = AppIdentity(bundleIdentifier)
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = nil
        self.applicationPath = applicationPath
        self.processIdentifier = processIdentifier
    }

    public init(executablePath: String, processIdentifier: Int32) {
        self.identity = AppIdentity(executablePath)
        self.bundleIdentifier = nil
        self.executablePath = executablePath
        self.applicationPath = nil
        self.processIdentifier = processIdentifier
    }

    public var itemIdentity: ApplicationItemIdentity {
        if bundleIdentifier == nil, let executablePath {
            // 保留裸进程原有的 ASCII 不区分大小写路径身份语义。
            return ApplicationItemIdentity(
                bundleIdentifier: nil,
                applicationPath: AppIdentity(executablePath).bundleIdentifier
            )
        }
        return ApplicationItemIdentity(
            bundleIdentifier: bundleIdentifier,
            applicationPath: applicationPath ?? executablePath
        )
    }
}

public struct PinnedApplicationDescription: Equatable, Sendable {
    public let bundleIdentifier: String
    public let applicationPath: String?

    public init(bundleIdentifier: String, applicationPath: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
    }

    public var itemIdentity: ApplicationItemIdentity {
        ApplicationItemIdentity(bundleIdentifier: bundleIdentifier, applicationPath: applicationPath)
    }
}

/// 组合后的应用资源 item。`identity` 只负责运行策略，`itemIdentity` 负责栏内资源身份。
public struct ComposedAppDescription: Equatable, Sendable {
    public let itemIdentity: ApplicationItemIdentity
    public let identity: AppIdentity
    public let behavior: AppBehavior
    public let pinnedBundleIdentifier: String?
    public let pinnedApplicationPath: String?
    public let runningInstances: [RunningAppDescription]

    public var isPinned: Bool { pinnedBundleIdentifier != nil }
    public var isRunning: Bool { !runningInstances.isEmpty }
}

public enum AppListComposer {
    public static func compose(
        pinnedApplications: [PinnedApplicationDescription],
        runningApps: [RunningAppDescription]
    ) -> [ComposedAppDescription] {
        var pinnedOrder: [ApplicationItemIdentity] = []
        var pinnedLocators: [ApplicationItemIdentity: PinnedApplicationDescription] = [:]
        for application in pinnedApplications {
            guard pinnedLocators[application.itemIdentity] == nil else { continue }
            pinnedOrder.append(application.itemIdentity)
            pinnedLocators[application.itemIdentity] = application
        }

        var runningOrder: [ApplicationItemIdentity] = []
        var runningGroups: [ApplicationItemIdentity: [RunningAppDescription]] = [:]
        for app in runningApps {
            if runningGroups[app.itemIdentity] == nil {
                runningOrder.append(app.itemIdentity)
            }
            runningGroups[app.itemIdentity, default: []].append(app)
        }

        var result: [ComposedAppDescription] = []
        for itemIdentity in pinnedOrder {
            let pinned = pinnedLocators[itemIdentity]
            var running = runningGroups.removeValue(forKey: itemIdentity) ?? []
            // 旧 bundle-only 固定项没有路径，只能把同 bundle 的一个运行副本
            // 作为它的运行状态；其余路径仍作为独立临时 item 保留。
            if running.isEmpty, itemIdentity.applicationPath == nil,
               let runtimeIdentity = itemIdentity.runtimeIdentity,
               let fallbackKey = runningOrder.first(where: {
                   $0.runtimeIdentity == runtimeIdentity && runningGroups[$0] != nil
               }) {
                running = runningGroups.removeValue(forKey: fallbackKey) ?? []
            }
            let runtimeIdentity = running.first?.identity
                ?? itemIdentity.runtimeIdentity
                ?? AppIdentity(itemIdentity.key)
            result.append(ComposedAppDescription(
                itemIdentity: itemIdentity,
                identity: runtimeIdentity,
                behavior: AppBehavior.resolve(for: runtimeIdentity),
                pinnedBundleIdentifier: pinned?.bundleIdentifier,
                pinnedApplicationPath: pinned?.applicationPath,
                runningInstances: running
            ))
        }

        for itemIdentity in runningOrder {
            guard let running = runningGroups.removeValue(forKey: itemIdentity),
                  let first = running.first else { continue }
            result.append(ComposedAppDescription(
                itemIdentity: itemIdentity,
                identity: first.identity,
                behavior: AppBehavior.resolve(for: first.identity),
                pinnedBundleIdentifier: nil,
                pinnedApplicationPath: nil,
                runningInstances: running
            ))
        }
        return result
    }

    /// 旧 bundle-only 输入的兼容入口；运行时调用应传入带路径的 pinnedApplications。
    public static func compose(pinnedBundleIdentifiers: [String],
                               runningApps: [RunningAppDescription]) -> [ComposedAppDescription] {
        compose(
            pinnedApplications: pinnedBundleIdentifiers.map {
                PinnedApplicationDescription(bundleIdentifier: $0, applicationPath: nil)
            },
            runningApps: runningApps
        )
    }
}

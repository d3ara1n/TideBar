/// 一个可参与应用列表组合的运行实例。系统对象仍由 TideBar 进程以 PID 映射持有。
/// 标准应用以 bundle identifier 为身份；裸进程（无 bundle 的 regular GUI，
/// 如 .NET/Avalonia 调试目标、直跑的 jar）以可执行路径为身份。
/// 路径身份与 bundle 身份天然不碰撞（bundle identifier 不含路径分隔符）。
public struct RunningAppDescription: Equatable, Sendable {
    public let identity: AppIdentity
    /// 标准应用的原始 bundle identifier；裸进程为 nil
    public let bundleIdentifier: String?
    /// 裸进程的可执行路径（真实大小写，供文件操作与展示）；标准应用为 nil
    public let executablePath: String?
    public let processIdentifier: Int32

    public init(bundleIdentifier: String, processIdentifier: Int32) {
        self.identity = AppIdentity(bundleIdentifier)
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = nil
        self.processIdentifier = processIdentifier
    }

    public init(executablePath: String, processIdentifier: Int32) {
        self.identity = AppIdentity(executablePath)
        self.bundleIdentifier = nil
        self.executablePath = executablePath
        self.processIdentifier = processIdentifier
    }
}

/// 组合后的应用身份描述。固定项保留原始 locator，运行实例按身份聚合。
public struct ComposedAppDescription: Equatable, Sendable {
    public let identity: AppIdentity
    public let behavior: AppBehavior
    public let pinnedBundleIdentifier: String?
    public let runningInstances: [RunningAppDescription]

    public var isPinned: Bool { pinnedBundleIdentifier != nil }
    public var isRunning: Bool { !runningInstances.isEmpty }
}

/// 固定项与运行实例的纯列表组合器。输出保证每个 AppIdentity 最多出现一次。
public enum AppListComposer {
    public static func compose(pinnedBundleIdentifiers: [String],
                               runningApps: [RunningAppDescription]) -> [ComposedAppDescription] {
        var pinnedOrder: [AppIdentity] = []
        var pinnedLocators: [AppIdentity: String] = [:]
        for bundleIdentifier in pinnedBundleIdentifiers {
            let identity = AppIdentity(bundleIdentifier)
            guard pinnedLocators[identity] == nil else { continue }
            pinnedOrder.append(identity)
            pinnedLocators[identity] = bundleIdentifier
        }

        var runningOrder: [AppIdentity] = []
        var runningGroups: [AppIdentity: [RunningAppDescription]] = [:]
        for app in runningApps {
            if runningGroups[app.identity] == nil {
                runningOrder.append(app.identity)
            }
            runningGroups[app.identity, default: []].append(app)
        }

        var result = pinnedOrder.map { identity in
            ComposedAppDescription(identity: identity,
                                   behavior: AppBehavior.resolve(for: identity),
                                   pinnedBundleIdentifier: pinnedLocators[identity],
                                   runningInstances: runningGroups.removeValue(forKey: identity) ?? [])
        }
        result += runningOrder.compactMap { identity in
            guard let instances = runningGroups.removeValue(forKey: identity) else { return nil }
            return ComposedAppDescription(identity: identity,
                                          behavior: AppBehavior.resolve(for: identity),
                                          pinnedBundleIdentifier: nil,
                                          runningInstances: instances)
        }
        return result
    }
}

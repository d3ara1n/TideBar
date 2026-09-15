import Foundation

/// 开发运行的 defaults：读取正式版的持久化值，但所有写入只落在当前进程内。
/// 这样 `swift run` 可以复用正式版的固定项目等配置，退出后调试修改全部丢弃。
private final class ReadThroughUserDefaults: UserDefaults, @unchecked Sendable {
    private var overrides: [String: Any] = [:]
    private var removedKeys: Set<String> = []
    private var registeredValues: [String: Any] = [:]
    private let base: UserDefaults

    init(base: UserDefaults) {
        self.base = base
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        if removedKeys.contains(defaultName) { return nil }
        return overrides[defaultName]
            ?? base.object(forKey: defaultName)
            ?? registeredValues[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        removedKeys.remove(defaultName)
        if let value {
            overrides[defaultName] = value
        } else {
            overrides.removeValue(forKey: defaultName)
            removedKeys.insert(defaultName)
        }
    }

    override func removeObject(forKey defaultName: String) {
        overrides.removeValue(forKey: defaultName)
        // 不触碰 base；遮蔽正式版值，模拟本次调试进程内的删除。
        removedKeys.insert(defaultName)
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        registeredValues.merge(registrationDictionary) { current, _ in current }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        var result = base.dictionaryRepresentation()
        result.merge(registeredValues) { _, value in value }
        result.merge(overrides) { _, value in value }
        for key in removedKeys { result.removeValue(forKey: key) }
        return result
    }

    override func synchronize() -> Bool { true }
}

/// 运行环境区分：`swift run` 仅用于开发预览，不得接管或修改系统 Dock，也不写入持久化配置。
@MainActor
enum RuntimeEnvironment {
    /// 正式构建由 Finder/open 启动时位于 `.app` bundle；`swift run` 是裸可执行文件。
    static let isDevelopment = Bundle.main.bundleURL.pathExtension != "app"
    static let isProduction = !isDevelopment

    /// 正式应用沿用标准 defaults；开发运行从正式域读取、写入只落在内存覆盖层。
    static let defaults: UserDefaults = {
        guard isDevelopment else { return .standard }
        let productionDefaults = UserDefaults(suiteName: "dev.dearain.TideBar") ?? .standard
        return ReadThroughUserDefaults(base: productionDefaults)
    }()
}

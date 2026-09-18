import ServiceManagement

/// 登录项注册/注销的统一入口；裸可执行（swift run）无注册能力，静默跳过。
@MainActor
enum LoginItem {
    static func set(_ enabled: Bool) {
        guard RuntimeEnvironment.isProduction else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Login item operation failed: %@", String(describing: error))
        }
    }
}

import AppKit
import Sparkle

/// Sparkle 更新会话的外壳：正式 bundle 才启动 updater，
/// `swift run` 裸可执行没有 bundle 环境（SUFeedURL 无从读取），开发路径整体不可用。
@MainActor
final class UpdateCoordinator: NSObject {
    static let shared = UpdateCoordinator()

    /// 正式 .app bundle 判定；登录项等其他 bundle 依赖能力共用。
    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard Self.isAppBundle, controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
    }

    var isAvailable: Bool {
        Self.isAppBundle && controller != nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 打开 Sparkle 标准检查窗口（含进度与确认）。
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

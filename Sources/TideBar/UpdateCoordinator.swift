import AppKit
import Sparkle

/// Sparkle 更新会话的外壳：正式 bundle 才启动 updater，
/// `swift run` 裸可执行没有 bundle 环境（SUFeedURL 无从读取），开发路径整体不可用。
@MainActor
final class UpdateCoordinator: NSObject {
    static let shared = UpdateCoordinator()

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard RuntimeEnvironment.isProduction, controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
    }

    var isAvailable: Bool {
        RuntimeEnvironment.isProduction && controller != nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 打开 Sparkle 标准检查窗口（含进度与确认）；兼作状态栏菜单项动作，
    /// 更新能力不可用（开发运行）时静默。
    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}

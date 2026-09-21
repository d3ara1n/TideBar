import AppKit
import Sparkle

/// Sparkle 更新会话的外壳：正式 bundle 才启动 updater，
/// `swift run` 裸可执行没有 bundle 环境（SUFeedURL 无从读取），开发路径整体不可用。
@MainActor
final class UpdateCoordinator: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateCoordinator()

    private var controller: SPUStandardUpdaterController?

    /// Sparkle 即将安装更新并重启本应用（仅「安装并重启」路径，
    /// 不含「退出时静默安装」）；终止时据此跳过 Dock 恢复，接管状态跨重启保留。
    private(set) var isRelaunchingForUpdate = false

    private override init() {
        super.init()
    }

    func start() {
        guard RuntimeEnvironment.isProduction, controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
        )
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        isRelaunchingForUpdate = true
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

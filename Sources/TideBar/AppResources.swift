import Foundation

/// SwiftPM 为 executable 生成的 `Bundle.module` 只查 app 根目录与编译期构建路径，
/// 手工组装的 .app 将资源放在 Contents/Resources，两者对不上会导致启动即崩。
/// 此处自建解析，查找顺序同时覆盖打包态（Resources）与开发态（swift run 时 bundle 在可执行文件旁）。
enum AppResources {
    private final class Marker {}

    static nonisolated let bundle: Bundle = {
        let name = "TideBar_TideBar"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,                                          // .app 的 Contents/Resources
            Bundle(for: Marker.self).resourceURL,                             // 以 framework/xctest 形态链接时
            Bundle(for: Marker.self).bundleURL.deletingLastPathComponent(),   // 测试：xctest 所在的构建输出目录
            Bundle.main.bundleURL,                                            // swift run：可执行文件所在目录
        ]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent("\(name).bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        let searched = candidates.compactMap { $0?.path }.joined(separator: ", ")
        fatalError("AppResources: unable to locate \(name).bundle; searched: \(searched)")
    }()
}

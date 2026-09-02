// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TideBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TideBar", path: "Sources/TideBar"),
        // AX 探针（M2 前置）：对真实 app 集实测 AX 窗口能力，见 plans/todo-2026-09-window-surge.md
        .executableTarget(name: "AXProbe", path: "Sources/AXProbe"),
    ]
)

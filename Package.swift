// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TideBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TideBarCore", path: "Sources/TideBarCore"),
        .executableTarget(name: "TideBar", dependencies: ["TideBarCore"], path: "Sources/TideBar"),
        .testTarget(name: "TideBarCoreTests", dependencies: ["TideBarCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TideBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TideBar", path: "Sources/TideBar"),
    ]
)

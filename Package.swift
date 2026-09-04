// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TideBar",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
    ],
    targets: [
        .target(name: "TideBarCore", path: "Sources/TideBarCore"),
        .executableTarget(
            name: "TideBar",
            dependencies: [
                "TideBarCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/TideBar"
        ),
        .testTarget(name: "TideBarCoreTests", dependencies: ["TideBarCore"]),
    ]
)

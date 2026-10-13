// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FreeDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "FreeDock", path: "Sources/FreeDock")
    ]
)

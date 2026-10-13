// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NewMacBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NewMacBar", targets: ["NewMacBar"])],
    targets: [.executableTarget(name: "NewMacBar", linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
        .linkedFramework("ServiceManagement"), .linkedFramework("EventKit"),
        .linkedFramework("Carbon")
    ])],
    swiftLanguageVersions: [.v5]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Panopticon",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Panopticon", targets: ["Panopticon"])],
    targets: [.executableTarget(name: "Panopticon", resources: [.process("Resources")], linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
        .linkedFramework("ServiceManagement"), .linkedFramework("EventKit"),
        .linkedFramework("Carbon")
    ])],
    swiftLanguageVersions: [.v5]
)

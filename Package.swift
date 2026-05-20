// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "menutray", path: "Sources")
    ]
)

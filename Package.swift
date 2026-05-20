// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "webtray", path: "Sources")
    ]
)

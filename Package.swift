// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snip",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "Snip", path: "Sources/Snip")
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Question",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Question", path: "Sources/Question")
    ]
)

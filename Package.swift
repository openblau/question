// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Question",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Question",
            dependencies: [.product(name: "Textual", package: "textual")],
            path: "Sources/Question")
    ]
)

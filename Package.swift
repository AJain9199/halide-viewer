// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HalideViewer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "HalideViewer",
            path: "Sources/HalideViewer",
            exclude: ["Info.plist"]
        )
    ]
)

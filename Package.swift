// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IrisViewer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "IrisViewer",
            path: "Sources/IrisViewer",
            exclude: ["Info.plist"]
        )
    ]
)

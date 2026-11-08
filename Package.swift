// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fingertip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Fingertip",
            path: "Sources/Fingertip"
        )
    ]
)

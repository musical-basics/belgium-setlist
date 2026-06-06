// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShowRunner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShowRunner",
            path: "Sources/ShowRunner"
        )
    ]
)

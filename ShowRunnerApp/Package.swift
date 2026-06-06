// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShowRunner",
    platforms: [.macOS(.v13)],
    targets: [
        // The lighting feature lives in its OWN module. It depends only on Foundation/AppKit
        // and a small `ShowClock` protocol it defines itself — it never imports the audio
        // engine or any host type, so nothing here can affect the sound code. Maximum modularity.
        .target(
            name: "Lighting",
            path: "Sources/Lighting"
        ),
        // The existing audio app. Unchanged except that it now *links* Lighting and wires it
        // up through a tiny fail-safe bridge (LightingBridge.swift).
        .executableTarget(
            name: "ShowRunner",
            dependencies: ["Lighting"],
            path: "Sources/ShowRunner"
        ),
    ]
)

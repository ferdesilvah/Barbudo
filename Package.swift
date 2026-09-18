// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barbudo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BarbudoCore", targets: ["BarbudoCore"]),
        .library(name: "BarbudoUI", targets: ["BarbudoUI"]),
    ],
    targets: [
        // Pure rules engine. No dependencies, so it builds identically on iOS and on the Linux server.
        .target(name: "BarbudoCore"),
        // SwiftUI table. Every file is wrapped in `#if canImport(SwiftUI)` so Linux CI still builds.
        .target(name: "BarbudoUI", dependencies: ["BarbudoCore"]),
        .testTarget(name: "BarbudoCoreTests", dependencies: ["BarbudoCore"]),
    ]
)

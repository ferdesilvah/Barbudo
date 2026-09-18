// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barbudo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BarbudoCore", targets: ["BarbudoCore"]),
    ],
    targets: [
        // Pure rules engine. No dependencies, no Foundation-only APIs beyond Codable,
        // so it builds identically on iOS and on the Linux server.
        .target(name: "BarbudoCore"),
        .testTarget(name: "BarbudoCoreTests", dependencies: ["BarbudoCore"]),
    ]
)

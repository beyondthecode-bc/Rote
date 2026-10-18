// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoteCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RoteCore", targets: ["RoteCore"])
    ],
    targets: [
        .target(name: "RoteCore"),
        .testTarget(name: "RoteCoreTests", dependencies: ["RoteCore"])
    ]
)

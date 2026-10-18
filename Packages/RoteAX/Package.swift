// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoteAX",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RoteAX", targets: ["RoteAX"])
    ],
    dependencies: [
        .package(path: "../RoteCore")
    ],
    targets: [
        .target(name: "RoteAX", dependencies: ["RoteCore"]),
        .testTarget(
            name: "RoteAXTests",
            dependencies: ["RoteAX"],
            resources: [.copy("Fixtures")]
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HeddleActor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HeddleActor",
            targets: ["HeddleActor"]
        )
    ],
    targets: [
        .target(name: "HeddleActor"),
        .testTarget(
            name: "HeddleActorTests",
            dependencies: ["HeddleActor"]
        )
    ]
)


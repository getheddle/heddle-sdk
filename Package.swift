// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HeddleSDK",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HeddleActor",
            targets: ["HeddleActor"]
        ),
        .library(
            name: "HeddleActorNATS",
            targets: ["HeddleActorNATS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nats-io/nats.swift.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "HeddleActor",
            path: "swift/Sources/HeddleActor"
        ),
        .target(
            name: "HeddleActorNATS",
            dependencies: [
                "HeddleActor",
                .product(
                    name: "Nats",
                    package: "nats.swift",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            path: "swift-nats/Sources/HeddleActorNATS"
        ),
        .testTarget(
            name: "HeddleActorTests",
            dependencies: ["HeddleActor"],
            path: "swift/Tests/HeddleActorTests"
        ),
    ]
)

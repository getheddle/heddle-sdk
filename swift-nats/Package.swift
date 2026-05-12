// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HeddleActorNATS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HeddleActorNATS",
            targets: ["HeddleActorNATS"]
        )
    ],
    dependencies: [
        .package(path: "../swift"),
        .package(url: "https://github.com/nats-io/nats.swift.git", from: "0.4.0"),
        // Keep the NKeys transitive dependency on a libsodium API surface
        // available in Ubuntu LTS packages used by CI and common deployments.
        .package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.9.1"),
    ],
    targets: [
        .target(
            name: "HeddleActorNATS",
            dependencies: [
                .product(name: "HeddleActor", package: "swift"),
                .product(name: "Nats", package: "nats.swift"),
                .product(name: "Sodium", package: "swift-sodium"),
            ]
        )
    ]
)

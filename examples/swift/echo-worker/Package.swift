// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EchoWorker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "EchoWorker",
            targets: ["EchoWorker"]
        )
    ],
    dependencies: [
        .package(path: "../../../swift")
    ],
    targets: [
        .executableTarget(
            name: "EchoWorker",
            dependencies: [
                .product(name: "HeddleActor", package: "swift")
            ]
        )
    ]
)

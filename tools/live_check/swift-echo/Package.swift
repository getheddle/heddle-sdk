// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LiveEcho",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../../swift"),
        .package(path: "../../../swift-nats"),
    ],
    targets: [
        .executableTarget(name: "LiveEcho", dependencies: [
            .product(name: "HeddleActor", package: "swift"),
            .product(name: "HeddleActorNATS", package: "swift-nats"),
        ]),
    ]
)

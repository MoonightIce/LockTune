// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LockTune",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LockTuneDomain", targets: ["LockTuneDomain"]),
        .library(name: "LockTuneCore", targets: ["LockTuneCore"]),
        .library(name: "LockTuneInfrastructure", targets: ["LockTuneInfrastructure"]),
    ],
    targets: [
        .target(name: "LockTuneDomain"),
        .target(
            name: "LockTuneCore",
            dependencies: ["LockTuneDomain"]
        ),
        .target(
            name: "LockTuneInfrastructure",
            dependencies: ["LockTuneCore", "LockTuneDomain"]
        ),
        .testTarget(
            name: "LockTuneCoreTests",
            dependencies: ["LockTuneCore", "LockTuneDomain", "LockTuneInfrastructure"]
        ),
    ]
)

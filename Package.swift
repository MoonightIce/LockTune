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
    dependencies: [
        .package(
            url: "https://github.com/sbooth/CXXMonkeysAudio",
            revision: "a33138a7bff0ef65dfa67f2a25463e201d7dff64"
        ),
    ],
    targets: [
        .target(name: "LockTuneDomain"),
        .target(
            name: "LockTuneCore",
            dependencies: ["LockTuneDomain"]
        ),
        .target(
            name: "LockTuneAPEBridge",
            dependencies: [
                .product(name: "MAC", package: "CXXMonkeysAudio"),
            ],
            publicHeadersPath: "include",
            cxxSettings: [.define("PLATFORM_APPLE")]
        ),
        .target(
            name: "LockTuneInfrastructure",
            dependencies: ["LockTuneCore", "LockTuneDomain", "LockTuneAPEBridge"]
        ),
        .testTarget(
            name: "LockTuneCoreTests",
            dependencies: ["LockTuneCore", "LockTuneDomain", "LockTuneInfrastructure"]
        ),
    ]
)

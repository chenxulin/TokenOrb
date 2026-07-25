// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TokenOrb",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "TokenOrbCore", targets: ["TokenOrbCore"]),
        .executable(name: "TokenOrb", targets: ["TokenOrbMac"]),
        .executable(name: "TokenOrbCoreChecks", targets: ["TokenOrbCoreChecks"]),
    ],
    targets: [
        .target(name: "TokenOrbCore"),
        .executableTarget(
            name: "TokenOrbMac",
            dependencies: ["TokenOrbCore"]
        ),
        .executableTarget(
            name: "TokenOrbCoreChecks",
            dependencies: ["TokenOrbCore"]
        ),
    ]
)

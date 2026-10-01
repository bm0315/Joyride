// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Joyride",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "JoyrideCore", targets: ["JoyrideCore"]),
        .executable(name: "Joyride", targets: ["JoyrideApp"]),
        .executable(name: "JoyrideCoreChecks", targets: ["JoyrideCoreChecks"]),
    ],
    targets: [
        .target(name: "JoyrideCore"),
        .executableTarget(
            name: "JoyrideApp",
            dependencies: ["JoyrideCore"],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "JoyrideCoreChecks",
            dependencies: ["JoyrideCore"]
        ),
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Joyride",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AgentAvatarCore", targets: ["AgentAvatarCore"]),
        .executable(name: "Joyride", targets: ["AgentAvatarApp"]),
        .executable(name: "AgentAvatarCoreChecks", targets: ["AgentAvatarCoreChecks"]),
    ],
    targets: [
        .target(name: "AgentAvatarCore"),
        .executableTarget(
            name: "AgentAvatarApp",
            dependencies: ["AgentAvatarCore"],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "AgentAvatarCoreChecks",
            dependencies: ["AgentAvatarCore"]
        ),
    ]
)

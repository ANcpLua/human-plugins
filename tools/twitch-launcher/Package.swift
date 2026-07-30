// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwitchLauncher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TwitchCore", targets: ["TwitchCore"]),
        .executable(name: "TwitchLauncher", targets: ["TwitchLauncher"]),
        .executable(
            name: "twitch-launcher-self-test",
            targets: ["TwitchLauncherSelfTest"]
        ),
    ],
    targets: [
        .target(
            name: "TwitchCore",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "TwitchLauncher",
            dependencies: ["TwitchCore"]
        ),
        .executableTarget(
            name: "TwitchLauncherSelfTest",
            dependencies: ["TwitchCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ribbon",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Ribbon", targets: ["RibbonApp"]),
        .executable(name: "ribbon", targets: ["RibbonCLI"]),
        .executable(name: "RibbonFixture", targets: ["RibbonFixture"]),
    ],
    targets: [
        // Pure Swift: layout, strips, commands, config, gestures. Builds and tests on Linux too.
        .target(name: "RibbonCore"),
        // The menu bar app: Accessibility window control, hotkeys, overlays, settings, onboarding.
        .executableTarget(
            name: "RibbonApp",
            dependencies: ["RibbonCore"],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS])),
            ]
        ),
        // `ribbon` command-line tool: talks to the running app over a local message port.
        .executableTarget(name: "RibbonCLI", dependencies: ["RibbonCore"]),
        // A tiny window-making app used only by the end-to-end tests.
        .executableTarget(name: "RibbonFixture"),
        .testTarget(name: "RibbonCoreTests", dependencies: ["RibbonCore"]),
    ]
)

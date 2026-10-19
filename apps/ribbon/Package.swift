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
    dependencies: [
        // The layout engine and its unit tests live in their own package (run `swift test` in Core/).
        .package(path: "Core"),
    ],
    targets: [
        // The menu bar app: Accessibility window control, hotkeys, overlays, settings, onboarding.
        .executableTarget(
            name: "RibbonApp",
            dependencies: [.product(name: "RibbonCore", package: "Core")],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("ServiceManagement", .when(platforms: [.macOS])),
            ]
        ),
        // `ribbon` command-line tool: talks to the running app over a local message port.
        .executableTarget(name: "RibbonCLI", dependencies: [.product(name: "RibbonCore", package: "Core")]),
        // A tiny window-making app used only by the end-to-end tests.
        .executableTarget(name: "RibbonFixture"),
    ]
)

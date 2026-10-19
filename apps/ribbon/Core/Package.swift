// swift-tools-version:5.9
import PackageDescription

// Ribbon's window-layout engine: pure Swift, no AppKit, so it builds and tests anywhere.
let package = Package(
    name: "RibbonCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "RibbonCore", targets: ["RibbonCore"])],
    targets: [
        .target(name: "RibbonCore"),
        .testTarget(name: "RibbonCoreTests", dependencies: ["RibbonCore"]),
    ]
)

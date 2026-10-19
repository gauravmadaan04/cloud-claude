// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HavenCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HavenCore", targets: ["HavenCore"]),
    ],
    targets: [
        .target(name: "HavenCore"),
        .testTarget(name: "HavenCoreTests", dependencies: ["HavenCore"]),
    ]
)

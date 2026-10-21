// swift-tools-version:5.9
import PackageDescription

// whisper.cpp (MIT) as the prebuilt framework its project publishes: Apple silicon and Intel, Metal on Apple GPUs.
// Pinned by checksum, so a changed download is refused.
let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperCpp", targets: ["whisper"]),
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip",
            checksum: "af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b"
        ),
    ]
)

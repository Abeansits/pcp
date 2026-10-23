// swift-tools-version:5.9
import PackageDescription

// Platform-independent logic for PEA (history, paste stack, secret detection,
// search). Kept free of AppKit/CloudKit so it can be unit-tested anywhere.
let package = Package(
    name: "PEACore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PEACore", targets: ["PEACore"])],
    targets: [
        .target(name: "PEACore"),
        .testTarget(name: "PEACoreTests", dependencies: ["PEACore"]),
    ]
)

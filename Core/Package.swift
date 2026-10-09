// swift-tools-version:5.9
import PackageDescription

// Platform-independent logic for PCP (history, paste stack, secret detection,
// search). Kept free of AppKit/CloudKit so it can be unit-tested anywhere.
let package = Package(
    name: "PCPCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PCPCore", targets: ["PCPCore"])],
    targets: [
        .target(name: "PCPCore"),
        .testTarget(name: "PCPCoreTests", dependencies: ["PCPCore"]),
    ]
)

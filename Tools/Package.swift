// swift-tools-version: 6.2

import PackageDescription

// Tooling-only package for code generation. Nothing depends on it, so the generator can
// be pinned exactly and `Package.resolved` committed without affecting clients.
let package = Package(
    name: "swift-slack-tools",
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator.git", exact: "1.11.0"),
    ],
)

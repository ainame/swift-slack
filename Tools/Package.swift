// swift-tools-version: 6.2

import PackageDescription

// Tooling-only package for code generation and formatting. Nothing depends on it, so the
// generator can be pinned exactly and `Package.resolved` committed without affecting clients.
let package = Package(
    name: "swift-slack-tools",
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator.git", exact: "1.11.0"),
    ],
    targets: [
        // renovate: datasource=github-release-attachments depName=nicklockwood/SwiftFormat versioning=semver
        .binaryTarget(
            name: "swiftformat",
            url: "https://github.com/nicklockwood/SwiftFormat/releases/download/0.63.1/swiftformat.artifactbundle.zip",
            checksum: "7b24a274b64c5510ae618b86da78ca24f64f61f376b5fd825881c4276784c8b7",
        ),
        // Formats files outside this package, so `make format` grants write access to the
        // repository with `--allow-writing-to-directory` instead of the package directory.
        .plugin(
            name: "SwiftFormatPlugin",
            capability: .command(
                intent: .custom(
                    verb: "swiftformat",
                    description: "Formats Swift source files using SwiftFormat",
                ),
            ),
            dependencies: ["swiftformat"],
        ),
    ],
)

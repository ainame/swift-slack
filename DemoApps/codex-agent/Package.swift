// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "codex-agent",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "codex-agent", targets: ["CodexAgent"]),
    ],
    traits: [
        .trait(name: "HummingbirdHTTPAdapter"),
    ],
    dependencies: [
        .package(
            path: "../..",
            traits: [
                "SocketMode",
                "Events",
                "HummingbirdHTTPAdapter",
                "WebAPI_Agents",
                "WebAPI_Assistant",
                "WebAPI_Auth",
                "WebAPI_Chat",
                "WebAPI_Conversations",
            ],
        ),
        .package(url: "https://github.com/ainame/swift-codex.git", from: "0.162.1"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodexAgent",
            dependencies: [
                "SlackStreaming",
                .product(name: "SlackKit", package: "swift-slack"),
                .product(name: "Codex", package: "swift-codex"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ],
        ),
        // The AsyncStream layer over chat.startStream, chat.appendStream, and chat.stopStream.
        // It depends only on swift-slack so it can move into the library later.
        .target(
            name: "SlackStreaming",
            dependencies: [
                .product(name: "SlackKit", package: "swift-slack"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
        ),
        .testTarget(
            name: "SlackStreamingTests",
            dependencies: ["SlackStreaming"],
        ),
    ],
)

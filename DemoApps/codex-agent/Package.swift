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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodexAgent",
            dependencies: [
                .product(name: "SlackKit", package: "swift-slack"),
                .product(name: "Codex", package: "swift-codex"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ],
        ),
        .testTarget(
            name: "CodexAgentTests",
            dependencies: [
                "CodexAgent",
                .product(name: "Codex", package: "swift-codex"),
            ],
        ),
    ],
)

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
                "WebAPI_Files",
            ],
        ),
        .package(url: "https://github.com/ainame/swift-codex.git", from: "0.162.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.13.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodexAgent",
            dependencies: [
                .product(name: "SlackKit", package: "swift-slack"),
                .product(name: "Codex", package: "swift-codex"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
        ),
        .testTarget(
            name: "CodexAgentTests",
            dependencies: [
                "CodexAgent",
                .product(name: "SlackKit", package: "swift-slack"),
                .product(name: "Codex", package: "swift-codex"),
                .product(name: "Logging", package: "swift-log"),
                // The tests answer Web API calls with a fake ClientTransport.
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            resources: [.copy("Fixtures")],
        ),
    ],
)

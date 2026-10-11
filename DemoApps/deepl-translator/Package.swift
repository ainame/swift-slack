// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "deepl-translator",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "deepl-translator", targets: ["DeepLTranslator"])
    ],
    traits: [
        .trait(name: "HummingbirdHTTPAdapter")
    ],
    dependencies: [
        .package(
            path: "../..",
            traits: [
                "SocketMode",
                "Events",
                "HummingbirdHTTPAdapter",
                "WebAPI_Chat",
                "WebAPI_Views",
                "WebAPI_Conversations"
            ]
        ),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.26.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.79.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "DeepLTranslator",
            dependencies: [
                .product(name: "SlackKit", package: "swift-slack"),
                .product(name: "SlackBlockKitDSL", package: "swift-slack"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration")
            ]
        )
    ]
)

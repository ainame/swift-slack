// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// BEGIN: Generated WebAPI traits - Do not edit manually
let webAPITraits: [String] = [
    "WebAPI_Admin",
    "WebAPI_Chat",
    "WebAPI_Views",
    "WebAPI_Apps",
    "WebAPI_Assistant",
    "WebAPI_Auth",
    "WebAPI_Bookmarks",
    "WebAPI_Bots",
    "WebAPI_Canvases",
    "WebAPI_Conversations",
    "WebAPI_DND",
    "WebAPI_Emoji",
    "WebAPI_Entity",
    "WebAPI_Files",
    "WebAPI_Functions",
    "WebAPI_Lists",
    "WebAPI_Migration",
    "WebAPI_OAuth",
    "WebAPI_OpenID",
    "WebAPI_Pins",
    "WebAPI_Reactions",
    "WebAPI_Reminders",
    "WebAPI_Search",
    "WebAPI_Stars",
    "WebAPI_Team",
    "WebAPI_Tooling",
    "WebAPI_Users",
]

var traits: [Trait] = webAPITraits.map { .trait(name: $0) }
// END: Generated WebAPI traits

traits.append(.trait(name: "SocketMode", enabledTraits: ["WebAPI_Apps"]))
traits.append(.trait(name: "Events"))
traits.append(.trait(name: "HummingbirdHTTPAdapter"))

// By default, enable all traits except optional integrations.
let defaultTraitNames = traits
    .map(\.name)
    .filter { $0 != "HummingbirdHTTPAdapter" }
traits.append(.default(enabledTraits: Set(defaultTraitNames)))

let package = Package(
    name: "swift-slack",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlackClient", targets: ["SlackClient"]),
        .library(name: "SlackApp", targets: ["SlackApp"]),
        .library(name: "SlackKit", targets: ["SlackKit"]),
        .library(name: "SlackBlockKit", targets: ["SlackBlockKit"]),
        .library(name: "SlackBlockKitDSL", targets: ["SlackBlockKitDSL"]),
        .library(name: "SlackModels", targets: ["SlackModels"]),
    ],
    traits: Set(traits),
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto", from: "4.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.94.1"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.11.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/swift-websocket", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client.git", from: "1.1.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.6"),
    ],
    targets: [
        .target(
            name: "SlackKit",
            dependencies: [
                .target(name: "SlackApp"),
                .target(name: "SlackClient"),
                .target(name: "SlackBlockKit"),
            ],
        ),
        .target(
            name: "SlackClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Logging", package: "swift-log"),
                .target(name: "SlackBlockKit"),
                .target(name: "SlackModels"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"], .when(configuration: .debug)),
            ],
        ),
        .testTarget(
            name: "SlackClientTests",
            dependencies: ["SlackClient", "SlackModels"],
        ),
        .target(
            name: "SlackApp",
            dependencies: [
                .target(name: "SlackClient"),
                .target(name: "SlackBlockKit"),
                .target(name: "SlackModels"),
                .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(
                    name: "WSClient", package: "swift-websocket",
                    condition: .when(traits: ["SocketMode"]),
                ),
                .product(
                    name: "Hummingbird", package: "hummingbird",
                    condition: .when(traits: ["HummingbirdHTTPAdapter"]),
                ),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"], .when(configuration: .debug)),
            ],
        ),
        .testTarget(
            name: "SlackAppTests",
            dependencies: [
                "SlackApp",
                "SlackClient",
                "SlackModels",
                .product(name: "NIOCore", package: "swift-nio"),
            ],
        ),
        .target(
            name: "SlackModels",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .target(name: "SlackBlockKit"),
            ],
        ),
        .target(
            name: "SlackBlockKit",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
        ),
        .testTarget(
            name: "SlackBlockKitTests",
            dependencies: ["SlackBlockKit"],
        ),
        .target(
            name: "SlackBlockKitDSL",
            dependencies: [
                .target(name: "SlackBlockKit"),
            ],
        ),
        .testTarget(
            name: "SlackBlockKitDSLTests",
            dependencies: ["SlackBlockKitDSL"],
        ),
        // renovate: datasource=github-release-attachments depName=nicklockwood/SwiftFormat versioning=semver
        .binaryTarget(
            name: "swiftformat",
            url: "https://github.com/nicklockwood/SwiftFormat/releases/download/0.61.0/swiftformat.artifactbundle.zip",
            checksum: "3d6d8a321d9cf17c2841652f19e39cde37ced02e6b7dfc65486402f9941f9e49",
        ),
        .plugin(
            name: "SwiftFormatPlugin",
            capability: .command(
                intent: .custom(
                    verb: "swiftformat",
                    description: "Formats Swift source files using SwiftFormat",
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "This command reformats source files"),
                ],
            ),
            dependencies: ["swiftformat"],
        ),
    ],
)

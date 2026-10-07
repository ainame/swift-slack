// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var targets: [Target] = []
// Only include actual executables, not snippet files
targets.append(executable("chatPostMessage"))
targets.append(executable("router"))
targets.append(executable("dsl"))
targets.append(executable("echoSlashCommand"))
targets.append(executable("threadExpander"))
targets.append(executable("blockActionsMessageContainer"))
targets.append(executable("externalSelect"))

let package = Package(
    name: "Examples",
    platforms: [.macOS(.v14)],
    products: products(from: targets),
    dependencies: [
        .package(
            path: "../../",
            traits: [
                "SocketMode",
                "Events",
                "WebAPI_Auth",
                "WebAPI_Apps",
                "WebAPI_Chat",
                "WebAPI_Views",
            ],
        ),
    ],
    targets: targets + [
        .target(
            name: "Snippets",
            dependencies: [
                .product(name: "SlackBlockKit", package: "swift-slack"),
                .product(name: "SlackBlockKitDSL", package: "swift-slack"),
            ],
        ),
    ],
)

func products(from targets: [Target]) -> [Product] {
    targets.map { .executable(name: $0.name, targets: [$0.name]) }
}

func executable(_ name: String) -> Target {
    .executableTarget(
        name: name,
        dependencies: [
            .product(name: "SlackKit", package: "swift-slack"),
            .product(name: "SlackBlockKitDSL", package: "swift-slack"),
        ],
    )
}

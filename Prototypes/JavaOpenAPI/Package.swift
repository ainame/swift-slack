// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JavaProto",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../..", traits: []),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.11.0"),
    ],
    targets: [
        .target(
            name: "JavaProtoTypes",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "SlackBlockKit", package: "swift-slack"),
            ],
        ),
        .executableTarget(
            name: "DecodeCheck",
            dependencies: ["JavaProtoTypes", .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")],
        ),
    ],
)
